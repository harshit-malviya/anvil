import 'dart:io';
import 'dart:typed_data';
import 'package:anvil/tools/pdf_to_image/pdf_to_image_controller.dart';
import 'package:anvil/tools/pdf_to_image/pdf_to_image_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> createMultiPagePdf(int pagesCount) async {
  final document = PdfDocument();
  for (int i = 0; i < pagesCount; i++) {
    final page = document.pages.add();
    page.graphics.drawString(
      'Sample Page ${i + 1} Content',
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
  document.security.userPassword = 'user_pass';
  document.security.ownerPassword = 'admin_pass';
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

/// Helper renderer that produces valid PNG/JPEG bytes for testing without native pdfium.
Future<Uint8List?> mockImageRenderer(
  Uint8List pdfBytes,
  int pageIndex,
  int targetDpi,
  ImageFormat format,
) async {
  final image = img.Image(width: 100, height: 100);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  if (format == ImageFormat.png) {
    return Uint8List.fromList(img.encodePng(image));
  } else {
    return Uint8List.fromList(img.encodeJpg(image));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfToImageController controller;
  late Uint8List multiPageBytes;
  late Uint8List protectedBytes;

  setUpAll(() async {
    multiPageBytes = await createMultiPagePdf(4);
    protectedBytes = await createProtectedPdf();
  });

  setUp(() {
    controller = PdfToImageController(customRenderer: mockImageRenderer);
  });

  group('PdfToImageController Unit Tests', () {
    test('loadDocument parses PDF and selects all pages by default', () async {
      final pf = PlatformFile(
        name: 'report.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
      );

      await controller.loadDocument(pf, overrideBytes: multiPageBytes);

      final state = controller.testState;
      expect(state.isLoaded, isTrue);
      expect(state.totalPageCount, 4);
      expect(state.selectedCount, 4);
      expect(state.selectedPages, {0, 1, 2, 3});
      expect(state.canExport, isTrue);
      expect(state.summaryText, 'Export 4 pages as PNG at 150 DPI');
    });

    test('loadDocument rejects password-protected PDFs', () async {
      final pf = PlatformFile(
        name: 'locked.pdf',
        size: protectedBytes.length,
        bytes: protectedBytes,
      );

      await controller.loadDocument(pf, overrideBytes: protectedBytes);

      final state = controller.testState;
      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains('password-protected'));
      expect(state.canExport, isFalse);
    });

    test('selection actions: selectAll, selectNone, togglePageSelected', () async {
      final pf = PlatformFile(
        name: 'report.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
      );
      await controller.loadDocument(pf, overrideBytes: multiPageBytes);

      // Deselect page index 1
      controller.togglePageSelected(1);
      expect(controller.testState.selectedCount, 3);
      expect(controller.testState.selectedPages.contains(1), isFalse);

      // Select none
      controller.selectNone();
      expect(controller.testState.selectedCount, 0);
      expect(controller.testState.canExport, isFalse);
      expect(controller.testState.summaryText, 'Select at least one page to export');

      // Select all
      controller.selectAll();
      expect(controller.testState.selectedCount, 4);
      expect(controller.testState.canExport, isTrue);
    });

    test('format and resolution configuration updates state correctly', () async {
      final pf = PlatformFile(
        name: 'report.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
      );
      await controller.loadDocument(pf, overrideBytes: multiPageBytes);

      controller.setFormat(ImageFormat.jpeg);
      expect(controller.testState.format, ImageFormat.jpeg);
      expect(controller.testState.summaryText, 'Export 4 pages as JPEG at 150 DPI');

      controller.setResolution(ExportResolution.high);
      expect(controller.testState.resolution, ExportResolution.high);
      expect(controller.testState.summaryText, 'Export 4 pages as JPEG at 300 DPI');
    });

    test('single-page export path produces single image file', () async {
      final tempDir = Directory.systemTemp.createTempSync('pdf_to_image_single_');
      final sourcePath = p.join(tempDir.path, 'doc.pdf');
      await File(sourcePath).writeAsBytes(multiPageBytes);

      final pf = PlatformFile(
        name: 'doc.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
        path: sourcePath,
      );
      await controller.loadDocument(pf, overrideBytes: multiPageBytes);

      // Select only page 1 (index 0)
      controller.selectNone();
      controller.togglePageSelected(0);
      expect(controller.testState.selectedCount, 1);

      final result = await controller.export();
      final state = controller.testState;

      expect(result, isNotNull);
      expect(File(result!).existsSync(), isTrue);
      expect(state.isSingleFileExport, isTrue);
      expect(state.exportedCount, 1);
      expect(state.skippedPages, isEmpty);
      expect(p.basename(result), 'doc_page1.png');

      tempDir.deleteSync(recursive: true);
    });

    test('multi-page export path produces folder with named images in order', () async {
      final tempDir = Directory.systemTemp.createTempSync('pdf_to_image_multi_');
      final sourcePath = p.join(tempDir.path, 'report.pdf');
      await File(sourcePath).writeAsBytes(multiPageBytes);

      final pf = PlatformFile(
        name: 'report.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
        path: sourcePath,
      );
      await controller.loadDocument(pf, overrideBytes: multiPageBytes);

      final result = await controller.export();
      final state = controller.testState;

      expect(result, isNotNull);
      expect(Directory(result!).existsSync(), isTrue);
      expect(state.isSingleFileExport, isFalse);
      expect(state.exportedCount, 4);
      expect(state.skippedPages, isEmpty);
      expect(p.basename(result), 'report_images');

      final exportedFiles = Directory(result).listSync().whereType<File>().toList();
      expect(exportedFiles.length, 4);

      final names = exportedFiles.map((f) => p.basename(f.path)).toList()..sort();
      expect(names, [
        'report_page1.png',
        'report_page2.png',
        'report_page3.png',
        'report_page4.png',
      ]);

      tempDir.deleteSync(recursive: true);
    });

    test('folder name collision appends _2 suffix', () async {
      final tempDir = Directory.systemTemp.createTempSync('pdf_to_image_collision_');
      final sourcePath = p.join(tempDir.path, 'data.pdf');
      await File(sourcePath).writeAsBytes(multiPageBytes);

      // Pre-create 'data_images' folder to simulate existing export
      final existingFolder = Directory(p.join(tempDir.path, 'data_images'));
      await existingFolder.create();
      await File(p.join(existingFolder.path, 'old.txt')).writeAsString('existing content');

      final pf = PlatformFile(
        name: 'data.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
        path: sourcePath,
      );
      await controller.loadDocument(pf, overrideBytes: multiPageBytes);

      final result = await controller.export();

      expect(result, isNotNull);
      expect(p.basename(result!), 'data_images_2');
      expect(Directory(result).existsSync(), isTrue);

      // Verify existing folder content was preserved
      expect(File(p.join(existingFolder.path, 'old.txt')).existsSync(), isTrue);

      tempDir.deleteSync(recursive: true);
    });

    test('per-page rendering failure skips bad page and reports skipped list', () async {
      final tempDir = Directory.systemTemp.createTempSync('pdf_to_image_skip_');
      final sourcePath = p.join(tempDir.path, 'batch.pdf');
      await File(sourcePath).writeAsBytes(multiPageBytes);

      // Custom controller where page index 2 (Page 3) fails to render
      final faultyController = PdfToImageController(
        customRenderer: (bytes, pageIndex, dpi, format) async {
          if (pageIndex == 2) return null; // Page 3 fails
          return mockImageRenderer(bytes, pageIndex, dpi, format);
        },
      );

      final pf = PlatformFile(
        name: 'batch.pdf',
        size: multiPageBytes.length,
        bytes: multiPageBytes,
        path: sourcePath,
      );
      await faultyController.loadDocument(pf, overrideBytes: multiPageBytes);

      final result = await faultyController.export();
      final state = faultyController.testState;

      expect(result, isNotNull);
      expect(state.exportedCount, 3);
      expect(state.skippedPages, [3]); // Page 3 (1-indexed) was skipped

      final exportedFiles = Directory(result!).listSync().whereType<File>().toList();
      expect(exportedFiles.length, 3);

      final names = exportedFiles.map((f) => p.basename(f.path)).toList()..sort();
      expect(names, [
        'batch_page1.png',
        'batch_page2.png',
        'batch_page4.png',
      ]);

      tempDir.deleteSync(recursive: true);
    });
  });
}
