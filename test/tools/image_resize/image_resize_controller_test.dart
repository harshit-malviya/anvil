import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:anvil/core/services/file_service.dart';
import 'package:anvil/tools/image_resize/image_resize_controller.dart';
import 'package:anvil/tools/image_resize/image_resize_state.dart';

class MockFileService extends Mock implements FileService {}

Uint8List createTestImage({int width = 200, int height = 100}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(0, 128, 255));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List createCorruptedBytes() {
  return Uint8List.fromList('NOT_AN_IMAGE_FILE_HEADER_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFileService mockFileService;
  late ImageResizeController controller;
  late Directory tempDir;

  late Uint8List testImageBytes;
  late Uint8List corruptedBytes;

  setUpAll(() {
    testImageBytes = createTestImage(width: 200, height: 100);
    corruptedBytes = createCorruptedBytes();
  });

  setUp(() async {
    mockFileService = MockFileService();
    tempDir = await Directory.systemTemp.createTemp('image_resize_test_');

    when(() => mockFileService.getDefaultOutputDirectory(
          sourceFilePath: any(named: 'sourceFilePath'),
        )).thenAnswer((_) async => tempDir);
    when(() => mockFileService.openFolder(any())).thenAnswer((_) async {});
    when(() => mockFileService.saveFile(
          bytes: any(named: 'bytes'),
          defaultFileName: any(named: 'defaultFileName'),
        )).thenAnswer((_) async => '${tempDir.path}/saved_image.png');

    controller = ImageResizeController(mockFileService);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ImageResizeController Unit Tests', () {
    test('Initial state is empty', () {
      final state = controller.state;
      expect(state.isSourceLoaded, isFalse);
      expect(state.file, isNull);
      expect(state.errorMessage, isNull);
      expect(state.aspectRatioLocked, isTrue);
      expect(state.mode, equals(ResizeMode.exactDimensions));
    });

    test('loadImage sets dimensions, ratio, and thumbnail correctly', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isSourceLoaded, isTrue);
      expect(state.sourceWidth, equals(200));
      expect(state.sourceHeight, equals(100));
      expect(state.targetWidth, equals(200));
      expect(state.targetHeight, equals(100));
      expect(state.aspectRatio, equals(2.0));
      expect(state.thumbnailBytes, isNotNull);
      expect(state.errorMessage, isNull);
    });

    test('loadImage rejects unsupported file extension', () async {
      final file = PlatformFile(
        name: 'doc.txt',
        size: 10,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isSourceLoaded, isFalse);
      expect(state.errorMessage, contains("isn't supported"));
    });

    test('loadImage rejects corrupted image file', () async {
      final file = PlatformFile(
        name: 'corrupted.png',
        size: corruptedBytes.length,
        bytes: corruptedBytes,
      );

      await controller.loadImage(file);
      final state = controller.state;

      expect(state.isSourceLoaded, isFalse);
      expect(state.errorMessage, contains("couldn't be read"));
    });

    test('aspect-ratio-locked width edit auto-computes height', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      controller.setWidth(400); // 200x100 -> ratio 2.0 -> 400x200
      final state = controller.state;

      expect(state.targetWidth, equals(400));
      expect(state.targetHeight, equals(200));
      expect(state.percentage, equals(200.0));
    });

    test('aspect-ratio-locked height edit auto-computes width', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      controller.setHeight(50); // 200x100 -> ratio 2.0 -> 100x50
      final state = controller.state;

      expect(state.targetWidth, equals(100));
      expect(state.targetHeight, equals(50));
      expect(state.percentage, equals(50.0));
    });

    test('unlocked independent width/height allows stretching', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      controller.toggleAspectRatioLock(); // Unlock
      expect(controller.state.aspectRatioLocked, isFalse);

      controller.setWidth(300);
      expect(controller.state.targetWidth, equals(300));
      expect(controller.state.targetHeight, equals(100)); // Height unchanged

      controller.setHeight(500);
      expect(controller.state.targetWidth, equals(300)); // Width unchanged
      expect(controller.state.targetHeight, equals(500));
    });

    test('percentage mode scales dimensions proportionally', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      controller.setMode(ResizeMode.percentage);
      controller.setPercentage(50.0);

      final state = controller.state;
      expect(state.targetWidth, equals(100));
      expect(state.targetHeight, equals(50));
      expect(state.percentage, equals(50.0));
    });

    test('percentage to exact mode switch preserves equivalent size', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      controller.setWidth(300); // 150%
      controller.setMode(ResizeMode.percentage);

      expect(controller.state.percentage, equals(150.0));

      controller.setMode(ResizeMode.exactDimensions);
      expect(controller.state.targetWidth, equals(300));
      expect(controller.state.targetHeight, equals(150));
    });

    test('preset selection respects aspect ratio lock', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      // Locked: Full HD preset (1920 x 1080) -> width=1920, height auto-computed (1920/2.0 = 960)
      controller.selectPreset(ImagePreset.fullHd);
      expect(controller.state.targetWidth, equals(1920));
      expect(controller.state.targetHeight, equals(960));
      expect(controller.state.selectedPreset, equals(ImagePreset.fullHd));

      // Unlocked: Preset exact height applies (1080)
      controller.toggleAspectRatioLock();
      expect(controller.state.targetWidth, equals(1920));
      expect(controller.state.targetHeight, equals(1080));
    });

    test('minimum dimension floor validation triggers error on resize', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      controller.setWidth(5); // Below 10px minimum floor
      expect(controller.state.isValidDimensions, isFalse);
      expect(controller.state.isBelowMinFloor, isTrue);

      await controller.resize();
      expect(controller.state.errorMessage, equals('Minimum size is 10×10px'));
    });

    test('isUpscaling derived getter detects upscale dimensions', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);

      expect(controller.state.isUpscaling, isFalse);

      controller.setWidth(400); // Original is 200x100
      expect(controller.state.isUpscaling, isTrue);
    });

    test('resize Happy Path executes via isolate worker and creates resized PNG file', () async {
      final sourceFile = File('${tempDir.path}/sample.png');
      await sourceFile.writeAsBytes(testImageBytes);

      final platformFile = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        path: sourceFile.path,
        bytes: testImageBytes,
      );

      await controller.loadImage(platformFile);
      controller.setWidth(100); // 200x100 -> 100x50

      await controller.resize();

      final state = controller.state;
      expect(state.outputPath, isNotNull);
      expect(state.outputPath, endsWith('_resized.png'));
      expect(state.outputSize, greaterThan(0));

      final outFile = File(state.outputPath!);
      expect(outFile.existsSync(), isTrue);

      final outBytes = await outFile.readAsBytes();
      final decodedOut = img.decodePng(outBytes);
      expect(decodedOut, isNotNull);
      expect(decodedOut!.width, equals(100));
      expect(decodedOut.height, equals(50));
    });

    test('reset clears state back to initial state', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testImageBytes.length,
        bytes: testImageBytes,
      );
      await controller.loadImage(file);
      expect(controller.state.isSourceLoaded, isTrue);

      controller.reset();
      expect(controller.state.isSourceLoaded, isFalse);
      expect(controller.state.file, isNull);
    });
  });
}
