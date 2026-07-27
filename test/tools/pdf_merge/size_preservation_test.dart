import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  test('Verify page size preservation during merge', () async {
    // 1. Create a source PDF with A4 portrait page
    final sourceDoc1 = PdfDocument();
    sourceDoc1.pageSettings.size = PdfPageSize.a4;
    sourceDoc1.pageSettings.orientation = PdfPageOrientation.portrait;
    sourceDoc1.pageSettings.margins.all = 0;
    sourceDoc1.pages.add();
    final bytes1 = await sourceDoc1.save();
    sourceDoc1.dispose();

    // 2. Create a source PDF with US Letter landscape page
    final sourceDoc2 = PdfDocument();
    sourceDoc2.pageSettings.size = PdfPageSize.letter;
    sourceDoc2.pageSettings.orientation = PdfPageOrientation.landscape;
    sourceDoc2.pageSettings.margins.all = 0;
    sourceDoc2.pages.add();
    final bytes2 = await sourceDoc2.save();
    sourceDoc2.dispose();

    // Re-open source docs
    final doc1 = PdfDocument(inputBytes: bytes1);
    final doc2 = PdfDocument(inputBytes: bytes2);

    final src1PageSize = doc1.pages[0].size;
    final src2PageSize = doc2.pages[0].size;

    // Perform merge preserving exact page dimensions and zero margins
    final dest = PdfDocument();
    for (final doc in [doc1, doc2]) {
      for (int i = 0; i < doc.pages.count; i++) {
        final page = doc.pages[i];
        final section = dest.sections!.add();
        section.pageSettings.size = page.size;
        section.pageSettings.margins.all = 0;
        if (page.size.width > page.size.height) {
          section.pageSettings.orientation = PdfPageOrientation.landscape;
        } else {
          section.pageSettings.orientation = PdfPageOrientation.portrait;
        }

        final newPage = section.pages.add();
        final template = page.createTemplate();
        newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), page.size);
      }
    }

    final mergedBytes = await dest.save();
    dest.dispose();
    doc1.dispose();
    doc2.dispose();

    final mergedDoc = PdfDocument(inputBytes: mergedBytes);
    expect(mergedDoc.pages.count, equals(2));

    expect(mergedDoc.pages[0].size.width, equals(src1PageSize.width));
    expect(mergedDoc.pages[0].size.height, equals(src1PageSize.height));

    expect(mergedDoc.pages[1].size.width, equals(src2PageSize.width));
    expect(mergedDoc.pages[1].size.height, equals(src2PageSize.height));

    mergedDoc.dispose();
  });
}
