import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:anvil/core/services/file_service.dart';
import 'package:anvil/tools/image_crop_rotate/image_crop_rotate_controller.dart';
import 'package:anvil/tools/image_crop_rotate/image_crop_rotate_state.dart';

class MockFileService extends Mock implements FileService {}

Uint8List createTestPng({int width = 200, int height = 150}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 3) % 255, (y * 5) % 255, (x + y * 2) % 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List createCorruptedBytes() {
  return Uint8List.fromList('NOT_AN_IMAGE_FILE_HEADER_1234567890'.codeUnits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFileService mockFileService;
  late ImageCropRotateController controller;
  late Directory tempDir;

  late Uint8List testPngBytes;
  late Uint8List corruptedBytes;

  setUpAll(() {
    testPngBytes = createTestPng(width: 200, height: 150);
    corruptedBytes = createCorruptedBytes();
  });

  setUp(() async {
    mockFileService = MockFileService();
    tempDir = await Directory.systemTemp.createTemp('image_crop_rotate_test_');

    when(() => mockFileService.getDefaultOutputDirectory(
          sourceFilePath: any(named: 'sourceFilePath'),
        )).thenAnswer((_) async => tempDir);
    when(() => mockFileService.openFolder(any())).thenAnswer((_) async {});
    when(() => mockFileService.saveFile(
          bytes: any(named: 'bytes'),
          defaultFileName: any(named: 'defaultFileName'),
        )).thenAnswer((invocation) async {
      final fileName = invocation.namedArguments[#defaultFileName] as String?;
      return p.join(tempDir.path, fileName ?? 'saved_file.png');
    });

    controller = ImageCropRotateController(mockFileService);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ImageCropRotateController - Image Loading & Validation', () {
    test('loadImage rejects unsupported file extension', () async {
      final file = PlatformFile(
        name: 'document.xyz',
        size: 100,
        bytes: testPngBytes,
      );

      await controller.loadImage(file);

      final state = controller.state;
      expect(state.isLoaded, false);
      expect(state.errorMessage, contains("This file type isn't supported"));
    });

    test('loadImage rejects corrupted image bytes', () async {
      final file = PlatformFile(
        name: 'corrupt.png',
        size: corruptedBytes.length,
        bytes: corruptedBytes,
      );

      await controller.loadImage(file);

      final state = controller.state;
      expect(state.isLoaded, false);
      expect(state.errorMessage, contains("This image couldn't be read"));
    });

    test('loadImage parses valid PNG and sets dimensions and initial full crop rect', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testPngBytes.length,
        bytes: testPngBytes,
      );

      await controller.loadImage(file);

      final state = controller.state;
      expect(state.isLoaded, true);
      expect(state.originalWidth, 200);
      expect(state.originalHeight, 150);
      expect(state.currentWidth, 200);
      expect(state.currentHeight, 150);
      expect(state.cropRect, const Rect.fromLTWH(0, 0, 200, 150));
      expect(state.detectedFormat, 'PNG');
      expect(state.thumbnailBytes, isNotNull);
      expect(state.hasUnsavedChanges, false);
    });
  });

  group('ImageCropRotateController - Rotation & Crop Manipulation', () {
    test('rotate cycles 0° -> 90° -> 180° -> 270° -> 0° and resets crop rect', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      // Rotate to 90°: W/H swap (200x150 becomes 150x200)
      controller.rotate();
      expect(controller.state.rotation, 90);
      expect(controller.state.currentWidth, 150);
      expect(controller.state.currentHeight, 200);
      expect(controller.state.cropRect, const Rect.fromLTWH(0, 0, 150, 200));
      expect(controller.state.rotationResetNoticeVisible, true);
      expect(controller.state.hasUnsavedChanges, true);

      // Rotate to 180°: 200x150
      controller.rotate();
      expect(controller.state.rotation, 180);
      expect(controller.state.currentWidth, 200);
      expect(controller.state.currentHeight, 150);
      expect(controller.state.cropRect, const Rect.fromLTWH(0, 0, 200, 150));

      // Rotate to 270°: 150x200
      controller.rotate();
      expect(controller.state.rotation, 270);
      expect(controller.state.currentWidth, 150);
      expect(controller.state.currentHeight, 200);

      // Rotate back to 0°: 200x150
      controller.rotate();
      expect(controller.state.rotation, 0);
      expect(controller.state.currentWidth, 200);
      expect(controller.state.currentHeight, 150);
      expect(controller.state.cropRect, const Rect.fromLTWH(0, 0, 200, 150));
      expect(controller.state.hasUnsavedChanges, false);
    });

    test('setCropRect clamps rect within current bounds and enforces 10x10px floor', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      // Set valid crop rect
      final set1 = controller.setCropRect(const Rect.fromLTWH(10, 10, 100, 80));
      expect(set1, true);
      expect(controller.state.cropRect, const Rect.fromLTWH(10, 10, 100, 80));
      expect(controller.state.outputWidth, 100);
      expect(controller.state.outputHeight, 80);
      expect(controller.state.hasUnsavedChanges, true);

      // Reject too-small rect (<10x10px)
      final set2 = controller.setCropRect(const Rect.fromLTWH(10, 10, 8, 8));
      expect(set2, false);
      expect(controller.state.errorMessage, contains('Minimum size is 10×10 pixels'));

      // Clamp oversized rect extending past 200x150 image edge
      final set3 = controller.setCropRect(const Rect.fromLTWH(-20, -20, 300, 300));
      expect(set3, true);
      expect(controller.state.cropRect, const Rect.fromLTWH(0, 0, 200, 150));
    });

    test('setAspectRatioPreset recalculates crop rect centered fitting within bounds', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      // 200x150 image, select Square (1:1) -> max fitting square is 150x150 centered at left=25, top=0
      controller.setAspectRatioPreset(AspectRatioPreset.square);
      expect(controller.state.aspectRatioPreset, AspectRatioPreset.square);
      expect(controller.state.cropRect.width, 150.0);
      expect(controller.state.cropRect.height, 150.0);
      expect(controller.state.cropRect.left, 25.0);
      expect(controller.state.cropRect.top, 0.0);

      // Select 16:9 ratio -> max fitting 16:9 in 200x150 is W=200, H=200/(16/9) = 112.5 centered at top=18.75
      controller.setAspectRatioPreset(AspectRatioPreset.sixteenNine);
      expect(controller.state.aspectRatioPreset, AspectRatioPreset.sixteenNine);
      expect(controller.state.cropRect.width, 200.0);
      expect(controller.state.cropRect.height, closeTo(112.5, 0.1));
    });

    test('Original aspect ratio updates according to current rotation state', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      // Original 200x150 (4:3)
      final ratio0 = AspectRatioPreset.original.getRatio(
        controller.state.currentWidth.toDouble(),
        controller.state.currentHeight.toDouble(),
      );
      expect(ratio0, closeTo(200 / 150, 0.01));

      // Rotate to 90° -> current orientation is 150x200 (3:4)
      controller.rotate();
      final ratio90 = AspectRatioPreset.original.getRatio(
        controller.state.currentWidth.toDouble(),
        controller.state.currentHeight.toDouble(),
      );
      expect(ratio90, closeTo(150 / 200, 0.01));
    });
  });

  group('ImageCropRotateController - Apply & Isolate Execution', () {
    test('apply combined rotate + crop produces correct output dimensions and file', () async {
      final file = PlatformFile(
        name: 'sample.png',
        size: testPngBytes.length,
        bytes: testPngBytes,
        path: p.join(tempDir.path, 'sample.png'),
      );
      await controller.loadImage(file);

      // Rotate 90° (image becomes 150x200) then set crop to 100x120
      controller.rotate();
      controller.setCropRect(const Rect.fromLTWH(10, 20, 100, 120));

      await controller.apply();

      final state = controller.state;
      expect(state.isSuccess, true);
      expect(state.outputPath, isNotNull);

      final outputFile = File(state.outputPath!);
      expect(outputFile.existsSync(), true);

      // Decode generated output file and verify pixel dimensions match crop 100x120
      final decodedOut = img.decodeImage(outputFile.readAsBytesSync());
      expect(decodedOut, isNotNull);
      expect(decodedOut!.width, 100);
      expect(decodedOut.height, 120);
    });

    test('reset clears state back to initial values', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);
      controller.rotate();

      controller.reset();

      final state = controller.state;
      expect(state.isLoaded, false);
      expect(state.file, isNull);
      expect(state.rotation, 0);
      expect(state.cropRect, Rect.zero);
    });
  });
}
