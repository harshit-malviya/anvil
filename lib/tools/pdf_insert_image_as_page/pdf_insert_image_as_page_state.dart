import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

enum PageFitMode {
  matchNeighboringPage,
  fitToImage,
}

class PdfInsertImageAsPageState {
  final PlatformFile? targetFile;
  final Uint8List? targetBytes;
  final List<Uint8List?> targetThumbnails;
  final int targetPageCount;

  final PlatformFile? imageFile;
  final Uint8List? imageBytes;
  final Uint8List? imageThumbnail;
  final int imageWidth;
  final int imageHeight;

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
    this.imageFile,
    this.imageBytes,
    this.imageThumbnail,
    this.imageWidth = 0,
    this.imageHeight = 0,
    this.fitMode = PageFitMode.matchNeighboringPage,
    this.insertionPoint = -1,
    this.isProcessing = false,
    this.progressMessage,
    this.errorMessage,
    this.outputPath,
  });

  bool get hasTarget => targetBytes != null && targetBytes!.isNotEmpty && targetPageCount > 0;
  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
  bool get canSubmit =>
      hasTarget &&
      hasImage &&
      insertionPoint >= -1 &&
      insertionPoint < targetPageCount &&
      !isProcessing;

  int get totalResultPageCount => hasTarget ? targetPageCount + 1 : 0;

  PdfInsertImageAsPageState copyWith({
    PlatformFile? targetFile,
    Uint8List? targetBytes,
    List<Uint8List?>? targetThumbnails,
    int? targetPageCount,
    PlatformFile? imageFile,
    Uint8List? imageBytes,
    Uint8List? imageThumbnail,
    int? imageWidth,
    int? imageHeight,
    PageFitMode? fitMode,
    int? insertionPoint,
    bool? isProcessing,
    String? progressMessage,
    String? errorMessage,
    String? outputPath,
    bool resetTarget = false,
    bool resetImage = false,
    bool resetError = false,
    bool resetOutput = false,
    bool resetProgressMessage = false,
  }) {
    return PdfInsertImageAsPageState(
      targetFile: resetTarget ? null : (targetFile ?? this.targetFile),
      targetBytes: resetTarget ? null : (targetBytes ?? this.targetBytes),
      targetThumbnails: resetTarget ? const [] : (targetThumbnails ?? this.targetThumbnails),
      targetPageCount: resetTarget ? 0 : (targetPageCount ?? this.targetPageCount),
      imageFile: resetImage ? null : (imageFile ?? this.imageFile),
      imageBytes: resetImage ? null : (imageBytes ?? this.imageBytes),
      imageThumbnail: resetImage ? null : (imageThumbnail ?? this.imageThumbnail),
      imageWidth: resetImage ? 0 : (imageWidth ?? this.imageWidth),
      imageHeight: resetImage ? 0 : (imageHeight ?? this.imageHeight),
      fitMode: fitMode ?? this.fitMode,
      insertionPoint: resetTarget ? -1 : (insertionPoint ?? this.insertionPoint),
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage ? null : (progressMessage ?? this.progressMessage),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
