import 'package:image/image.dart' as img;

/// Shared service for image resizing and dimension calculations.
class ImageResizeService {
  /// Bakes EXIF orientation and resizes image using high-quality cubic interpolation.
  /// If width or height is omitted, aspect ratio is preserved if maintainAspect is true.
  static img.Image resize(
    img.Image input, {
    int? targetWidth,
    int? targetHeight,
    img.Interpolation interpolation = img.Interpolation.cubic,
    bool maintainAspect = true,
  }) {
    var source = input;
    source = img.bakeOrientation(source);

    if (source.numFrames > 1) {
      source = source.frames.first;
    }

    if (targetWidth == null && targetHeight == null) {
      return source;
    }

    return img.copyResize(
      source,
      width: targetWidth,
      height: targetHeight,
      interpolation: interpolation,
      maintainAspect: maintainAspect,
    );
  }

  /// Calculates next dimensions stepped down by [stepFactor] (e.g. 0.9 for 90%),
  /// stopping at or before the [floorFactor] (e.g. 0.5 for 50%) relative to original dimensions.
  /// Returns null if the current dimensions are already at or below the floor limit.
  static ({int width, int height})? calculateNextStepDimensions({
    required int currentWidth,
    required int currentHeight,
    required int originalWidth,
    required int originalHeight,
    double stepFactor = 0.9,
    double floorFactor = 0.5,
  }) {
    final minW = (originalWidth * floorFactor).round().clamp(1, originalWidth);
    final minH = (originalHeight * floorFactor).round().clamp(1, originalHeight);

    if (currentWidth <= minW || currentHeight <= minH) {
      return null;
    }

    int nextW = (currentWidth * stepFactor).round().clamp(1, originalWidth);
    int nextH = (currentHeight * stepFactor).round().clamp(1, originalHeight);

    if (nextW < minW) nextW = minW;
    if (nextH < minH) nextH = minH;

    // Check if stepped dimensions actually reduced width/height
    if (nextW >= currentWidth && nextH >= currentHeight) {
      return null;
    }

    return (width: nextW, height: nextH);
  }
}
