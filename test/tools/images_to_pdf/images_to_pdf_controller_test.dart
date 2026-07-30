import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/tools/images_to_pdf/images_to_pdf_controller.dart';

Uint8List createValidJpgImage({int width = 200, int height = 100, img.Color? color}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgb8(255, 0, 0));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List createValidPngImage({int width = 300, int height = 450, img.Color? color}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: color ?? img.ColorRgba8(0, 255, 0, 128));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List createCorruptedImageBytes() {
  return Uint8List.fromList('NOT_AN_IMAGE_FILE_HEADER_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImagesToPdfController controller;
  late Uint8List sampleJpgLandscape;
  late Uint8List samplePngPortrait;
  late Uint8List sampleOversizedJpg;
  late Uint8List corruptedBytes;

  setUpAll(() {
    sampleJpgLandscape = createValidJpgImage(width: 800, height: 600);
    samplePngPortrait = createValidPngImage(width: 600, height: 900);
    sampleOversizedJpg = createValidJpgImage(width: 3200, height: 1600);
    corruptedBytes = createCorruptedImageBytes();
  });

  setUp(() {
    controller = ImagesToPdfController();
  });

  group('ImagesToPdfController Unit Tests', () {
    test('Initial state is empty and canSubmit is false', () {
      final state = controller.testState;
      expect(state.hasImages, isFalse);
      expect(state.totalImages, equals(0));
      expect(state.canSubmit, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('addImages adds single valid JPEG image and enables submit', () async {
      final pfJpg = PlatformFile(
        name: 'receipt.jpg',
        size: sampleJpgLandscape.length,
        bytes: sampleJpgLandscape,
      );

      await controller.addImages([pfJpg]);

      final state = controller.testState;
      expect(state.hasImages, isTrue);
      expect(state.totalImages, equals(1));
      expect(state.canSubmit, isTrue);
      expect(state.images.first.fileName, equals('receipt.jpg'));
      expect(state.images.first.width, equals(800));
      expect(state.images.first.height, equals(600));
      expect(state.errorMessage, isNull);
    });

    test('addImages adds multiple valid images and preserves list order', () async {
      final pfJpg = PlatformFile(
        name: 'photo1.jpg',
        size: sampleJpgLandscape.length,
        bytes: sampleJpgLandscape,
      );
      final pfPng = PlatformFile(
        name: 'photo2.png',
        size: samplePngPortrait.length,
        bytes: samplePngPortrait,
      );

      await controller.addImages([pfJpg, pfPng]);

      final state = controller.testState;
      expect(state.totalImages, equals(2));
      expect(state.images[0].fileName, equals('photo1.jpg'));
      expect(state.images[1].fileName, equals('photo2.png'));
      expect(state.errorMessage, isNull);
    });

    test('addImages rejects unsupported format (.heic, .tiff, .gif) with explicit error message', () async {
      final pfHeic = PlatformFile(
        name: 'document.heic',
        size: 1000,
        bytes: Uint8List(100),
      );

      await controller.addImages([pfHeic]);

      final state = controller.testState;
      expect(state.hasImages, isFalse);
      expect(state.errorMessage, contains('Unsupported format — PNG and JPEG images only.'));
    });

    test('addImages rejects corrupted/unreadable image bytes with explicit error message', () async {
      final pfCorrupted = PlatformFile(
        name: 'bad_photo.jpg',
        size: corruptedBytes.length,
        bytes: corruptedBytes,
      );

      await controller.addImages([pfCorrupted]);

      final state = controller.testState;
      expect(state.hasImages, isFalse);
      expect(state.errorMessage, contains("This image couldn't be read"));
    });

    test('addImages automatically downscales oversized images (>3000px max dimension cap)', () async {
      final pfOversized = PlatformFile(
        name: 'huge_photo.jpg',
        size: sampleOversizedJpg.length,
        bytes: sampleOversizedJpg,
      );

      await controller.addImages([pfOversized]);

      final state = controller.testState;
      expect(state.hasImages, isTrue);
      expect(state.images.first.width, equals(3000));
      expect(state.images.first.height, equals(1500));
    });

    test('reorderImages reorders items correctly', () async {
      final pf1 = PlatformFile(name: 'img1.jpg', size: sampleJpgLandscape.length, bytes: sampleJpgLandscape);
      final pf2 = PlatformFile(name: 'img2.png', size: samplePngPortrait.length, bytes: samplePngPortrait);

      await controller.addImages([pf1, pf2]);
      expect(controller.testState.images[0].fileName, equals('img1.jpg'));
      expect(controller.testState.images[1].fileName, equals('img2.png'));

      controller.reorderImages(0, 2);

      expect(controller.testState.images[0].fileName, equals('img2.png'));
      expect(controller.testState.images[1].fileName, equals('img1.jpg'));
    });

    test('removeImage removes image item by ID and clears when empty', () async {
      final pf1 = PlatformFile(name: 'img1.jpg', size: sampleJpgLandscape.length, bytes: sampleJpgLandscape);
      await controller.addImages([pf1]);

      final item = controller.testState.images.first;
      controller.removeImage(item.id);

      final state = controller.testState;
      expect(state.hasImages, isFalse);
      expect(state.canSubmit, isFalse);
    });

    test('clearImages resets state back to initial empty drop zone state', () async {
      final pf1 = PlatformFile(name: 'img1.jpg', size: sampleJpgLandscape.length, bytes: sampleJpgLandscape);
      await controller.addImages([pf1]);
      expect(controller.testState.hasImages, isTrue);

      controller.clearImages();

      final state = controller.testState;
      expect(state.hasImages, isFalse);
      expect(state.canSubmit, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('createPdf single image conversion (happy path)', () async {
      final pfJpg = PlatformFile(name: 'single.jpg', size: sampleJpgLandscape.length, bytes: sampleJpgLandscape);
      await controller.addImages([pfJpg]);

      final tempDir = Directory.systemTemp.createTempSync('anvil_img_pdf_test_');
      final customPath = '${tempDir.path}${Platform.pathSeparator}output_single.pdf';

      final resultPath = await controller.createPdf(customOutputPath: customPath);

      expect(resultPath, equals(customPath));
      final outputFile = File(customPath);
      expect(outputFile.existsSync(), isTrue);

      final pdfDoc = PdfDocument(inputBytes: outputFile.readAsBytesSync());
      expect(pdfDoc.pages.count, equals(1));
      expect(pdfDoc.pages[0].size.width, equals(800));
      expect(pdfDoc.pages[0].size.height, equals(600));
      pdfDoc.dispose();

      tempDir.deleteSync(recursive: true);
    });

    test('createPdf multi-image conversion preserving mixed orientation page sizing', () async {
      final pfLandscape = PlatformFile(name: 'land.jpg', size: sampleJpgLandscape.length, bytes: sampleJpgLandscape);
      final pfPortrait = PlatformFile(name: 'port.png', size: samplePngPortrait.length, bytes: samplePngPortrait);
      await controller.addImages([pfLandscape, pfPortrait]);

      final tempDir = Directory.systemTemp.createTempSync('anvil_img_pdf_test_');
      final customPath = '${tempDir.path}${Platform.pathSeparator}output_multi.pdf';

      final resultPath = await controller.createPdf(customOutputPath: customPath);

      expect(resultPath, equals(customPath));
      final outputFile = File(customPath);
      expect(outputFile.existsSync(), isTrue);

      final pdfDoc = PdfDocument(inputBytes: outputFile.readAsBytesSync());
      expect(pdfDoc.pages.count, equals(2));

      // Page 1: Landscape (800 x 600)
      expect(pdfDoc.pages[0].size.width, equals(800));
      expect(pdfDoc.pages[0].size.height, equals(600));

      // Page 2: Portrait (600 x 900)
      expect(pdfDoc.pages[1].size.width, equals(600));
      expect(pdfDoc.pages[1].size.height, equals(900));

      pdfDoc.dispose();
      tempDir.deleteSync(recursive: true);
    });
  });
}
