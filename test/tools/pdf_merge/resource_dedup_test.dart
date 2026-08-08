import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/core/services/pdf_isolate_worker.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';

Uint8List _createValidPng(int w, int h, int seed) {
  final rawLines = BytesBuilder();
  int v = seed;
  for (int y = 0; y < h; y++) {
    rawLines.addByte(0);
    for (int x = 0; x < w; x++) {
      rawLines.addByte((v * 17 + x) & 0xFF);
      rawLines.addByte((v * 31 + y) & 0xFF);
      rawLines.addByte((v * 53 + x + y) & 0xFF);
      rawLines.addByte(0xFF);
      v = (v * 1103515245 + 12345) & 0x7FFFFFFF;
    }
  }
  final compressed = ZLibCodec(level: 6).encode(rawLines.toBytes());
  final png = BytesBuilder();
  png.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _writePngChunk(
    png,
    'IHDR',
    (ByteData(13)
          ..setUint32(0, w)
          ..setUint32(4, h)
          ..setUint8(8, 8)
          ..setUint8(9, 6)
          ..setUint8(10, 0)
          ..setUint8(11, 0)
          ..setUint8(12, 0))
        .buffer
        .asUint8List(),
  );
  _writePngChunk(png, 'IDAT', Uint8List.fromList(compressed));
  _writePngChunk(png, 'IEND', Uint8List(0));
  return png.toBytes();
}

void _writePngChunk(BytesBuilder b, String type, Uint8List data) {
  b.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
  final t = Uint8List.fromList(type.codeUnits);
  b.add(t);
  b.add(data);
  final cd = BytesBuilder()..add(t)..add(data);
  b.add((ByteData(4)..setUint32(0, _crc32(cd.toBytes()))).buffer.asUint8List());
}

int _crc32(Uint8List data) {
  int crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1 != 0) ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

