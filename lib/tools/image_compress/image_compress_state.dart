import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Compression modes available for Image Compress.
enum CompressionMode {
  qualityLevel,
  targetSizeRange,
}

/// Compression levels available for Quality Level mode.
enum CompressionLevel {
  low,
  medium,
  high,
}

/// Size units available for Target Size Range mode.
enum SizeUnit {
  kb,
  mb,
}

extension SizeUnitExtension on SizeUnit {
  String get displayName => name.toUpperCase();

  int toBytes(double value) {
    if (this == SizeUnit.mb) {
      return (value * 1024 * 1024).round();
    }
    return (value * 1024).round();
  }
}

/// Compression result classification.
enum CompressionResultType {
  normalSuccess,
  minimalReduction,
  outputLarger,
  inRangeSuccess,
  closestEffort,
  alreadyInRange,
  smallerThanMin,
}

class ImageCompressState {
  final PlatformFile? file;
  final Uint8List? thumbnailBytes;
  final String? detectedFormat;
  final int originalWidth;
  final int originalHeight;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final CompressionMode mode;
  final CompressionLevel level;
  final double minSizeValue;
  final SizeUnit minSizeUnit;
  final double maxSizeValue;
  final SizeUnit maxSizeUnit;
  final CompressionResultType? resultType;
  final bool isProcessing;
  final String? errorMessage;
  final String? outputPath;

  const ImageCompressState({
    this.file,
    this.thumbnailBytes,
    this.detectedFormat,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.originalSizeBytes = 0,
    this.compressedSizeBytes = 0,
    this.mode = CompressionMode.qualityLevel,
    this.level = CompressionLevel.medium,
    this.minSizeValue = 100.0,
    this.minSizeUnit = SizeUnit.kb,
    this.maxSizeValue = 500.0,
    this.maxSizeUnit = SizeUnit.kb,
    this.resultType,
    this.isProcessing = false,
    this.errorMessage,
    this.outputPath,
  });

  bool get isLoaded => file != null && originalSizeBytes > 0 && originalWidth > 0;

  /// Hard floor of 5 KB (5,120 bytes)
  static const int minFloorBytes = 5 * 1024;

  int get minSizeBytes {
    final rawBytes = minSizeUnit.toBytes(minSizeValue);
    return rawBytes < minFloorBytes ? minFloorBytes : rawBytes;
  }

  int get maxSizeBytes => maxSizeUnit.toBytes(maxSizeValue);

  bool get isMinBelowFloor {
    final rawBytes = minSizeUnit.toBytes(minSizeValue);
    return rawBytes < minFloorBytes;
  }

  bool get isRangeValid => maxSizeBytes > minSizeBytes;

  double get reductionPercentage {
    if (originalSizeBytes <= 0 || compressedSizeBytes <= 0) return 0;
    if (compressedSizeBytes >= originalSizeBytes) return 0;
    final diff = originalSizeBytes - compressedSizeBytes;
    return (diff / originalSizeBytes * 100);
  }

  String get formattedOriginalSize => formatBytes(originalSizeBytes);
  String get formattedCompressedSize => formatBytes(compressedSizeBytes);
  String get formattedMinTargetSize => formatBytes(minSizeBytes);
  String get formattedMaxTargetSize => formatBytes(maxSizeBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = (log(bytes) / log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    final num = bytes / pow(1024, i);
    return '${num.toStringAsFixed(num < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  ImageCompressState copyWith({
    PlatformFile? file,
    bool clearFile = false,
    Uint8List? thumbnailBytes,
    bool clearThumbnail = false,
    String? detectedFormat,
    int? originalWidth,
    int? originalHeight,
    int? originalSizeBytes,
    int? compressedSizeBytes,
    CompressionMode? mode,
    CompressionLevel? level,
    double? minSizeValue,
    SizeUnit? minSizeUnit,
    double? maxSizeValue,
    SizeUnit? maxSizeUnit,
    CompressionResultType? resultType,
    bool clearResultType = false,
    bool? isProcessing,
    String? errorMessage,
    bool clearError = false,
    String? outputPath,
    bool clearOutput = false,
  }) {
    return ImageCompressState(
      file: clearFile ? null : (file ?? this.file),
      thumbnailBytes: clearThumbnail ? null : (thumbnailBytes ?? this.thumbnailBytes),
      detectedFormat: detectedFormat ?? this.detectedFormat,
      originalWidth: originalWidth ?? this.originalWidth,
      originalHeight: originalHeight ?? this.originalHeight,
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      compressedSizeBytes: compressedSizeBytes ?? this.compressedSizeBytes,
      mode: mode ?? this.mode,
      level: level ?? this.level,
      minSizeValue: minSizeValue ?? this.minSizeValue,
      minSizeUnit: minSizeUnit ?? this.minSizeUnit,
      maxSizeValue: maxSizeValue ?? this.maxSizeValue,
      maxSizeUnit: maxSizeUnit ?? this.maxSizeUnit,
      resultType: clearResultType ? null : (resultType ?? this.resultType),
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      outputPath: clearOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
