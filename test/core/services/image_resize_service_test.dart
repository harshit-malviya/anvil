import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:anvil/core/services/image_resize_service.dart';

void main() {
  group('ImageResizeService Unit Tests', () {
    test('calculateNextStepDimensions computes 90% decrements', () {
      final step1 = ImageResizeService.calculateNextStepDimensions(
        currentWidth: 1000,
        currentHeight: 800,
        originalWidth: 1000,
        originalHeight: 800,
        stepFactor: 0.9,
        floorFactor: 0.5,
      );

      expect(step1, isNotNull);
      expect(step1!.width, equals(900));
      expect(step1.height, equals(720));
    });

    test('calculateNextStepDimensions stops at 50% floor', () {
      // 50% floor of 1000x800 is 500x400
      final step = ImageResizeService.calculateNextStepDimensions(
        currentWidth: 520,
        currentHeight: 416,
        originalWidth: 1000,
        originalHeight: 800,
        stepFactor: 0.9,
        floorFactor: 0.5,
      );

      expect(step, isNotNull);
      expect(step!.width, equals(500));
      expect(step.height, equals(400));

      final pastFloor = ImageResizeService.calculateNextStepDimensions(
        currentWidth: 500,
        currentHeight: 400,
        originalWidth: 1000,
        originalHeight: 800,
        stepFactor: 0.9,
        floorFactor: 0.5,
      );

      expect(pastFloor, isNull);
    });

    test('resize correctly scales image dimensions', () {
      final testImg = img.Image(width: 400, height: 200);
      final resized = ImageResizeService.resize(
        testImg,
        targetWidth: 200,
        targetHeight: 100,
      );

      expect(resized.width, equals(200));
      expect(resized.height, equals(100));
    });
  });
}
