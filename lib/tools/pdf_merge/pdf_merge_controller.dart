import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_isolate_worker.dart';
import 'pdf_merge_state.dart';

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Pre-render divider strip using Flutter's HarfBuzz engine for 100% accurate Complex Text Layout (Devanagari/Hindi).
Future<Uint8List> renderDividerImage({
  required String text,
  required double widthPt,
  required double heightPt,
  double fontSize = 14.0,
  bool isBold = false,
  double pixelRatio = 3.0,
}) async {
  final widthPx = (widthPt * pixelRatio).round();
  final heightPx = (heightPt * pixelRatio).round();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, widthPx.toDouble(), heightPx.toDouble()));

  final bgPaint = Paint()..color = const Color(0xFFFFFFFF);
  canvas.drawRect(Rect.fromLTWH(0, 0, widthPx.toDouble(), heightPx.toDouble()), bgPaint);

  final textStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: fontSize * pixelRatio,
    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    color: const Color(0xFF1E2226),
  );

  final textPainter = TextPainter(
    text: TextSpan(text: text, style: textStyle),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '...',
  );

  textPainter.layout(maxWidth: widthPx * 0.9);

  final x = (widthPx - textPainter.width) / 2;
  final y = (heightPx - textPainter.height) / 2;
  textPainter.paint(canvas, Offset(x, y));

  final picture = recorder.endRecording();
  final image = await picture.toImage(widthPx, heightPx);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

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

  /// Set whether to insert divider pages between files.
  void setInsertDividers(bool value) {
    state = state.copyWith(insertDividers: value);
  }

  /// Set divider font size in predefined range.
  void setDividerFontSize(double size) {
    state = state.copyWith(dividerFontSize: size);
  }

  /// Set whether divider text is bold.
  void setDividerIsBold(bool isBold) {
    state = state.copyWith(dividerIsBold: isBold);
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

    try {
      // Run heavy PDF work on a background isolate
      final fileBytesList = state.files.map((f) => f.bytes).toList();
      final fileNames = state.files.map((f) => p.basenameWithoutExtension(f.name)).toList();
      List<Uint8List>? dividerImages;
      Uint8List? fontBytes;
      if (state.insertDividers) {
        dividerImages = [];
        for (int k = 1; k < state.files.length; k++) {
          final item = state.files[k];
          final fileName = p.basenameWithoutExtension(item.name);

          double widthPt = 595.28;
          try {
            final doc = PdfDocument(inputBytes: item.bytes);
            if (doc.pages.count > 0) {
              widthPt = doc.pages[0].size.width;
            }
            doc.dispose();
          } catch (_) {}

          try {
            final pngBytes = await renderDividerImage(
              text: fileName,
              widthPt: widthPt,
              heightPt: 72.0,
              fontSize: state.dividerFontSize,
              isBold: state.dividerIsBold,
            );
            dividerImages.add(pngBytes);
          } catch (_) {
            dividerImages.add(Uint8List(0));
          }
        }

        try {
          final fontData = await rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf');
          fontBytes = fontData.buffer.asUint8List();
        } catch (_) {
          fontBytes = null;
        }
      }

      final params = MergeParams(
        fileBytesList: fileBytesList,
        fileNames: fileNames,
        insertDividers: state.insertDividers,
        dividerFontSize: state.dividerFontSize,
        dividerIsBold: state.dividerIsBold,
        fontBytes: fontBytes,
        dividerImages: dividerImages,
      );
      final Uint8List mergedBytes = await compute(isolateMergePdfs, params);

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
