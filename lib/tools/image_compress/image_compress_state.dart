import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Compression levels available for Image Compress.
enum CompressionLevel {
  low,
  medium,
  high,
}

/// Compression result classification.
enum CompressionResultType {
  normalSuccess,
  minimalReduction,
  outputLarger,
}

class ImageCompressState {
  final PlatformFile? file;
  final Uint8List? thumbnailBytes;
  final String? detectedFormat;
  final int originalWidth;
  final int originalHeight;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final CompressionLevel level;
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
    this.level = CompressionLevel.medium,
    this.resultType,
    this.isProcessing = false,
    this.errorMessage,
    this.outputPath,
  });

  bool get isLoaded => file != null && originalSizeBytes > 0 && originalWidth > 0;

  double get reductionPercentage {
    if (originalSizeBytes <= 0 || compressedSizeBytes <= 0) return 0;
    if (compressedSizeBytes >= originalSizeBytes) return 0;
    final diff = originalSizeBytes - compressedSizeBytes;
    return (diff / originalSizeBytes * 100);
  }

  String get formattedOriginalSize => formatBytes(originalSizeBytes);
  String get formattedCompressedSize => formatBytes(compressedSizeBytes);

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
    CompressionLevel? level,
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
      level: level ?? this.level,
      resultType: clearResultType ? null : (resultType ?? this.resultType),
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      outputPath: clearOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
