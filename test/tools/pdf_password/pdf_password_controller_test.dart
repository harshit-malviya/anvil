import 'dart:io';
import 'dart:typed_data';
import 'package:anvil/tools/pdf_password/pdf_password_controller.dart';
import 'package:anvil/tools/pdf_password/pdf_password_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> createSamplePdf({int pageCount = 2}) async {
  final document = PdfDocument();
  for (int i = 0; i < pageCount; i++) {
    final page = document.pages.add();
    page.graphics.drawString(
      'Test PDF Content Page ${i + 1}',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
    );
  }
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

Future<Uint8List> createProtectedPdf(String password) async {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    'Protected PDF Content',
    PdfStandardFont(PdfFontFamily.helvetica, 12),
  );
  document.security.userPassword = password;
  document.security.ownerPassword = password;
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfPasswordController controller;
  late Uint8List samplePdfBytes;
  late Uint8List protectedPdfBytes;
  const String samplePassword = 'securePassword123';

  setUpAll(() async {
    samplePdfBytes = await createSamplePdf(pageCount: 2);
    protectedPdfBytes = await createProtectedPdf(samplePassword);
  });

  setUp(() {
    controller = PdfPasswordController();
  });

  group('PdfPasswordController Unit Tests', () {
    test('loadDocument auto-detects unprotected PDF state', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      final state = controller.testState;
      expect(state.isLoaded, isTrue);
      expect(state.isProtected, isFalse);
      expect(state.mode, PdfPasswordMode.add);
      expect(state.errorMessage, isNull);
    });

    test('loadDocument auto-detects protected PDF state', () async {
      final pf = PlatformFile(
        name: 'protected.pdf',
        size: protectedPdfBytes.length,
        bytes: protectedPdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: protectedPdfBytes);

      final state = controller.testState;
      expect(state.isLoaded, isTrue);
      expect(state.isProtected, isTrue);
      expect(state.mode, PdfPasswordMode.remove);
      expect(state.errorMessage, isNull);
    });

    test('loadDocument rejects corrupted non-PDF files', () async {
      final corruptedBytes = Uint8List.fromList('Not a PDF file content'.codeUnits);
      final pf = PlatformFile(
        name: 'corrupted.pdf',
        size: corruptedBytes.length,
        bytes: corruptedBytes,
      );

      await controller.loadDocument(pf, overrideBytes: corruptedBytes);

      final state = controller.testState;
      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains('corrupted or unreadable'));
    });

    test('loadDocument rejects empty files', () async {
      final emptyBytes = Uint8List(0);
      final pf = PlatformFile(
        name: 'empty.pdf',
        size: 0,
        bytes: emptyBytes,
      );

      await controller.loadDocument(pf, overrideBytes: emptyBytes);

      final state = controller.testState;
      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains('empty or unreadable'));
    });

    test('Add Password validation: rejects password under 6 characters', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      controller.setPassword('12345');
      controller.setConfirmPassword('12345');

      final state = controller.testState;
      expect(state.isPasswordTooShort, isTrue);
      expect(state.passwordsMatch, isTrue);
      expect(state.canSubmitAdd, isFalse);
    });

    test('Add Password validation: rejects mismatched confirm password', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      controller.setPassword('password123');
      controller.setConfirmPassword('different123');

      final state = controller.testState;
      expect(state.isPasswordTooShort, isFalse);
      expect(state.passwordsMatch, isFalse);
      expect(state.canSubmitAdd, isFalse);
    });

    test('Add Password happy path: encrypts PDF and output requires password', () async {
      final tempDir = Directory.systemTemp.createTempSync('pwd_add_test_');
      final inputPath = '${tempDir.path}${Platform.pathSeparator}input.pdf';
      final outputPath = '${tempDir.path}${Platform.pathSeparator}output_protected.pdf';
      await File(inputPath).writeAsBytes(samplePdfBytes);

      final pf = PlatformFile(
        name: 'input.pdf',
        path: inputPath,
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      controller.setPassword('secretKey123');
      controller.setConfirmPassword('secretKey123');
      expect(controller.testState.canSubmitAdd, isTrue);

      final result = await controller.submit(customOutputPath: outputPath);

      expect(result, equals(outputPath));
      expect(File(outputPath).existsSync(), isTrue);

      // Verify that opening output without password throws encrypted exception
      final outputBytes = await File(outputPath).readAsBytes();
      expect(() => PdfDocument(inputBytes: outputBytes), throwsA(anything));

      // Verify that opening output with correct password succeeds
      final openedDoc = PdfDocument(inputBytes: outputBytes, password: 'secretKey123');
      expect(openedDoc.pages.count, equals(2));
      openedDoc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('Remove Password with incorrect password: fails with error and NO output file', () async {
      final tempDir = Directory.systemTemp.createTempSync('pwd_remove_fail_');
      final outputPath = '${tempDir.path}${Platform.pathSeparator}should_not_exist.pdf';

      final pf = PlatformFile(
        name: 'protected.pdf',
        size: protectedPdfBytes.length,
        bytes: protectedPdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: protectedPdfBytes);

      controller.setRemovalPassword('wrong_password');
      expect(controller.testState.canSubmitRemove, isTrue);

      final result = await controller.submit(customOutputPath: outputPath);

      final state = controller.testState;
      expect(result, isNull);
      expect(state.errorMessage, equals("Incorrect password — the file wasn't changed."));
      expect(File(outputPath).existsSync(), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('Remove Password happy path: decrypts PDF with valid password into unencrypted PDF', () async {
      final tempDir = Directory.systemTemp.createTempSync('pwd_remove_success_');
      final inputPath = '${tempDir.path}${Platform.pathSeparator}protected.pdf';
      final outputPath = '${tempDir.path}${Platform.pathSeparator}output_unprotected.pdf';
      await File(inputPath).writeAsBytes(protectedPdfBytes);

      final pf = PlatformFile(
        name: 'protected.pdf',
        path: inputPath,
        size: protectedPdfBytes.length,
        bytes: protectedPdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: protectedPdfBytes);

      controller.setRemovalPassword(samplePassword);
      expect(controller.testState.canSubmitRemove, isTrue);

      final result = await controller.submit(customOutputPath: outputPath);

      expect(result, equals(outputPath));
      expect(File(outputPath).existsSync(), isTrue);

      // Verify output opens cleanly without password
      final outputBytes = await File(outputPath).readAsBytes();
      final openedDoc = PdfDocument(inputBytes: outputBytes);
      expect(openedDoc.pages.count, equals(1));
      openedDoc.dispose();

      // Original input file is untouched
      final originalAfter = await File(inputPath).readAsBytes();
      expect(originalAfter, equals(protectedPdfBytes));

      tempDir.deleteSync(recursive: true);
    });

    test('Add Password file system save error: handles FileSystemException cleanly', () async {
      final invalidPath = '${Platform.isWindows ? "Z:" : ""}/non_existent_dir_12345/output.pdf';

      final pf = PlatformFile(
        name: 'unprotected.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      controller.setPassword('secretKey123');
      controller.setConfirmPassword('secretKey123');

      final result = await controller.submit(customOutputPath: invalidPath);

      final state = controller.testState;
      expect(result, isNull);
      expect(state.errorMessage, contains("Couldn't save the file"));
    });
  });
}
