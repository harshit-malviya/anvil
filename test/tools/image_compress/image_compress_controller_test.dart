import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:anvil/core/services/file_service.dart';
import 'package:anvil/tools/image_compress/image_compress_controller.dart';
import 'package:anvil/tools/image_compress/image_compress_state.dart';

class MockFileService extends Mock implements FileService {}

Uint8List createTestJpg({int width = 400, int height = 300, int quality = 95}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 255, (y * 13) % 255, (x + y) % 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

Uint8List createTestPng({int width = 200, int height = 100}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 128, 255));
  return Uint8List.fromList(img.encodePng(image, level: 6));
}

Uint8List createCorruptedBytes() {
  return Uint8List.fromList('NOT_AN_IMAGE_FILE_HEADER_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFileService mockFileService;
  late ImageCompressController controller;
  late Directory tempDir;

  late Uint8List testJpgBytes;
  late Uint8List testPngBytes;
  late Uint8List corruptedBytes;

  setUpAll(() {
    testJpgBytes = createTestJpg(width: 400, height: 300, quality: 95);
    testPngBytes = createTestPng(width: 200, height: 100);
    corruptedBytes = createCorruptedBytes();
  });

  setUp(() async {
    mockFileService = MockFileService();
    tempDir = await Directory.systemTemp.createTemp('image_compress_test_');

    when(() => mockFileService.getDefaultOutputDirectory(
          sourceFilePath: any(named: 'sourceFilePath'),
        )).thenAnswer((_) async => tempDir);
    when(() => mockFileService.openFolder(any())).thenAnswer((_) async {});
    when(() => mockFileService.saveFile(
          bytes: any(named: 'bytes'),
          defaultFileName: any(named: 'defaultFileName'),
        )).thenAnswer((_) async => '${tempDir.path}/saved_image.jpg');

    controller = ImageCompressController(mockFileService);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ImageCompressController Unit Tests', () {
    test('Initial state is empty', () {
      final state = controller.state;
      expect(state.isLoaded, isFalse);
      expect(state.file, isNull);
      expect(state.errorMessage, isNull);
      expect(state.level, equals(CompressionLevel.medium));
      expect(state.resultType, isNull);
    });

    test('loadImage sets image dimensions, format, and thumbnail', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isLoaded, isTrue);
      expect(state.originalWidth, equals(400));
      expect(state.originalHeight, equals(300));
      expect(state.originalSizeBytes, equals(testJpgBytes.length));
      expect(state.detectedFormat, equals('JPG'));
      expect(state.thumbnailBytes, isNotNull);
      expect(state.errorMessage, isNull);
    });

    test('loadImage rejects unsupported file extension', () async {
      final file = PlatformFile(
        name: 'document.txt',
        size: 10,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains("isn't supported"));
    });

    test('loadImage rejects WebP format with clear error message', () async {
      final file = PlatformFile(
        name: 'image.webp',
        size: 20,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains("WebP format compression is not supported"));
    });

    test('loadImage rejects corrupted bytes', () async {
      final file = PlatformFile(
        name: 'corrupt.jpg',
        size: corruptedBytes.length,
        bytes: corruptedBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isLoaded, isFalse);
      expect(state.errorMessage, contains("couldn't be read"));
    });

    test('setCompressionLevel updates level state', () async {
      controller.setCompressionLevel(CompressionLevel.high);
      expect(controller.state.level, equals(CompressionLevel.high));

      controller.setCompressionLevel(CompressionLevel.low);
      expect(controller.state.level, equals(CompressionLevel.low));
    });

    test('compress on JPEG at High level compresses file and preserves pixel dimensions', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      controller.setCompressionLevel(CompressionLevel.high);
      await controller.compress();

      final state = controller.state;
      expect(state.outputPath, isNotNull);
      expect(state.compressedSizeBytes, greaterThan(0));

      final compressedFile = File(state.outputPath!);
      expect(compressedFile.existsSync(), isTrue);

      final decodedCompressed = img.decodeImage(compressedFile.readAsBytesSync());
      expect(decodedCompressed, isNotNull);
      expect(decodedCompressed!.width, equals(400));
      expect(decodedCompressed.height, equals(300));
    });

    test('compress on PNG executes compression and preserves pixel dimensions', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testPngBytes.length,
        bytes: testPngBytes,
      );

      await controller.loadImage(file);
      controller.setCompressionLevel(CompressionLevel.high);
      await controller.compress();

      final state = controller.state;
      expect(state.outputPath, isNotNull);
      expect(state.compressedSizeBytes, greaterThan(0));

      final compressedFile = File(state.outputPath!);
      expect(compressedFile.existsSync(), isTrue);

      final decodedCompressed = img.decodeImage(compressedFile.readAsBytesSync());
      expect(decodedCompressed, isNotNull);
      expect(decodedCompressed!.width, equals(200));
      expect(decodedCompressed.height, equals(100));
    });

    test('compress categorizes outputLarger if compressed result >= original size', () async {
      // Create small low-quality JPEG
      final smallJpg = createTestJpg(width: 50, height: 50, quality: 30);
      final file = PlatformFile(
        name: 'small.jpg',
        size: smallJpg.length,
        bytes: smallJpg,
      );

      await controller.loadImage(file);
      controller.setCompressionLevel(CompressionLevel.low); // Quality 85 will be larger than quality 30 input
      await controller.compress();

      final state = controller.state;
      expect(state.resultType, equals(CompressionResultType.outputLarger));
    });

    test('saveAs, openFolder, and reset work as expected', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      await controller.compress();

      await controller.saveAs();
      verify(() => mockFileService.saveFile(
            bytes: any(named: 'bytes'),
            defaultFileName: any(named: 'defaultFileName'),
          )).called(1);

      await controller.openFolder();
      verify(() => mockFileService.openFolder(any())).called(1);

      controller.reset();
      expect(controller.state.isLoaded, isFalse);
      expect(controller.state.file, isNull);
    });
  });
}
