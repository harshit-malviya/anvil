import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'image_convert_state.dart';

/// Provider for ImageConvertController.
final imageConvertControllerProvider =
    StateNotifierProvider.autoDispose<ImageConvertController, ImageConvertState>(
  (ref) => ImageConvertController(
    FileService(),
    null,
    ref.read(appLogServiceProvider),
  ),
);

/// Parameters passed to isolate worker for background image conversion.
class ImageConvertParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final ImageOutputFormat targetFormat;
  final int jpegQuality;
  final String outputPath;

  ImageConvertParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.targetFormat,
    required this.jpegQuality,
    required this.outputPath,
  });
}

/// Result returned from isolate conversion worker.
class ImageConvertResult {
  final String outputPath;
  final int outputSize;

  ImageConvertResult({
    required this.outputPath,
    required this.outputSize,
  });
}

/// Top-level isolate worker for CPU-bound image encoding.
Future<ImageConvertResult> isolateImageConvertWorker(ImageConvertParams params) async {
  img.Image? decoded = img.decodeImage(params.inputBytes);
  if (decoded == null) {
    throw const FormatException("This image couldn't be read. File may be corrupt.");
  }

  // Animated sources: extract and convert only the first frame
  if (decoded.numFrames > 1) {
    decoded = decoded.frames.first;
  }

  img.Image imageToEncode = decoded;

  // Flatten transparency onto white background if target is JPEG and source has alpha
  if (params.targetFormat == ImageOutputFormat.jpeg && decoded.hasAlpha) {
    final whiteBg = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(whiteBg, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(whiteBg, decoded);
    imageToEncode = whiteBg;
  }

  Uint8List encodedBytes;
  switch (params.targetFormat) {
    case ImageOutputFormat.png:
      encodedBytes = Uint8List.fromList(img.encodePng(imageToEncode));
      break;
    case ImageOutputFormat.jpeg:
      encodedBytes =
          Uint8List.fromList(img.encodeJpg(imageToEncode, quality: params.jpegQuality));
      break;
    case ImageOutputFormat.bmp:
      encodedBytes = Uint8List.fromList(img.encodeBmp(imageToEncode));
      break;
    case ImageOutputFormat.gif:
      encodedBytes = Uint8List.fromList(img.encodeGif(imageToEncode));
      break;
    case ImageOutputFormat.tiff:
      encodedBytes = Uint8List.fromList(img.encodeTiff(imageToEncode));
      break;
  }

  final outFile = File(params.outputPath);
  await outFile.writeAsBytes(encodedBytes);

  return ImageConvertResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
  );
}

class ImageConvertController extends StateNotifier<ImageConvertState> {
  final FileService _fileService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;
  int? _pickerLoadTimeMs;

