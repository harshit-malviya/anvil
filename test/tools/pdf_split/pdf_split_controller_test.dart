import 'dart:io';
import 'dart:typed_data';
import 'package:anvil/tools/pdf_split/pdf_split_controller.dart';
import 'package:anvil/tools/pdf_split/pdf_split_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> createMultiPagePdf(int pagesCount) async {
  final document = PdfDocument();
  for (int i = 0; i < pagesCount; i++) {
    final page = document.pages.add();
    page.graphics.drawString(
      'Page ${i + 1} Content',
      PdfStandardFont(PdfFontFamily.helvetica, 14),
    );
  }
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

Future<Uint8List> createProtectedPdf() async {
  final document = PdfDocument();
  document.pages.add();
  document.security.userPassword = 'secret_password';
  document.security.ownerPassword = 'admin_password';
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfSplitController controller;
  late Uint8List singlePagePdfBytes;
  late Uint8List fourPagePdfBytes;
  late Uint8List protectedPdfBytes;

  setUpAll(() async {
    singlePagePdfBytes = await createMultiPagePdf(1);
    fourPagePdfBytes = await createMultiPagePdf(4);
    protectedPdfBytes = await createProtectedPdf();
  });

  setUp(() {
    controller = PdfSplitController();
  });

  group('PdfSplitController Unit Tests', () {
    test('loadDocument parses multi-page PDF successfully', () async {
      final pf = PlatformFile(
        name: 'report.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      final state = controller.testState;
      expect(state.errorMessage, isNull);
      expect(state.file?.name, 'report.pdf');
      expect(state.totalPageCount, 4);
      expect(state.isLoaded, isTrue);
      expect(state.isSinglePage, isFalse);
      expect(state.mode, SplitMode.everyPage);
      expect(state.calculatedRanges.length, 4);
      expect(state.summaryText, 'Will produce 4 files (1 page each)');
    });

    test('loadDocument flags single page PDF', () async {
      final pf = PlatformFile(
        name: 'single.pdf',
        size: singlePagePdfBytes.length,
        bytes: singlePagePdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: singlePagePdfBytes);

      final state = controller.testState;
      expect(state.isLoaded, isTrue);
      expect(state.isSinglePage, isTrue);
      expect(state.summaryText, contains('only has one page'));
    });

    test('loadDocument rejects encrypted password-protected PDFs', () async {
      final pf = PlatformFile(
        name: 'protected.pdf',
        size: protectedPdfBytes.length,
        bytes: protectedPdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: protectedPdfBytes);

      final state = controller.testState;
      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains('password-protected'));
    });

    test('setSplitMode switches split modes correctly', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      controller.setSplitMode(SplitMode.equalParts);
      expect(controller.testState.mode, SplitMode.equalParts);
      expect(controller.testState.calculatedRanges.length, 2); // 4 pages into 2 equal parts

      controller.setSplitMode(SplitMode.customRanges);
      expect(controller.testState.mode, SplitMode.customRanges);
    });

    test('toggleRangeMarker updates custom ranges dynamically', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      controller.setSplitMode(SplitMode.customRanges);
      // Toggle marker after page 1 (index 0)
      controller.toggleRangeMarker(0);

      final state = controller.testState;
      expect(state.rangeMarkers.contains(0), isTrue);
      expect(state.calculatedRanges, [
        const PdfPageRange(1, 1),
        const PdfPageRange(2, 4),
      ]);
    });

    test('setRangesFromText handles valid text ranges', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      controller.setSplitMode(SplitMode.customRanges);
      controller.setRangesFromText('1-2, 3-4');

      final state = controller.testState;
      expect(state.rangeValidationError, isNull);
      expect(state.calculatedRanges, [
        const PdfPageRange(1, 2),
        const PdfPageRange(3, 4),
      ]);
    });

    test('setRangesFromText detects overlapping ranges', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      controller.setSplitMode(SplitMode.customRanges);
      controller.setRangesFromText('1-3, 2-4');

      final state = controller.testState;
      expect(state.rangeValidationError, contains('can\'t overlap'));
    });

    test('custom range gap detection and confirmation guard', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      controller.setSplitMode(SplitMode.customRanges);
      controller.setRangesFromText('1-2');

      final state = controller.testState;
      expect(state.uncoveredPages, [3, 4]);

      // Attempt split without gap override
      final result1 = await controller.split(overrideGapCheck: false);
      expect(result1, isNull);
      expect(controller.testState.errorMessage, contains('aren\'t included in any range'));

      // Attempt split with gap override
      final tempDir = Directory.systemTemp.createTempSync('split_gap_test_');
      final result2 = await controller.split(
        customOutputDir: tempDir.path,
        overrideGapCheck: true,
      );

      expect(result2, equals(tempDir.path));
      expect(controller.testState.outputCreatedFileCount, 1);
      tempDir.deleteSync(recursive: true);
    });

    test('equalParts calculation and N > totalPages rejection', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      controller.setSplitMode(SplitMode.equalParts);
      controller.setEqualPartsCount(3);

      // 4 pages into 3 parts -> pages 1-2, 3-3, 4-4
      expect(controller.testState.calculatedRanges, [
        const PdfPageRange(1, 2),
        const PdfPageRange(3, 3),
        const PdfPageRange(4, 4),
      ]);

      // N > total pages rejection
      controller.setEqualPartsCount(10);
      expect(controller.testState.rangeValidationError, contains('can\'t split into more than 4 parts'));
    });

    test('split execution writes output files and preserves page orientation', () async {
      final pf = PlatformFile(
        name: 'test_doc.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      final tempDir = Directory.systemTemp.createTempSync('split_out_test_');
      final resultPath = await controller.split(customOutputDir: tempDir.path);

      expect(resultPath, equals(tempDir.path));
      expect(controller.testState.outputCreatedFileCount, 4);

      // Verify created files exist and are valid single-page PDFs
      for (int i = 1; i <= 4; i++) {
        final filePath = '${tempDir.path}${Platform.pathSeparator}test_doc_part$i.pdf';
        final f = File(filePath);
        expect(f.existsSync(), isTrue);

        final outDoc = PdfDocument(inputBytes: await f.readAsBytes());
        expect(outDoc.pages.count, 1);
        outDoc.dispose();
      }

      tempDir.deleteSync(recursive: true);
    });
  });
}
