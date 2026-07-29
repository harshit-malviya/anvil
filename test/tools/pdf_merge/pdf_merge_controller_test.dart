import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/tools/pdf_merge/pdf_merge_controller.dart';

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
      'Test Page ${i + 1}',
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
  return Uint8List.fromList('NOT_A_VALID_PDF_STREAM_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfMergeController controller;
  late Uint8List validPdf1;
  late Uint8List validPdf2;
  late Uint8List protectedPdf;
  late Uint8List corruptedPdf;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    validPdf1 = await createValidPdf(pagesCount: 1);
    validPdf2 = await createValidPdf(pagesCount: 2);
    protectedPdf = await createProtectedPdf();
    corruptedPdf = createCorruptedPdf();
  });

  setUp(() {
    controller = PdfMergeController();
  });

  group('PdfMergeController Unit Tests', () {
    test('Initial state is empty and canMerge is false', () {
      final state = controller.testState;
      expect(state.files, isEmpty);
      expect(state.canMerge, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('Adding valid PDF files updates state correctly', () async {
      final pf1 = PlatformFile(name: 'valid1.pdf', size: validPdf1.length, bytes: validPdf1);
      final pf2 = PlatformFile(name: 'valid2.pdf', size: validPdf2.length, bytes: validPdf2);

      await controller.addFiles([pf1, pf2]);

      final state = controller.testState;
      expect(state.files.length, equals(2));
      expect(state.files[0].name, equals('valid1.pdf'));
      expect(state.files[0].pageCount, equals(1));
      expect(state.files[1].name, equals('valid2.pdf'));
      expect(state.files[1].pageCount, equals(2));
      expect(state.canMerge, isTrue);
      expect(state.errorMessage, isNull);
    });

    test('Adding 1 file keeps canMerge as false', () async {
      final pf1 = PlatformFile(name: 'valid1.pdf', size: validPdf1.length, bytes: validPdf1);

      await controller.addFiles([pf1]);

      final state = controller.testState;
      expect(state.files.length, equals(1));
      expect(state.canMerge, isFalse);
    });

    test('Adding password-protected file rejects file at add-time with specific error', () async {
      final pfProtected = PlatformFile(name: 'protected.pdf', size: protectedPdf.length, bytes: protectedPdf);

      await controller.addFiles([pfProtected]);

      final state = controller.testState;
      expect(state.files, isEmpty);
      expect(state.errorMessage, contains('password-protected'));
    });

    test('Adding corrupted file rejects file at add-time with specific error', () async {
      final pfCorrupted = PlatformFile(name: 'corrupted.pdf', size: corruptedPdf.length, bytes: corruptedPdf);

      await controller.addFiles([pfCorrupted]);

      final state = controller.testState;
      expect(state.files, isEmpty);
      expect(state.errorMessage, contains('corrupted or unreadable'));
    });

    test('Reordering files updates list order correctly', () async {
      final pf1 = PlatformFile(name: 'valid1.pdf', size: validPdf1.length, bytes: validPdf1);
      final pf2 = PlatformFile(name: 'valid2.pdf', size: validPdf2.length, bytes: validPdf2);

      await controller.addFiles([pf1, pf2]);
      controller.reorderFiles(0, 2);

      final state = controller.testState;
      expect(state.files[0].name, equals('valid2.pdf'));
      expect(state.files[1].name, equals('valid1.pdf'));
    });

    test('Removing file updates state and resets error', () async {
      final pf1 = PlatformFile(name: 'valid1.pdf', size: validPdf1.length, bytes: validPdf1);
      final pf2 = PlatformFile(name: 'valid2.pdf', size: validPdf2.length, bytes: validPdf2);

      await controller.addFiles([pf1, pf2]);
      final firstId = controller.testState.files.first.id;

      controller.removeFile(firstId);

      final state = controller.testState;
      expect(state.files.length, equals(1));
      expect(state.files.first.name, equals('valid2.pdf'));
      expect(state.canMerge, isFalse);
    });

    test('Removing all files returns state to empty Drop Zone state', () async {
      final pf1 = PlatformFile(name: 'valid1.pdf', size: validPdf1.length, bytes: validPdf1);
      await controller.addFiles([pf1]);

      controller.removeAll();

      final state = controller.testState;
      expect(state.files, isEmpty);
      expect(state.canMerge, isFalse);
    });

    test('Merging 2 valid PDFs produces a valid merged output PDF', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_merge_test');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}output_merged.pdf';

      final pf1 = PlatformFile(name: 'valid1.pdf', size: validPdf1.length, bytes: validPdf1);
      final pf2 = PlatformFile(name: 'valid2.pdf', size: validPdf2.length, bytes: validPdf2);

      await controller.addFiles([pf1, pf2]);
      final resultPath = await controller.merge(customOutputPath: targetPath);

      expect(resultPath, equals(targetPath));
      final outputFile = File(targetPath);
      expect(outputFile.existsSync(), isTrue);

      final mergedBytes = outputFile.readAsBytesSync();
      final doc = PdfDocument(inputBytes: mergedBytes);
      expect(doc.pages.count, equals(3)); // 1 + 2 pages
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('Regression test: Merging mixed page sizes (A4 portrait and Letter landscape) preserves exact per-page dimensions', () async {
      final a4Pdf = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.a4, orientation: PdfPageOrientation.portrait);
      final letterLandscapePdf = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.letter, orientation: PdfPageOrientation.landscape);

      final pfA4 = PlatformFile(name: 'a4.pdf', size: a4Pdf.length, bytes: a4Pdf);
      final pfLetter = PlatformFile(name: 'letter_landscape.pdf', size: letterLandscapePdf.length, bytes: letterLandscapePdf);

      await controller.addFiles([pfA4, pfLetter]);

      final tempDir = Directory.systemTemp.createTempSync('anvil_merge_mixed_size');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}mixed_output.pdf';

      final resultPath = await controller.merge(customOutputPath: targetPath);
      expect(resultPath, isNotNull);

      final outputFile = File(targetPath);
      final mergedDoc = PdfDocument(inputBytes: outputFile.readAsBytesSync());

      expect(mergedDoc.pages.count, equals(2));

      final srcA4Doc = PdfDocument(inputBytes: a4Pdf);
      final srcLetterDoc = PdfDocument(inputBytes: letterLandscapePdf);

      expect(mergedDoc.pages[0].size.width, equals(srcA4Doc.pages[0].size.width));
      expect(mergedDoc.pages[0].size.height, equals(srcA4Doc.pages[0].size.height));

      expect(mergedDoc.pages[1].size.width, equals(srcLetterDoc.pages[0].size.width));
      expect(mergedDoc.pages[1].size.height, equals(srcLetterDoc.pages[0].size.height));

      srcA4Doc.dispose();
      srcLetterDoc.dispose();
      mergedDoc.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('setInsertDividers updates state correctly', () {
      expect(controller.testState.insertDividers, isFalse);
      controller.setInsertDividers(true);
      expect(controller.testState.insertDividers, isTrue);
      controller.setInsertDividers(false);
      expect(controller.testState.insertDividers, isFalse);
    });

    test('Merging with dividers enabled inserts divider pages with 72pt height and matching width', () async {
      final letterDoc = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.letter);
      final a4Doc = await createValidPdf(pagesCount: 2, pageSize: PdfPageSize.a4);

      final pf1 = PlatformFile(name: 'first_document.pdf', size: letterDoc.length, bytes: letterDoc);
      final pf2 = PlatformFile(name: 'second_document_with_very_long_filename_that_should_truncate_cleanly.pdf', size: a4Doc.length, bytes: a4Doc);

      await controller.addFiles([pf1, pf2]);
      controller.setInsertDividers(true);

      final tempDir = Directory.systemTemp.createTempSync('anvil_merge_divider_test');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}divider_merged.pdf';

      final resultPath = await controller.merge(customOutputPath: targetPath);
      expect(resultPath, isNotNull);

      final outputFile = File(targetPath);
      final mergedDoc = PdfDocument(inputBytes: outputFile.readAsBytesSync());

      // 1 (file1) + 1 (divider before file2) + 2 (file2) = 4 pages
      expect(mergedDoc.pages.count, equals(4));

      // Page 0: file 1 (letter size)
      expect(mergedDoc.pages[0].size.height, equals(PdfPageSize.letter.height));

      // Page 1: divider page before file 2. Height = 72pt, width matches file 2 page 1 (A4 width)
      expect(mergedDoc.pages[1].size.height, equals(72.0));
      expect(mergedDoc.pages[1].size.width, equals(PdfPageSize.a4.width));

      // Page 2 & 3: file 2 pages (A4 size)
      expect(mergedDoc.pages[2].size.height, equals(PdfPageSize.a4.height));
      expect(mergedDoc.pages[3].size.height, equals(PdfPageSize.a4.height));

      mergedDoc.dispose();
      tempDir.deleteSync(recursive: true);
    });

    test('Merging with Hindi filename ("भारत की नदियां #1.pdf") renders divider page without throwing', () async {
      final letterDoc = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.letter);
      final hindiDoc = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.a4);

      final pf1 = PlatformFile(name: 'first_document.pdf', size: letterDoc.length, bytes: letterDoc);
      final pf2 = PlatformFile(name: 'भारत की नदियां #1.pdf', size: hindiDoc.length, bytes: hindiDoc);

      await controller.addFiles([pf1, pf2]);
      controller.setInsertDividers(true);

      final tempDir = Directory.systemTemp.createTempSync('anvil_merge_hindi_test');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}hindi_merged.pdf';
      final resultPath = await controller.merge(customOutputPath: targetPath);
      expect(resultPath, isNotNull);

      final outputFile = File(targetPath);
      final mergedDoc = PdfDocument(inputBytes: outputFile.readAsBytesSync());

      // 1 (file1) + 1 (divider before hindi file) + 1 (file2) = 3 pages
      expect(mergedDoc.pages.count, equals(3));
      expect(mergedDoc.pages[1].size.height, equals(72.0));

      mergedDoc.dispose();
      tempDir.deleteSync(recursive: true);
    });
  });
}
