import 'package:flutter/foundation.dart';

@immutable
class PdfMergeItem {
  final String id;
  final String? path;
  final String name;
  final int sizeBytes;
  final int pageCount;
  final Uint8List bytes;

  const PdfMergeItem({
    required this.id,
    this.path,
    required this.name,
    required this.sizeBytes,
    required this.pageCount,
    required this.bytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    } else if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  PdfMergeItem copyWith({
    String? id,
    String? path,
    String? name,
    int? sizeBytes,
    int? pageCount,
    Uint8List? bytes,
  }) {
    return PdfMergeItem(
      id: id ?? this.id,
      path: path ?? this.path,
      name: name ?? this.name,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      pageCount: pageCount ?? this.pageCount,
      bytes: bytes ?? this.bytes,
    );
  }
}

@immutable
class PdfMergeState {
  final List<PdfMergeItem> files;
  final String? errorMessage;
  final String? outputPath;
  final bool isProcessing;
  final String? progressMessage;

  const PdfMergeState({
    this.files = const [],
    this.errorMessage,
    this.outputPath,
    this.isProcessing = false,
    this.progressMessage,
  });

  bool get canMerge => files.length >= 2 && !isProcessing;

  PdfMergeState copyWith({
    List<PdfMergeItem>? files,
    String? errorMessage,
    bool resetError = false,
    String? outputPath,
    bool resetOutput = false,
    bool? isProcessing,
    String? progressMessage,
    bool resetProgressMessage = false,
  }) {
    return PdfMergeState(
      files: files ?? this.files,
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage ? null : (progressMessage ?? this.progressMessage),
    );
  }
}
