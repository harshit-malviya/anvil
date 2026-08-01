import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';

/// Style of redaction applied to marked regions.
enum RedactionStyle {
  pixelate,
  blur,
  solidBlock,
}

/// Intensity level for pixelate or blur styles.
enum RedactionIntensity {
  small, // Pixelate Small / Blur Light
  medium, // Pixelate Medium / Blur Medium
  large, // Pixelate Large / Blur Strong
}

/// A rectangular region marked for redaction in source image pixel coordinates.
class RedactionRegion {
  final String id;
  final Rect rect; // Coordinates in source image pixel space (0..width, 0..height)

  const RedactionRegion({
    required this.id,
    required this.rect,
  });

  RedactionRegion copyWith({
    String? id,
    Rect? rect,
  }) {
    return RedactionRegion(
      id: id ?? this.id,
      rect: rect ?? this.rect,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RedactionRegion && other.id == id && other.rect == rect;
  }

  @override
  int get hashCode => Object.hash(id, rect);
}

/// Immutable state for ImageBlurController.
class ImageBlurState {
  final PlatformFile? file;
  final String? detectedFormat;
  final int originalWidth;
  final int originalHeight;
  final int originalSizeBytes;
  final Uint8List? thumbnailBytes;
  final List<RedactionRegion> regions;
  final RedactionStyle style;
  final RedactionIntensity intensity;
  final Color solidBlockColor;
  final bool isProcessing;
  final String? errorMessage;
  final String? outputPath;
  final int outputSizeBytes;

  const ImageBlurState({
    this.file,
    this.detectedFormat,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.originalSizeBytes = 0,
    this.thumbnailBytes,
    this.regions = const [],
    this.style = RedactionStyle.pixelate,
    this.intensity = RedactionIntensity.medium,
    this.solidBlockColor = Colors.black,
    this.isProcessing = false,
    this.errorMessage,
    this.outputPath,
    this.outputSizeBytes = 0,
  });

  bool get isLoaded => file != null && originalWidth > 0 && originalHeight > 0;
  bool get hasRegions => regions.isNotEmpty;
  int get regionCount => regions.length;
  bool get isBlurStyle => style == RedactionStyle.blur;

  ImageBlurState copyWith({
    PlatformFile? file,
    String? detectedFormat,
    int? originalWidth,
    int? originalHeight,
    int? originalSizeBytes,
    Uint8List? thumbnailBytes,
    List<RedactionRegion>? regions,
    RedactionStyle? style,
    RedactionIntensity? intensity,
    Color? solidBlockColor,
    bool? isProcessing,
    String? errorMessage,
    bool clearError = false,
    String? outputPath,
    bool clearOutput = false,
    int? outputSizeBytes,
  }) {
    return ImageBlurState(
      file: file ?? this.file,
      detectedFormat: detectedFormat ?? this.detectedFormat,
      originalWidth: originalWidth ?? this.originalWidth,
      originalHeight: originalHeight ?? this.originalHeight,
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      regions: regions ?? this.regions,
      style: style ?? this.style,
      intensity: intensity ?? this.intensity,
      solidBlockColor: solidBlockColor ?? this.solidBlockColor,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      outputPath: clearOutput ? null : (outputPath ?? this.outputPath),
      outputSizeBytes: outputSizeBytes ?? this.outputSizeBytes,
    );
  }
}
