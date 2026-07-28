import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import 'pdf_to_image_state.dart';

typedef PageRenderer = Future<Uint8List?> Function(
  Uint8List pdfBytes,
  int pageIndex,
  int targetDpi,
  ImageFormat format,
);

final pdfToImageControllerProvider =
    StateNotifierProvider<PdfToImageController, PdfToImageState>((ref) {
  return PdfToImageController();
});

class PdfToImageController extends StateNotifier<PdfToImageState> {
  final PdfThumbnailService _thumbnailService;
  final PageRenderer? _customRenderer;
  final FileService _fileService;

  PdfToImageController({
    PdfThumbnailService? thumbnailService,
    PageRenderer? customRenderer,
    FileService? fileService,
  })  : _thumbnailService = thumbnailService ?? PdfThumbnailService(),
        _customRenderer = customRenderer,
        _fileService = fileService ?? FileService(),
        super(const PdfToImageState());

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
    double firstWidth = 612.0;
    double firstHeight = 792.0;
    try {
      final doc = PdfDocument(inputBytes: bytes);
      pageCount = doc.pages.count;
      if (pageCount > 0) {
        firstWidth = doc.pages[0].size.width;
        firstHeight = doc.pages[0].size.height;
      }
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

    // All pages selected by default
    final initialSelected = Set<int>.from(List.generate(pageCount, (i) => i));

    state = state.copyWith(
      file: platformFile,
      fileBytes: bytes,
      totalPageCount: pageCount,
      selectedPages: initialSelected,
      firstPageWidthPt: firstWidth,
      firstPageHeightPt: firstHeight,
      isProcessing: false,
      isLoadingThumbnails: true,
      resetProgressMessage: true,
      resetError: true,
    );

    // Asynchronously generate page thumbnails
    _generateThumbnails(bytes);
  }

  /// Generate thumbnails for all pages asynchronously.
  Future<void> _generateThumbnails(Uint8List bytes) async {
    final Map<int, Uint8List?> thumbs = {};
    await _thumbnailService.generateThumbnails(
      bytes,
      onPageRendered: (pageIndex, thumbnailBytes) {
        if (state.fileBytes != bytes) return;
        thumbs[pageIndex] = thumbnailBytes;
        state = state.copyWith(
          thumbnails: Map<int, Uint8List?>.from(thumbs),
        );
      },
    );

    if (state.fileBytes == bytes) {
      state = state.copyWith(
        isLoadingThumbnails: false,
      );
    }
  }

  /// Toggle selection for page index.
  void togglePageSelected(int pageIndex) {
    if (pageIndex < 0 || pageIndex >= state.totalPageCount) return;

    final updated = Set<int>.from(state.selectedPages);
    if (updated.contains(pageIndex)) {
      updated.remove(pageIndex);
    } else {
      updated.add(pageIndex);
    }

    state = state.copyWith(
      selectedPages: updated,
      resetError: true,
    );
  }

  /// Select all pages.
  void selectAll() {
    final all = Set<int>.from(List.generate(state.totalPageCount, (i) => i));
    state = state.copyWith(selectedPages: all, resetError: true);
  }

  /// Deselect all pages.
  void selectNone() {
    state = state.copyWith(selectedPages: const {}, resetError: true);
  }

  /// Set target image format (PNG/JPEG).
  void setFormat(ImageFormat format) {
    state = state.copyWith(format: format);
  }

  /// Set target resolution (72, 150, 300 DPI).
  void setResolution(ExportResolution res) {
    state = state.copyWith(resolution: res);
  }

  /// Clear active error message.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Reset state to default empty state.
  void reset() {
    state = const PdfToImageState();
  }

  /// Export selected pages to image file(s).
  Future<String?> export({String? customOutputPath}) async {
    if (!state.canExport || state.fileBytes == null) {
      if (state.selectedCount == 0) {
        state = state.copyWith(errorMessage: "Select at least one page to export.");
      }
      return null;
    }

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Preparing export…",
      progressPercent: 0.0,
      resetError: true,
      resetOutput: true,
      exportedCount: 0,
      skippedPages: const [],
    );
    await Future.delayed(const Duration(milliseconds: 50));

    // Selected page indices in document order (0-indexed)
    final sortedPages = state.selectedPages.toList()..sort();
    final bool isSingle = sortedPages.length == 1;

