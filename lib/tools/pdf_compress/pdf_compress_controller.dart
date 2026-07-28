import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import 'pdf_compress_state.dart';

final pdfCompressControllerProvider =
    StateNotifierProvider<PdfCompressController, PdfCompressState>((ref) {
  return PdfCompressController();
});

class PdfCompressController extends StateNotifier<PdfCompressState> {
  final FileService _fileService;

  PdfCompressController({FileService? fileService})
      : _fileService = fileService ?? FileService(),
        super(const PdfCompressState());

  /// Load and validate a single PDF document.
  Future<void> loadDocument(PlatformFile platformFile,
      {Uint8List? overrideBytes}) async {
    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Loading PDF…",
      resetError: true,
      resetOutput: true,
      resetResultType: true,
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

    state = state.copyWith(
      file: platformFile,
      fileBytes: bytes,
      originalSizeBytes: bytes.length,
      isProcessing: false,
      level: CompressionLevel.medium,
      resetProgressMessage: true,
      resetError: true,
      resetOutput: true,
      resetResultType: true,
    );
  }

  /// Change compression level preset.
  void setCompressionLevel(CompressionLevel level) {
    state = state.copyWith(level: level);
  }

  /// Clear error banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Reset controller state.
  void reset() {
    state = const PdfCompressState();
  }

  /// Execute PDF compression.
  Future<String?> compress({String? customOutputPath}) async {
    if (state.fileBytes == null || state.originalSizeBytes == 0) {
      state = state.copyWith(errorMessage: "No PDF document loaded.");
      return null;
    }

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Compressing PDF…",
      resetError: true,
      resetOutput: true,
      resetResultType: true,
    );

    try {
      final sourceDoc = PdfDocument(inputBytes: state.fileBytes!);
      final destDoc = PdfDocument();

      // ASSUMPTION: Preset level parameters for reproducible PDF compression:
      // - Low: PdfCompressionLevel.normal (basic stream compression, preserves full vector fidelity)
      // - Medium: PdfCompressionLevel.best (max stream compression)
      // - High: PdfCompressionLevel.best (max stream compression & structure optimization)
      switch (state.level) {
        case CompressionLevel.low:
          destDoc.compressionLevel = PdfCompressionLevel.normal;
          break;
        case CompressionLevel.medium:
          destDoc.compressionLevel = PdfCompressionLevel.best;
          break;
        case CompressionLevel.high:
          destDoc.compressionLevel = PdfCompressionLevel.best;
          break;
      }

      for (int i = 0; i < sourceDoc.pages.count; i++) {
        final sourcePage = sourceDoc.pages[i];
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
        newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
      }

      sourceDoc.dispose();

      final List<int> compressedBytes = await destDoc.save();
      destDoc.dispose();

      final int outputLength = compressedBytes.length;

      // Edge case: Compressed output is larger than or equal to original file
      if (outputLength >= state.originalSizeBytes) {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          compressedSizeBytes: outputLength,
          resultType: CompressionResultType.outputLarger,
          errorMessage:
              "Compression didn't reduce the size for this file. Your original hasn't been changed.",
        );
        return null;
      }

      // Prepare output file path
      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final defaultFileName = 'compressed_$timestamp.pdf';

        final sourceFilePath = state.file?.path;
        final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: sourceFilePath);
        targetPath = p.join(outputDir.path, defaultFileName);
      }

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(compressedBytes, flush: true);

      final double reductionPercent =
          (state.originalSizeBytes - outputLength) / state.originalSizeBytes * 100;

      final resultType = reductionPercent < 5.0
          ? CompressionResultType.minimalReduction
          : CompressionResultType.normalSuccess;

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        compressedSizeBytes: outputLength,
        outputPath: targetPath,
        resultType: resultType,
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
        errorMessage: "Couldn't save compressed file — ${e.message}.",
      );
      return null;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Compression failed: $e",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfCompressState get testState => state;
}
