import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum ImageFormat {
  png,
  jpeg;

  String get label => name.toUpperCase();
  String get fileExtension => name.toLowerCase();
}

enum ExportResolution {
  low(72, '72 DPI', 'Screen use'),
  medium(150, '150 DPI', 'Default'),
  high(300, '300 DPI', 'Print quality');

  final int dpi;
  final String label;
  final String sublabel;

  const ExportResolution(this.dpi, this.label, this.sublabel);
}

class PdfToImageState {
  final PlatformFile? file;
  final Uint8List? fileBytes;
  final int totalPageCount;
  final Set<int> selectedPages;
  final ImageFormat format;
  final ExportResolution resolution;
  final bool isProcessing;
  final String? progressMessage;
  final double? progressPercent;
  final bool isLoadingThumbnails;
  final Map<int, Uint8List?> thumbnails;
  final String? errorMessage;
  final String? outputPath;
  final int exportedCount;
  final List<int> skippedPages;
  final bool isSingleFileExport;
  final double firstPageWidthPt;
  final double firstPageHeightPt;

  const PdfToImageState({
    this.file,
    this.fileBytes,
    this.totalPageCount = 0,
    this.selectedPages = const {},
    this.format = ImageFormat.png,
    this.resolution = ExportResolution.medium,
    this.isProcessing = false,
    this.progressMessage,
    this.progressPercent,
    this.isLoadingThumbnails = false,
    this.thumbnails = const {},
    this.errorMessage,
    this.outputPath,
    this.exportedCount = 0,
    this.skippedPages = const [],
    this.isSingleFileExport = false,
    this.firstPageWidthPt = 612.0,
    this.firstPageHeightPt = 792.0,
  });

  bool get isLoaded => file != null && fileBytes != null && totalPageCount > 0;
  int get selectedCount => selectedPages.length;
  bool get canExport => isLoaded && selectedCount > 0 && !isProcessing;

  String get summaryText {
    if (!isLoaded) return '';
    if (selectedCount == 0) return 'Select at least one page to export';
    final pageLabel = selectedCount == 1 ? 'page' : 'pages';
    return 'Export $selectedCount $pageLabel as ${format.label} at ${resolution.dpi} DPI';
  }

  String estimatedDimensionsText(ExportResolution res) {
    final w = (firstPageWidthPt * res.dpi / 72.0).round();
    final h = (firstPageHeightPt * res.dpi / 72.0).round();
    return '${res.dpi} DPI — approx. ${w}×${h}px';
  }

  PdfToImageState copyWith({
    PlatformFile? file,
    Uint8List? fileBytes,
    int? totalPageCount,
    Set<int>? selectedPages,
    ImageFormat? format,
    ExportResolution? resolution,
    bool? isProcessing,
    String? progressMessage,
    bool resetProgressMessage = false,
    double? progressPercent,
    bool resetProgressPercent = false,
    bool? isLoadingThumbnails,
    Map<int, Uint8List?>? thumbnails,
    String? errorMessage,
    bool resetError = false,
    String? outputPath,
    bool resetOutput = false,
    int? exportedCount,
    List<int>? skippedPages,
    bool? isSingleFileExport,
    double? firstPageWidthPt,
    double? firstPageHeightPt,
  }) {
    return PdfToImageState(
      file: file ?? this.file,
      fileBytes: fileBytes ?? this.fileBytes,
      totalPageCount: totalPageCount ?? this.totalPageCount,
      selectedPages: selectedPages ?? this.selectedPages,
      format: format ?? this.format,
      resolution: resolution ?? this.resolution,
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage ? null : (progressMessage ?? this.progressMessage),
      progressPercent: resetProgressPercent ? null : (progressPercent ?? this.progressPercent),
      isLoadingThumbnails: isLoadingThumbnails ?? this.isLoadingThumbnails,
      thumbnails: thumbnails ?? this.thumbnails,
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
      exportedCount: exportedCount ?? this.exportedCount,
      skippedPages: skippedPages ?? this.skippedPages,
      isSingleFileExport: isSingleFileExport ?? this.isSingleFileExport,
      firstPageWidthPt: firstPageWidthPt ?? this.firstPageWidthPt,
      firstPageHeightPt: firstPageHeightPt ?? this.firstPageHeightPt,
    );
  }
}
