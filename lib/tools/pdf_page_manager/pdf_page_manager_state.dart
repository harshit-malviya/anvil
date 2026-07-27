import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

@immutable
class PageItem {
  final int originalIndex;
  final int rotation; // 0, 90, 180, 270
  final bool isDeleted;
  final Uint8List? thumbnailBytes;
  final bool hasThumbnailError;

  const PageItem({
    required this.originalIndex,
    this.rotation = 0,
    this.isDeleted = false,
    this.thumbnailBytes,
    this.hasThumbnailError = false,
  });

  PageItem copyWith({
    int? originalIndex,
    int? rotation,
    bool? isDeleted,
    Uint8List? thumbnailBytes,
    bool? hasThumbnailError,
  }) {
    return PageItem(
      originalIndex: originalIndex ?? this.originalIndex,
      rotation: rotation ?? this.rotation,
      isDeleted: isDeleted ?? this.isDeleted,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      hasThumbnailError: hasThumbnailError ?? this.hasThumbnailError,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageItem &&
          runtimeType == other.runtimeType &&
          originalIndex == other.originalIndex &&
          rotation == other.rotation &&
          isDeleted == other.isDeleted &&
          thumbnailBytes == other.thumbnailBytes &&
          hasThumbnailError == other.hasThumbnailError;

  @override
  int get hashCode =>
      originalIndex.hashCode ^
      rotation.hashCode ^
      isDeleted.hashCode ^
      thumbnailBytes.hashCode ^
      hasThumbnailError.hashCode;
}

@immutable
class PdfPageManagerState {
  final PlatformFile? file;
  final Uint8List? fileBytes;
  final List<PageItem> pages;
  final bool isProcessing;
  final bool isLoadingThumbnails;
  final String? progressMessage;
  final String? errorMessage;
  final String? outputPath;

  const PdfPageManagerState({
    this.file,
    this.fileBytes,
    this.pages = const [],
    this.isProcessing = false,
    this.isLoadingThumbnails = false,
    this.progressMessage,
    this.errorMessage,
    this.outputPath,
  });

  List<PageItem> get activePages => pages.where((p) => !p.isDeleted).toList();
  int get activePageCount => activePages.length;
  int get rotatedPageCount =>
      activePages.where((p) => (p.rotation % 360) != 0).length;
  int get originalPageCount => pages.length;
  bool get canApply => file != null && activePageCount > 0 && !isProcessing;

  String get summaryText {
    if (pages.isEmpty) return '';
    final rotatedCount = rotatedPageCount;
    String base = '$originalPageCount pages → $activePageCount pages';
    if (originalPageCount == activePageCount) {
      base = '$originalPageCount pages';
    }
    if (rotatedCount > 0) {
      base += ', $rotatedCount rotated';
    }
    return base;
  }

  PdfPageManagerState copyWith({
    PlatformFile? file,
    bool resetFile = false,
    Uint8List? fileBytes,
    bool resetFileBytes = false,
    List<PageItem>? pages,
    bool? isProcessing,
    bool? isLoadingThumbnails,
    String? progressMessage,
    bool resetProgressMessage = false,
    String? errorMessage,
    bool resetError = false,
    String? outputPath,
    bool resetOutput = false,
  }) {
    return PdfPageManagerState(
      file: resetFile ? null : (file ?? this.file),
      fileBytes: resetFileBytes ? null : (fileBytes ?? this.fileBytes),
      pages: pages ?? this.pages,
      isProcessing: isProcessing ?? this.isProcessing,
      isLoadingThumbnails: isLoadingThumbnails ?? this.isLoadingThumbnails,
      progressMessage: resetProgressMessage
          ? null
          : (progressMessage ?? this.progressMessage),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageManagerState &&
          runtimeType == other.runtimeType &&
          file == other.file &&
          fileBytes == other.fileBytes &&
          listEquals(pages, other.pages) &&
          isProcessing == other.isProcessing &&
          isLoadingThumbnails == other.isLoadingThumbnails &&
          progressMessage == other.progressMessage &&
          errorMessage == other.errorMessage &&
          outputPath == other.outputPath;

  @override
  int get hashCode =>
      file.hashCode ^
      fileBytes.hashCode ^
      Object.hashAll(pages) ^
      isProcessing.hashCode ^
      isLoadingThumbnails.hashCode ^
      progressMessage.hashCode ^
      errorMessage.hashCode ^
      outputPath.hashCode;
}
