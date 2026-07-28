import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import 'pdf_merge_state.dart';

final pdfMergeControllerProvider =
    StateNotifierProvider<PdfMergeController, PdfMergeState>((ref) {
  return PdfMergeController();
});

class PdfMergeController extends StateNotifier<PdfMergeState> {
  final FileService _fileService;

  PdfMergeController({FileService? fileService})
      : _fileService = fileService ?? FileService(),
        super(const PdfMergeState());

  /// Validate and add PDF files to state list.
  Future<void> addFiles(List<PlatformFile> platformFiles) async {
    final List<PdfMergeItem> newValidItems = [];
    String? firstError;

    for (final pf in platformFiles) {
      Uint8List? bytes = pf.bytes;
      if (bytes == null && pf.path != null) {
        final f = File(pf.path!);
        if (f.existsSync()) {
          try {
            bytes = await f.readAsBytes();
          } catch (e) {
            firstError ??= "Could not read '${pf.name}': permission denied or file unreadable.";
            continue;
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        firstError ??= "File '${pf.name}' is empty or unreadable.";
        continue;
      }

      try {
        final doc = PdfDocument(inputBytes: bytes);
        final pageCount = doc.pages.count;
        doc.dispose();

        final item = PdfMergeItem(
          id: '${DateTime.now().microsecondsSinceEpoch}_${pf.name}_${newValidItems.length}',
          path: pf.path,
          name: pf.name,
          sizeBytes: bytes.length,
          pageCount: pageCount,
          bytes: bytes,
        );

        newValidItems.add(item);
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('password') || errStr.contains('encrypted') || errStr.contains('security')) {
          firstError ??= "This file is password-protected and can't be merged. Remove the password first.";
        } else {
          firstError ??= "File '${pf.name}' appears corrupted or unreadable.";
        }
      }
    }

    state = state.copyWith(
      files: [...state.files, ...newValidItems],
      errorMessage: firstError,
      resetError: firstError == null,
    );
  }

  /// Reorder files in list.
  void reorderFiles(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.files.length) return;
    int index = newIndex;
    if (oldIndex < index) {
      index -= 1;
    }

    final updated = List<PdfMergeItem>.from(state.files);
    final item = updated.removeAt(oldIndex);
    updated.insert(index, item);

    state = state.copyWith(files: updated);
  }

  /// Remove single file from list by id.
  void removeFile(String id) {
    final updated = state.files.where((f) => f.id != id).toList();
    state = state.copyWith(
      files: updated,
      resetError: true,
      resetOutput: updated.isEmpty,
    );
  }

  /// Remove all files from list.
  void removeAll() {
    state = const PdfMergeState();
  }

  /// Dismiss error banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Merge PDFs in current list order.
  Future<String?> merge({String? customOutputPath}) async {
    if (state.files.length < 2) {
      state = state.copyWith(errorMessage: "Add at least 2 PDFs to merge");
      return null;
    }

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Merging ${state.files.length} files…",
      resetError: true,
      resetOutput: true,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final destinationDoc = PdfDocument();

      for (final item in state.files) {
        final sourceDoc = PdfDocument(inputBytes: item.bytes);
        for (int i = 0; i < sourceDoc.pages.count; i++) {
          final page = sourceDoc.pages[i];
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
        sourceDoc.dispose();
      }

      final List<int> mergedBytes = await destinationDoc.save();
      destinationDoc.dispose();

      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final defaultFileName = 'merged_$timestamp.pdf';

        final firstFilePath = state.files.first.path;
        final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: firstFilePath);
        targetPath = p.join(outputDir.path, defaultFileName);
      }

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(mergedBytes, flush: true);

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputPath: targetPath,
      );

      return targetPath;
    } on OutOfMemoryError {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This merge is too large to process on this device. Try merging fewer files at once.",
      );
      return null;
    } on FileSystemException catch (e) {
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
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('memory') || errStr.contains('allocation')) {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage: "This merge is too large to process on this device. Try merging fewer files at once.",
        );
      } else {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage: "Merge failed: $e",
        );
      }
      return null;
    }
  }

  @visibleForTesting
  PdfMergeState get testState => state;
}
