import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:anvil/core/services/file_service.dart';
import 'package:anvil/tools/image_convert/image_convert_controller.dart';
import 'package:anvil/tools/image_convert/image_convert_state.dart';

class MockFileService extends Mock implements FileService {}

Uint8List createPngWithAlpha({int width = 100, int height = 100}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(255, 0, 0, 128));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List createJpgImage({int width = 120, int height = 80}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 255, 0));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List createBmpImage({int width = 60, int height = 60}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 0, 255));
  return Uint8List.fromList(img.encodeBmp(image));
}

Uint8List createGifImage({int width = 50, int height = 50}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(255, 255, 0));
  return Uint8List.fromList(img.encodeGif(image));
}

Uint8List createCorruptedBytes() {
  return Uint8List.fromList('NOT_AN_IMAGE_FILE_HEADER_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFileService mockFileService;
  late ImageConvertController controller;
  late Directory tempDir;

  late Uint8List pngAlphaBytes;
  late Uint8List jpgBytes;
  late Uint8List corruptedBytes;

  setUpAll(() {
    pngAlphaBytes = createPngWithAlpha();
    jpgBytes = createJpgImage();
    corruptedBytes = createCorruptedBytes();
  });

  setUp(() async {
    mockFileService = MockFileService();
    tempDir = await Directory.systemTemp.createTemp('image_convert_test_');

    when(() => mockFileService.getDefaultOutputDirectory(
          sourceFilePath: any(named: 'sourceFilePath'),
        )).thenAnswer((_) async => tempDir);
    when(() => mockFileService.openFolder(any())).thenAnswer((_) async {});
    when(() => mockFileService.saveFile(
          bytes: any(named: 'bytes'),
          defaultFileName: any(named: 'defaultFileName'),
        )).thenAnswer((_) async => '${tempDir.path}/saved_image.png');

    controller = ImageConvertController(mockFileService);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ImageConvertController Unit Tests', () {
    test('Initial state is empty', () {
      final state = controller.state;
      expect(state.hasFile, isFalse);
      expect(state.isSuccess, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.jpegQuality, equals(90));
      expect(state.targetFormat, equals(ImageOutputFormat.jpeg));
    });

    test('loadImage detects PNG format, dimensions, and alpha channel', () async {
      final file = PlatformFile(
        name: 'test_graphic.png',
        size: pngAlphaBytes.length,
        bytes: pngAlphaBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.hasFile, isTrue);
      expect(state.detectedFormat, equals('PNG'));
      expect(state.width, equals(100));
      expect(state.height, equals(100));
      expect(state.hasAlpha, isTrue);
      expect(state.targetFormat, equals(ImageOutputFormat.jpeg)); // Default non-matching
      expect(state.errorMessage, isNull);
    });

    test('loadImage detects JPEG format and defaults target format to PNG', () async {
      final file = PlatformFile(
        name: 'photo.jpg',
        size: jpgBytes.length,
        bytes: jpgBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.hasFile, isTrue);
      expect(state.detectedFormat, equals('JPEG'));
      expect(state.width, equals(120));
      expect(state.height, equals(80));
      expect(state.targetFormat, equals(ImageOutputFormat.png));
    });

    test('loadImage rejects unsupported file extension', () async {
      final file = PlatformFile(
        name: 'document.pdf',
        size: 100,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.hasFile, isFalse);
      expect(state.errorMessage, contains("isn't supported for conversion"));
    });

    test('loadImage rejects corrupted image file', () async {
      final file = PlatformFile(
        name: 'broken.png',
        size: corruptedBytes.length,
        bytes: corruptedBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.hasFile, isFalse);
      expect(state.errorMessage, contains("couldn't be read as an image"));
    });

    test('setTargetFormat prevents setting format to source format', () async {
      final file = PlatformFile(
        name: 'test.png',
        size: pngAlphaBytes.length,
        bytes: pngAlphaBytes,
      );

      await controller.loadImage(file);
      controller.setTargetFormat(ImageOutputFormat.png);

      // PNG is source, so attempt to set targetFormat to PNG should be ignored
      expect(controller.state.targetFormat, isNot(equals(ImageOutputFormat.png)));
    });

    test('setJpegQuality updates quality score clamped between 0 and 100', () {
      controller.setJpegQuality(75);
      expect(controller.state.jpegQuality, equals(75));

      controller.setJpegQuality(150);
      expect(controller.state.jpegQuality, equals(100));

      controller.setJpegQuality(-20);
      expect(controller.state.jpegQuality, equals(0));
    });

    test('convert PNG to JPEG flattens transparency onto white background', () async {
      final sourceFile = File('${tempDir.path}/alpha.png');
      await sourceFile.writeAsBytes(pngAlphaBytes);

      final platformFile = PlatformFile(
        name: 'alpha.png',
        size: pngAlphaBytes.length,
        path: sourceFile.path,
        bytes: pngAlphaBytes,
      );

      await controller.loadImage(platformFile);
      controller.setTargetFormat(ImageOutputFormat.jpeg);
      await controller.convert();

      final state = controller.state;
      expect(state.isSuccess, isTrue);
      expect(state.outputPath, endsWith('.jpg'));
      expect(state.outputSize, greaterThan(0));

      final outputFile = File(state.outputPath!);
      expect(outputFile.existsSync(), isTrue);

      final outputBytes = await outputFile.readAsBytes();
      final decodedOutput = img.decodeJpg(outputBytes);
      expect(decodedOutput, isNotNull);
      expect(decodedOutput!.width, equals(100));
      expect(decodedOutput.height, equals(100));
      expect(decodedOutput.hasAlpha, isFalse); // JPEG flattens alpha
    });

    test('convert PNG to BMP outputs valid BMP file', () async {
      final sourceFile = File('${tempDir.path}/graphic.png');
      await sourceFile.writeAsBytes(pngAlphaBytes);

      final platformFile = PlatformFile(
        name: 'graphic.png',
        size: pngAlphaBytes.length,
        path: sourceFile.path,
        bytes: pngAlphaBytes,
      );

      await controller.loadImage(platformFile);
      controller.setTargetFormat(ImageOutputFormat.bmp);
      await controller.convert();

      final state = controller.state;
      expect(state.isSuccess, isTrue);
      expect(state.outputPath, endsWith('.bmp'));

      final outputFile = File(state.outputPath!);
      expect(outputFile.existsSync(), isTrue);
    });

    test('reset clears file state back to initial state', () async {
      final file = PlatformFile(
        name: 'test.jpg',
        size: jpgBytes.length,
        bytes: jpgBytes,
      );

      await controller.loadImage(file);
      expect(controller.state.hasFile, isTrue);

      controller.reset();
      expect(controller.state.hasFile, isFalse);
      expect(controller.state.file, isNull);
    });
  });
}
