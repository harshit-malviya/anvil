import 'dart:typed_data';
import 'package:anvil/core/services/pdf_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> _createValidPdf({int pagesCount = 1}) async {
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

Future<Uint8List> _createProtectedPdf() async {
  final document = PdfDocument();
  document.pages.add();
  document.security.userPassword = 'user123';
  document.security.ownerPassword = 'owner123';
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

Uint8List _createCorruptedPdf() {
  return Uint8List.fromList('NOT_A_VALID_PDF_STREAM_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List validSinglePagePdf;
  late Uint8List validMultiPagePdf;
  late Uint8List protectedPdf;
  late Uint8List corruptedPdf;

  setUpAll(() async {
    validSinglePagePdf = await _createValidPdf(pagesCount: 1);
    validMultiPagePdf = await _createValidPdf(pagesCount: 5);
    protectedPdf = await _createProtectedPdf();
    corruptedPdf = _createCorruptedPdf();
  });

  group('PdfValidationService', () {
    test('returns valid result and correct page count for single-page PDF', () {
      final info = PdfValidationService.validate(validSinglePagePdf);

      expect(info.result, PdfValidationResult.valid);
      expect(info.isValid, isTrue);
      expect(info.isPasswordProtected, isFalse);
      expect(info.isCorrupted, isFalse);
      expect(info.pageCount, equals(1));
    });

    test('returns valid result and correct page count for multi-page PDF', () {
      final info = PdfValidationService.validate(validMultiPagePdf);

      expect(info.result, PdfValidationResult.valid);
      expect(info.isValid, isTrue);
      expect(info.pageCount, equals(5));
    });

    test('returns passwordProtected result for encrypted PDF', () {
      final info = PdfValidationService.validate(protectedPdf);

      expect(info.result, PdfValidationResult.passwordProtected);
      expect(info.isPasswordProtected, isTrue);
      expect(info.isValid, isFalse);
      expect(info.isCorrupted, isFalse);
      expect(info.pageCount, equals(0));
    });

    test('returns corrupted result for non-PDF garbage bytes', () {
      final info = PdfValidationService.validate(corruptedPdf);

      expect(info.result, PdfValidationResult.corrupted);
      expect(info.isCorrupted, isTrue);
      expect(info.isValid, isFalse);
      expect(info.isPasswordProtected, isFalse);
      expect(info.pageCount, equals(0));
    });

    test('returns corrupted result for null bytes', () {
      final info = PdfValidationService.validate(null);

      expect(info.result, PdfValidationResult.corrupted);
      expect(info.isCorrupted, isTrue);
      expect(info.errorDetail, contains('empty or unreadable'));
    });

    test('returns corrupted result for empty Uint8List', () {
      final info = PdfValidationService.validate(Uint8List(0));

      expect(info.result, PdfValidationResult.corrupted);
      expect(info.isCorrupted, isTrue);
      expect(info.errorDetail, contains('empty or unreadable'));
    });
  });
}
