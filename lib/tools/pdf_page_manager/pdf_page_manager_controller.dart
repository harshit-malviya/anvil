import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import 'pdf_page_manager_state.dart';

final pdfPageManagerControllerProvider =
    StateNotifierProvider<PdfPageManagerController, PdfPageManagerState>((ref) {
  return PdfPageManagerController();
});

class PdfPageManagerController extends StateNotifier<PdfPageManagerState> {
  PdfPageManagerController() : super(const PdfPageManagerState());

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

    int pageCount = 0;
    try {
      final doc = PdfDocument(inputBytes: bytes);
      pageCount = doc.pages.count;
      doc.dispose();
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('password') || errStr.contains('encrypted') || errStr.contains('security')) {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage: "This file is password-protected and can't be modified. Remove the password first.",
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage: "File '${platformFile.name}' appears corrupted or unreadable.",
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
    List<PageItem> updatedPages = List<PageItem>.from(state.pages);

    await _thumbnailService.generateThumbnails(
      bytes,
      onPageRendered: (pageIndex, thumbnailBytes) {
        if (state.fileBytes != bytes) return;
        if (pageIndex < updatedPages.length) {
          updatedPages[pageIndex] = updatedPages[pageIndex].copyWith(
            thumbnailBytes: thumbnailBytes,
            hasThumbnailError: thumbnailBytes == null,
          );
        }
      },
    );

    if (state.fileBytes == bytes) {
      // Mark any remaining unrendered thumbnails as errors
      final finalPages = updatedPages.map((p) {
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

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Saving page changes…",
      resetError: true,
      resetOutput: true,
    );

    try {
      final sourceDoc = PdfDocument(inputBytes: state.fileBytes!);
      final destinationDoc = PdfDocument();

      for (final item in state.activePages) {
        final sourcePage = sourceDoc.pages[item.originalIndex];
        final section = destinationDoc.sections!.add();
        section.pageSettings.size = sourcePage.size;
        section.pageSettings.margins.all = 0;

        if (sourcePage.size.width > sourcePage.size.height) {
          section.pageSettings.orientation = PdfPageOrientation.landscape;
        } else {
          section.pageSettings.orientation = PdfPageOrientation.portrait;
        }

        switch (item.rotation % 360) {
          case 90:
            section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle90;
            break;
          case 180:
            section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle180;
            break;
          case 270:
            section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle270;
            break;
          case 0:
          default:
            section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle0;
            break;
        }

        final template = sourcePage.createTemplate();
        final newPage = section.pages.add();
        newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
      }

      sourceDoc.dispose();

      final List<int> outputBytes = await destinationDoc.save();
      destinationDoc.dispose();

      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final defaultFileName = 'arranged_$timestamp.pdf';

        final sourceFilePath = state.file?.path;
        if (sourceFilePath != null && sourceFilePath.isNotEmpty) {
          final dir = p.dirname(sourceFilePath);
          targetPath = p.join(dir, defaultFileName);
        } else {
          final tempDir = Directory.systemTemp;
          targetPath = p.join(tempDir.path, defaultFileName);
        }
      }

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(outputBytes, flush: true);

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputPath: targetPath,
      );

      return targetPath;
    } on OutOfMemoryError {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This operation is too large to process on this device.",
      );
      return null;
    } on FileSystemException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Failed to apply page changes: $e",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfPageManagerState get testState => state;
}
