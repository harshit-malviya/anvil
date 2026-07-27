import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum SplitMode {
  everyPage,
  customRanges,
  equalParts,
}

class PdfPageRange {
  final int startPage; // 1-indexed
  final int endPage; // 1-indexed

  const PdfPageRange(this.startPage, this.endPage);

  int get pageCount => endPage - startPage + 1;

  String get label =>
      startPage == endPage ? 'page $startPage' : 'pages $startPage-$endPage';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageRange &&
          runtimeType == other.runtimeType &&
          startPage == other.startPage &&
          endPage == other.endPage;

  @override
  int get hashCode => startPage.hashCode ^ endPage.hashCode;

  @override
  String toString() => startPage == endPage ? '$startPage' : '$startPage-$endPage';
}

class PdfSplitThumbnail {
  final int pageIndex; // 0-indexed
  final Uint8List? thumbnailBytes;
  final bool hasError;

  const PdfSplitThumbnail({
    required this.pageIndex,
    this.thumbnailBytes,
    this.hasError = false,
  });

  PdfSplitThumbnail copyWith({
    Uint8List? thumbnailBytes,
    bool? hasError,
  }) {
    return PdfSplitThumbnail(
      pageIndex: pageIndex,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      hasError: hasError ?? this.hasError,
    );
  }
}

class PdfSplitState {
  final PlatformFile? file;
  final Uint8List? fileBytes;
  final int totalPageCount;
  final List<PdfSplitThumbnail> thumbnails;
  final bool isLoadingThumbnails;
  final SplitMode mode;
  final Set<int> rangeMarkers; // 0-indexed page index after which split occurs
  final String customRangeText;
  final int equalPartsCount;
  final String? rangeValidationError;
  final String? errorMessage;
  final bool isProcessing;
  final String? progressMessage;
  final String? outputFolderPath;
  final int? outputCreatedFileCount;

  const PdfSplitState({
    this.file,
    this.fileBytes,
    this.totalPageCount = 0,
    this.thumbnails = const [],
    this.isLoadingThumbnails = false,
    this.mode = SplitMode.everyPage,
    this.rangeMarkers = const {},
    this.customRangeText = '',
    this.equalPartsCount = 2,
    this.rangeValidationError,
    this.errorMessage,
    this.isProcessing = false,
    this.progressMessage,
    this.outputFolderPath,
    this.outputCreatedFileCount,
  });

  bool get isLoaded => file != null && totalPageCount > 0;
  bool get isSinglePage => totalPageCount == 1;

  /// Calculate output ranges based on current mode and settings.
  List<PdfPageRange> get calculatedRanges {
    if (totalPageCount <= 0) return [];

    switch (mode) {
      case SplitMode.everyPage:
        return List.generate(
          totalPageCount,
          (i) => PdfPageRange(i + 1, i + 1),
        );

      case SplitMode.customRanges:
        if (customRangeText.trim().isNotEmpty) {
          final parsed = parseRangesText(customRangeText, totalPageCount);
          if (parsed.ranges != null) {
            return parsed.ranges!;
          }
        }
        // Fallback to visual range markers
        final List<PdfPageRange> ranges = [];
        int currentStart = 1;
        for (int i = 0; i < totalPageCount; i++) {
          if (rangeMarkers.contains(i) || i == totalPageCount - 1) {
            ranges.add(PdfPageRange(currentStart, i + 1));
            currentStart = i + 2;
          }
        }
        return ranges;

      case SplitMode.equalParts:
        if (equalPartsCount <= 0 || equalPartsCount > totalPageCount) return [];
        final List<PdfPageRange> ranges = [];
        final basePages = totalPageCount ~/ equalPartsCount;
        final remainder = totalPageCount % equalPartsCount;

        int currentStart = 1;
        for (int i = 0; i < equalPartsCount; i++) {
          final pagesInThisPart = basePages + (i < remainder ? 1 : 0);
          final end = currentStart + pagesInThisPart - 1;
          ranges.add(PdfPageRange(currentStart, end));
          currentStart = end + 1;
        }
        return ranges;
    }
  }

