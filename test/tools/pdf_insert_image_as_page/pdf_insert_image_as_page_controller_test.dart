import 'dart:io';
import 'dart:ui';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_controller.dart';
import 'package:anvil/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_state.dart';

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

Uint8List createValidJpgImage({int width = 200, int height = 100}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List createValidPngImage({int width = 300, int height = 150}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgba8(0, 255, 0, 128));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfInsertImageAsPageController controller;
  late Uint8List targetPdf3Pages;
  late Uint8List protectedPdf;
  late Uint8List corruptedPdf;
  late Uint8List sampleJpg;
  late Uint8List samplePng;

  setUpAll(() async {
    targetPdf3Pages = await createValidPdf(pagesCount: 3);
    protectedPdf = await createProtectedPdf();
    corruptedPdf = createCorruptedPdf();
    sampleJpg = createValidJpgImage(width: 200, height: 100);
    samplePng = createValidPngImage(width: 300, height: 150);
  });

  setUp(() {
    controller = PdfInsertImageAsPageController();
  });

  group('PdfInsertImageAsPageController Unit Tests', () {
    test('Initial state is empty and canSubmit is false', () {
      final state = controller.testState;
      expect(state.hasTarget, isFalse);
      expect(state.hasImage, isFalse);
      expect(state.canSubmit, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('loadTargetDocument loads target PDF and defaults insertion point to at end', () async {
      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);

      await controller.loadTargetDocument(pfTarget);

      final state = controller.testState;
      expect(state.hasTarget, isTrue);
      expect(state.targetPageCount, equals(3));
      expect(state.insertionPoint, equals(2));
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

    test('loadImage loads valid JPEG and PNG images', () async {
      final pfJpg = PlatformFile(name: 'photo.jpg', size: sampleJpg.length, bytes: sampleJpg);
      await controller.loadImage(pfJpg);

      var state = controller.testState;
      expect(state.hasImage, isTrue);
      expect(state.imageWidth, equals(200));
      expect(state.imageHeight, equals(100));

      final pfPng = PlatformFile(name: 'graphic.png', size: samplePng.length, bytes: samplePng);
      await controller.loadImage(pfPng);

      state = controller.testState;
      expect(state.hasImage, isTrue);
      expect(state.imageWidth, equals(300));
      expect(state.imageHeight, equals(150));
    });

    test('loadImage rejects unsupported image formats (e.g. GIF, WebP)', () async {
      final pfGif = PlatformFile(name: 'anim.gif', size: 10, bytes: Uint8List.fromList([1, 2, 3]));

      await controller.loadImage(pfGif);

      final state = controller.testState;
      expect(state.hasImage, isFalse);
      expect(state.errorMessage, contains('Only JPEG and PNG images are supported'));
    });

    test('loadImage rejects corrupted or unreadable image bytes', () async {
      final pfBadJpg = PlatformFile(name: 'broken.jpg', size: 10, bytes: Uint8List.fromList([0, 0, 0, 0]));

      await controller.loadImage(pfBadJpg);

      final state = controller.testState;
      expect(state.hasImage, isFalse);
      expect(state.errorMessage, contains("image couldn't be read"));
    });

    test('insertImagePage at start (insertionPoint = -1) with matchNeighboringPage', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_img_insert_start');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_start.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfImage = PlatformFile(name: 'image.png', size: samplePng.length, bytes: samplePng);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadImage(pfImage);

      controller.setInsertionPoint(-1);
      controller.setPageFitMode(PageFitMode.matchNeighboringPage);

      final resultPath = await controller.insertImagePage(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(4)); // 3 original + 1 inserted image page
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertImagePage at end (insertionPoint = targetPageCount - 1) with fitToImage', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_img_insert_end');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_end.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfImage = PlatformFile(name: 'image.jpg', size: sampleJpg.length, bytes: sampleJpg);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadImage(pfImage);

      controller.setInsertionPoint(2);
      controller.setPageFitMode(PageFitMode.fitToImage);

      final resultPath = await controller.insertImagePage(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(4));
      // Last page should match image aspect size (200x100)
      expect(doc.pages[3].size.width, equals(200));
      expect(doc.pages[3].size.height, equals(100));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertImagePage in middle uses page immediately preceding insertion point as neighbor reference', () async {
      // Create target PDF with distinct page size for page 2 (index 1): Letter Landscape (792 x 612)
      final customTarget = await createValidPdf(pagesCount: 1, pageSize: PdfPageSize.letter, orientation: PdfPageOrientation.landscape);
      final pfTarget = PlatformFile(name: 'custom_target.pdf', size: customTarget.length, bytes: customTarget);
      final pfImage = PlatformFile(name: 'image.jpg', size: sampleJpg.length, bytes: sampleJpg);

      await controller.loadTargetDocument(pfTarget);
      await controller.loadImage(pfImage);

      controller.setInsertionPoint(0); // Insert after page index 0
      controller.setPageFitMode(PageFitMode.matchNeighboringPage);

      final tempDir = Directory.systemTemp.createTempSync('anvil_img_insert_middle');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_middle.pdf';

      await controller.insertImagePage(customOutputPath: targetPath);

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(2));
      // Inserted page (index 1) should match preceding page 0 size (Letter Landscape: 792 x 612)
      expect(doc.pages[1].size.width, equals(792));
      expect(doc.pages[1].size.height, equals(612));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('zero-existing-pages target document falls back to fitToImage automatically', () async {
      final pfImage = PlatformFile(name: 'image.jpg', size: sampleJpg.length, bytes: sampleJpg);
      await controller.loadImage(pfImage);

      controller.setPageFitMode(PageFitMode.matchNeighboringPage);
      expect(controller.testState.fitMode, equals(PageFitMode.fitToImage));
    });
  });
}
