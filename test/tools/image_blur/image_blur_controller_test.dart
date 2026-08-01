import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:anvil/core/services/file_service.dart';
import 'package:anvil/tools/image_blur/image_blur_controller.dart';
import 'package:anvil/tools/image_blur/image_blur_state.dart';

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
  late ImageBlurController controller;
  late Directory tempDir;

  late Uint8List testPngBytes;
  late Uint8List corruptedBytes;

  setUpAll(() {
    testPngBytes = createTestPng(width: 200, height: 150);
    corruptedBytes = createCorruptedBytes();
  });

  setUp(() async {
    mockFileService = MockFileService();
    tempDir = await Directory.systemTemp.createTemp('image_blur_test_');

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

    controller = ImageBlurController(mockFileService);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ImageBlurController - Image Loading & Validation', () {
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

    test('loadImage parses valid PNG and sets dimensions and thumbnail', () async {
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
      expect(state.detectedFormat, 'PNG');
      expect(state.thumbnailBytes, isNotNull);
    });
  });

  group('ImageBlurController - Region Drawing & Manipulation', () {
    test('addRegion adds valid region and clamps within image bounds', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      // Oversized rect extends past edges
      final added = controller.addRegion(const Rect.fromLTWH(-10, -10, 300, 300));
      expect(added, true);

      final state = controller.state;
      expect(state.regionCount, 1);
      expect(state.regions.first.rect, const Rect.fromLTWH(0, 0, 200, 150));
    });

    test('addRegion rejects region smaller than 10x10px floor', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      final added = controller.addRegion(const Rect.fromLTWH(20, 20, 5, 5));
      expect(added, false);

      final state = controller.state;
      expect(state.regionCount, 0);
      expect(state.errorMessage, contains('Minimum region size is 10×10 pixels'));
    });

    test('updateRegion resizes existing region and enforces minimum size floor', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      controller.addRegion(const Rect.fromLTWH(20, 20, 50, 50));
      final regionId = controller.state.regions.first.id;

      // Update to valid new size
      final updated = controller.updateRegion(regionId, const Rect.fromLTWH(20, 20, 80, 60));
      expect(updated, true);
      expect(controller.state.regions.first.rect, const Rect.fromLTWH(20, 20, 80, 60));

      // Attempt to shrink below 10x10px floor
      final invalidUpdate = controller.updateRegion(regionId, const Rect.fromLTWH(20, 20, 4, 4));
      expect(invalidUpdate, false);
      expect(controller.state.errorMessage, contains('Minimum region size is 10×10 pixels'));
    });

    test('removeRegion and clearRegions remove marked regions', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      controller.addRegion(const Rect.fromLTWH(10, 10, 30, 30));
      controller.addRegion(const Rect.fromLTWH(50, 50, 40, 40));
      expect(controller.state.regionCount, 2);

      final firstId = controller.state.regions.first.id;
      controller.removeRegion(firstId);
      expect(controller.state.regionCount, 1);

      controller.clearRegions();
      expect(controller.state.regionCount, 0);
    });

    test('Style and intensity setters update state correctly', () async {
      controller.setRedactionStyle(RedactionStyle.blur);
      expect(controller.state.style, RedactionStyle.blur);
      expect(controller.state.isBlurStyle, true);

      controller.setIntensity(RedactionIntensity.large);
      expect(controller.state.intensity, RedactionIntensity.large);

      controller.setSolidBlockColor(Colors.red);
      expect(controller.state.solidBlockColor, Colors.red);
    });
  });

  group('ImageBlurController - Apply & Pixel Level Verification', () {
    test('apply with zero regions sets error message', () async {
      final file = PlatformFile(name: 'sample.png', size: testPngBytes.length, bytes: testPngBytes);
      await controller.loadImage(file);

      await controller.apply();

      final state = controller.state;
      expect(state.outputPath, isNull);
      expect(state.errorMessage, contains('Draw at least one region to redact'));
    });

    test('apply Solid Block alters pixel data inside region to exact fill color', () async {
      final file = PlatformFile(
        name: 'test_solid.png',
        size: testPngBytes.length,
        bytes: testPngBytes,
        path: p.join(tempDir.path, 'test_solid.png'),
      );
      await controller.loadImage(file);

      controller.setRedactionStyle(RedactionStyle.solidBlock);
      controller.setSolidBlockColor(const Color(0xFFFF0000)); // Pure Red
      controller.addRegion(const Rect.fromLTWH(20, 20, 50, 50));

      await controller.apply();

      final state = controller.state;
      expect(state.outputPath, isNotNull);
      final outputFile = File(state.outputPath!);
      expect(outputFile.existsSync(), true);

      // Verify output pixels
      final outputImg = img.decodeImage(outputFile.readAsBytesSync())!;

      // Pixel inside region should be solid red (RGB 255, 0, 0)
      final insidePixel = outputImg.getPixel(30, 30);
      expect(insidePixel.r, 255);
      expect(insidePixel.g, 0);
      expect(insidePixel.b, 0);

      // Pixel outside region should remain original color
      final origImg = img.decodeImage(testPngBytes)!;
      final origPixel = origImg.getPixel(5, 5);
      final outPixel = outputImg.getPixel(5, 5);
      expect(outPixel.r, origPixel.r);
      expect(outPixel.g, origPixel.g);
      expect(outPixel.b, origPixel.b);
    });

    test('apply Pixelate style alters pixel data inside region', () async {
      final file = PlatformFile(
        name: 'test_pixelate.png',
        size: testPngBytes.length,
        bytes: testPngBytes,
        path: p.join(tempDir.path, 'test_pixelate.png'),
      );
      await controller.loadImage(file);

      controller.setRedactionStyle(RedactionStyle.pixelate);
      controller.setIntensity(RedactionIntensity.medium);
      controller.addRegion(const Rect.fromLTWH(10, 10, 60, 60));

      await controller.apply();

      final state = controller.state;
      expect(state.outputPath, isNotNull);
      final outputFile = File(state.outputPath!);
      expect(outputFile.existsSync(), true);

      final outputImg = img.decodeImage(outputFile.readAsBytesSync())!;
      final origImg = img.decodeImage(testPngBytes)!;

      // Inside region pixel data should be altered compared to original gradient
      bool changedInside = false;
      for (int y = 15; y < 45; y++) {
        for (int x = 15; x < 45; x++) {
          if (outputImg.getPixel(x, y).r != origImg.getPixel(x, y).r ||
              outputImg.getPixel(x, y).g != origImg.getPixel(x, y).g) {
            changedInside = true;
            break;
          }
        }
      }
      expect(changedInside, true);
    });

    test('apply Blur style alters pixel data inside region', () async {
      final file = PlatformFile(
        name: 'test_blur.png',
        size: testPngBytes.length,
        bytes: testPngBytes,
        path: p.join(tempDir.path, 'test_blur.png'),
      );
      await controller.loadImage(file);

      controller.setRedactionStyle(RedactionStyle.blur);
      controller.setIntensity(RedactionIntensity.medium);
      controller.addRegion(const Rect.fromLTWH(20, 20, 60, 60));

      await controller.apply();

      final state = controller.state;
      expect(state.outputPath, isNotNull);
      final outputFile = File(state.outputPath!);
      expect(outputFile.existsSync(), true);

      final outputImg = img.decodeImage(outputFile.readAsBytesSync())!;
      final origImg = img.decodeImage(testPngBytes)!;

      bool changedInside = false;
      for (int y = 25; y < 55; y++) {
        for (int x = 25; x < 55; x++) {
          if (outputImg.getPixel(x, y).r != origImg.getPixel(x, y).r ||
              outputImg.getPixel(x, y).g != origImg.getPixel(x, y).g) {
            changedInside = true;
            break;
          }
        }
      }
      expect(changedInside, true);
    });
  });
}