  ImageConvertController(
    this._fileService, [
    TempFileManager? tempFileManager,
    AppLogService? logService,
  ])  : _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const ImageConvertState());

  /// Detect format using magic bytes header, fallback to extension.
  static String detectFormat(Uint8List bytes, String fileName) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return 'PNG';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'JPEG';
      }
      if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
        return 'GIF';
      }
      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        return 'BMP';
      }
      if ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
          (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[0] == 0x00 && bytes[3] == 0x2A)) {
        return 'TIFF';
      }
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'WebP';
      }
    }
    final ext = p.extension(fileName).toLowerCase();
    switch (ext) {
      case '.png':
        return 'PNG';
      case '.jpg':
      case '.jpeg':
        return 'JPEG';
      case '.gif':
        return 'GIF';
      case '.bmp':
        return 'BMP';
      case '.tif':
      case '.tiff':
        return 'TIFF';
      case '.webp':
        return 'WebP';
      default:
        return ext.replaceAll('.', '').toUpperCase();
    }
  }

  /// Load and parse selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    final stopwatch = Stopwatch()..start();
    state = state.copyWith(isProcessing: true, clearError: true, clearResult: true);

    final ext = p.extension(platformFile.name).toLowerCase();
    final allowedExts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tiff', '.webp'];
    if (!allowedExts.contains(ext)) {
      stopwatch.stop();
      _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file type isn't supported for conversion.",
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
          stopwatch.stop();
          _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Could not read '${platformFile.name}': permission denied.",
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      stopwatch.stop();
      _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file couldn't be read as an image.",
      );
      return;
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }

    stopwatch.stop();
    _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;

    if (decoded == null) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file couldn't be read as an image.",
      );
      return;
    }

    final formatName = detectFormat(bytes, platformFile.name);
    final hasAlpha = decoded.hasAlpha;
    final isAnimated = decoded.numFrames > 1;

    ImageOutputFormat defaultTarget = ImageOutputFormat.jpeg;
    if (formatName.toUpperCase() == 'JPEG' || formatName.toUpperCase() == 'JPG') {
      defaultTarget = ImageOutputFormat.png;
    }

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
      width: decoded.width,
      height: decoded.height,
      fileSize: bytes.length,
      hasAlpha: hasAlpha,
      isAnimated: isAnimated,
      targetFormat: defaultTarget,
      thumbnailBytes: thumbBytes,
      isProcessing: false,
    );
  }

  /// Change target format.
  void setTargetFormat(ImageOutputFormat format) {
    if (state.detectedFormat != null &&
        state.detectedFormat!.toUpperCase() == format.displayName.toUpperCase()) {
      return;
    }
    state = state.copyWith(targetFormat: format, clearError: true);
  }

  /// Set JPEG quality (0 - 100).
  void setJpegQuality(int quality) {
    final clamped = quality.clamp(0, 100);
    state = state.copyWith(jpegQuality: clamped);
  }

  /// Perform image format conversion.
  Future<void> convert() async {
    if (state.file == null || state.thumbnailBytes == null) return;
    if (state.isSameFormat) {
      state = state.copyWith(
        errorMessage: "Target format cannot be the same as the source format.",
      );
      return;
    }

    state = state.copyWith(isProcessing: true, clearError: true);

    final logId = _logService.logStarted(
      'image_convert',
      'Image Format Convert',
      'convert',
      inputFileCount: 1,
      inputFilesCombinedSizeBytes: state.fileSize,
      filePickerLoadTimeMs: _pickerLoadTimeMs,
      parameters: {
        'targetFormat': state.targetFormat.displayName,
        'sourceFormat': state.detectedFormat,
        'quality': state.jpegQuality,
      },
    );

    try {
      Uint8List? inputBytes = state.file!.bytes;
      if (inputBytes == null && state.file!.path != null) {
        inputBytes = await File(state.file!.path!).readAsBytes();
      }

      if (inputBytes == null || inputBytes.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: "This file couldn't be read as an image.",
        );
        _logService.logFailed(
          logId,
          stage: LogFailureStage.validation,
          errorMessage: "Image file empty or unreadable",
        );
        return;
      }

      final defaultDir =
          await _fileService.getDefaultOutputDirectory(sourceFilePath: state.file!.path);
      final outputDir = defaultDir.path;

      final baseName = p.basenameWithoutExtension(state.file!.name);
      final targetExt = state.targetFormat.extension;
      final defaultOutputPath = p.join(outputDir, '${baseName}_converted$targetExt');

      final params = ImageConvertParams(
        inputBytes: inputBytes,
        sourceFileName: state.file!.name,
        targetFormat: state.targetFormat,
        jpegQuality: state.jpegQuality,
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageConvertWorker, params);

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        outputPath: result.outputPath,
        outputSize: result.outputSize,
      );

      _logService.logCompleted(
        logId,
        outputFileCount: 1,
        outputFilesCombinedSizeBytes: result.outputSize,
        message: 'output: ${p.basename(result.outputPath)}',
      );
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to convert on this device.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.isolateExecution,
        errorMessage: "Out of memory during image format conversion",
      );
      return;
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.fileWrite,
        errorMessage: "File system error: ${e.message}",
        errorDetail: e.toString(),
      );
      return;
    } catch (e) {
      await _tempFileManager.cleanupSession();
      final msg = e is FormatException ? e.message : "Conversion failed. Please try again.";
      state = state.copyWith(
        isProcessing: false,
        errorMessage: msg,
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.processing,
        errorMessage: msg,
        errorDetail: e.toString(),
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

  /// Reset controller back to initial state.
  void reset() {
    _tempFileManager.cleanupSession();
    state = const ImageConvertState();
  }
}
