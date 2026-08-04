import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_isolate_worker.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import '../../core/services/pdf_validation_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'pdf_insert_pages_state.dart';

final pdfInsertPagesControllerProvider =
    StateNotifierProvider<PdfInsertPagesController, PdfInsertPagesState>((ref) {
  return PdfInsertPagesController(
    logService: ref.read(appLogServiceProvider),
  );
});

class PdfInsertPagesController extends StateNotifier<PdfInsertPagesState> {
  final FileService _fileService;
  final PdfThumbnailService _thumbnailService;
  final PdfValidationService _validationService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;

  PdfInsertPagesController({
    FileService? fileService,
    PdfThumbnailService? thumbnailService,
    PdfValidationService? validationService,
    TempFileManager? tempFileManager,
    AppLogService? logService,
  })  : _fileService = fileService ?? FileService(),
        _thumbnailService = thumbnailService ?? PdfThumbnailService(),
        _validationService = validationService ?? const PdfValidationService(),
        _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const PdfInsertPagesState());

  /// Load and validate target PDF document into which pages will be inserted.
  Future<void> loadTargetDocument(PlatformFile platformFile) async {
    Uint8List? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          state = state.copyWith(
            errorMessage: "Could not read '${platformFile.name}': permission denied or file unreadable.",
            resetError: false,
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        errorMessage: "File '${platformFile.name}' is empty or unreadable.",
        resetError: false,
      );
      return;
    }

    final valInfo = _validationService.validate(bytes);
    if (valInfo.isPasswordProtected) {
      state = state.copyWith(
        errorMessage: "This file is password-protected and can't be modified. Remove the password first.",
        resetError: false,
      );
      return;
    } else if (valInfo.isCorrupted) {
      state = state.copyWith(
        errorMessage: "File '${platformFile.name}' appears corrupted or unreadable.",
        resetError: false,
      );
      return;
    }

    final pageCount = valInfo.pageCount;
    if (pageCount == 0) {
      state = state.copyWith(
        errorMessage: "File '${platformFile.name}' contains no pages.",
        resetError: false,
      );
      return;
    }

    final thumbnails = await _thumbnailService.generateThumbnails(bytes);

    // ASSUMPTION: Insertion point defaults to 'at the end' (after the last target page) once target file is loaded.
    final defaultInsertionPoint = pageCount - 1;

    state = state.copyWith(
      targetFile: platformFile,
      targetBytes: bytes,
      targetThumbnails: thumbnails,
      targetPageCount: pageCount,
      insertionPoint: defaultInsertionPoint,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Load and validate source PDF document from which pages will be taken.
  Future<void> loadSourceDocument(PlatformFile platformFile) async {
    Uint8List? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          state = state.copyWith(
            errorMessage: "Could not read '${platformFile.name}': permission denied or file unreadable.",
            resetError: false,
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        errorMessage: "Source file '${platformFile.name}' is empty or unreadable.",
        resetError: false,
      );
      return;
    }

    final valInfo = _validationService.validate(bytes);
    if (valInfo.isPasswordProtected) {
      state = state.copyWith(
        errorMessage: "Source file is password-protected. Remove password before inserting pages.",
        resetError: false,
      );
      return;
    } else if (valInfo.isCorrupted) {
      state = state.copyWith(
        errorMessage: "Source file '${platformFile.name}' appears corrupted or unreadable.",
        resetError: false,
      );
      return;
    }

    final pageCount = valInfo.pageCount;
    if (pageCount == 0) {
      state = state.copyWith(
        errorMessage: "Source file '${platformFile.name}' contains no pages.",
        resetError: false,
      );
      return;
    }

    final thumbnails = await _thumbnailService.generateThumbnails(bytes);
    final allIndices = List<int>.generate(pageCount, (i) => i);

    state = state.copyWith(
      sourceFile: platformFile,
      sourceBytes: bytes,
      sourceThumbnails: thumbnails,
      sourcePageCount: pageCount,
      selectedSourcePageIndices: allIndices,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Toggle selection of a page in the source document.
  /// Preserves tap selection order when manually selecting pages.
  void togglePageSelected(int sourcePageIndex) {
    if (sourcePageIndex < 0 || sourcePageIndex >= state.sourcePageCount) return;

    final current = List<int>.from(state.selectedSourcePageIndices);
    if (current.contains(sourcePageIndex)) {
      current.remove(sourcePageIndex);
    } else {
      current.add(sourcePageIndex);
    }

    state = state.copyWith(selectedSourcePageIndices: current);
  }

  /// Select all pages from the source PDF in document order.
  void selectAllSource() {
    if (state.sourcePageCount == 0) return;
    state = state.copyWith(
      selectedSourcePageIndices: List<int>.generate(state.sourcePageCount, (i) => i),
    );
  }

  /// Select no pages from the source PDF.
  void selectNoneSource() {
    state = state.copyWith(selectedSourcePageIndices: const []);
  }

  /// Set the insertion point index in the target PDF.
  /// `-1` means at start, `i` (0 <= i < targetPageCount) means after target page index `i`.
  /// ASSUMPTION: Single insertion point operation per session for v1 scope.
  void setInsertionPoint(int afterTargetPageIndex) {
    if (afterTargetPageIndex < -1 || afterTargetPageIndex >= state.targetPageCount) return;
    state = state.copyWith(insertionPoint: afterTargetPageIndex);
  }

  /// Clear the loaded source document and return target grid preview to unmodified state.
  void clearSource() {
    state = state.copyWith(
      resetSource: true,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Clear the loaded target document and reset state.
  void clearTarget() {
    _tempFileManager.cleanupSession();
    state = const PdfInsertPagesState();
  }

  /// Dismiss error message banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Insert selected source pages into target PDF at chosen insertion point.
  Future<String?> insertPages({String? customOutputPath}) async {
    if (!state.canSubmit) {
      if (state.selectedSourceCount == 0) {
        state = state.copyWith(errorMessage: "Select at least one page to insert.");
      } else if (!state.hasTarget) {
        state = state.copyWith(errorMessage: "Select a target PDF document first.");
      } else if (!state.hasSource) {
        state = state.copyWith(errorMessage: "Select a source PDF document first.");
      }
      return null;
    }

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Inserting ${state.selectedSourceCount} pages into document…",
      resetError: true,
      resetOutput: true,
    );

    _logService.logStarted('pdf_insert_pages', 'insert',
        message: '${state.selectedSourceCount} pages');

    try {
      // Run heavy PDF work on a background isolate
      final Uint8List resultBytes = await compute(
        isolateInsertPages,
        InsertPagesParams(
          targetBytes: state.targetBytes!,
          sourceBytes: state.sourceBytes!,
          selectedSourceIndices: state.selectedSourcePageIndices,
          insertionPoint: state.insertionPoint,
        ),
      );

      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final targetFileName = state.targetFile?.name ?? 'document.pdf';
        final baseName = p.basenameWithoutExtension(targetFileName);
        final defaultFileName = '${baseName}_inserted.pdf';

        final firstFilePath = state.targetFile?.path;
        final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: firstFilePath);
        targetPath = p.join(outputDir.path, defaultFileName);
      }

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(resultBytes, flush: true);

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputPath: targetPath,
      );

      _logService.logSuccess('pdf_insert_pages', 'insert',
          message: 'output: ${p.basename(targetPath)}');

      return targetPath;
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This insertion is too large to process on this device. Try inserting fewer pages.",
      );
      _logService.logError('pdf_insert_pages', 'insert',
          message: 'out of memory');
      return null;
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
      _logService.logError('pdf_insert_pages', 'insert',
          message: 'file system error', errorDetail: e.toString());
      return null;
    } catch (e) {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Page insertion couldn't be completed — one of the files may be damaged. Try different source files.",
      );
      _logService.logError('pdf_insert_pages', 'insert',
          message: 'insert failed', errorDetail: e.toString());
      return null;
    }
  }

  /// Splice pages from [sourceBytes] (indices in [selectedSourceIndices]) into [targetBytes]
  /// after target page index [insertionPoint] (`-1` means at start).
  static Future<Uint8List> splicePages({
    required Uint8List targetBytes,
    required Uint8List sourceBytes,
    required List<int> selectedSourceIndices,
    required int insertionPoint,
  }) async {
    // Delegate to isolate worker for consistency
    return compute(
      isolateInsertPages,
      InsertPagesParams(
        targetBytes: targetBytes,
        sourceBytes: sourceBytes,
        selectedSourceIndices: selectedSourceIndices,
        insertionPoint: insertionPoint,
      ),
    );
  }

  /// Helper to copy page with preserved dimensions, zero margins, and explicit orientation.
  static void copyPageToDestination(PdfPage page, PdfDocument destinationDoc) {
    final section = destinationDoc.sections!.add();
    section.pageSettings.size = page.size;
    section.pageSettings.margins.all = 0;
    if (page.size.width > page.size.height) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    } else {
      section.pageSettings.orientation = PdfPageOrientation.portrait;
    }

    final template = page.createTemplate();
    final newPage = section.pages.add();
    newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), page.size);
  }

  @visibleForTesting
  PdfInsertPagesState get testState => state;
}
