import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/core/services/pdf_isolate_worker.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_reference_holder.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_cross_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Diagnose real user files X0 nested content', () async {
    final dirPath = r'C:\Users\harsh\Downloads\AHC\3 - Polity\06 - Constituent Assembly';
    final f1 = File('$dirPath\\संविधान सभा #1.pdf');
    final f2 = File('$dirPath\\संविधान सभा #2.pdf');
    final f3 = File('$dirPath\\संविधान सभा #3.pdf');

    final fileBytesList = [f1.readAsBytesSync(), f2.readAsBytesSync(), f3.readAsBytesSync()];

    final loadedDocs = fileBytesList.map((b) => PdfDocument(inputBytes: b)).toList();
    final dest = PdfDocument();
    dest.compressionLevel = PdfCompressionLevel.best;

    for (final doc in loadedDocs) {
      for (int i = 0; i < doc.pages.count; i++) {
        final page = doc.pages[i];
        final sec = dest.sections!.add();
        sec.pageSettings.size = page.size;
        sec.pageSettings.margins.all = 0;
        sec.pages.add().graphics.drawPdfTemplate(page.createTemplate(), Offset.zero, page.size);
      }
      doc.dispose();
    }

    // Inspect nested X0 on pages 24..26
    for (int p = 24; p <= 26; p++) {
      final pageHelper = PdfPageHelper.getHelper(dest.pages[p]);
      final dict = pageHelper.dictionary!;
      final resDict = PdfCrossTable.dereference(dict['Resources']) as PdfDictionary?;
      final xoDict = PdfCrossTable.dereference(resDict?['XObject']) as PdfDictionary?;
      xoDict?.items?.forEach((k, v) {
        final derefV = PdfCrossTable.dereference(v);
        if (derefV is PdfStream && derefV.containsKey('Resources')) {
          final nestedRes = PdfCrossTable.dereference(derefV['Resources']) as PdfDictionary?;
          final nestedXo = PdfCrossTable.dereference(nestedRes?['XObject']) as PdfDictionary?;
          nestedXo?.items?.forEach((nk, nv) {
            final nName = (nk as PdfName?)?.name;
            final nDeref = PdfCrossTable.dereference(nv);
            if (nName == 'X0' && nDeref is PdfStream) {
              print('Page $p Nested X0 dataStream: "${String.fromCharCodes(nDeref.dataStream ?? [])}"');
              print('Page $p Nested X0 keys: ${nDeref.items?.keys.map((x) => (x as PdfName?)?.name).toList()}');
              if (nDeref.containsKey('Resources')) {
                final x0Res = PdfCrossTable.dereference(nDeref['Resources']) as PdfDictionary?;
                print('Page $p X0 Resources keys: ${x0Res?.items?.keys.map((x) => (x as PdfName?)?.name).toList()}');
                if (x0Res != null && x0Res.containsKey('XObject')) {
                  final x0Xo = PdfCrossTable.dereference(x0Res['XObject']) as PdfDictionary?;
                  print('Page $p X0 XObject entries count: ${x0Xo?.count}');
                  x0Xo?.items?.forEach((x0k, x0v) {
                    final x0Deref = PdfCrossTable.dereference(x0v);
                    print('  X0 XObject ${(x0k as PdfName?)?.name} -> ${x0Deref.runtimeType}');
                  });
                }
              }
            }
          });
        }
      });
    }

    dest.dispose();
  });
}
