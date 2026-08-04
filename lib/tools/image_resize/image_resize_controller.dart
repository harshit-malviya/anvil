import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/image_resize_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'image_resize_state.dart';

/// Provider for ImageResizeController.
final imageResizeControllerProvider =
    StateNotifierProvider.autoDispose<ImageResizeController, ImageResizeState>(
  (ref) => ImageResizeController(
    FileService(),
    null,
    ref.read(appLogServiceProvider),
  ),
);

/// Parameters passed to background isolate worker for image resizing.
class ImageResizeParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final int targetWidth;
  final int targetHeight;
  final String outputPath;

  ImageResizeParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.targetWidth,
    required this.targetHeight,
    required this.outputPath,
  });
}

/// Result returned from background isolate resize worker.
class ImageResizeResult {
  final String outputPath;
  final int outputSize;

  ImageResizeResult({
    required this.outputPath,
    required this.outputSize,
  });
}

/// Top-level isolate worker for CPU-bound image resizing.
Future<ImageResizeResult> isolateImageResizeWorker(ImageResizeParams params) async {
  img.Image? decoded = img.decodeImage(params.inputBytes);
  if (decoded == null) {
    throw const FormatException("This image couldn't be read. File may be corrupt.");
  }

  // // ASSUMPTION: img.Interpolation.cubic used for high-quality cubic interpolation resize via ImageResizeService.
  final resized = ImageResizeService.resize(
    decoded,
    targetWidth: params.targetWidth,
    targetHeight: params.targetHeight,
    interpolation: img.Interpolation.cubic,
    maintainAspect: false,
  );

  final ext = p.extension(params.sourceFileName).toLowerCase();
  Uint8List encodedBytes;

  switch (ext) {
    case '.png':
      encodedBytes = Uint8List.fromList(img.encodePng(resized));
      break;
    case '.jpg':
    case '.jpeg':
      encodedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 90));
      break;
    case '.bmp':
      encodedBytes = Uint8List.fromList(img.encodeBmp(resized));
      break;
    case '.gif':
      encodedBytes = Uint8List.fromList(img.encodeGif(resized));
      break;
    case '.tif':
    case '.tiff':
      encodedBytes = Uint8List.fromList(img.encodeTiff(resized));
      break;
    default:
      // Default fallback for formats like WebP without encoder support
      encodedBytes = Uint8List.fromList(img.encodePng(resized));
      break;
  }

  final outFile = File(params.outputPath);
  await outFile.writeAsBytes(encodedBytes);

  return ImageResizeResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
  );
}

class ImageResizeController extends StateNotifier<ImageResizeState> {
  final FileService _fileService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;

