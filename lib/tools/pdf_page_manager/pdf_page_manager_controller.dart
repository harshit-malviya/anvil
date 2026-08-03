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
import 'pdf_page_manager_state.dart';

final pdfPageManagerControllerProvider =
    StateNotifierProvider<PdfPageManagerController, PdfPageManagerState>((ref) {
  return PdfPageManagerController();
});

class PdfPageManagerController extends StateNotifier<PdfPageManagerState> {
  final FileService _fileService;
  final PdfValidationService _validationService;
  final TempFileManager _tempFileManager;

  PdfPageManagerController({
    FileService? fileService,
    PdfValidationService? validationService,
    TempFileManager? tempFileManager,
  })  : _fileService = fileService ?? FileService(),
        _validationService = validationService ?? const PdfValidationService(),
        _tempFileManager = tempFileManager ?? TempFileManager(),
        super(const PdfPageManagerState());

  /// Load and validate a single PDF document.
  Future<void> loadDocument(PlatformFile platformFile, {Uint8List? overrideBytes}) async {
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
            errorMessage: "Could not read '${platformFile.name}': permission denied or file unreadable.",
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

    final valInfo = _validationService.validate(bytes);
    if (valInfo.isPasswordProtected) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This file is password-protected and can't be modified. Remove the password first.",
      );
      return;
    } else if (valInfo.isCorrupted) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "File '${platformFile.name}' appears corrupted or unreadable.",
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

    final initialPages = List<PageItem>.generate(
      pageCount,
      (index) => PageItem(originalIndex: index),
    );

    state = state.copyWith(
      file: platformFile,
      fileBytes: bytes,
      pages: initialPages,
      isProcessing: false,
      isLoadingThumbnails: true,
      resetProgressMessage: true,
      resetError: true,
    );

    // Asynchronously generate page thumbnails
    _generateThumbnails(bytes);
  }

  final PdfThumbnailService _thumbnailService = PdfThumbnailService();

  /// Generate thumbnails for all pages asynchronously.
  Future<void> _generateThumbnails(Uint8List bytes) async {
    await _thumbnailService.generateThumbnails(
      bytes,
      onPageRendered: (pageIndex, thumbnailBytes) {
        if (state.fileBytes != bytes) return;
        final currentPages = List<PageItem>.from(state.pages);
        final idx = currentPages.indexWhere((p) => p.originalIndex == pageIndex);
        if (idx != -1) {
          currentPages[idx] = currentPages[idx].copyWith(
            thumbnailBytes: thumbnailBytes,
            hasThumbnailError: thumbnailBytes == null,
          );
          state = state.copyWith(pages: currentPages);
        }
      },
    );

    if (state.fileBytes == bytes) {
      // Mark any remaining unrendered thumbnails as errors
      final finalPages = state.pages.map((p) {
        if (p.thumbnailBytes == null) {
          return p.copyWith(hasThumbnailError: true);
        }
        return p;
      }).toList();

      state = state.copyWith(
        pages: finalPages,
        isLoadingThumbnails: false,
      );
    }
  }

  /// Toggle deletion mark for page at current list [index].
  void togglePageDeleted(int index) {
    if (index < 0 || index >= state.pages.length) return;

    final updated = List<PageItem>.from(state.pages);
    final target = updated[index];
    updated[index] = target.copyWith(isDeleted: !target.isDeleted);

    final activeCount = updated.where((p) => !p.isDeleted).length;
    String? err;
    if (activeCount == 0) {
      err = "A PDF needs at least one page. Undo a deletion to continue.";
    }

    state = state.copyWith(
      pages: updated,
      errorMessage: err,
      resetError: err == null,
    );
  }

  /// Rotate page at current list [index] clockwise by 90 degrees.
  void rotatePage(int index) {
    if (index < 0 || index >= state.pages.length) return;

    final updated = List<PageItem>.from(state.pages);
    final target = updated[index];
    final nextRotation = (target.rotation + 90) % 360;
    updated[index] = target.copyWith(rotation: nextRotation);

    state = state.copyWith(pages: updated);
  }

  /// Reorder page from [oldIndex] to [newIndex].
  void reorderPage(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.pages.length) return;
    int targetIndex = newIndex;
    if (oldIndex < targetIndex) {
      targetIndex -= 1;
    }
    if (targetIndex < 0 || targetIndex >= state.pages.length) return;

    final updated = List<PageItem>.from(state.pages);
    final item = updated.removeAt(oldIndex);
    updated.insert(targetIndex, item);

    state = state.copyWith(pages: updated);
  }

  /// Clear error banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Reset state to initial empty file state.
  void reset() {
    _tempFileManager.cleanupSession();
    state = const PdfPageManagerState();
  }

  /// Apply page changes (delete, reorder, rotate) and write output PDF.
  Future<String?> applyChanges({String? customOutputPath}) async {
    if (state.activePageCount == 0) {
      state = state.copyWith(
        errorMessage: "A PDF needs at least one page. Undo a deletion to continue.",
      );
      return null;
    }

    if (state.fileBytes == null) {
      state = state.copyWith(errorMessage: "No PDF file loaded.");
      return null;
    }

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Saving page changes…",
      resetError: true,
      resetOutput: true,
    );

    try {
      // Build isolate-compatible page arrangement list
      final arrangedPages = state.activePages
          .map((item) => ArrangedPage(
                originalIndex: item.originalIndex,
                rotation: item.rotation,
              ))
          .toList();

      // Run heavy PDF work on a background isolate
      final Uint8List outputBytes = await compute(
        isolateArrangePages,
        ArrangePagesParams(inputBytes: state.fileBytes!, pages: arrangedPages),
      );

      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final defaultFileName = 'arranged_$timestamp.pdf';

        final sourceFilePath = state.file?.path;
        final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: sourceFilePath);
        targetPath = p.join(outputDir.path, defaultFileName);
      }

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(outputBytes, flush: true);

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
        errorMessage: "This operation is too large to process on this device.",
      );
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
        errorMessage: "Couldn't apply page changes — the file may be damaged. Try a different PDF.",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfPageManagerState get testState => state;
}
