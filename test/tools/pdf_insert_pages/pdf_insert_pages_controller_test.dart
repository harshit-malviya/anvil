import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/tools/pdf_insert_pages/pdf_insert_pages_controller.dart';

Future<Uint8List> createValidPdf({
  int pagesCount = 1,
  Size? pageSize,
  PdfPageOrientation orientation = PdfPageOrientation.portrait,
}) async {
  final document = PdfDocument();
  if (pageSize != null) {
    document.pageSettings.size = pageSize;
    document.pageSettings.orientation = orientation;
    document.pageSettings.margins.all = 0;
  }
  for (int i = 0; i < pagesCount; i++) {
    final page = document.pages.add();
    page.graphics.drawString(
      'Page ${i + 1}',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
    );
  }
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

Future<Uint8List> createProtectedPdf() async {
  final document = PdfDocument();
  document.pages.add();
  document.security.userPassword = 'user123';
  document.security.ownerPassword = 'owner123';
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

Uint8List createCorruptedPdf() {
  return Uint8List.fromList('NOT_A_VALID_PDF_STREAM_9876543210'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfInsertPagesController controller;
  late Uint8List targetPdf3Pages;
  late Uint8List sourcePdf3Pages;
  late Uint8List protectedPdf;
  late Uint8List corruptedPdf;

  setUpAll(() async {
    targetPdf3Pages = await createValidPdf(pagesCount: 3);
    sourcePdf3Pages = await createValidPdf(pagesCount: 3);
    protectedPdf = await createProtectedPdf();
    corruptedPdf = createCorruptedPdf();
  });

  setUp(() {
    controller = PdfInsertPagesController();
  });

  group('PdfInsertPagesController Unit Tests', () {
    test('Initial state is empty and canSubmit is false', () {
      final state = controller.testState;
      expect(state.hasTarget, isFalse);
      expect(state.hasSource, isFalse);
      expect(state.canSubmit, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('loadTargetDocument loads target PDF and defaults insertion point to at end', () async {
      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);

      await controller.loadTargetDocument(pfTarget);

      final state = controller.testState;
      expect(state.hasTarget, isTrue);
      expect(state.targetPageCount, equals(3));
      expect(state.insertionPoint, equals(2)); // 3 pages -> default insertion point index 2 (after page 3)
      expect(state.errorMessage, isNull);
    });

    test('loadTargetDocument rejects password-protected PDF', () async {
      final pfProtected = PlatformFile(name: 'protected.pdf', size: protectedPdf.length, bytes: protectedPdf);

      await controller.loadTargetDocument(pfProtected);

      final state = controller.testState;
      expect(state.hasTarget, isFalse);
      expect(state.errorMessage, contains('password-protected'));
    });

    test('loadTargetDocument rejects corrupted PDF', () async {
      final pfCorrupted = PlatformFile(name: 'corrupted.pdf', size: corruptedPdf.length, bytes: corruptedPdf);

      await controller.loadTargetDocument(pfCorrupted);

      final state = controller.testState;
      expect(state.hasTarget, isFalse);
      expect(state.errorMessage, contains('corrupted or unreadable'));
    });

    test('loadSourceDocument loads source PDF and selects all pages by default', () async {
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadSourceDocument(pfSource);

      final state = controller.testState;
      expect(state.hasSource, isTrue);
      expect(state.sourcePageCount, equals(3));
      expect(state.selectedSourcePageIndices, equals([0, 1, 2]));
    });

    test('loadSourceDocument rejects password-protected source PDF independently', () async {
      final pfProtected = PlatformFile(name: 'protected.pdf', size: protectedPdf.length, bytes: protectedPdf);

      await controller.loadSourceDocument(pfProtected);

      final state = controller.testState;
      expect(state.hasSource, isFalse);
      expect(state.errorMessage, contains('password-protected'));
    });

    test('togglePageSelected toggles selection and preserves tap order', () async {
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);
      await controller.loadSourceDocument(pfSource);

      controller.selectNoneSource();
      expect(controller.testState.selectedSourcePageIndices, isEmpty);

      // Select page 2 (index 2), then page 0 (index 0)
      controller.togglePageSelected(2);
      controller.togglePageSelected(0);

      expect(controller.testState.selectedSourcePageIndices, equals([2, 0]));

      // Unselect page 2
      controller.togglePageSelected(2);
      expect(controller.testState.selectedSourcePageIndices, equals([0]));
    });

    test('Zero source pages selected guard disables submission', () async {
      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      expect(controller.testState.canSubmit, isTrue);

      controller.selectNoneSource();

      expect(controller.testState.canSubmit, isFalse);
      final result = await controller.insertPages();
      expect(result, isNull);
      expect(controller.testState.errorMessage, contains('Select at least one page'));
    });

    test('insertPages at start (insertionPoint = -1)', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_insert_start');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_start.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      controller.setInsertionPoint(-1); // At start

      final resultPath = await controller.insertPages(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final outputFile = File(targetPath);
      expect(outputFile.existsSync(), isTrue);

      final doc = PdfDocument(inputBytes: outputFile.readAsBytesSync());
      expect(doc.pages.count, equals(6)); // 3 target + 3 source
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertPages at end (insertionPoint = targetPageCount - 1)', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_insert_end');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_end.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      controller.setInsertionPoint(2); // At end (after page 3 / index 2)

      final resultPath = await controller.insertPages(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(6));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertPages in middle (after target page index 0)', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_insert_middle');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_middle.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      controller.setInsertionPoint(0); // After target page index 0 (after Page 1)

      final resultPath = await controller.insertPages(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(6));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertPages with partial source selection and custom tap order', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_insert_partial');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_partial.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      controller.selectNoneSource();
      controller.togglePageSelected(2); // Pick source page index 2
      controller.togglePageSelected(0); // Pick source page index 0

      expect(controller.testState.selectedSourceCount, equals(2));

      final resultPath = await controller.insertPages(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(5)); // 3 target + 2 inserted source pages
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('Same file as source and target is allowed', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_insert_same_file');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_same.pdf';

      final pfSame = PlatformFile(name: 'doc.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);

      await controller.loadTargetDocument(pfSame);
      await controller.loadSourceDocument(pfSame);

      expect(controller.testState.canSubmit, isTrue);

      final resultPath = await controller.insertPages(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(6)); // 3 target + 3 source pages duplicated
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('clearSource removes source document and returns target to unmodified state', () async {
      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfSource = PlatformFile(name: 'source.pdf', size: sourcePdf3Pages.length, bytes: sourcePdf3Pages);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      expect(controller.testState.hasSource, isTrue);

      controller.clearSource();

      final state = controller.testState;
      expect(state.hasTarget, isTrue);
      expect(state.hasSource, isFalse);
      expect(state.selectedSourcePageIndices, isEmpty);
      expect(state.canSubmit, isFalse);
    });

    test('Preserves exact page dimensions and orientation for target and inserted pages', () async {
      final a4Target = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.a4, orientation: PdfPageOrientation.portrait);
      final letterLandscapeSource = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.letter, orientation: PdfPageOrientation.landscape);

      final pfTarget = PlatformFile(name: 'a4.pdf', size: a4Target.length, bytes: a4Target);
      final pfSource = PlatformFile(name: 'letter.pdf', size: letterLandscapeSource.length, bytes: letterLandscapeSource);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadSourceDocument(pfSource);

      final tempDir = Directory.systemTemp.createTempSync('anvil_insert_dims');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_dims.pdf';

      await controller.insertPages(customOutputPath: targetPath);

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(2));

      final srcA4 = PdfDocument(inputBytes: a4Target);
      final srcLetter = PdfDocument(inputBytes: letterLandscapeSource);

      expect(doc.pages[0].size.width, equals(srcA4.pages[0].size.width));
      expect(doc.pages[0].size.height, equals(srcA4.pages[0].size.height));

      expect(doc.pages[1].size.width, equals(srcLetter.pages[0].size.width));
      expect(doc.pages[1].size.height, equals(srcLetter.pages[0].size.height));

      srcA4.dispose();
      srcLetter.dispose();
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });
  });
}
