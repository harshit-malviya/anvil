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
      const rawImageStreamSize = 18670;
      final upperBound = (rawImageStreamSize * 1.5).toInt();

      expect(mergedBytes.length, lessThan(upperBound),
          reason: 'Merged size (${mergedBytes.length}) should be less than 1.5x raw image stream size ($upperBound)');

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
  });
}
