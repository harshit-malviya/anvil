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
      expect(state.mode, equals(CompressionMode.qualityLevel));
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

    test('setMinSize enforces 5 KB hard floor', () {
      controller.setMinSize(2.0, SizeUnit.kb);
      expect(controller.state.minSizeValue, equals(5.0));

      controller.setMinSize(10.0, SizeUnit.kb);
      expect(controller.state.minSizeValue, equals(10.0));
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

    test('compress in Target Size Range mode lands in target range', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      controller.setMode(CompressionMode.targetSizeRange);
      controller.setMinSize(20.0, SizeUnit.kb);
      controller.setMaxSize(40.0, SizeUnit.kb);

      await controller.compress();

      final state = controller.state;
      expect(state.resultType, equals(CompressionResultType.inRangeSuccess));
      expect(state.compressedSizeBytes, greaterThanOrEqualTo(20 * 1024));
      expect(state.compressedSizeBytes, lessThanOrEqualTo(40 * 1024));
    });

    test('compress in Target Size Range mode detects original already inside target range', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      controller.setMode(CompressionMode.targetSizeRange);

      final origKb = testJpgBytes.length / 1024.0;
      controller.setMinSize(origKb - 5, SizeUnit.kb);
      controller.setMaxSize(origKb + 5, SizeUnit.kb);

      await controller.compress();

      final state = controller.state;
      expect(state.resultType, equals(CompressionResultType.alreadyInRange));
      expect(state.outputPath, isNull);
    });

    test('compress in Target Size Range mode detects original smaller than minimum', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      controller.setMode(CompressionMode.targetSizeRange);

      final origKb = testJpgBytes.length / 1024.0;
      controller.setMinSize(origKb + 50, SizeUnit.kb);
      controller.setMaxSize(origKb + 100, SizeUnit.kb);

      await controller.compress();

      final state = controller.state;
      expect(state.resultType, equals(CompressionResultType.smallerThanMin));
      expect(state.outputPath, isNull);
    });

    test('JPEG Target Size Range search stops at quality floor (30) when maximum is unachievable', () async {
      final file = PlatformFile(
        name: 'sample.jpg',
        size: testJpgBytes.length,
        bytes: testJpgBytes,
      );

      await controller.loadImage(file);
      controller.setMode(CompressionMode.targetSizeRange);
      // Set an unachievably low target max size (e.g. 5.0 KB to 5.1 KB for a complex 400x300 JPG)
      controller.setMinSize(5.0, SizeUnit.kb);
      controller.setMaxSize(5.1, SizeUnit.kb);

      await controller.compress();

      final state = controller.state;
      expect(state.resultType, equals(CompressionResultType.closestEffort));
      expect(state.outputPath, isNotNull);

      // Verify the compressed JPEG quality wasn't pushed below quality floor (30)
      final compressedBytes = File(state.outputPath!).readAsBytesSync();
      // Floor quality output (30) should equal or match the generated compressed size
      final floorBytes = Uint8List.fromList(img.encodeJpg(img.bakeOrientation(img.decodeImage(testJpgBytes)!), quality: 30));
      expect(compressedBytes.length, equals(floorBytes.length));
    });

    test('PNG Target Size Range search stops at palette floor (64) with dithering', () async {
      // Create a 500x500 test PNG with pseudo-random RGB noise so original size is ~300 KB (> 5 KB floor)
      final pngImage = img.Image(width: 500, height: 500);
      var seed = 12345;
      for (var y = 0; y < 500; y++) {
        for (var x = 0; x < 500; x++) {
          seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF;
          final r = (seed >> 16) & 0xFF;
          final g = (seed >> 8) & 0xFF;
          final b = seed & 0xFF;
          pngImage.setPixelRgb(x, y, r, g, b);
        }
      }
      final multiColorPngBytes = Uint8List.fromList(img.encodePng(pngImage, level: 6));

      final file = PlatformFile(
        name: 'multicolor.png',
        size: multiColorPngBytes.length,
        bytes: multiColorPngBytes,
      );

      await controller.loadImage(file);
      controller.setMode(CompressionMode.targetSizeRange);
      controller.setMinSize(5.0, SizeUnit.kb);
      controller.setMaxSize(6.0, SizeUnit.kb);

      await controller.compress();

      final state = controller.state;
      expect(state.resultType, equals(CompressionResultType.closestEffort));
      expect(state.outputPath, isNotNull);

      final compressedBytes = File(state.outputPath!).readAsBytesSync();
      // Quantized at 64 colors with Floyd-Steinberg dither
      final decodedOrig = img.bakeOrientation(img.decodeImage(multiColorPngBytes)!);
      final floorQuantized = img.quantize(decodedOrig, numberOfColors: 64, dither: img.DitherKernel.floydSteinberg);
      final floorPngBytes = Uint8List.fromList(img.encodePng(floorQuantized, level: 9));

      expect(compressedBytes.length, equals(floorPngBytes.length));
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

    group('Dimension Fallback Unit Tests', () {
      test('Enabling checkbox without tapping Retry leaves state at quality-only closest effort', () async {
        final file = PlatformFile(
          name: 'sample.jpg',
          size: testJpgBytes.length,
          bytes: testJpgBytes,
        );

        await controller.loadImage(file);
        controller.setMode(CompressionMode.targetSizeRange);
        controller.setMinSize(5.0, SizeUnit.kb);
        controller.setMaxSize(5.1, SizeUnit.kb);

        await controller.compress();

        expect(controller.state.resultType, equals(CompressionResultType.closestEffort));
        expect(controller.state.compressedWidth, equals(400));
        expect(controller.state.compressedHeight, equals(300));
        expect(controller.state.isDimensionReduced, isFalse);

        // User checks box but does NOT retry
        controller.setDimensionFallbackEnabled(true);
        expect(controller.state.isDimensionFallbackEnabled, isTrue);
        expect(controller.state.compressedWidth, equals(400));
        expect(controller.state.compressedHeight, equals(300));
        expect(controller.state.isDimensionReduced, isFalse);
      });

      test('retryWithDimensionReduction steps down resolution and lands in range or reaches 50% floor', () async {
        final file = PlatformFile(
          name: 'sample.jpg',
          size: testJpgBytes.length,
          bytes: testJpgBytes,
        );

        await controller.loadImage(file);
        controller.setMode(CompressionMode.targetSizeRange);
        // Set target range reachable only with resolution reduction
        controller.setMinSize(5.0, SizeUnit.kb);
        controller.setMaxSize(6.5, SizeUnit.kb);

        await controller.compress();
        expect(controller.state.resultType, equals(CompressionResultType.closestEffort));

        controller.setDimensionFallbackEnabled(true);
        await controller.retryWithDimensionReduction();

        final state = controller.state;
        expect(state.isDimensionReduced, isTrue);
        expect(state.compressedWidth, lessThan(400));
        expect(state.compressedHeight, lessThan(300));
        // Verify 50% floor bound (>= 200x150)
        expect(state.compressedWidth, greaterThanOrEqualTo(200));
        expect(state.compressedHeight, greaterThanOrEqualTo(150));
      });

      test('Dimension stepping reaches 50% floor without landing in range sets bothFloorsHit', () async {
        final file = PlatformFile(
          name: 'sample.jpg',
          size: testJpgBytes.length,
          bytes: testJpgBytes,
        );

        await controller.loadImage(file);
        controller.setMode(CompressionMode.targetSizeRange);
        // Extremely low target range unattainable even at 50% floor
        controller.setMinSize(5.0, SizeUnit.kb);
        controller.setMaxSize(5.01, SizeUnit.kb);

        controller.setDimensionFallbackEnabled(true);
        await controller.compress();

        final state = controller.state;
        expect(state.resultType, equals(CompressionResultType.closestEffort));
        expect(state.bothFloorsHit, isTrue);
        // Width/height stopped at 50% floor: 400 * 0.5 = 200, 300 * 0.5 = 150
        expect(state.compressedWidth, equals(200));
        expect(state.compressedHeight, equals(150));
      });

      test('Unchecking dimension fallback after successful resize reverts state to pre-resize quality-only result', () async {
        final file = PlatformFile(
          name: 'sample.jpg',
          size: testJpgBytes.length,
          bytes: testJpgBytes,
        );

        await controller.loadImage(file);
        controller.setMode(CompressionMode.targetSizeRange);
        controller.setMinSize(5.0, SizeUnit.kb);
        controller.setMaxSize(6.5, SizeUnit.kb);

        // Quality only search runs first
        await controller.compress();
        final qOnlySize = controller.state.compressedSizeBytes;
        expect(controller.state.isDimensionReduced, isFalse);

        // Retry with dimension reduction succeeds
        controller.setDimensionFallbackEnabled(true);
        await controller.retryWithDimensionReduction();
        expect(controller.state.isDimensionReduced, isTrue);

        // User unchecks the box
        controller.setDimensionFallbackEnabled(false);

        final state = controller.state;
        expect(state.isDimensionFallbackEnabled, isFalse);
        expect(state.isDimensionReduced, isFalse);
        expect(state.compressedWidth, equals(400));
        expect(state.compressedHeight, equals(300));
        expect(state.compressedSizeBytes, equals(qOnlySize));
        expect(state.resultType, equals(CompressionResultType.closestEffort));
      });
    });
  });
}
