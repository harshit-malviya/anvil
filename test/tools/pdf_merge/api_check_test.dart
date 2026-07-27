import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('Verify Syncfusion PDF template drawing merge', () async {
    final doc1 = PdfDocument();
    doc1.pages.add();
    final bytes1 = await doc1.save();
    doc1.dispose();

    final doc2 = PdfDocument();
    doc2.pages.add();
    final bytes2 = await doc2.save();
    doc2.dispose();

    final dest = PdfDocument();
    final source1 = PdfDocument(inputBytes: bytes1);
    final source2 = PdfDocument(inputBytes: bytes2);

    for (int i = 0; i < source1.pages.count; i++) {
      final page = source1.pages[i];
      final template = page.createTemplate();
      final newPage = dest.pages.add();
      newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), page.size);
    }

    for (int i = 0; i < source2.pages.count; i++) {
      final page = source2.pages[i];
      final template = page.createTemplate();
      final newPage = dest.pages.add();
      newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), page.size);
    }

    final mergedBytes = await dest.save();
    dest.dispose();
    source1.dispose();
    source2.dispose();

    final checkDoc = PdfDocument(inputBytes: mergedBytes);
    expect(checkDoc.pages.count, equals(2));
    checkDoc.dispose();
  });
}
