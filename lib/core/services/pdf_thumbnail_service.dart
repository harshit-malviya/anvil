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
}