  /// List of 1-indexed page numbers that are not included in any calculated range.
  List<int> get uncoveredPages {
    if (totalPageCount <= 0) return [];
    final covered = <int>{};
    for (final r in calculatedRanges) {
      for (int i = r.startPage; i <= r.endPage; i++) {
        covered.add(i);
      }
    }
    final List<int> missing = [];
    for (int i = 1; i <= totalPageCount; i++) {
      if (!covered.contains(i)) {
        missing.add(i);
      }
    }
    return missing;
  }

  /// Human readable summary of the split configuration.
  String get summaryText {
    if (isSinglePage) {
      return "This PDF only has one page — nothing to split.";
    }
    final ranges = calculatedRanges;
    if (ranges.isEmpty) {
      return "Configure split settings above.";
    }

    if (mode == SplitMode.everyPage) {
      return "Will produce $totalPageCount files (1 page each)";
    }

    final rangeLabels = ranges.map((r) => r.toString()).join(', ');
    return "Will produce ${ranges.length} files: pages $rangeLabels";
  }

  PdfSplitState copyWith({
    PlatformFile? file,
    Uint8List? fileBytes,
    int? totalPageCount,
    List<PdfSplitThumbnail>? thumbnails,
    bool? isLoadingThumbnails,
    SplitMode? mode,
    Set<int>? rangeMarkers,
    String? customRangeText,
    int? equalPartsCount,
    String? rangeValidationError,
    bool resetRangeValidationError = false,
    String? errorMessage,
    bool resetError = false,
    bool? isProcessing,
    String? progressMessage,
    bool resetProgressMessage = false,
    String? outputFolderPath,
    int? outputCreatedFileCount,
    bool resetOutput = false,
  }) {
    return PdfSplitState(
      file: file ?? this.file,
      fileBytes: fileBytes ?? this.fileBytes,
      totalPageCount: totalPageCount ?? this.totalPageCount,
      thumbnails: thumbnails ?? this.thumbnails,
      isLoadingThumbnails: isLoadingThumbnails ?? this.isLoadingThumbnails,
      mode: mode ?? this.mode,
      rangeMarkers: rangeMarkers ?? this.rangeMarkers,
      customRangeText: customRangeText ?? this.customRangeText,
      equalPartsCount: equalPartsCount ?? this.equalPartsCount,
      rangeValidationError: resetRangeValidationError
          ? null
          : (rangeValidationError ?? this.rangeValidationError),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage
          ? null
          : (progressMessage ?? this.progressMessage),
      outputFolderPath:
          resetOutput ? null : (outputFolderPath ?? this.outputFolderPath),
      outputCreatedFileCount: resetOutput
          ? null
          : (outputCreatedFileCount ?? this.outputCreatedFileCount),
    );
  }

  /// Parse text input (e.g. "1-3, 4-10, 11-15") into ranges and check for overlaps / syntax.
  static ({List<PdfPageRange>? ranges, String? error}) parseRangesText(
      String input, int totalPages) {
    final cleaned = input.trim();
    if (cleaned.isEmpty) return (ranges: [], error: null);

    final parts = cleaned.split(RegExp(r'[,;]'));
    final List<PdfPageRange> parsedRanges = [];
    final Map<int, int> pageCoverage = {}; // pageNumber -> rangeIndex

    for (int rIdx = 0; rIdx < parts.length; rIdx++) {
      final part = parts[rIdx].trim();
      if (part.isEmpty) continue;

      final rangeMatch = RegExp(r'^(\d+)(?:\s*-\s*(\d+))?$').firstMatch(part);
      if (rangeMatch == null) {
        return (ranges: null, error: "Invalid range syntax: '$part'. Use format like '1-3, 4-10'.");
      }

      final start = int.parse(rangeMatch.group(1)!);
      final end = rangeMatch.group(2) != null
          ? int.parse(rangeMatch.group(2)!)
          : start;

      if (start < 1 || end < 1 || start > totalPages || end > totalPages) {
        return (
          ranges: null,
          error: "Page numbers must be between 1 and $totalPages."
        );
      }

      if (start > end) {
        return (
          ranges: null,
          error: "Range '$part' is invalid (start page must be <= end page)."
        );
      }

      for (int p = start; p <= end; p++) {
        if (pageCoverage.containsKey(p)) {
          return (
            ranges: null,
            error: "Ranges can't overlap (page $p appears in multiple ranges)."
          );
        }
        pageCoverage[p] = rIdx;
      }

      parsedRanges.add(PdfPageRange(start, end));
    }

    return (ranges: parsedRanges, error: null);
  }
}