    try {
      final ext = state.format.fileExtension;
      final dpi = state.resolution.dpi;
      final pdfxFormat = state.format == ImageFormat.png
          ? pdfx.PdfPageImageFormat.png
          : pdfx.PdfPageImageFormat.jpeg;

      // Extract source base name (without extension)
      final sourceName = state.file?.name ?? 'document.pdf';
      final baseName = p.basenameWithoutExtension(sourceName);

      if (isSingle) {
        final pageIdx = sortedPages.first;
        state = state.copyWith(
          progressMessage: "Exporting page ${pageIdx + 1}…",
          progressPercent: 0.5,
        );

        Uint8List? imageBytes;
        if (_customRenderer != null) {
          imageBytes = await _customRenderer!(state.fileBytes!, pageIdx, dpi, state.format);
        } else {
          imageBytes = await _thumbnailService.renderPage(
            state.fileBytes!,
            pageIdx,
            targetDpi: dpi,
            format: pdfxFormat,
          );
        }

        if (imageBytes == null) {
          final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
          if (elapsedMs < 600) {
            await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
          }
          state = state.copyWith(
            isProcessing: false,
            resetProgressMessage: true,
            resetProgressPercent: true,
            errorMessage: "Page ${pageIdx + 1} couldn't be rendered.",
          );
          return null;
        }

        String targetFilePath;
        if (customOutputPath != null && customOutputPath.isNotEmpty) {
          targetFilePath = customOutputPath;
        } else {
          final fileName = '${baseName}_page${pageIdx + 1}.$ext';
          final sourceFilePath = state.file?.path;
          final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: sourceFilePath);
          targetFilePath = p.join(outputDir.path, fileName);
        }

        final file = File(targetFilePath);
        await file.writeAsBytes(imageBytes, flush: true);

        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsedMs < 600) {
          await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
        }

        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          resetProgressPercent: true,
          outputPath: targetFilePath,
          exportedCount: 1,
          skippedPages: const [],
          isSingleFileExport: true,
        );

        return targetFilePath;
      } else {
        // Multi-page export into folder
        String baseDirName = '${baseName}_images';
        String targetDirPath;

        final sourceFilePath = state.file?.path;
        final parentDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: sourceFilePath);

        targetDirPath = p.join(parentDir.path, baseDirName);
        int counter = 2;
        while (Directory(targetDirPath).existsSync()) {
          targetDirPath = p.join(parentDir.path, '${baseDirName}_$counter');
          counter++;
        }

        final outDir = Directory(targetDirPath);
        await outDir.create(recursive: true);

        int exported = 0;
        final List<int> skipped = [];

        for (int i = 0; i < sortedPages.length; i++) {
          final pageIdx = sortedPages[i];
          final progressRatio = (i + 1) / sortedPages.length;
          state = state.copyWith(
            progressMessage: "Exporting page ${pageIdx + 1} (${i + 1} of ${sortedPages.length})…",
            progressPercent: progressRatio,
          );
          await Future.delayed(const Duration(milliseconds: 15));

          Uint8List? imageBytes;
          if (_customRenderer != null) {
            imageBytes = await _customRenderer!(state.fileBytes!, pageIdx, dpi, state.format);
          } else {
            imageBytes = await _thumbnailService.renderPage(
              state.fileBytes!,
              pageIdx,
              targetDpi: dpi,
              format: pdfxFormat,
            );
          }

          if (imageBytes != null) {
            final imgFileName = '${baseName}_page${pageIdx + 1}.$ext';
            final imgFile = File(p.join(targetDirPath, imgFileName));
            await imgFile.writeAsBytes(imageBytes, flush: true);
            exported++;
          } else {
            // Record 1-indexed skipped page
            skipped.add(pageIdx + 1);
          }
        }

        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsedMs < 600) {
          await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
        }

        if (exported == 0) {
          // Cleanup empty directory
          try {
            if (outDir.existsSync()) {
              outDir.deleteSync(recursive: true);
            }
          } catch (_) {}

          state = state.copyWith(
            isProcessing: false,
            resetProgressMessage: true,
            resetProgressPercent: true,
            errorMessage: "Failed to render selected pages.",
          );
          return null;
        }

        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          resetProgressPercent: true,
          outputPath: targetDirPath,
          exportedCount: exported,
          skippedPages: skipped,
          isSingleFileExport: false,
        );

        return targetDirPath;
      }
    } on OutOfMemoryError {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        resetProgressPercent: true,
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
        resetProgressPercent: true,
        errorMessage: "Couldn't save image files — ${e.message}. Try a different location.",
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
        resetProgressPercent: true,
        errorMessage: "Failed to export images: $e",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfToImageState get testState => state;
}
