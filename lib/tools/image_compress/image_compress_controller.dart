import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import 'image_compress_state.dart';

/// Provider for ImageCompressController.
final imageCompressControllerProvider =
    StateNotifierProvider.autoDispose<ImageCompressController, ImageCompressState>(
  (ref) => ImageCompressController(FileService()),
);

/// Parameters passed to background isolate worker for image compression.
class ImageCompressParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final CompressionLevel level;
  final String outputPath;

  ImageCompressParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.level,
    required this.outputPath,
  });
}

/// Result returned from background isolate compression worker.
class ImageCompressResult {
  final String outputPath;
  final int outputSize;
  final int outputWidth;
  final int outputHeight;

  ImageCompressResult({
    required this.outputPath,
    required this.outputSize,
    required this.outputWidth,
    required this.outputHeight,
  });
}

/// Top-level isolate worker for CPU-bound image compression.
Future<ImageCompressResult> isolateImageCompressWorker(ImageCompressParams params) async {
  img.Image? decoded = img.decodeImage(params.inputBytes);
  if (decoded == null) {
    throw const FormatException("This image couldn't be read. File may be corrupt.");
  }

  // Bake EXIF orientation so output is correctly oriented
  decoded = img.bakeOrientation(decoded);

  // Animated sources: extract first frame
  if (decoded.numFrames > 1) {
    decoded = decoded.frames.first;
  }

  final origW = decoded.width;
  final origH = decoded.height;

  final ext = p.extension(params.sourceFileName).toLowerCase();
  Uint8List encodedBytes;

  switch (ext) {
    case '.jpg':
    case '.jpeg':
      // // ASSUMPTION: Quality mapping for JPEG compression:
      // Low: 85 (minimal reduction, high visual quality)
      // Medium: 65 (balanced quality & file size reduction)
      // High: 40 (maximum size reduction)
      int quality;
      switch (params.level) {
        case CompressionLevel.low:
          quality = 85;
          break;
        case CompressionLevel.medium:
          quality = 65;
          break;
        case CompressionLevel.high:
          quality = 40;
          break;
      }
      encodedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
      break;
    case '.png':
      // // ASSUMPTION: Zlib compression level mapping for PNG compression:
      // Low: level 3, Medium: level 6, High: level 9
      int zlibLevel;
      switch (params.level) {
        case CompressionLevel.low:
          zlibLevel = 3;
          break;
        case CompressionLevel.medium:
          zlibLevel = 6;
          break;
        case CompressionLevel.high:
          zlibLevel = 9;
          break;
      }
      encodedBytes = Uint8List.fromList(img.encodePng(decoded, level: zlibLevel));
      break;
    case '.bmp':
      encodedBytes = Uint8List.fromList(img.encodeBmp(decoded));
      break;
    case '.gif':
      encodedBytes = Uint8List.fromList(img.encodeGif(decoded));
      break;
    case '.tif':
    case '.tiff':
      encodedBytes = Uint8List.fromList(img.encodeTiff(decoded));
      break;
    default:
      encodedBytes = Uint8List.fromList(img.encodePng(decoded));
      break;
  }

  final outFile = File(params.outputPath);
  await outFile.writeAsBytes(encodedBytes);

  return ImageCompressResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
    outputWidth: origW,
    outputHeight: origH,
  );
}

class ImageCompressController extends StateNotifier<ImageCompressState> {
  final FileService _fileService;

  ImageCompressController(this._fileService) : super(const ImageCompressState());

  /// Load and validate selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    state = state.copyWith(isProcessing: true, clearError: true, clearOutput: true, clearResultType: true);

