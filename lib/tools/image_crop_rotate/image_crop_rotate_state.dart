import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

/// Aspect ratio preset options for crop selection.
enum AspectRatioPreset {
  free,
  original,
  square,
  fourThree,
  sixteenNine,
  threeTwo,
}

extension AspectRatioPresetExtension on AspectRatioPreset {
  String get label {
    switch (this) {
      case AspectRatioPreset.free:
        return 'Free';
      case AspectRatioPreset.original:
        return 'Original';
      case AspectRatioPreset.square:
        return '1:1 Square';
      case AspectRatioPreset.fourThree:
        return '4:3';
      case AspectRatioPreset.sixteenNine:
        return '16:9';
      case AspectRatioPreset.threeTwo:
        return '3:2';
    }
  }

  /// Target aspect ratio (width / height), or null if free.
  double? getRatio(double currentImageWidth, double currentImageHeight) {
    switch (this) {
      case AspectRatioPreset.free:
        return null;
      case AspectRatioPreset.original:
        if (currentImageHeight == 0) return 1.0;
        return currentImageWidth / currentImageHeight;
      case AspectRatioPreset.square:
        return 1.0;
      case AspectRatioPreset.fourThree:
        return 4.0 / 3.0;
      case AspectRatioPreset.sixteenNine:
        return 16.0 / 9.0;
      case AspectRatioPreset.threeTwo:
        return 3.0 / 2.0;
    }
  }
}

/// Immutable UI state for Image Crop & Rotate feature.
class ImageCropRotateState {
  final PlatformFile? file;
  final String? detectedFormat;
  final int originalWidth;
  final int originalHeight;
  final int originalSizeBytes;
  final Uint8List? thumbnailBytes;
  final int rotation; // 0, 90, 180, 270 degrees clockwise
  final Rect cropRect; // In current rotated orientation's pixel space
  final AspectRatioPreset aspectRatioPreset;
  final bool rotationResetNoticeVisible;
  final bool isProcessing;
  final String? outputPath;
  final int? outputSizeBytes;
  final String? errorMessage;

  const ImageCropRotateState({
    this.file,
    this.detectedFormat,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.originalSizeBytes = 0,
    this.thumbnailBytes,
    this.rotation = 0,
    this.cropRect = Rect.zero,
    this.aspectRatioPreset = AspectRatioPreset.free,
    this.rotationResetNoticeVisible = false,
    this.isProcessing = false,
    this.outputPath,
    this.outputSizeBytes,
    this.errorMessage,
  });

  bool get isLoaded => file != null && originalWidth > 0 && originalHeight > 0;
  bool get isSuccess => outputPath != null && outputSizeBytes != null;

  /// Width in current orientation (swaps W and H at 90° / 270°).
  int get currentWidth =>
      (rotation == 90 || rotation == 270) ? originalHeight : originalWidth;

  /// Height in current orientation (swaps W and H at 90° / 270°).
  int get currentHeight =>
      (rotation == 90 || rotation == 270) ? originalWidth : originalHeight;

  int get outputWidth => cropRect.width.round();
  int get outputHeight => cropRect.height.round();

  /// True if user modified rotation or adjusted crop away from full bounds.
  bool get hasUnsavedChanges {
    if (!isLoaded) return false;
    if (rotation != 0) return true;
    final isFullBounds = cropRect.left == 0 &&
        cropRect.top == 0 &&
        cropRect.width.round() == currentWidth &&
        cropRect.height.round() == currentHeight;
    return !isFullBounds;
  }

  ImageCropRotateState copyWith({
    PlatformFile? file,
    String? detectedFormat,
    int? originalWidth,
    int? originalHeight,
    int? originalSizeBytes,
    Uint8List? thumbnailBytes,
    int? rotation,
    Rect? cropRect,
    AspectRatioPreset? aspectRatioPreset,
    bool? rotationResetNoticeVisible,
    bool? isProcessing,
    String? outputPath,
    int? outputSizeBytes,
    String? errorMessage,
    bool clearError = false,
    bool clearOutput = false,
    bool clearThumbnail = false,
  }) {
    return ImageCropRotateState(
      file: file ?? this.file,
      detectedFormat: detectedFormat ?? this.detectedFormat,
      originalWidth: originalWidth ?? this.originalWidth,
      originalHeight: originalHeight ?? this.originalHeight,
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      thumbnailBytes:
          clearThumbnail ? null : (thumbnailBytes ?? this.thumbnailBytes),
      rotation: rotation ?? this.rotation,
      cropRect: cropRect ?? this.cropRect,
      aspectRatioPreset: aspectRatioPreset ?? this.aspectRatioPreset,
      rotationResetNoticeVisible:
          rotationResetNoticeVisible ?? this.rotationResetNoticeVisible,
      isProcessing: isProcessing ?? this.isProcessing,
      outputPath: clearOutput ? null : (outputPath ?? this.outputPath),
      outputSizeBytes:
          clearOutput ? null : (outputSizeBytes ?? this.outputSizeBytes),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
