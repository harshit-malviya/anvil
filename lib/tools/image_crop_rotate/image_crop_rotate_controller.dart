import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'image_crop_rotate_state.dart';

/// Provider for ImageCropRotateController.
final imageCropRotateControllerProvider = StateNotifierProvider.autoDispose<
    ImageCropRotateController, ImageCropRotateState>(
  (ref) => ImageCropRotateController(
    FileService(),
    null,
    ref.read(appLogServiceProvider),
  ),
);

/// Parameters passed to background isolate worker for crop and rotate.
class ImageCropRotateParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final int rotation;
  final double fineRotationAngle;
  final Rect cropRect;
  final String outputPath;

  ImageCropRotateParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.rotation,
    required this.fineRotationAngle,
    required this.cropRect,
    required this.outputPath,
  });
}

/// Result returned from background isolate crop & rotate worker.
class ImageCropRotateResult {
  final String outputPath;
  final int outputSize;

  ImageCropRotateResult({
    required this.outputPath,
    required this.outputSize,
  });
}

/// Top-level isolate worker for CPU-bound crop & rotate pixel processing.
Future<ImageCropRotateResult> isolateImageCropRotateWorker(
    ImageCropRotateParams params) async {
  img.Image? decoded = img.decodeImage(params.inputBytes);
  if (decoded == null) {
    throw const FormatException("This image couldn't be read. File may be corrupt.");
  }

  // Bake EXIF orientation first so baseline orientation is upright
  decoded = img.bakeOrientation(decoded);

  // Animated sources: extract first frame
  if (decoded.numFrames > 1) {
    decoded = decoded.frames.first;
  }

  // Step 1: User rotation (90 degree steps clockwise)
  if (params.rotation != 0) {
    decoded = img.copyRotate(decoded, angle: params.rotation);
  }

  final origW = decoded.width;
  final origH = decoded.height;

  // Step 2: Fine-angle rotation (Straighten) with cubic interpolation
  if (params.fineRotationAngle != 0.0) {
    decoded = img.copyRotate(
      decoded,
      angle: params.fineRotationAngle,
      interpolation: img.Interpolation.cubic,
    );
  }

  final bboxW = decoded.width;
  final bboxH = decoded.height;

  // Coordinate shift between original 90°-rotated space and fine-rotated bounding box
  final shiftX = (bboxW - origW) / 2.0;
  final shiftY = (bboxH - origH) / 2.0;

  // Step 3: Crop selection in fine-rotated coordinate space
  final clampX = (params.cropRect.left + shiftX).round().clamp(0, bboxW - 1);
  final clampY = (params.cropRect.top + shiftY).round().clamp(0, bboxH - 1);
  final clampW = params.cropRect.width.round().clamp(1, bboxW - clampX);
  final clampH = params.cropRect.height.round().clamp(1, bboxH - clampY);

  decoded = img.copyCrop(
    decoded,
    x: clampX,
    y: clampY,
    width: clampW,
    height: clampH,
  );

  final ext = p.extension(params.sourceFileName).toLowerCase();
  Uint8List encodedBytes;

  switch (ext) {
    case '.jpg':
    case '.jpeg':
      encodedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      break;
    case '.png':
      encodedBytes = Uint8List.fromList(img.encodePng(decoded));
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

  return ImageCropRotateResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
  );
}

class ImageCropRotateController extends StateNotifier<ImageCropRotateState> {
  final FileService _fileService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;

