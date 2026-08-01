import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import 'image_crop_rotate_state.dart';

/// Provider for ImageCropRotateController.
final imageCropRotateControllerProvider = StateNotifierProvider.autoDispose<
    ImageCropRotateController, ImageCropRotateState>(
  (ref) => ImageCropRotateController(FileService()),
);

/// Parameters passed to background isolate worker for crop and rotate.
class ImageCropRotateParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final int rotation;
  final Rect cropRect;
  final String outputPath;

  ImageCropRotateParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.rotation,
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

  // Step 2: Crop selection in rotated image coordinate space
  final imgW = decoded.width;
  final imgH = decoded.height;

  final clampX = params.cropRect.left.round().clamp(0, imgW - 1);
  final clampY = params.cropRect.top.round().clamp(0, imgH - 1);
  final clampW = params.cropRect.width.round().clamp(1, imgW - clampX);
  final clampH = params.cropRect.height.round().clamp(1, imgH - clampY);

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

  ImageCropRotateController(this._fileService)
      : super(const ImageCropRotateState());

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
      cropRect: defaultCrop,
      aspectRatioPreset: AspectRatioPreset.free,
      rotationResetNoticeVisible: false,
      isProcessing: false,
    );
  }

  /// Advance rotation 90° clockwise (0° → 90° → 180° → 270° → 0°).
  /// Resets crop selection to full bounds of the new orientation.
  void rotate() {
    if (!state.isLoaded) return;

    final newRotation = (state.rotation + 90) % 360;
    final newCurrentW = (newRotation == 90 || newRotation == 270)
        ? state.originalHeight
        : state.originalWidth;
    final newCurrentH = (newRotation == 90 || newRotation == 270)
        ? state.originalWidth
        : state.originalHeight;

    var newCrop = Rect.fromLTWH(
        0, 0, newCurrentW.toDouble(), newCurrentH.toDouble());

    // If an aspect ratio lock is active, recalculate full-fit crop for new orientation
    final targetRatio = state.aspectRatioPreset.getRatio(
      newCurrentW.toDouble(),
      newCurrentH.toDouble(),
    );
    if (targetRatio != null) {
      newCrop = _recalculateCropForRatio(
        targetRatio,
        newCrop.center,
        newCurrentW.toDouble(),
        newCurrentH.toDouble(),
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
  /// Validates minimum size (10×10px floor) and clamps to current orientation bounds.
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

    Rect updatedRect = state.cropRect;
    if (targetRatio != null) {
      updatedRect = _recalculateCropForRatio(
        targetRatio,
        state.cropRect.center,
        currentW,
        currentH,
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

  /// Recalculate crop rect of `targetRatio` centered at `center` inside bounds `(maxW, maxH)`.
  Rect _recalculateCropForRatio(
    double targetRatio,
    Offset center,
    double maxW,
    double maxH,
  ) {
    double rectW;
    double rectH;

    if (maxW / maxH > targetRatio) {
      rectH = maxH;
      rectW = rectH * targetRatio;
    } else {
      rectW = maxW;
      rectH = rectW / targetRatio;
    }

    double left = center.dx - rectW / 2;
    double top = center.dy - rectH / 2;

    // Clamp to canvas bounds
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (left + rectW > maxW) left = maxW - rectW;
    if (top + rectH > maxH) top = maxH - rectH;

    return Rect.fromLTWH(left, top, rectW, rectH);
  }

  /// Helper to clamp rect within current orientation image bounds and enforce 10×10px floor.
  Rect? _clampAndValidateRect(Rect rect) {
    final maxW = state.currentWidth.toDouble();
    final maxH = state.currentHeight.toDouble();

    final left = rect.left.clamp(0.0, maxW);
    final top = rect.top.clamp(0.0, maxH);
    final right = rect.right.clamp(0.0, maxW);
    final bottom = rect.bottom.clamp(0.0, maxH);

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

  /// Execute rotation + crop off the UI thread via background isolate worker.
  Future<void> apply() async {
    if (state.file == null || !state.isLoaded) return;

    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearOutput: true,
    );

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
        cropRect: state.cropRect,
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageCropRotateWorker, params);

      state = state.copyWith(
        isProcessing: false,
        outputPath: result.outputPath,
        outputSizeBytes: result.outputSize,
      );
    } on OutOfMemoryError {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to crop on this device.",
      );
    } on FileSystemException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage:
            "Couldn't save the file — ${e.message}. Try a different location.",
      );
    } catch (e) {
      final msg = e is FormatException
          ? e.message
          : "Crop & rotate failed. Please try again.";
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
    state = const ImageCropRotateState();
  }
}
