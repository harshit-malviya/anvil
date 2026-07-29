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

Uint8List createValidJpgImage({int width = 200, int height = 100, img.Color? color}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List createValidPngImage({int width = 300, int height = 150, img.Color? color}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgba8(0, 255, 0, 128));
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
  late Uint8List sampleJpg2;

  setUpAll(() async {
    targetPdf3Pages = await createValidPdf(pagesCount: 3);
    protectedPdf = await createProtectedPdf();
    corruptedPdf = createCorruptedPdf();
    sampleJpg = createValidJpgImage(width: 200, height: 100);
    samplePng = createValidPngImage(width: 300, height: 150);
    sampleJpg2 = createValidJpgImage(width: 400, height: 500, color: img.ColorRgb8(0, 0, 255));
  });

  setUp(() {
    controller = PdfInsertImageAsPageController();
  });

  group('PdfInsertImageAsPageController Unit Tests (v2 Batch Insertion)', () {
    test('Initial state is empty and canSubmit is false', () {
      final state = controller.testState;
      expect(state.hasTarget, isFalse);
      expect(state.hasImages, isFalse);
      expect(state.canSubmit, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('loadTargetDocument loads target PDF and defaults insertion point to end', () async {
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

    test('addImages loads valid JPEG and PNG images into batch list', () async {
      final pfJpg = PlatformFile(name: 'photo.jpg', size: sampleJpg.length, bytes: sampleJpg);
      final pfPng = PlatformFile(name: 'graphic.png', size: samplePng.length, bytes: samplePng);

      await controller.addImages([pfJpg, pfPng]);

      final state = controller.testState;
      expect(state.hasImages, isTrue);
      expect(state.imageCount, equals(2));
      expect(state.images[0].file.name, equals('photo.jpg'));
      expect(state.images[0].width, equals(200));
      expect(state.images[1].file.name, equals('graphic.png'));
      expect(state.images[1].width, equals(300));
    });

    test('addImages rejects unsupported image format per file', () async {
      final pfGif = PlatformFile(name: 'anim.gif', size: 10, bytes: Uint8List.fromList([1, 2, 3]));

      await controller.addImages([pfGif]);

      final state = controller.testState;
      expect(state.hasImages, isFalse);
      expect(state.errorMessage, contains('Only JPEG and PNG images are supported'));
    });

    test('addImages handles bad image per file without blocking valid ones', () async {
      final pfJpg = PlatformFile(name: 'good.jpg', size: sampleJpg.length, bytes: sampleJpg);
      final pfBadGif = PlatformFile(name: 'bad.gif', size: 10, bytes: Uint8List.fromList([1, 2, 3]));
      final pfPng = PlatformFile(name: 'good.png', size: samplePng.length, bytes: samplePng);

      await controller.addImages([pfJpg, pfBadGif, pfPng]);

      final state = controller.testState;
      expect(state.imageCount, equals(2)); // good.jpg and good.png added
      expect(state.images[0].file.name, equals('good.jpg'));
      expect(state.images[1].file.name, equals('good.png'));
      expect(state.errorMessage, contains("bad.gif wasn't added"));
    });

    test('removeImage removes image item from batch', () async {
      final pfJpg = PlatformFile(name: 'photo.jpg', size: sampleJpg.length, bytes: sampleJpg);
      final pfPng = PlatformFile(name: 'graphic.png', size: samplePng.length, bytes: samplePng);

      await controller.addImages([pfJpg, pfPng]);
      expect(controller.testState.imageCount, equals(2));

      final firstId = controller.testState.images[0].id;
      controller.removeImage(firstId);

      final state = controller.testState;
      expect(state.imageCount, equals(1));
      expect(state.images[0].file.name, equals('graphic.png'));
    });

    test('reorderImages changes order of images in batch list', () async {
      final pfJpg = PlatformFile(name: 'first.jpg', size: sampleJpg.length, bytes: sampleJpg);
      final pfPng = PlatformFile(name: 'second.png', size: samplePng.length, bytes: samplePng);

      await controller.addImages([pfJpg, pfPng]);
      expect(controller.testState.images[0].file.name, equals('first.jpg'));

      controller.reorderImages(0, 2);

      final state = controller.testState;
      expect(state.images[0].file.name, equals('second.png'));
      expect(state.images[1].file.name, equals('first.jpg'));
    });

    test('insertImagePages (1 image regression) at start with matchNeighboringPage', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_img_insert_reg');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_start.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfImage = PlatformFile(name: 'image.png', size: samplePng.length, bytes: samplePng);

      await controller.loadTargetDocument(pfTarget);
      await controller.addImages([pfImage]);

      controller.setInsertionPoint(-1);
      controller.setPageFitMode(PageFitMode.matchNeighboringPage);

      final resultPath = await controller.insertImagePages(customOutputPath: targetPath);
      expect(resultPath, equals(targetPath));

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(4)); // 3 original + 1 inserted image page
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertImagePages N images at start with matchNeighboringPage (all N share resolved neighbor size)', () async {
      final customTarget = await createValidPdf(pagesCount: 2, pageSize: PdfPageSize.letter, orientation: PdfPageOrientation.landscape);
      final pfTarget = PlatformFile(name: 'target.pdf', size: customTarget.length, bytes: customTarget);
      final pfImg1 = PlatformFile(name: 'img1.jpg', size: sampleJpg.length, bytes: sampleJpg);
      final pfImg2 = PlatformFile(name: 'img2.png', size: samplePng.length, bytes: samplePng);

      await controller.loadTargetDocument(pfTarget);
      await controller.addImages([pfImg1, pfImg2]);

      controller.setInsertionPoint(-1); // At start -> matches page 0 (Letter Landscape: 792x612)
      controller.setPageFitMode(PageFitMode.matchNeighboringPage);

      final tempDir = Directory.systemTemp.createTempSync('anvil_img_batch_start');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_batch_start.pdf';

      await controller.insertImagePages(customOutputPath: targetPath);

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(4)); // 2 target + 2 images inserted at start
      // Inserted pages (index 0 and 1) should both match page 0's size (Letter Landscape: 792x612)
      expect(doc.pages[0].size.width, equals(792));
      expect(doc.pages[0].size.height, equals(612));
      expect(doc.pages[1].size.width, equals(792));
      expect(doc.pages[1].size.height, equals(612));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertImagePages N images at end with fitToImage (each page uses its image aspect ratio)', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_img_batch_end');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_batch_end.pdf';

      final pfTarget = PlatformFile(name: 'target.pdf', size: targetPdf3Pages.length, bytes: targetPdf3Pages);
      final pfImg1 = PlatformFile(name: 'img1.jpg', size: sampleJpg.length, bytes: sampleJpg); // 200x100
      final pfImg2 = PlatformFile(name: 'img2.png', size: samplePng.length, bytes: samplePng); // 300x150
      final pfImg3 = PlatformFile(name: 'img3.jpg', size: sampleJpg2.length, bytes: sampleJpg2); // 400x500

      await controller.loadTargetDocument(pfTarget);
      await controller.addImages([pfImg1, pfImg2, pfImg3]);

      controller.setInsertionPoint(2); // At end
      controller.setPageFitMode(PageFitMode.fitToImage);

      await controller.insertImagePages(customOutputPath: targetPath);

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(6)); // 3 target + 3 images inserted at end
      // Check last 3 pages dimensions match each image individually
      expect(doc.pages[3].size.width, equals(200));
      expect(doc.pages[3].size.height, equals(100));

      expect(doc.pages[4].size.width, equals(300));
      expect(doc.pages[4].size.height, equals(150));

      expect(doc.pages[5].size.width, equals(400));
      expect(doc.pages[5].size.height, equals(500));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('insertImagePages in middle with N images (preceding target page used as shared neighbor reference)', () async {
      final customTarget = await createValidPdf(pagesCount: 3, pageSize: PdfPageSize.a4, orientation: PdfPageOrientation.landscape);
      final pfTarget = PlatformFile(name: 'target.pdf', size: customTarget.length, bytes: customTarget);
      final pfImg1 = PlatformFile(name: 'img1.jpg', size: sampleJpg.length, bytes: sampleJpg);
      final pfImg2 = PlatformFile(name: 'img2.png', size: samplePng.length, bytes: samplePng);

      await controller.loadTargetDocument(pfTarget);
      await controller.addImages([pfImg1, pfImg2]);

      controller.setInsertionPoint(0); // Insert after target page 0
      controller.setPageFitMode(PageFitMode.matchNeighboringPage);

      final tempDir = Directory.systemTemp.createTempSync('anvil_img_batch_middle');
      final targetPath = '${tempDir.path}${Platform.pathSeparator}inserted_batch_middle.pdf';

      await controller.insertImagePages(customOutputPath: targetPath);

      final doc = PdfDocument(inputBytes: File(targetPath).readAsBytesSync());
      expect(doc.pages.count, equals(5)); // 3 original + 2 inserted
      // Page 1 and Page 2 (0-indexed) are the inserted image pages, both matching Page 0's size
      expect(doc.pages[1].size.width, equals(doc.pages[0].size.width));
      expect(doc.pages[1].size.height, equals(doc.pages[0].size.height));
      expect(doc.pages[2].size.width, equals(doc.pages[0].size.width));
      expect(doc.pages[2].size.height, equals(doc.pages[0].size.height));
      doc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('zero-existing-pages target document falls back to fitToImage automatically', () async {
      final pfImage = PlatformFile(name: 'image.jpg', size: sampleJpg.length, bytes: sampleJpg);
      await controller.addImages([pfImage]);

      controller.setPageFitMode(PageFitMode.matchNeighboringPage);
      expect(controller.testState.fitMode, equals(PageFitMode.fitToImage));
    });
  });
}
