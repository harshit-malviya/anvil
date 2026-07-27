import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

class PdfThumbnailService {
  /// Render page thumbnails for a PDF given its raw [bytes].
  ///
  /// Calls optional [onPageRendered] callback as each page finishes rendering.
  Future<List<Uint8List?>> generateThumbnails(
    Uint8List bytes, {
    void Function(int pageIndex, Uint8List? thumbnailBytes)? onPageRendered,
  }) async {
    final List<Uint8List?> thumbnails = [];
    try {
      final pdfxDoc = await pdfx.PdfDocument.openData(bytes);
      final totalPages = pdfxDoc.pagesCount;

      for (int i = 0; i < totalPages; i++) {
        Uint8List? imgBytes;
        try {
          final page = await pdfxDoc.getPage(i + 1);
          final pageImage = await page.render(
            width: page.width / 2 > 300 ? 300 : (page.width / 2 < 100 ? 150 : page.width / 2),
            height: page.height / 2 > 400 ? 400 : (page.height / 2 < 120 ? 200 : page.height / 2),
            format: pdfx.PdfPageImageFormat.jpeg,
          );
          await page.close();
          imgBytes = pageImage?.bytes;
        } catch (_) {
          imgBytes = null;
        }
        thumbnails.add(imgBytes);
        onPageRendered?.call(i, imgBytes);
      }

      await pdfxDoc.close();
    } catch (_) {
      // Gracefully handle native rendering errors (e.g. headless tests)
    }
    return thumbnails;
  }

  /// Render a single page of a PDF at specified [targetDpi] and image [format].
  Future<Uint8List?> renderPage(
    Uint8List bytes,
    int pageIndex, {
    required int targetDpi,
    required pdfx.PdfPageImageFormat format,
  }) async {
    try {
      final pdfxDoc = await pdfx.PdfDocument.openData(bytes);
      if (pageIndex < 0 || pageIndex >= pdfxDoc.pagesCount) {
        await pdfxDoc.close();
        return null;
      }
      final page = await pdfxDoc.getPage(pageIndex + 1);
      final double scale = targetDpi / 72.0;
      final double targetWidth = page.width * scale;
      final double targetHeight = page.height * scale;

      final pageImage = await page.render(
        width: targetWidth,
        height: targetHeight,
        format: format,
      );
      await page.close();
      await pdfxDoc.close();
      return pageImage?.bytes;
    } catch (_) {
      return null;
    }
  }

  /// Render multiple [pageIndexes] of a PDF at specified [targetDpi] and image [format].
  /// Calls optional [onProgress] as pages are rendered.
  Future<Map<int, Uint8List>> renderPages(
    Uint8List bytes,
    List<int> pageIndexes, {
    required int targetDpi,
    required pdfx.PdfPageImageFormat format,
    void Function(int current, int total)? onProgress,
  }) async {
    final Map<int, Uint8List> results = {};
    try {
      final pdfxDoc = await pdfx.PdfDocument.openData(bytes);
      for (int i = 0; i < pageIndexes.length; i++) {
        final idx = pageIndexes[i];
        onProgress?.call(i + 1, pageIndexes.length);
        try {
          if (idx >= 0 && idx < pdfxDoc.pagesCount) {
            final page = await pdfxDoc.getPage(idx + 1);
            final double scale = targetDpi / 72.0;
            final double targetWidth = page.width * scale;
            final double targetHeight = page.height * scale;

            final pageImage = await page.render(
              width: targetWidth,
              height: targetHeight,
              format: format,
            );
            await page.close();
            if (pageImage?.bytes != null) {
              results[idx] = pageImage!.bytes;
            }
          }
        } catch (_) {
          // Skip page if individual page rendering fails
        }
      }
      await pdfxDoc.close();
    } catch (_) {
      // Gracefully handle native errors
    }
    return results;
  }
}
