import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

@immutable
class PdfInsertPagesState {
  final PlatformFile? targetFile;
  final Uint8List? targetBytes;
  final List<Uint8List?> targetThumbnails;
  final int targetPageCount;

  final PlatformFile? sourceFile;
  final Uint8List? sourceBytes;
  final List<Uint8List?> sourceThumbnails;
  final int sourcePageCount;

  /// Ordered list of 0-based page indices selected from the source document to insert.
  final List<int> selectedSourcePageIndices;

  /// Target insertion point index:
  /// `-1` = at start (before target page 0 / index 0)
  /// `targetPageCount - 1` = at end (after last target page)
  /// `i` = after target page index `i` (page `i + 1`)
  final int insertionPoint;

  final bool isProcessing;
  final String? progressMessage;
  final String? errorMessage;
  final String? outputPath;

  const PdfInsertPagesState({
    this.targetFile,
    this.targetBytes,
    this.targetThumbnails = const [],
    this.targetPageCount = 0,
    this.sourceFile,
    this.sourceBytes,
    this.sourceThumbnails = const [],
    this.sourcePageCount = 0,
    this.selectedSourcePageIndices = const [],
    this.insertionPoint = -1,
    this.isProcessing = false,
    this.progressMessage,
    this.errorMessage,
    this.outputPath,
  });

  bool get hasTarget => targetFile != null && targetBytes != null && targetPageCount > 0;
  bool get hasSource => sourceFile != null && sourceBytes != null && sourcePageCount > 0;
  int get selectedSourceCount => selectedSourcePageIndices.length;
  bool get canSubmit => hasTarget && hasSource && selectedSourceCount > 0 && !isProcessing;
  int get totalResultPageCount => (hasTarget ? targetPageCount : 0) + selectedSourceCount;

  PdfInsertPagesState copyWith({
    PlatformFile? targetFile,
    Uint8List? targetBytes,
    List<Uint8List?>? targetThumbnails,
    int? targetPageCount,
    PlatformFile? sourceFile,
    Uint8List? sourceBytes,
    List<Uint8List?>? sourceThumbnails,
    int? sourcePageCount,
    List<int>? selectedSourcePageIndices,
    int? insertionPoint,
    bool? isProcessing,
    String? progressMessage,
    String? errorMessage,
    String? outputPath,
    bool resetTarget = false,
    bool resetSource = false,
    bool resetError = false,
    bool resetOutput = false,
    bool resetProgressMessage = false,
  }) {
    return PdfInsertPagesState(
      targetFile: resetTarget ? null : (targetFile ?? this.targetFile),
      targetBytes: resetTarget ? null : (targetBytes ?? this.targetBytes),
      targetThumbnails: resetTarget ? const [] : (targetThumbnails ?? this.targetThumbnails),
      targetPageCount: resetTarget ? 0 : (targetPageCount ?? this.targetPageCount),
      sourceFile: resetSource ? null : (sourceFile ?? this.sourceFile),
      sourceBytes: resetSource ? null : (sourceBytes ?? this.sourceBytes),
      sourceThumbnails: resetSource ? const [] : (sourceThumbnails ?? this.sourceThumbnails),
      sourcePageCount: resetSource ? 0 : (sourcePageCount ?? this.sourcePageCount),
      selectedSourcePageIndices: resetSource
          ? const []
          : (selectedSourcePageIndices ?? this.selectedSourcePageIndices),
      insertionPoint: resetTarget ? -1 : (insertionPoint ?? this.insertionPoint),
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage ? null : (progressMessage ?? this.progressMessage),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
