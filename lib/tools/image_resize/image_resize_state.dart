import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

/// Available resize modes for the Image Resize tool.
enum ResizeMode {
  exactDimensions,
  percentage,
  preset,
}

/// Standard predefined image dimension presets.
enum ImagePreset {
  hd('HD', 1280, 720),
  fullHd('Full HD', 1920, 1080),
  fourK('4K', 3840, 2160),
  square('Square (social)', 1080, 1080),
  story('Story / Portrait (social)', 1080, 1920),
  webBanner('Web banner', 1200, 630);

  final String label;
  final int width;
  final int height;

  const ImagePreset(this.label, this.width, this.height);
}

/// Immutable state container for ImageResizeController.
class ImageResizeState {
  final PlatformFile? file;
  final String? detectedFormat;
  final int? sourceWidth;
  final int? sourceHeight;
  final int? sourceFileSize;
  final Uint8List? thumbnailBytes;

  final ResizeMode mode;
  final int targetWidth;
  final int targetHeight;
  final double percentage;
  final ImagePreset? selectedPreset;
  final bool aspectRatioLocked;

  final bool isProcessing;
  final String? outputPath;
  final int? outputSize;
  final String? errorMessage;

  const ImageResizeState({
    this.file,
    this.detectedFormat,
    this.sourceWidth,
    this.sourceHeight,
    this.sourceFileSize,
    this.thumbnailBytes,
    this.mode = ResizeMode.exactDimensions,
    this.targetWidth = 0,
    this.targetHeight = 0,
    this.percentage = 100.0,
    this.selectedPreset,
    this.aspectRatioLocked = true,
    this.isProcessing = false,
    this.outputPath,
    this.outputSize,
    this.errorMessage,
  });

  bool get isSourceLoaded => file != null && sourceWidth != null && sourceHeight != null;

  /// Returns true if target dimensions exceed original source dimensions on either axis.
  bool get isUpscaling {
    if (!isSourceLoaded) return false;
    return targetWidth > sourceWidth! || targetHeight > sourceHeight!;
  }

  /// Returns true if target dimensions are at or above minimum sane floor (10x10px).
  bool get isValidDimensions => targetWidth >= 10 && targetHeight >= 10;

  /// Returns true if target dimensions drop below the sane minimum floor (10x10px).
  bool get isBelowMinFloor {
    if (!isSourceLoaded) return false;
    return targetWidth < 10 || targetHeight < 10;
  }

  /// Source aspect ratio (width / height).
  double get aspectRatio {
    if (sourceWidth != null && sourceHeight != null && sourceHeight! > 0) {
      return sourceWidth! / sourceHeight!;
    }
    return 1.0;
  }

  ImageResizeState copyWith({
    PlatformFile? file,
    String? detectedFormat,
    int? sourceWidth,
    int? sourceHeight,
    int? sourceFileSize,
    Uint8List? thumbnailBytes,
    ResizeMode? mode,
    int? targetWidth,
    int? targetHeight,
    double? percentage,
    ImagePreset? selectedPreset,
    bool clearPreset = false,
    bool? aspectRatioLocked,
    bool? isProcessing,
    String? outputPath,
    int? outputSize,
    String? errorMessage,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return ImageResizeState(
      file: file ?? this.file,
      detectedFormat: detectedFormat ?? this.detectedFormat,
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
      sourceFileSize: sourceFileSize ?? this.sourceFileSize,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      mode: mode ?? this.mode,
      targetWidth: targetWidth ?? this.targetWidth,
      targetHeight: targetHeight ?? this.targetHeight,
      percentage: percentage ?? this.percentage,
      selectedPreset: clearPreset ? null : (selectedPreset ?? this.selectedPreset),
      aspectRatioLocked: aspectRatioLocked ?? this.aspectRatioLocked,
      isProcessing: isProcessing ?? this.isProcessing,
      outputPath: clearResult ? null : (outputPath ?? this.outputPath),
      outputSize: clearResult ? null : (outputSize ?? this.outputSize),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
