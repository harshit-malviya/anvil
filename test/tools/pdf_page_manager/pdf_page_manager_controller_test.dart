import 'dart:io';
import 'dart:typed_data';
import 'package:anvil/tools/pdf_page_manager/pdf_page_manager_controller.dart';
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

  late PdfPageManagerController controller;
  late Uint8List fourPagePdfBytes;
  late Uint8List protectedPdfBytes;

  setUpAll(() async {
    fourPagePdfBytes = await createMultiPagePdf(4);
    protectedPdfBytes = await createProtectedPdf();
  });

  setUp(() {
    controller = PdfPageManagerController();
  });

  group('PdfPageManagerController Unit Tests', () {
    test('loadDocument parses PDF page count and initializes page list', () async {
      final pf = PlatformFile(
        name: 'sample.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      final state = controller.testState;
      expect(state.errorMessage, isNull);
      expect(state.file?.name, 'sample.pdf');
      expect(state.originalPageCount, 4);
      expect(state.activePageCount, 4);
      expect(state.rotatedPageCount, 0);
      expect(state.canApply, isTrue);
      expect(state.summaryText, '4 pages');
      expect(state.pages.map((p) => p.originalIndex).toList(), [0, 1, 2, 3]);
    });

    test('loadDocument rejects encrypted password-protected PDFs', () async {
      final pf = PlatformFile(
        name: 'locked.pdf',
        size: protectedPdfBytes.length,
        bytes: protectedPdfBytes,
      );

      await controller.loadDocument(pf, overrideBytes: protectedPdfBytes);

      final state = controller.testState;
      expect(state.file, isNull);
      expect(state.errorMessage, contains('password-protected'));
      expect(state.canApply, isFalse);
    });

    test('togglePageDeleted marks page deleted and undoes deletion', () async {
      final pf = PlatformFile(
        name: 'test.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      // Delete page 1 (index 1)
      controller.togglePageDeleted(1);
      expect(controller.testState.activePageCount, 3);
      expect(controller.testState.summaryText, '4 pages → 3 pages');
      expect(controller.testState.pages[1].isDeleted, isTrue);

      // Undo deletion
      controller.togglePageDeleted(1);
      expect(controller.testState.activePageCount, 4);
      expect(controller.testState.summaryText, '4 pages');
      expect(controller.testState.pages[1].isDeleted, isFalse);
    });

    test('rotatePage advances 0 -> 90 -> 180 -> 270 -> 0', () async {
      final pf = PlatformFile(
        name: 'rotate.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      expect(controller.testState.pages[0].rotation, 0);

      controller.rotatePage(0);
      expect(controller.testState.pages[0].rotation, 90);
      expect(controller.testState.rotatedPageCount, 1);
      expect(controller.testState.summaryText, '4 pages, 1 rotated');

      controller.rotatePage(0);
      expect(controller.testState.pages[0].rotation, 180);

      controller.rotatePage(0);
      expect(controller.testState.pages[0].rotation, 270);

      // Cycle back to 0° (net 0 rotation)
      controller.rotatePage(0);
      expect(controller.testState.pages[0].rotation, 0);
      expect(controller.testState.rotatedPageCount, 0);
      expect(controller.testState.summaryText, '4 pages');
    });

    test('reorderPage updates page sequence correctly', () async {
      final pf = PlatformFile(
        name: 'reorder.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      // Move page at index 0 to index 3
      controller.reorderPage(0, 3);
      expect(
        controller.testState.pages.map((p) => p.originalIndex).toList(),
        [1, 2, 0, 3],
      );
    });

    test('deleting all pages disables apply and shows warning', () async {
      final pf = PlatformFile(
        name: 'delete_all.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      for (int i = 0; i < 4; i++) {
        controller.togglePageDeleted(i);
      }

      expect(controller.testState.activePageCount, 0);
      expect(controller.testState.canApply, isFalse);
      expect(controller.testState.errorMessage, contains('at least one page'));
    });

    test('applyChanges writes new PDF with remaining reordered/rotated pages', () async {
      final pf = PlatformFile(
        name: 'apply.pdf',
        size: fourPagePdfBytes.length,
        bytes: fourPagePdfBytes,
      );
      await controller.loadDocument(pf, overrideBytes: fourPagePdfBytes);

      // Delete original page index 0
      controller.togglePageDeleted(0);

      // Rotate original page index 1 (now at list index 1)
      controller.rotatePage(1);

      // Reorder list index 2 to list index 1
      controller.reorderPage(2, 1);

      final tempDir = Directory.systemTemp.createTempSync('anvil_test_');
      final outputPath = '${tempDir.path}${Platform.pathSeparator}output.pdf';

      final result = await controller.applyChanges(customOutputPath: outputPath);

      expect(result, equals(outputPath));
      expect(File(outputPath).existsSync(), isTrue);

      // Inspect output PDF
      final outputBytes = await File(outputPath).readAsBytes();
      final outputDoc = PdfDocument(inputBytes: outputBytes);

      // Should have 3 active pages
      expect(outputDoc.pages.count, 3);

      outputDoc.dispose();
      tempDir.deleteSync(recursive: true);
    });
  });
}
