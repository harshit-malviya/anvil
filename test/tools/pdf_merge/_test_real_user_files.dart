import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/core/services/pdf_isolate_worker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Verify संविधान सभा #1–3 merge with dedup disabled produces ~1.98MB intact output', () async {
    final dirPath = r'C:\Users\harsh\Downloads\AHC\3 - Polity\06 - Constituent Assembly';
    final f1 = File('$dirPath\\संविधान सभा #1.pdf');
    final f2 = File('$dirPath\\संविधान सभा #2.pdf');
    final f3 = File('$dirPath\\संविधान सभा #3.pdf');

    final fileBytesList = [f1.readAsBytesSync(), f2.readAsBytesSync(), f3.readAsBytesSync()];
    final fileNames = ['संविधान सभा #1.pdf', 'संविधान सभा #2.pdf', 'संविधान सभा #3.pdf'];

    final inputSize = fileBytesList.fold(0, (sum, b) => sum + b.length);
    print('Input files combined size: $inputSize bytes');

    final mergedBytes = await isolateMergePdfs(MergeParams(
      fileBytesList: fileBytesList,
      fileNames: fileNames,
      insertDividers: false,
    ));

    print('Merged output size (dedup disabled): ${mergedBytes.length} bytes');

    final doc = PdfDocument(inputBytes: mergedBytes);
    print('Merged page count: ${doc.pages.count}');
    
    expect(doc.pages.count, equals(27));
    // Output size should be ~1.98 MB (close to combined input size 1.946 MB), NOT 60-70 KB!
    expect(mergedBytes.length, greaterThan(1800000), reason: 'Output size must be ~1.98MB with all content intact');
    doc.dispose();
  });
}