  ImageResizeController(
    this._fileService, [
    TempFileManager? tempFileManager,
    AppLogService? logService,
  ])  : _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const ImageResizeState());

  /// Load and parse selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    state = state.copyWith(isProcessing: true, clearError: true, clearResult: true);

    final ext = p.extension(platformFile.name).toLowerCase();
    final allowedExts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tiff', '.webp'];
    if (!allowedExts.contains(ext)) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file type isn't supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF, WebP.",
      );
      _logService.logError('image_resize', 'load_image',
          message: 'unsupported file type');
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
      sourceWidth: decoded.width,
      sourceHeight: decoded.height,
      sourceFileSize: bytes.length,
      targetWidth: decoded.width,
      targetHeight: decoded.height,
      percentage: 100.0,
      thumbnailBytes: thumbBytes,
      isProcessing: false,
    );
  }

  /// Change active resize mode while preserving target intent.
  void setMode(ResizeMode mode) {
    if (state.mode == mode) return;

    final newState = state.copyWith(mode: mode, clearError: true);

    if (!state.isSourceLoaded) {
      state = newState;
      return;
    }

    if (mode == ResizeMode.percentage) {
      final pct = (state.targetWidth / state.sourceWidth! * 100.0);
      state = newState.copyWith(percentage: double.parse(pct.toStringAsFixed(1)));
    } else if (mode == ResizeMode.preset) {
      // Pick default preset if none selected yet
      final preset = state.selectedPreset ?? ImagePreset.fullHd;
      selectPreset(preset, overrideMode: mode);
    } else {
      state = newState;
    }
  }

  /// Set target width. Auto-computes height if aspect ratio is locked.
  void setWidth(int width) {
    if (!state.isSourceLoaded) return;

    final clampedWidth = width.clamp(1, 100000);
    int newHeight = state.targetHeight;

    if (state.aspectRatioLocked && state.aspectRatio > 0) {
      newHeight = (clampedWidth / state.aspectRatio).round().clamp(1, 100000);
    }

    final pct = (clampedWidth / state.sourceWidth! * 100.0);

    state = state.copyWith(
      targetWidth: clampedWidth,
      targetHeight: newHeight,
      percentage: double.parse(pct.toStringAsFixed(1)),
      clearPreset: true,
      clearError: true,
    );
  }

  /// Set target height. Auto-computes width if aspect ratio is locked.
  void setHeight(int height) {
    if (!state.isSourceLoaded) return;

    final clampedHeight = height.clamp(1, 100000);
    int newWidth = state.targetWidth;

    if (state.aspectRatioLocked && state.aspectRatio > 0) {
      newWidth = (clampedHeight * state.aspectRatio).round().clamp(1, 100000);
    }

    final pct = (newWidth / state.sourceWidth! * 100.0);

    state = state.copyWith(
      targetWidth: newWidth,
      targetHeight: clampedHeight,
      percentage: double.parse(pct.toStringAsFixed(1)),
      clearPreset: true,
      clearError: true,
    );
  }

  /// Set scaling percentage.
  void setPercentage(double percent) {
    if (!state.isSourceLoaded) return;

    final clampedPct = percent.clamp(1.0, 1000.0);
    final newWidth = (state.sourceWidth! * clampedPct / 100.0).round().clamp(1, 100000);
    final newHeight = (state.sourceHeight! * clampedPct / 100.0).round().clamp(1, 100000);

    state = state.copyWith(
      percentage: clampedPct,
      targetWidth: newWidth,
      targetHeight: newHeight,
      clearPreset: true,
      clearError: true,
    );
  }

  /// Select a preset size.
  /// Spec requirement: Presets are a starting width when aspect ratio lock is ON.
  /// If unlocked, exact preset height applies.
  void selectPreset(ImagePreset preset, {ResizeMode? overrideMode}) {
    if (!state.isSourceLoaded) return;

    final targetW = preset.width;
    int targetH;

    if (state.aspectRatioLocked && state.aspectRatio > 0) {
      targetH = (targetW / state.aspectRatio).round().clamp(1, 100000);
    } else {
      targetH = preset.height;
    }

    final pct = (targetW / state.sourceWidth! * 100.0);

    state = state.copyWith(
      mode: overrideMode ?? ResizeMode.preset,
      selectedPreset: preset,
      targetWidth: targetW,
      targetHeight: targetH,
      percentage: double.parse(pct.toStringAsFixed(1)),
      clearError: true,
    );
  }

  /// Toggle aspect ratio lock state.
  void toggleAspectRatioLock() {
    final newLock = !state.aspectRatioLocked;

    if (!state.isSourceLoaded) {
      state = state.copyWith(aspectRatioLocked: newLock);
      return;
    }

    if (newLock && state.aspectRatio > 0) {
      // Re-align height to width based on original aspect ratio when locking
      int newH = (state.targetWidth / state.aspectRatio).round().clamp(1, 100000);
      if (state.mode == ResizeMode.preset && state.selectedPreset != null) {
        newH = (state.selectedPreset!.width / state.aspectRatio).round().clamp(1, 100000);
      }
      state = state.copyWith(
        aspectRatioLocked: true,
        targetHeight: newH,
        clearError: true,
      );
    } else {
      // When unlocking, if a preset was active, apply the preset's exact height
      int newH = state.targetHeight;
      if (state.mode == ResizeMode.preset && state.selectedPreset != null) {
        newH = state.selectedPreset!.height;
      }
      state = state.copyWith(
        aspectRatioLocked: false,
        targetHeight: newH,
        clearError: true,
      );
    }
  }

  /// Execute image resizing via background isolate worker.
  Future<void> resize() async {
    if (state.file == null || !state.isSourceLoaded) return;

    if (!state.isValidDimensions) {
      state = state.copyWith(
        errorMessage: "Minimum size is 10×10px",
      );
      return;
    }

    state = state.copyWith(isProcessing: true, clearError: true);

    _logService.logStarted('image_resize', 'resize',
        message: '${state.targetWidth}×${state.targetHeight}');

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
      var ext = p.extension(state.file!.name).toLowerCase();
      if (ext == '.webp') {
        // Fallback for WebP read-only support in image package
        ext = '.png';
      }

      final defaultOutputPath = p.join(outputDir, '${baseName}_resized$ext');

      final params = ImageResizeParams(
        inputBytes: inputBytes,
        sourceFileName: state.file!.name,
        targetWidth: state.targetWidth,
        targetHeight: state.targetHeight,
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageResizeWorker, params);

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        outputPath: result.outputPath,
        outputSize: result.outputSize,
      );

      _logService.logSuccess('image_resize', 'resize',
          message: 'output: ${p.basename(result.outputPath)}');
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to resize at this size on this device. Try a smaller target size.",
      );
      _logService.logError('image_resize', 'resize',
          message: 'out of memory');
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
      _logService.logError('image_resize', 'resize',
          message: 'file system error', errorDetail: e.toString());
    } catch (e) {
      await _tempFileManager.cleanupSession();
      final msg = e is FormatException ? e.message : "Resize failed. Please try again.";
      state = state.copyWith(
        isProcessing: false,
        errorMessage: msg,
      );
      _logService.logError('image_resize', 'resize',
          message: 'resize failed', errorDetail: e.toString());
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
    state = const ImageResizeState();
  }
}
