import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class ProcessedImageResult {
  final Uint8List bytes;
  final Uint8List thumbnail;
  final int width;
  final int height;

  const ProcessedImageResult({
    required this.bytes,
    required this.thumbnail,
    required this.width,
    required this.height,
  });
}

class ImageToPdfPageService {
  /// Maximum allowed pixel dimension before downscaling to prevent excessive PDF bloat.
  static const int maxDimension = 3000;

  /// Maximum thumbnail dimension for UI grid preview.
  static const int maxThumbnailDimension = 400;

  /// Process a single [PlatformFile]: validates format (.jpg, .jpeg, .png), reads bytes,
  /// decodes image, downscales oversized images (>3000px), and generates thumbnail.
  /// Throws [FormatException] with user-friendly error message if invalid.
  Future<ProcessedImageResult> processImageFile(PlatformFile platformFile) async {
    final ext = p.extension(platformFile.name).toLowerCase();
    if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') {
      throw const FormatException("Unsupported format — PNG and JPEG images only.");
    }

    Uint8List? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          throw FormatException(
            "Could not read '${platformFile.name}': permission denied or file unreadable.",
          );
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      throw FormatException(
        "This image couldn't be read. Try a different file: ${platformFile.name}",
      );
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) {
      throw FormatException(
        "This image couldn't be read. Try a different file: ${platformFile.name}",
      );
    }

    // Downscale oversized images to max dimension of 3000px
    if (decoded.width > maxDimension || decoded.height > maxDimension) {
      if (decoded.width >= decoded.height) {
        decoded = img.copyResize(decoded, width: maxDimension, maintainAspect: true);
      } else {
        decoded = img.copyResize(decoded, height: maxDimension, maintainAspect: true);
      }
      if (ext == '.png') {
        bytes = Uint8List.fromList(img.encodePng(decoded));
      } else {
        bytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      }
    }

    // Generate preview thumbnail for UI display
    final previewImg = (decoded.width > maxThumbnailDimension || decoded.height > maxThumbnailDimension)
        ? (decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxThumbnailDimension, maintainAspect: true)
            : img.copyResize(decoded, height: maxThumbnailDimension, maintainAspect: true))
        : decoded;
    final thumbnailBytes = Uint8List.fromList(img.encodeJpg(previewImg, quality: 80));

    return ProcessedImageResult(
      bytes: bytes,
      thumbnail: thumbnailBytes,
      width: decoded.width,
      height: decoded.height,
    );
  }
}