  ImageCropRotateController(
    this._fileService, [
    TempFileManager? tempFileManager,
    AppLogService? logService,
  ])  : _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const ImageCropRotateState());

  /// Load and validate selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearOutput: true,
    );

    final ext = p.extension(platformFile.name).toLowerCase();
    final allowedExts = [
      '.png',
      '.jpg',
      '.jpeg',
      '.bmp',
      '.gif',
      '.tiff',
      '.webp'
    ];
    if (!allowedExts.contains(ext)) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage:
            "This file type isn't supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF, WebP.",
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
            errorMessage:
                "Could not read '${platformFile.name}': permission denied.",
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

    // Bake EXIF orientation for consistent preview & baseline dimension readings
    decoded = img.bakeOrientation(decoded);

    final formatName = ext.replaceAll('.', '').toUpperCase();

    // Create thumbnail
    img.Image thumbImg = decoded;
    if (thumbImg.numFrames > 1) {
      thumbImg = thumbImg.frames.first;
    }
    if (thumbImg.width > 600 || thumbImg.height > 600) {
      thumbImg = thumbImg.width >= thumbImg.height
          ? img.copyResize(thumbImg, width: 600, maintainAspect: true)
          : img.copyResize(thumbImg, height: 600, maintainAspect: true);
    }
    final thumbBytes =
        Uint8List.fromList(img.encodeJpg(thumbImg, quality: 85));

    final origW = decoded.width;
    final origH = decoded.height;
    final defaultCrop = Rect.fromLTWH(0, 0, origW.toDouble(), origH.toDouble());

    state = state.copyWith(
      file: platformFile,
      detectedFormat: formatName,
      originalWidth: origW,
      originalHeight: origH,
      originalSizeBytes: bytes.length,
      thumbnailBytes: thumbBytes,
      rotation: 0,
      fineRotationAngle: 0.0,
      cropRect: defaultCrop,
      aspectRatioPreset: AspectRatioPreset.free,
      rotationResetNoticeVisible: false,
      isProcessing: false,
    );
  }

  /// Set fine-angle Straighten rotation (−45° to +45°).
  /// Automatically shrinks/recenters crop selection to fit inside new inscribed bounds.
  void setFineRotationAngle(double degrees) {
    if (!state.isLoaded) return;

    final clampedAngle = degrees.clamp(-45.0, 45.0);
    final newState = state.copyWith(fineRotationAngle: clampedAngle);

    // Straighten is typically many small incremental slider drags, not one discrete action;
    // resetting the crop on every tick would make fine adjustment unusable.
    // This is why Straighten shrinks/recenters the crop rect to stay within inscribed bounds
    // rather than resetting it like 90° rotation does.
    final bounds = newState.inscribedCropBounds;
    final adjustedCrop = _adjustCropRectForInscribedBounds(
      state.cropRect,
      state.aspectRatioPreset,
      bounds,
      newState.currentWidth.toDouble(),
      newState.currentHeight.toDouble(),
    );

    state = newState.copyWith(
      cropRect: adjustedCrop,
      clearError: true,
    );
  }

  /// Reset fine-angle Straighten rotation back to 0°.
  void resetFineRotation() {
    if (!state.isLoaded) return;
    setFineRotationAngle(0.0);
  }

  /// Advance rotation 90° clockwise (0° → 90° → 180° → 270° → 0°).
  /// Resets crop selection to full inscribed bounds of the new orientation.
  void rotate() {
    if (!state.isLoaded) return;

    final newRotation = (state.rotation + 90) % 360;
    final newCurrentW = (newRotation == 90 || newRotation == 270)
        ? state.originalHeight
        : state.originalWidth;
    final newCurrentH = (newRotation == 90 || newRotation == 270)
        ? state.originalWidth
        : state.originalHeight;

    final tempState = state.copyWith(
      rotation: newRotation,
      originalWidth: state.originalWidth,
      originalHeight: state.originalHeight,
    );
    final bounds = tempState.inscribedCropBounds;

    var newCrop = bounds;

    // If an aspect ratio lock is active, recalculate full-fit crop for new orientation
    final targetRatio = state.aspectRatioPreset.getRatio(
      newCurrentW.toDouble(),
      newCurrentH.toDouble(),
    );
    if (targetRatio != null) {
      newCrop = _recalculateCropForRatio(
        targetRatio,
        bounds.center,
        bounds,
      );
    }

    state = state.copyWith(
      rotation: newRotation,
      cropRect: newCrop,
      rotationResetNoticeVisible: true,
      clearError: true,
    );
  }

  /// Update crop selection rect in current rotated image pixel space.
  /// Validates minimum size (10×10px floor) and clamps to current inscribed bounds.
  bool setCropRect(Rect rectInPixelSpace) {
    if (!state.isLoaded) return false;

    final clamped = _clampAndValidateRect(rectInPixelSpace);
    if (clamped == null) {
      state = state.copyWith(
        errorMessage: "Crop selection is too small. Minimum size is 10×10 pixels.",
      );
      return false;
    }

    state = state.copyWith(
      cropRect: clamped,
      rotationResetNoticeVisible: false,
      clearError: true,
    );
    return true;
  }

  /// Change aspect ratio preset and recalculate current crop selection.
  void setAspectRatioPreset(AspectRatioPreset preset) {
    if (!state.isLoaded) return;
    if (state.aspectRatioPreset == preset) return;

    final currentW = state.currentWidth.toDouble();
    final currentH = state.currentHeight.toDouble();
    final targetRatio = preset.getRatio(currentW, currentH);
    final bounds = state.inscribedCropBounds;

    Rect updatedRect = state.cropRect;
    if (targetRatio != null) {
      updatedRect = _recalculateCropForRatio(
        targetRatio,
        state.cropRect.center,
        bounds,
      );
    }

    state = state.copyWith(
      aspectRatioPreset: preset,
      cropRect: updatedRect,
      rotationResetNoticeVisible: false,
      clearError: true,
    );
  }

  /// Dismiss the inline notice about rotation resetting crop selection.
  void dismissRotationResetNotice() {
    state = state.copyWith(rotationResetNoticeVisible: false);
  }

  /// Recalculate crop rect of `targetRatio` centered at `center` inside `bounds`.
  Rect _recalculateCropForRatio(
    double targetRatio,
    Offset center,
    Rect bounds,
  ) {
    double rectW;
    double rectH;

    if (bounds.width / bounds.height > targetRatio) {
      rectH = bounds.height;
      rectW = rectH * targetRatio;
    } else {
      rectW = bounds.width;
      rectH = rectW / targetRatio;
    }

    double left = center.dx - rectW / 2;
    double top = center.dy - rectH / 2;

    // Clamp to bounds
    if (left < bounds.left) left = bounds.left;
    if (top < bounds.top) top = bounds.top;
    if (left + rectW > bounds.right) left = bounds.right - rectW;
    if (top + rectH > bounds.bottom) top = bounds.bottom - rectH;

    return Rect.fromLTWH(left, top, rectW, rectH);
  }

  /// Helper to shrink/recenter crop rect to fit inside new inscribed bounds.
  Rect _adjustCropRectForInscribedBounds(
    Rect currentRect,
    AspectRatioPreset preset,
    Rect bounds,
    double currentW,
    double currentH,
  ) {
    final targetRatio = preset.getRatio(currentW, currentH);

    double width = currentRect.width;
    double height = currentRect.height;

    if (targetRatio != null) {
      if (width / height > targetRatio) {
        width = height * targetRatio;
      } else {
        height = width / targetRatio;
      }
    }

    // Clamp size to bounds
    if (width > bounds.width) {
      width = bounds.width;
      if (targetRatio != null) {
        height = width / targetRatio;
      }
    }
    if (height > bounds.height) {
      height = bounds.height;
      if (targetRatio != null) {
        width = height * targetRatio;
      }
    }

    width = max(width, 10.0);
    height = max(height, 10.0);

    double left = currentRect.center.dx - width / 2.0;
    double top = currentRect.center.dy - height / 2.0;

    if (left < bounds.left) left = bounds.left;
    if (top < bounds.top) top = bounds.top;
    if (left + width > bounds.right) left = bounds.right - width;
    if (top + height > bounds.bottom) top = bounds.bottom - height;

    return Rect.fromLTWH(left, top, width, height);
  }

  /// Helper to clamp rect within current inscribed bounds and enforce 10×10px floor.
  Rect? _clampAndValidateRect(Rect rect) {
    final bounds = state.inscribedCropBounds;

    final left = rect.left.clamp(bounds.left, bounds.right);
    final top = rect.top.clamp(bounds.top, bounds.bottom);
    final right = rect.right.clamp(bounds.left, bounds.right);
    final bottom = rect.bottom.clamp(bounds.top, bounds.bottom);

    final width = (right - left).abs();
    final height = (bottom - top).abs();

    if (width < 10.0 || height < 10.0) {
      return null;
    }

    return Rect.fromLTWH(
      min(left, right),
      min(top, bottom),
      width,
      height,
    );
  }

  /// Execute rotation + fine rotation + crop off the UI thread via background isolate worker.
  Future<void> apply() async {
    if (state.file == null || !state.isLoaded) return;

    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearOutput: true,
    );

    _logService.logStarted('image_crop_rotate', 'apply',
        message: 'rotation: ${state.rotation}°, fine: ${state.fineRotationAngle}°');

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

      final defaultDir = await _fileService.getDefaultOutputDirectory(
        sourceFilePath: state.file!.path,
      );
      final outputDir = defaultDir.path;

      final baseName = p.basenameWithoutExtension(state.file!.name);
      final ext = p.extension(state.file!.name).toLowerCase();
      final defaultOutputPath = p.join(outputDir, '${baseName}_edited$ext');

      final params = ImageCropRotateParams(
        inputBytes: inputBytes,
        sourceFileName: state.file!.name,
        rotation: state.rotation,
        fineRotationAngle: state.fineRotationAngle,
        cropRect: state.cropRect,
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageCropRotateWorker, params);

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        outputPath: result.outputPath,
        outputSizeBytes: result.outputSize,
      );

      _logService.logSuccess('image_crop_rotate', 'apply',
          message: 'output: ${p.basename(result.outputPath)}');
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to crop on this device.",
      );
      _logService.logError('image_crop_rotate', 'apply',
          message: 'out of memory');
      return;
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage:
            "Couldn't save the file — ${e.message}. Try a different location.",
      );
      _logService.logError('image_crop_rotate', 'apply',
          message: 'file system error', errorDetail: e.toString());
      return;
    } catch (e) {
      await _tempFileManager.cleanupSession();
      final msg = e is FormatException
          ? e.message
          : "Crop & rotate failed. Please try again.";
      state = state.copyWith(
        isProcessing: false,
        errorMessage: msg,
      );
      _logService.logError('image_crop_rotate', 'apply',
          message: 'crop/rotate failed', errorDetail: e.toString());
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

  /// User action: Share output file.
  Future<void> shareFile() async {
    if (state.outputPath != null) {
      await _fileService.shareFile(state.outputPath!);
    }
  }

  /// Clear active error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Reset controller back to initial state.
  void reset() {
    _tempFileManager.cleanupSession();
    state = const ImageCropRotateState();
  }
}