    final ext = p.extension(platformFile.name).toLowerCase();
    if (ext == '.webp') {
      // // ASSUMPTION: WebP input rejected due to package:image 4.x read-only WebP decoder
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "WebP format compression is not supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF.",
      );
      return;
    }

    final allowedExts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tiff'];
    if (!allowedExts.contains(ext)) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file type isn't supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF.",
      );
      return;
    }

    Uint8List? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Could not read '${platformFile.name}': permission denied.",
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image couldn't be read. File may be corrupt.",
      );
      return;
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image couldn't be read. File may be corrupt.",
      );
      return;
    }

    // Bake EXIF orientation for consistent preview & dimension readings
    decoded = img.bakeOrientation(decoded);

    final formatName = ext.replaceAll('.', '').toUpperCase();

    // Create thumbnail
    img.Image thumbImg = decoded;
    if (thumbImg.numFrames > 1) {
      thumbImg = thumbImg.frames.first;
    }
    if (thumbImg.width > 400 || thumbImg.height > 400) {
      thumbImg = thumbImg.width >= thumbImg.height
          ? img.copyResize(thumbImg, width: 400, maintainAspect: true)
          : img.copyResize(thumbImg, height: 400, maintainAspect: true);
    }
    final thumbBytes = Uint8List.fromList(img.encodeJpg(thumbImg, quality: 80));

    state = state.copyWith(
      file: platformFile,
      detectedFormat: formatName,
      originalWidth: decoded.width,
      originalHeight: decoded.height,
      originalSizeBytes: bytes.length,
      thumbnailBytes: thumbBytes,
      isProcessing: false,
    );
  }

  /// Change active compression level.
  void setCompressionLevel(CompressionLevel level) {
    if (state.level == level) return;
    state = state.copyWith(level: level, clearError: true);
  }

  /// Perform image compression via background isolate worker.
  Future<void> compress() async {
    if (state.file == null || !state.isLoaded) return;

    state = state.copyWith(isProcessing: true, clearError: true, clearOutput: true, clearResultType: true);

    try {
      Uint8List? inputBytes = state.file!.bytes;
      if (inputBytes == null && state.file!.path != null) {
        inputBytes = await File(state.file!.path!).readAsBytes();
      }

      if (inputBytes == null || inputBytes.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: "This image couldn't be read. File may be corrupt.",
        );
        return;
      }

      final defaultDir =
          await _fileService.getDefaultOutputDirectory(sourceFilePath: state.file!.path);
      final outputDir = defaultDir.path;

      final baseName = p.basenameWithoutExtension(state.file!.name);
      final ext = p.extension(state.file!.name).toLowerCase();
      final defaultOutputPath = p.join(outputDir, '${baseName}_compressed$ext');

      final params = ImageCompressParams(
        inputBytes: inputBytes,
        sourceFileName: state.file!.name,
        level: state.level,
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageCompressWorker, params);

      // Determine result type based on size reduction comparison
      CompressionResultType resultType;
      if (result.outputSize >= state.originalSizeBytes) {
        resultType = CompressionResultType.outputLarger;
      } else {
        final diff = state.originalSizeBytes - result.outputSize;
        final pct = (diff / state.originalSizeBytes * 100);
        if (pct < 5.0) {
          resultType = CompressionResultType.minimalReduction;
        } else {
          resultType = CompressionResultType.normalSuccess;
        }
      }

      state = state.copyWith(
        isProcessing: false,
        compressedSizeBytes: result.outputSize,
        resultType: resultType,
        outputPath: result.outputPath,
      );
    } on OutOfMemoryError {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to compress on this device.",
      );
    } on FileSystemException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
    } catch (e) {
      final msg = e is FormatException ? e.message : "Compression failed. Please try again.";
      state = state.copyWith(
        isProcessing: false,
        errorMessage: msg,
      );
    }
  }

  /// User action: Save As custom destination.
  Future<void> saveAs() async {
    if (state.outputPath == null) return;
    final file = File(state.outputPath!);
    if (!file.existsSync()) return;

    final bytes = await file.readAsBytes();
    final defaultName = p.basename(state.outputPath!);
    await _fileService.saveFile(
      bytes: bytes,
      defaultFileName: defaultName,
    );
  }

  /// User action: Open containing folder.
  Future<void> openFolder() async {
    if (state.outputPath != null) {
      await _fileService.openFolder(state.outputPath!);
    }
  }

  /// Clear active error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Reset controller back to initial state.
  void reset() {
    state = const ImageCompressState();
  }
}
