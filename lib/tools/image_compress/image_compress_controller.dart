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
  final CompressionMode mode;
  final CompressionLevel level;
  final int minSizeBytes;
  final int maxSizeBytes;
  final String outputPath;

  ImageCompressParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.mode,
    required this.level,
    required this.minSizeBytes,
    required this.maxSizeBytes,
    required this.outputPath,
  });
}

/// Result returned from background isolate compression worker.
class ImageCompressResult {
  final String outputPath;
  final int outputSize;
  final int outputWidth;
  final int outputHeight;
  final bool landedInRange;

  ImageCompressResult({
    required this.outputPath,
    required this.outputSize,
    required this.outputWidth,
    required this.outputHeight,
    this.landedInRange = false,
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
  bool landedInRange = false;

  if (params.mode == CompressionMode.qualityLevel) {
    // Quality Level Mode
    encodedBytes = _encodeByQualityLevel(decoded, ext, params.level);
  } else {
    // Target Size Range Mode (Binary search / optimization)
    final searchResult = _encodeByTargetRange(
      decoded,
      ext,
      params.minSizeBytes,
      params.maxSizeBytes,
    );
    encodedBytes = searchResult.bytes;
    landedInRange = searchResult.landedInRange;
  }

  final outFile = File(params.outputPath);
  await outFile.writeAsBytes(encodedBytes);

  return ImageCompressResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
    outputWidth: origW,
    outputHeight: origH,
    landedInRange: landedInRange,
  );
}

Uint8List _encodeByQualityLevel(img.Image decoded, String ext, CompressionLevel level) {
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      int quality;
      switch (level) {
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
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    case '.png':
      int zlibLevel;
      switch (level) {
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
      return Uint8List.fromList(img.encodePng(decoded, level: zlibLevel));
    case '.bmp':
      return Uint8List.fromList(img.encodeBmp(decoded));
    case '.gif':
      return Uint8List.fromList(img.encodeGif(decoded));
    case '.tif':
    case '.tiff':
      return Uint8List.fromList(img.encodeTiff(decoded));
    default:
      return Uint8List.fromList(img.encodePng(decoded));
  }
}

class _RangeSearchResult {
  final Uint8List bytes;
  final bool landedInRange;

  _RangeSearchResult(this.bytes, this.landedInRange);
}

const int jpegQualityFloor = 30;
const int pngPaletteFloor = 64;

_RangeSearchResult _encodeByTargetRange(
  img.Image decoded,
  String ext,
  int minSizeBytes,
  int maxSizeBytes,
) {
  if (ext == '.jpg' || ext == '.jpeg') {
    // Binary search over JPEG quality [30..100], max 8 iterations
    int low = jpegQualityFloor;
    int high = 100;
    Uint8List? bestBytes;
    int bestDistance = 999999999;
    bool foundInRange = false;

    for (int iter = 0; iter < 8; iter++) {
      if (low > high) break;
      final mid = (low + high) ~/ 2;
      final bytes = Uint8List.fromList(img.encodeJpg(decoded, quality: mid));
      final size = bytes.length;

      if (size >= minSizeBytes && size <= maxSizeBytes) {
        bestBytes = bytes;
        foundInRange = true;
        break;
      }

      // Calculate distance to closest target bound
      int dist;
      if (size < minSizeBytes) {
        dist = minSizeBytes - size;
        low = mid + 1; // Needs higher quality for larger size
      } else {
        dist = size - maxSizeBytes;
        high = mid - 1; // Needs lower quality for smaller size
      }

      if (bestBytes == null || dist < bestDistance) {
        bestDistance = dist;
        bestBytes = bytes;
      }
    }

    bestBytes ??= Uint8List.fromList(img.encodeJpg(decoded, quality: 50));
    return _RangeSearchResult(bestBytes, foundInRange);
  } else if (ext == '.png') {
    // PNG search: palette quantization down to pngPaletteFloor (64) + Floyd-Steinberg dithering
    final colorCounts = [256, 128, 64];
    Uint8List? bestBytes;
    int bestDistance = 999999999;
    bool foundInRange = false;

    int attempts = 0;
    for (final numColors in colorCounts) {
      if (attempts >= 8) break;
      attempts++;

      // Quantize image to reduced color palette with dithering
      final quantized = img.quantize(
        decoded,
        numberOfColors: numColors,
        dither: img.DitherKernel.floydSteinberg,
      );
      final bytes = Uint8List.fromList(img.encodePng(quantized, level: 9));
      final size = bytes.length;

      if (size >= minSizeBytes && size <= maxSizeBytes) {
        bestBytes = bytes;
        foundInRange = true;
        break;
      }

      int dist;
      if (size < minSizeBytes) {
        dist = minSizeBytes - size;
      } else {
        dist = size - maxSizeBytes;
      }

      if (bestBytes == null || dist < bestDistance) {
        bestDistance = dist;
        bestBytes = bytes;
      }
    }

    bestBytes ??= Uint8List.fromList(img.encodePng(decoded, level: 9));
    return _RangeSearchResult(bestBytes, foundInRange);
  } else {
    // Default fallback for BMP/GIF/TIFF
    final bytes = _encodeByQualityLevel(decoded, ext, CompressionLevel.medium);
    final size = bytes.length;
    final inRange = size >= minSizeBytes && size <= maxSizeBytes;
    return _RangeSearchResult(bytes, inRange);
  }
}

class ImageCompressController extends StateNotifier<ImageCompressState> {
  final FileService _fileService;

  ImageCompressController(this._fileService) : super(const ImageCompressState());

  /// Load and validate selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    state = state.copyWith(isProcessing: true, clearError: true, clearOutput: true, clearResultType: true);

    final ext = p.extension(platformFile.name).toLowerCase();
    if (ext == '.webp') {
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

  /// Change active compression mode.
  void setMode(CompressionMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode, clearError: true);
  }

  /// Change active compression level (Quality Level mode).
  void setCompressionLevel(CompressionLevel level) {
    if (state.level == level) return;
    state = state.copyWith(level: level, clearError: true);
  }

  /// Set minimum target size (Target Size Range mode). Enforces 5 KB floor.
  void setMinSize(double value, SizeUnit unit) {
    double clampedValue = value;
    if (unit == SizeUnit.kb && value < 5.0) {
      clampedValue = 5.0;
    } else if (unit == SizeUnit.mb && value < (5.0 / 1024.0)) {
      clampedValue = 5.0 / 1024.0;
    }

    state = state.copyWith(
      minSizeValue: clampedValue,
      minSizeUnit: unit,
      clearError: true,
    );
  }

  /// Set maximum target size (Target Size Range mode).
  void setMaxSize(double value, SizeUnit unit) {
    state = state.copyWith(
      maxSizeValue: value,
      maxSizeUnit: unit,
      clearError: true,
    );
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

      if (state.mode == CompressionMode.targetSizeRange) {
        // Validation 1: Min size below hard floor
        if (state.minSizeBytes < ImageCompressState.minFloorBytes) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Minimum can't be set below 5 KB",
          );
          return;
        }

        // Validation 2: Max <= Min
        if (!state.isRangeValid) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Maximum must be greater than minimum",
          );
          return;
        }

        // Validation 3: Original file size is smaller than target minimum
        if (state.originalSizeBytes < state.minSizeBytes) {
          state = state.copyWith(
            isProcessing: false,
            resultType: CompressionResultType.smallerThanMin,
          );
          return;
        }

        // Validation 4: Original file size is already inside target range
        if (state.originalSizeBytes >= state.minSizeBytes &&
            state.originalSizeBytes <= state.maxSizeBytes) {
          state = state.copyWith(
            isProcessing: false,
            compressedSizeBytes: state.originalSizeBytes,
            resultType: CompressionResultType.alreadyInRange,
          );
          return;
        }
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
        mode: state.mode,
        level: state.level,
        minSizeBytes: state.minSizeBytes,
        maxSizeBytes: state.maxSizeBytes,
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageCompressWorker, params);

      // Determine result type
      CompressionResultType resultType;
      if (state.mode == CompressionMode.targetSizeRange) {
        if (result.landedInRange) {
          resultType = CompressionResultType.inRangeSuccess;
        } else {
          resultType = CompressionResultType.closestEffort;
        }
      } else {
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
