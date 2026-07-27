import 'dart:io';
import 'dart:typed_data';
import 'package:anvil/tools/pdf_compress/pdf_compress_controller.dart';
import 'package:anvil/tools/pdf_compress/pdf_compress_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> createSamplePdf(int pagesCount) async {
  final document = PdfDocument();
  for (int i = 0; i < pagesCount; i++) {
    final page = document.pages.add();
    page.graphics.drawString(
      'Sample PDF Content Page ${i + 1}',
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

  late PdfCompressController controller;
  late Uint8List samplePdfBytes;
  late Uint8List protectedPdfBytes;

  setUpAll(() async {
    samplePdfBytes = await createSamplePdf(3);
    protectedPdfBytes = await createProtectedPdf();
  });

  setUp(() {
    controller = PdfCompressController();
  });

  group('PdfCompressController Unit Tests', () {
    test('loadDocument parses valid PDF and captures original size', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      final state = controller.testState;
      expect(state.errorMessage, isNull);
      expect(state.file?.name, 'sample.pdf');
      expect(state.originalSizeBytes, samplePdfBytes.length);
      expect(state.isLoaded, isTrue);
      expect(state.level, CompressionLevel.medium);
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

    test('setCompressionLevel updates state correctly', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      controller.setCompressionLevel(CompressionLevel.high);
      expect(controller.testState.level, CompressionLevel.high);

      controller.setCompressionLevel(CompressionLevel.low);
      expect(controller.testState.level, CompressionLevel.low);
    });

    test('compress processes PDF and surfaces minimal reduction on text-only document', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: samplePdfBytes.length,
        bytes: samplePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: samplePdfBytes);

      final tempDir = Directory.systemTemp.createTempSync('compress_test_');
      final outputPath = '${tempDir.path}${Platform.pathSeparator}out.pdf';

      final result = await controller.compress(customOutputPath: outputPath);

      final state = controller.testState;
      if (result != null) {
        expect(File(outputPath).existsSync(), isTrue);
        expect(state.outputPath, equals(outputPath));
        expect(state.resultType, isNotNull);
      } else {
        expect(state.resultType, CompressionResultType.outputLarger);
        expect(state.errorMessage, contains('didn\'t reduce the size'));
      }

      tempDir.deleteSync(recursive: true);
    });
  });
}
