import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import 'pdf_split_state.dart';

final pdfSplitControllerProvider =
    StateNotifierProvider<PdfSplitController, PdfSplitState>((ref) {
  return PdfSplitController();
});

class PdfSplitController extends StateNotifier<PdfSplitState> {
  final PdfThumbnailService _thumbnailService;
  final FileService _fileService;

  PdfSplitController({
    PdfThumbnailService? thumbnailService,
    FileService? fileService,
  })  : _thumbnailService = thumbnailService ?? PdfThumbnailService(),
        _fileService = fileService ?? FileService(),
        super(const PdfSplitState());

  /// Load and validate a single PDF document.
  Future<void> loadDocument(PlatformFile platformFile,
      {Uint8List? overrideBytes}) async {
    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Loading PDF…",
      resetError: true,
      resetOutput: true,
    );

    Uint8List? bytes = overrideBytes ?? platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (e) {
          state = state.copyWith(
            isProcessing: false,
            resetProgressMessage: true,
            errorMessage:
                "Could not read '${platformFile.name}': permission denied or file unreadable.",
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "File '${platformFile.name}' is empty or unreadable.",
      );
      return;
    }

    int pageCount = 0;
    try {
      final doc = PdfDocument(inputBytes: bytes);
      pageCount = doc.pages.count;
      doc.dispose();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('password') ||
          errStr.contains('encrypted') ||
          errStr.contains('security')) {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage:
              "This file is password-protected and can't be modified. Remove the password first.",
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage:
              "File '${platformFile.name}' appears corrupted or unreadable.",
        );
      }
      return;
    }

    if (pageCount == 0) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "File '${platformFile.name}' contains no pages.",
      );
      return;
    }

    final initialThumbnails = List.generate(
      pageCount,
      (i) => PdfSplitThumbnail(pageIndex: i),
    );

    // Initial markers for custom ranges: default no markers until user taps
    state = state.copyWith(
      file: platformFile,
      fileBytes: bytes,
      totalPageCount: pageCount,
      thumbnails: initialThumbnails,
      isProcessing: false,
      isLoadingThumbnails: true,
      mode: SplitMode.everyPage,
      rangeMarkers: {},
      customRangeText: '',
      equalPartsCount: 2,
      resetProgressMessage: true,
      resetError: true,
      resetRangeValidationError: true,
      resetOutput: true,
    );

    _generateThumbnails(bytes);
  }

  /// Generate page thumbnails asynchronously.
  Future<void> _generateThumbnails(Uint8List bytes) async {
    List<PdfSplitThumbnail> updated = List.from(state.thumbnails);

    await _thumbnailService.generateThumbnails(
      bytes,
      onPageRendered: (pageIndex, thumbnailBytes) {
        if (state.fileBytes != bytes) return;
        if (pageIndex < updated.length) {
          updated[pageIndex] = updated[pageIndex].copyWith(
            thumbnailBytes: thumbnailBytes,
            hasError: thumbnailBytes == null,
          );
        }
      },
    );

    if (state.fileBytes == bytes) {
      final finalThumbnails = updated.map((t) {
        if (t.thumbnailBytes == null) {
          return t.copyWith(hasError: true);
        }
        return t;
      }).toList();

      state = state.copyWith(
        thumbnails: finalThumbnails,
        isLoadingThumbnails: false,
      );
    }
  }

  /// Set the split mode.
  void setSplitMode(SplitMode mode) {
    state = state.copyWith(
      mode: mode,
      resetRangeValidationError: true,
    );
    _validateCurrentState();
  }

  /// Toggle visual range marker after 0-indexed page [afterPageIndex].
  void toggleRangeMarker(int afterPageIndex) {
    if (afterPageIndex < 0 || afterPageIndex >= state.totalPageCount - 1) return;

    final markers = Set<int>.from(state.rangeMarkers);
    if (markers.contains(afterPageIndex)) {
      markers.remove(afterPageIndex);
    } else {
      markers.add(afterPageIndex);
    }

    // Sync typed text to reflect marker selections
    final ranges = <String>[];
    int start = 1;
    for (int i = 0; i < state.totalPageCount; i++) {
      if (markers.contains(i) || i == state.totalPageCount - 1) {
        ranges.add(start == i + 1 ? '$start' : '$start-${i + 1}');
        start = i + 2;
      }
    }

    state = state.copyWith(
      rangeMarkers: markers,
      customRangeText: ranges.join(', '),
      resetRangeValidationError: true,
    );
    _validateCurrentState();
  }

  /// Update ranges from typed user input string.
  void setRangesFromText(String input) {
    final parsed = PdfSplitState.parseRangesText(input, state.totalPageCount);
    Set<int> updatedMarkers = {};

    if (parsed.ranges != null && parsed.ranges!.isNotEmpty) {
      for (final r in parsed.ranges!) {
        if (r.endPage < state.totalPageCount) {
          updatedMarkers.add(r.endPage - 1);
        }
      }
    }

    state = state.copyWith(
      customRangeText: input,
      rangeMarkers: updatedMarkers,
      rangeValidationError: parsed.error,
      resetRangeValidationError: parsed.error == null,
    );
  }

  /// Set the number of equal parts N.
  void setEqualPartsCount(int n) {
    String? err;
    if (n > state.totalPageCount) {
      err = "This PDF only has ${state.totalPageCount} pages — can't split into more than ${state.totalPageCount} parts.";
    } else if (n <= 1) {
      err = "Equal parts must be at least 2.";
    }

    state = state.copyWith(
      equalPartsCount: n,
      rangeValidationError: err,
      resetRangeValidationError: err == null,
    );
  }

  void _validateCurrentState() {
    if (state.mode == SplitMode.equalParts) {
      setEqualPartsCount(state.equalPartsCount);
    } else if (state.mode == SplitMode.customRanges &&
        state.customRangeText.trim().isNotEmpty) {
      setRangesFromText(state.customRangeText);
    } else {
      state = state.copyWith(resetRangeValidationError: true);
    }
  }

  /// Clear error banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Reset controller to initial state.
  void reset() {
    state = const PdfSplitState();
  }

  /// Execute split processing and write files into directory.
  Future<String?> split({
    String? customOutputDir,
    bool overrideGapCheck = false,
  }) async {
    if (state.totalPageCount == 0 || state.fileBytes == null) {
      state = state.copyWith(errorMessage: "No PDF document loaded.");
      return null;
    }

    if (state.isSinglePage) {
      state = state.copyWith(
          errorMessage: "This PDF only has one page — nothing to split.");
      return null;
    }

    if (state.rangeValidationError != null) {
      state = state.copyWith(errorMessage: state.rangeValidationError);
      return null;
    }

    final ranges = state.calculatedRanges;
    if (ranges.isEmpty) {
      state = state.copyWith(
          errorMessage: "No valid page ranges defined for splitting.");
      return null;
    }

    // Check for uncovered pages gap
    final uncovered = state.uncoveredPages;
    if (uncovered.isNotEmpty && !overrideGapCheck) {
      final missingText = uncovered.length == 1
          ? 'Page ${uncovered.first}'
          : 'Pages ${uncovered.first}-${uncovered.last}';
      state = state.copyWith(
        errorMessage:
            "$missingText aren't included in any range — they'll be left out.",
      );
      return null;
    }

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Splitting into ${ranges.length} files…",
      resetError: true,
      resetOutput: true,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    // Prepare target directory
    late Directory outputDir;
    if (customOutputDir != null && customOutputDir.isNotEmpty) {
      outputDir = Directory(customOutputDir);
    } else {
      final sourcePath = state.file?.path;
      final baseName = p.basenameWithoutExtension(state.file?.name ?? 'document');
      final folderName = '${baseName}_split';

      final baseOutputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: sourcePath);
      outputDir = Directory(p.join(baseOutputDir.path, folderName));
    }

    try {
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }
    } catch (e) {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage:
            "Could not create output directory '${outputDir.path}': $e",
      );
      return null;
    }

    final List<String> createdFilePaths = [];
    final baseFileName =
        p.basenameWithoutExtension(state.file?.name ?? 'document');

    try {
      final sourceDoc = PdfDocument(inputBytes: state.fileBytes!);

      for (int rIdx = 0; rIdx < ranges.length; rIdx++) {
        final range = ranges[rIdx];
        final destDoc = PdfDocument();

        for (int pIdx = range.startPage - 1; pIdx < range.endPage; pIdx++) {
          final sourcePage = sourceDoc.pages[pIdx];
          final section = destDoc.sections!.add();
          section.pageSettings.size = sourcePage.size;
          section.pageSettings.margins.all = 0;
          if (sourcePage.size.width > sourcePage.size.height) {
            section.pageSettings.orientation = PdfPageOrientation.landscape;
          } else {
            section.pageSettings.orientation = PdfPageOrientation.portrait;
          }

          final template = sourcePage.createTemplate();
          final newPage = section.pages.add();
          newPage.graphics
              .drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
        }

        final List<int> pdfBytes = await destDoc.save();
        destDoc.dispose();

        final fileName = '${baseFileName}_part${rIdx + 1}.pdf';
        final filePath = p.join(outputDir.path, fileName);
        final file = File(filePath);

        await file.writeAsBytes(pdfBytes, flush: true);
        createdFilePaths.add(filePath);
      }

      sourceDoc.dispose();

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputFolderPath: outputDir.path,
        outputCreatedFileCount: createdFilePaths.length,
      );

      return outputDir.path;
    } catch (e) {
      // Rollback: delete any files written in this run
      for (final filePath in createdFilePaths) {
        try {
          final f = File(filePath);
          if (f.existsSync()) {
            f.deleteSync();
          }
        } catch (_) {}
      }

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage:
            "Split failed partway through and was rolled back — no partial files were kept. Failure: $e",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfSplitState get testState => state;
}