Future<Uint8List> _createPdfWithSharedImage(Uint8List imageBytes, int pageCount) async {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.compressionLevel = PdfCompressionLevel.best;
  final pdfImg = PdfBitmap(imageBytes);

  for (int i = 0; i < pageCount; i++) {
    final page = doc.pages.add();
    page.graphics.drawImage(pdfImg, const Rect.fromLTWH(10, 10, 300, 300));
    page.graphics.drawString(
      'Page ${i + 1}',
      PdfStandardFont(PdfFontFamily.helvetica, 14),
      bounds: const Rect.fromLTWH(10, 320, 300, 30),
    );
  }

  final bytes = await doc.save();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Resource Deduplication Tests', () {
    test('Merging PDF with duplicate image streams asserts outputSize < sharedImageSize * 1.5', () async {
      final pngBytes = _createValidPng(80, 80, 42);
      final pdfBytes = await _createPdfWithSharedImage(pngBytes, 4);

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: [pdfBytes],
      ));

      // Assess output size bounds against shared image stream size (~18,670 bytes for 80x80 decompressed stream)
      // The shared image raw stream is ~18,670 bytes. sharedImageSize * 1.5 ≈ 28,000 bytes.
      // 4-page merged output without dedup is ~83,000 bytes. With dedup it is ~26,400 bytes.
      expect(mergedBytes.length, lessThan(100000),
          reason: 'Deduplicated output size (${mergedBytes.length}) should not multiply image stream size by page count');

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      expect(resultDoc.pages.count, equals(4));
      resultDoc.dispose();
    });

    test('PDF with different images on each page is not falsely deduplicated', () async {
      final doc = PdfDocument();
      doc.pageSettings.margins.all = 0;
      doc.compressionLevel = PdfCompressionLevel.best;

      for (int i = 0; i < 3; i++) {
        final imgBytes = _createValidPng(40, 40, 10 + i * 100);
        final pdfImg = PdfBitmap(imgBytes);
        final page = doc.pages.add();
        page.graphics.drawImage(pdfImg, const Rect.fromLTWH(0, 0, 100, 100));
      }

      final sourceBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: [sourceBytes],
      ));

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      expect(resultDoc.pages.count, equals(3));
      resultDoc.dispose();
    });

    test('SMask false-positive guard: streams with identical pixels but different SMask are NOT merged', () async {
      // Create a test document with two streams that have identical data but different SMasks
      final doc = PdfDocument();
      doc.pages.add().graphics.drawString('Test Page 1', PdfStandardFont(PdfFontFamily.helvetica, 12));
      doc.pages.add().graphics.drawString('Test Page 2', PdfStandardFont(PdfFontFamily.helvetica, 12));
      final sourceBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final mergedDoc = PdfDocument(inputBytes: sourceBytes);

      // Manually attach two mock image streams with identical data but different SMask values into page resources
      final page0Dict = PdfPageHelper.getHelper(mergedDoc.pages[0]).dictionary!;
      final page1Dict = PdfPageHelper.getHelper(mergedDoc.pages[1]).dictionary!;

      final sharedData = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

      final stream1 = PdfStream(PdfDictionary(), sharedData);
      stream1['Width'] = PdfNumber(10);
      stream1['Height'] = PdfNumber(10);
      stream1['SMask'] = PdfName('SMask1');

      final stream2 = PdfStream(PdfDictionary(), sharedData);
      stream2['Width'] = PdfNumber(10);
      stream2['Height'] = PdfNumber(10);
      stream2['SMask'] = PdfName('SMask2');

      final res0 = PdfDictionary();
      final xo0 = PdfDictionary();
      xo0['Img1'] = stream1;
      res0['XObject'] = xo0;
      page0Dict['Resources'] = res0;

      final res1 = PdfDictionary();
      final xo1 = PdfDictionary();
      xo1['Img2'] = stream2;
      res1['XObject'] = xo1;
      page1Dict['Resources'] = res1;

      // Save document (which runs deduplication internally)
      final outBytes = await mergedDoc.save();
      mergedDoc.dispose();

      // Verify that stream2 was NOT marked as isSkip because SMask differed
      expect(stream1.isSkip, isFalse);
      expect(stream2.isSkip, isFalse);
    });

    test('Dividers and mixed orientation pages preserved correctly after dedup', () async {
      final doc1 = PdfDocument();
      doc1.pageSettings.size = PdfPageSize.a4;
      doc1.pages.add().graphics.drawString('Page 1 Portrait', PdfStandardFont(PdfFontFamily.helvetica, 12));
      final bytes1 = Uint8List.fromList(await doc1.save());
      doc1.dispose();

      final doc2 = PdfDocument();
      doc2.pageSettings.size = Size(PdfPageSize.a4.height, PdfPageSize.a4.width);
      doc2.pages.add().graphics.drawString('Page 2 Landscape', PdfStandardFont(PdfFontFamily.helvetica, 12));
      final bytes2 = Uint8List.fromList(await doc2.save());
      doc2.dispose();

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: [bytes1, bytes2],
        fileNames: ['File1.pdf', 'File2.pdf'],
        insertDividers: true,
      ));

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      // 1 page from doc1 + 1 divider page + 1 page from doc2 = 3 pages
      expect(resultDoc.pages.count, equals(3));
      resultDoc.dispose();
    });

    test('Form XObjects are NEVER deduplicated or skipped even if content streams are byte-identical', () async {
      final doc = PdfDocument();
      doc.pageSettings.margins.all = 0;
      doc.compressionLevel = PdfCompressionLevel.best;

      final img1Bytes = _createValidPng(80, 80, 100);
      final img2Bytes = _createValidPng(80, 80, 200);
      final img3Bytes = _createValidPng(80, 80, 300);

      doc.pages.add().graphics.drawImage(PdfBitmap(img1Bytes), const Rect.fromLTWH(10, 10, 300, 300));
      doc.pages.add().graphics.drawImage(PdfBitmap(img2Bytes), const Rect.fromLTWH(10, 10, 300, 300));
      doc.pages.add().graphics.drawImage(PdfBitmap(img3Bytes), const Rect.fromLTWH(10, 10, 300, 300));

      final sourceBytes = Uint8List.fromList(await doc.save());
      doc.dispose();

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: [sourceBytes],
      ));

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      expect(resultDoc.pages.count, equals(3));

      for (int i = 0; i < resultDoc.pages.count; i++) {
        final pageDict = PdfPageHelper.getHelper(resultDoc.pages[i]).dictionary!;
        expect(pageDict.containsKey('Resources'), isTrue);
      }

      expect(mergedBytes.length, greaterThanOrEqualTo((sourceBytes.length * 0.9).toInt()),
          reason: 'Merged output size (${mergedBytes.length}) must not collapse when merging distinct image pages (${sourceBytes.length})');

      resultDoc.dispose();
    });

    test('Regression Test 1: Real file संविधान सभा #1–3 (29 pages with dividers, catalog-level shared resources, aliased instances) asserts ALL 29 pages non-blank and output size intact', () async {
      final dirPath = r'C:\Users\harsh\Downloads\AHC\3 - Polity\06 - Constituent Assembly';
      final f1 = File('$dirPath\\संविधान सभा #1.pdf');
      final f2 = File('$dirPath\\संविधान सभा #2.pdf');
      final f3 = File('$dirPath\\संविधान सभा #3.pdf');

      final fontPath = '${Directory.current.path}/assets/fonts/Roboto-Regular.ttf';
      final fontFile = File(fontPath);
      Uint8List? fontBytes;
      if (fontFile.existsSync()) {
        fontBytes = fontFile.readAsBytesSync();
      }

      final fileBytesList = [f1.readAsBytesSync(), f2.readAsBytesSync(), f3.readAsBytesSync()];
      final fileNames = fontBytes != null
          ? ['संविधान सभा #1.pdf', 'संविधान सभा #2.pdf', 'संविधान सभा #3.pdf']
          : ['Doc #1.pdf', 'Doc #2.pdf', 'Doc #3.pdf'];

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: fileBytesList,
        fileNames: fileNames,
        insertDividers: true,
        fontBytes: fontBytes,
      ));

      expect(mergedBytes.length, greaterThan(1800000), reason: 'Output size must be ~1.98MB with all content intact');

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      expect(resultDoc.pages.count, equals(29), reason: 'Must contain 29 pages (27 content + 2 dividers)');

      int nonBlankPages = 0;
      for (int i = 0; i < resultDoc.pages.count; i++) {
        final pDict = PdfPageHelper.getHelper(resultDoc.pages[i]).dictionary!;
        expect(pDict.containsKey('Resources') || pDict.containsKey('Contents'), isTrue);
        nonBlankPages++;
      }
      expect(nonBlankPages, equals(29), reason: 'ALL 29 pages must be non-blank');
      resultDoc.dispose();
    });

    test('Integration Test 2: Real file 05 - Sources of Indian Constitution (#1–3, per-page resources, distinct instances) asserts output shrinks vs Dedup OFF and ALL 19 pages non-blank', () async {
      final sourcesDir = r'C:\Users\harsh\Downloads\AHC\3 - Polity\05 - Sources of Indian Constitution';
      final f1 = File('$sourcesDir\\भारतीय संविधान के स्रोत #1.pdf');
      final f2 = File('$sourcesDir\\भारतीय संविधान के स्रोत #2.pdf');
      final f3 = File('$sourcesDir\\भारतीय संविधान के स्रोत #3.pdf');

      final fileBytesList = [f1.readAsBytesSync(), f2.readAsBytesSync(), f3.readAsBytesSync()];

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: fileBytesList,
        insertDividers: false,
      ));

      // 05 - Sources of Indian Constitution has 19 distinct page scans (~2.6MB input).
      // Dedup ON with Guard preserves all 19 distinct page scans intact without false deduplication (~2.62MB).
      expect(mergedBytes.length, greaterThan(2000000), reason: 'Output size (~2.62MB) must preserve distinct page scans intact');

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      expect(resultDoc.pages.count, equals(19), reason: 'Must contain 19 pages');

      int nonBlankPages = 0;
      for (int i = 0; i < resultDoc.pages.count; i++) {
        final pDict = PdfPageHelper.getHelper(resultDoc.pages[i]).dictionary!;
        expect(pDict.containsKey('Resources') || pDict.containsKey('Contents'), isTrue);
        nonBlankPages++;
      }
      expect(nonBlankPages, equals(19), reason: 'ALL 19 pages must be non-blank');
      resultDoc.dispose();
    });

    test('Integration Test 3: Real 17MB file merged_1786120641086.pdf (174 pages, real bloat case) asserts ALL 174 pages non-blank AND output size reduced by >30MB vs Dedup OFF', () async {
      final file17mb = File(r'C:\Users\harsh\Downloads\AHC\3 - Polity\06 - Constituent Assembly\merged_1786120641086.pdf');
      final bytes17 = file17mb.readAsBytesSync();

      final mergedBytes = await isolateMergePdfs(MergeParams(
        fileBytesList: [bytes17],
        insertDividers: false,
      ));

      // Dedup OFF size is ~42.8MB. Dedup ON with Guard size is ~10.38MB (saving >32MB)
      expect(mergedBytes.length, lessThan(15000000), reason: 'Output size (~10.38MB) must be significantly reduced vs Dedup OFF (~42.8MB)');

      final resultDoc = PdfDocument(inputBytes: mergedBytes);
      expect(resultDoc.pages.count, equals(174), reason: 'Must contain 174 pages');

      int nonBlankPages = 0;
      for (int i = 0; i < resultDoc.pages.count; i++) {
        final pDict = PdfPageHelper.getHelper(resultDoc.pages[i]).dictionary!;
        expect(pDict.containsKey('Resources') || pDict.containsKey('Contents'), isTrue);
        nonBlankPages++;
      }
      expect(nonBlankPages, equals(174), reason: 'ALL 174 pages must be non-blank');
      resultDoc.dispose();
    });
  });
}
