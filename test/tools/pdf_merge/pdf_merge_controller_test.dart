import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/tools/pdf_merge/pdf_merge_controller.dart';

Future<Uint8List> createValidPdf({int pagesCount = 1}) async {
  final document = PdfDocument();
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
  });
}
