import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/pdf_isolate_worker.dart';
import '../../core/services/pdf_validation_service.dart';
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

    final valInfo = PdfValidationService.validate(bytes);
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

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Compressing PDF…",
      resetError: true,
      resetOutput: true,
      resetResultType: true,
    );

    try {
      // Map compression level to index for isolate
      final int levelIndex;
      switch (state.level) {
        case CompressionLevel.low:
          levelIndex = 0;
          break;
        case CompressionLevel.medium:
          levelIndex = 1;
          break;
        case CompressionLevel.high:
          levelIndex = 2;
          break;
      }

      // Run heavy PDF work on a background isolate
      final Uint8List compressedBytes = await compute(
        isolateCompressPdf,
        CompressParams(inputBytes: state.fileBytes!, levelIndex: levelIndex),
      );

      final int outputLength = compressedBytes.length;

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

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
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Couldn't save compressed file — ${e.message}.",
      );
      return null;
    } catch (e) {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This file couldn't be compressed. It may be damaged or use an unsupported format.",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfCompressState get testState => state;
}
