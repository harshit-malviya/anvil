import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import '../pdf_insert_pages/pdf_insert_pages_controller.dart';
import 'pdf_insert_image_as_page_state.dart';

final pdfInsertImageAsPageControllerProvider =
    StateNotifierProvider<PdfInsertImageAsPageController, PdfInsertImageAsPageState>((ref) {
  return PdfInsertImageAsPageController();
});

class PdfInsertImageAsPageController extends StateNotifier<PdfInsertImageAsPageState> {
  final FileService _fileService;
  final PdfThumbnailService _thumbnailService;

  PdfInsertImageAsPageController({
    FileService? fileService,
    PdfThumbnailService? thumbnailService,
  })  : _fileService = fileService ?? FileService(),
        _thumbnailService = thumbnailService ?? PdfThumbnailService(),
        super(const PdfInsertImageAsPageState());

  /// Load and validate target PDF document into which the image page will be inserted.
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

    try {
      final doc = PdfDocument(inputBytes: bytes);
      final pageCount = doc.pages.count;
      doc.dispose();

      if (pageCount == 0) {
        state = state.copyWith(
          errorMessage: "File '${platformFile.name}' contains no pages.",
          fitMode: PageFitMode.fitToImage,
          resetError: false,
        );
        return;
      }

      final thumbnails = await _thumbnailService.generateThumbnails(bytes);

      // Default insertion point is 'at the end' (after the last target page)
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
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('password') || errStr.contains('encrypted') || errStr.contains('security')) {
        state = state.copyWith(
          errorMessage: "This file is password-protected and can't be modified. Remove the password first.",
          resetError: false,
        );
      } else {
        state = state.copyWith(
          errorMessage: "File '${platformFile.name}' appears corrupted or unreadable.",
          resetError: false,
        );
      }
    }
  }

  /// Load and validate image file to insert as a page.
  Future<void> loadImage(PlatformFile platformFile) async {
    final ext = p.extension(platformFile.name).toLowerCase();
    if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') {
      state = state.copyWith(
        errorMessage: "Only JPEG and PNG images are supported.",
        resetError: false,
      );
      return;
    }

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
        errorMessage: "This image couldn't be read. Try a different file.",
        resetError: false,
      );
      return;
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) {
      state = state.copyWith(
        errorMessage: "This image couldn't be read. Try a different file.",
        resetError: false,
      );
      return;
    }

    // ASSUMPTION: Downscale oversized images to max dimension of 3000px to avoid PDF bloat while preserving clarity.
    const maxDimension = 3000;
    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(decoded, width: maxDimension, maintainAspect: true);
      } else {
        decoded = img.copyResize(decoded, height: maxDimension, maintainAspect: true);
      }
      if (ext == '.png') {
        bytes = Uint8List.fromList(img.encodePng(decoded));
      } else {
        bytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      }
    }

    // Generate preview thumbnail for UI display
    final previewImg = (decoded.width > 400 || decoded.height > 400)
        ? (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: 400, maintainAspect: true)
            : img.copyResize(decoded, height: 400, maintainAspect: true))
        : decoded;
    final thumbnailBytes = Uint8List.fromList(img.encodeJpg(previewImg, quality: 80));

    state = state.copyWith(
      imageFile: platformFile,
      imageBytes: bytes,
      imageThumbnail: thumbnailBytes,
      imageWidth: decoded.width,
      imageHeight: decoded.height,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Change page fit mode (Match neighboring page vs Fit to image).
  void setPageFitMode(PageFitMode mode) {
    if (mode == PageFitMode.matchNeighboringPage && state.targetPageCount == 0) {
      state = state.copyWith(fitMode: PageFitMode.fitToImage);
      return;
    }
    state = state.copyWith(fitMode: mode);
  }

  /// Set target insertion point index (`-1` = at start, `0` to `targetPageCount - 1`).
  void setInsertionPoint(int afterTargetPageIndex) {
    if (afterTargetPageIndex < -1 || afterTargetPageIndex >= state.targetPageCount) return;
    state = state.copyWith(insertionPoint: afterTargetPageIndex);
  }

  /// Clear target PDF document.
  void clearTarget() {
    state = const PdfInsertImageAsPageState();
  }

  /// Clear loaded image file.
  void clearImage() {
    state = state.copyWith(
      resetImage: true,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Dismiss error message banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Convert loaded image to single-page PDF and splice into target PDF.
  Future<String?> insertImagePage({String? customOutputPath}) async {
    if (!state.canSubmit) {
      if (!state.hasTarget) {
        state = state.copyWith(errorMessage: "Select a target PDF document first.");
      } else if (!state.hasImage) {
        state = state.copyWith(errorMessage: "Select an image file to insert.");
      }
      return null;
    }

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Inserting image as page into document…",
      resetError: true,
      resetOutput: true,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      // 1. Resolve page size and image rectangle
      Size pageSize;
      Rect imgRect;

      if (state.fitMode == PageFitMode.fitToImage || state.targetPageCount == 0) {
        pageSize = Size(state.imageWidth.toDouble(), state.imageHeight.toDouble());
        imgRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);
      } else {
        // Resolve neighbor page index
        int neighborIdx;
        if (state.insertionPoint == -1) {
          neighborIdx = 0;
        } else if (state.insertionPoint == state.targetPageCount - 1) {
          neighborIdx = state.targetPageCount - 1;
        } else {
          neighborIdx = state.insertionPoint; // Page immediately before insertion point
        }

        final targetDoc = PdfDocument(inputBytes: state.targetBytes!);
        if (neighborIdx >= 0 && neighborIdx < targetDoc.pages.count) {
          final neighborPage = targetDoc.pages[neighborIdx];
          pageSize = neighborPage.size;
        } else {
          pageSize = Size(state.imageWidth.toDouble(), state.imageHeight.toDouble());
        }
        targetDoc.dispose();

        // Calculate aspect ratio fit (centered, un-distorted)
        final double scale = min(pageSize.width / state.imageWidth, pageSize.height / state.imageHeight);
        final double sw = state.imageWidth * scale;
        final double sh = state.imageHeight * scale;
        final double dx = (pageSize.width - sw) / 2.0;
        final double dy = (pageSize.height - sh) / 2.0;
        imgRect = Rect.fromLTWH(dx, dy, sw, sh);
      }

      // 2. Create single-page PDF containing the image
      final imgPdf = PdfDocument();
      final section = imgPdf.sections!.add();
      section.pageSettings.size = pageSize;
      section.pageSettings.margins.all = 0;
      if (pageSize.width > pageSize.height) {
        section.pageSettings.orientation = PdfPageOrientation.landscape;
      } else {
        section.pageSettings.orientation = PdfPageOrientation.portrait;
      }

      final page = section.pages.add();

      // Explicitly draw white background to flatten PNG transparency
      page.graphics.drawRectangle(
        brush: PdfSolidBrush(PdfColor(255, 255, 255)),
        bounds: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      );

      final pdfImage = PdfBitmap(state.imageBytes!);
      page.graphics.drawImage(pdfImage, imgRect);

      final List<int> singlePagePdfBytes = await imgPdf.save();
      imgPdf.dispose();

      // 3. Splice single-page PDF into target document using shared logic
      final List<int> resultBytes = await PdfInsertPagesController.splicePages(
        targetBytes: state.targetBytes!,
        sourceBytes: Uint8List.fromList(singlePagePdfBytes),
        selectedSourceIndices: const [0],
        insertionPoint: state.insertionPoint,
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
        errorMessage: "This insertion is too large to process on this device.",
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
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Image insertion failed: $e",
      );
      return null;
    }
  }

  @visibleForTesting
  PdfInsertImageAsPageState get testState => state;
}
