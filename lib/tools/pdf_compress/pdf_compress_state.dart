import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum CompressionLevel {
  low,
  medium,
  high,
}

enum CompressionResultType {
  normalSuccess,
  minimalReduction,
  outputLarger,
}

class PdfCompressState {
  final PlatformFile? file;
  final Uint8List? fileBytes;
  final int originalSizeBytes;
  final int compressedSizeBytes;
  final CompressionLevel level;
  final CompressionResultType? resultType;
  final bool isProcessing;
  final String? progressMessage;
  final String? errorMessage;
  final String? outputPath;

  const PdfCompressState({
    this.file,
    this.fileBytes,
    this.originalSizeBytes = 0,
    this.compressedSizeBytes = 0,
    this.level = CompressionLevel.medium,
    this.resultType,
    this.isProcessing = false,
    this.progressMessage,
    this.errorMessage,
    this.outputPath,
  });

  bool get isLoaded => file != null && originalSizeBytes > 0;

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

  PdfCompressState copyWith({
    PlatformFile? file,
    Uint8List? fileBytes,
    int? originalSizeBytes,
    int? compressedSizeBytes,
    CompressionLevel? level,
    CompressionResultType? resultType,
    bool resetResultType = false,
    bool? isProcessing,
    String? progressMessage,
    bool resetProgressMessage = false,
    String? errorMessage,
    bool resetError = false,
    String? outputPath,
    bool resetOutput = false,
  }) {
    return PdfCompressState(
      file: file ?? this.file,
      fileBytes: fileBytes ?? this.fileBytes,
      originalSizeBytes: originalSizeBytes ?? this.originalSizeBytes,
      compressedSizeBytes: compressedSizeBytes ?? this.compressedSizeBytes,
      level: level ?? this.level,
      resultType: resetResultType ? null : (resultType ?? this.resultType),
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage
          ? null
          : (progressMessage ?? this.progressMessage),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
