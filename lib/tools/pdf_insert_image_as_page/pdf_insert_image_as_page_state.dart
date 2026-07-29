import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

enum PageFitMode {
  matchNeighboringPage,
  fitToImage,
}

class ImageItemState {
  final String id;
  final PlatformFile file;
  final Uint8List bytes;
  final Uint8List thumbnail;
  final int width;
  final int height;

  const ImageItemState({
    required this.id,
    required this.file,
    required this.bytes,
    required this.thumbnail,
    required this.width,
    required this.height,
  });
}

class PdfInsertImageAsPageState {
  final PlatformFile? targetFile;
  final Uint8List? targetBytes;
  final List<Uint8List?> targetThumbnails;
  final int targetPageCount;

  final List<ImageItemState> images;

  final PageFitMode fitMode;
  final int insertionPoint; // -1 = start, 0 to targetPageCount-1 = after target index

  final bool isProcessing;
  final String? progressMessage;
  final String? errorMessage;
  final String? outputPath;

  const PdfInsertImageAsPageState({
    this.targetFile,
    this.targetBytes,
    this.targetThumbnails = const [],
    this.targetPageCount = 0,
    this.images = const [],
    this.fitMode = PageFitMode.matchNeighboringPage,
    this.insertionPoint = -1,
    this.isProcessing = false,
    this.progressMessage,
    this.errorMessage,
    this.outputPath,
  });

  bool get hasTarget => targetBytes != null && targetBytes!.isNotEmpty && targetPageCount > 0;
  bool get hasImages => images.isNotEmpty;
  bool get hasImage => hasImages;
  int get imageCount => images.length;

  bool get canSubmit =>
      hasTarget &&
      hasImages &&
      insertionPoint >= -1 &&
      insertionPoint < targetPageCount &&
      !isProcessing;

  int get totalResultPageCount => hasTarget ? targetPageCount + images.length : 0;

  PdfInsertImageAsPageState copyWith({
    PlatformFile? targetFile,
    Uint8List? targetBytes,
    List<Uint8List?>? targetThumbnails,
    int? targetPageCount,
    List<ImageItemState>? images,
    PageFitMode? fitMode,
    int? insertionPoint,
    bool? isProcessing,
    String? progressMessage,
    String? errorMessage,
    String? outputPath,
    bool resetTarget = false,
    bool resetImages = false,
    bool resetError = false,
    bool resetOutput = false,
    bool resetProgressMessage = false,
  }) {
    return PdfInsertImageAsPageState(
      targetFile: resetTarget ? null : (targetFile ?? this.targetFile),
      targetBytes: resetTarget ? null : (targetBytes ?? this.targetBytes),
      targetThumbnails: resetTarget ? const [] : (targetThumbnails ?? this.targetThumbnails),
      targetPageCount: resetTarget ? 0 : (targetPageCount ?? this.targetPageCount),
      images: resetImages ? const [] : (images ?? this.images),
      fitMode: fitMode ?? this.fitMode,
      insertionPoint: resetTarget ? -1 : (insertionPoint ?? this.insertionPoint),
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage ? null : (progressMessage ?? this.progressMessage),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
