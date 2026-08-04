import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/pdf_isolate_worker.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import '../../core/services/pdf_validation_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'pdf_split_state.dart';

final pdfSplitControllerProvider =
    StateNotifierProvider<PdfSplitController, PdfSplitState>((ref) {
  return PdfSplitController(
    logService: ref.read(appLogServiceProvider),
  );
});

class PdfSplitController extends StateNotifier<PdfSplitState> {
  final PdfThumbnailService _thumbnailService;
  final FileService _fileService;
  final PdfValidationService _validationService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;
  int? _pickerLoadTimeMs;

  PdfSplitController({
    PdfThumbnailService? thumbnailService,
    FileService? fileService,
    PdfValidationService? validationService,
    TempFileManager? tempFileManager,
    AppLogService? logService,
  })  : _thumbnailService = thumbnailService ?? PdfThumbnailService(),
        _fileService = fileService ?? FileService(),
        _validationService = validationService ?? const PdfValidationService(),
        _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const PdfSplitState());

  /// Load and validate a single PDF document.
  Future<void> loadDocument(PlatformFile platformFile,
      {Uint8List? overrideBytes}) async {
    final stopwatch = Stopwatch()..start();
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
          stopwatch.stop();
          _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
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
      stopwatch.stop();
      _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "File '${platformFile.name}' is empty or unreadable.",
      );
      return;
    }

    final valInfo = _validationService.validate(bytes);
    stopwatch.stop();
    _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;

    if (valInfo.isPasswordProtected) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage:
            "This file is password-protected and can't be modified. Remove the password first.",
      );
      return;
    } else if (valInfo.isCorrupted) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage:
            "File '${platformFile.name}' appears corrupted or unreadable.",
      );
      return;
    }

    final pageCount = valInfo.pageCount;

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
    _tempFileManager.cleanupSession();
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

    final Map<String, dynamic> splitParams = {
      'mode': state.mode.name,
      if (state.mode == SplitMode.equalParts) 'parts': state.equalPartsCount,
      if (state.mode == SplitMode.customRanges) 'ranges': state.customRangeText,
    };

    final logId = _logService.logStarted(
      'pdf_split',
      'PDF Split',
      'split',
      inputFileCount: 1,
      inputFilesCombinedSizeBytes: state.fileBytes!.length,
      filePickerLoadTimeMs: _pickerLoadTimeMs,
      parameters: splitParams,
    );

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
      final errText = "Could not create output directory '${outputDir.path}': $e";
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: errText,
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.fileWrite,
        errorMessage: errText,
        errorDetail: e.toString(),
      );
      return null;
    }

    final baseFileName =
        p.basenameWithoutExtension(state.file?.name ?? 'document');

    try {
      final isolateRanges = ranges
          .map((r) => SplitRange(startPage: r.startPage, endPage: r.endPage))
          .toList();

      final List<Uint8List> splitResults = await compute(
        isolateSplitPdf,
        SplitParams(inputBytes: state.fileBytes!, ranges: isolateRanges),
      );

      final List<String> createdFilePaths = [];
      int totalBytesWritten = 0;
      for (int rIdx = 0; rIdx < splitResults.length; rIdx++) {
        final fileName = '${baseFileName}_part${rIdx + 1}.pdf';
        final filePath = p.join(outputDir.path, fileName);
        final file = File(filePath);
        await file.writeAsBytes(splitResults[rIdx], flush: true);
        createdFilePaths.add(filePath);
        totalBytesWritten += splitResults[rIdx].length;
      }

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputFolderPath: outputDir.path,
        outputCreatedFileCount: createdFilePaths.length,
      );

      _logService.logCompleted(
        logId,
        outputFileCount: createdFilePaths.length,
        outputFilesCombinedSizeBytes: totalBytesWritten,
        message: '${createdFilePaths.length} files created',
      );

      return outputDir.path;
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This operation is too large to process on this device.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.isolateExecution,
        errorMessage: "Out of memory during PDF split",
      );
      return null;
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      _rollbackOutputDir(outputDir);
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage:
            "Split failed partway through and was rolled back — no partial files were kept. Couldn't save split files — ${e.message}.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.fileWrite,
        errorMessage: "File system error: ${e.message}",
        errorDetail: e.toString(),
      );
      return null;
    } catch (e) {
      await _tempFileManager.cleanupSession();
      _rollbackOutputDir(outputDir);
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage:
            "Split failed — the PDF may be damaged or too complex. Try a different PDF.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.processing,
        errorMessage: "Split failed",
        errorDetail: e.toString(),
      );
      return null;
    }
  }

  void _rollbackOutputDir(Directory outputDir) {
    try {
      if (outputDir.existsSync()) {
        final files = outputDir.listSync().whereType<File>();
        for (final f in files) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  @visibleForTesting
  PdfSplitState get testState => state;
}
