import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import 'image_blur_state.dart';

/// Provider for ImageBlurController.
final imageBlurControllerProvider =
    StateNotifierProvider.autoDispose<ImageBlurController, ImageBlurState>(
  (ref) => ImageBlurController(FileService()),
);

/// Parameters passed to background isolate worker for image redaction/blur.
class ImageBlurParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final List<Rect> regions;
  final RedactionStyle style;
  final RedactionIntensity intensity;
  final int solidBlockColorValue;
  final String outputPath;

  ImageBlurParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.regions,
    required this.style,
    required this.intensity,
    required this.solidBlockColorValue,
    required this.outputPath,
  });
}

/// Result returned from background isolate blur worker.
class ImageBlurResult {
  final String outputPath;
  final int outputSize;

  ImageBlurResult({
    required this.outputPath,
    required this.outputSize,
  });
}

/// Top-level isolate worker for CPU-bound image redaction/blur pixel processing.
Future<ImageBlurResult> isolateImageBlurWorker(ImageBlurParams params) async {
  img.Image? decoded = img.decodeImage(params.inputBytes);
  if (decoded == null) {
    throw const FormatException("This image couldn't be read. File may be corrupt.");
  }

  // Bake EXIF orientation so output is correctly oriented
  decoded = img.bakeOrientation(decoded);

  // Animated sources: extract first frame
  if (decoded.numFrames > 1) {
    decoded = decoded.frames.first;
  }

  final imgW = decoded.width;
  final imgH = decoded.height;

  for (final rect in params.regions) {
    // Clamp rect to image bounds
    final clampedLeft = rect.left.clamp(0.0, imgW.toDouble()).toInt();
    final clampedTop = rect.top.clamp(0.0, imgH.toDouble()).toInt();
    final clampedRight = rect.right.clamp(0.0, imgW.toDouble()).toInt();
    final clampedBottom = rect.bottom.clamp(0.0, imgH.toDouble()).toInt();

    final rw = clampedRight - clampedLeft;
    final rh = clampedBottom - clampedTop;

    if (rw < 1 || rh < 1) continue;

    switch (params.style) {
      case RedactionStyle.pixelate:
        // ASSUMPTION: Pixelate block sizes: Small = 12px, Medium = 24px, Large = 40px
        int blockSize = 24;
        if (params.intensity == RedactionIntensity.small) {
          blockSize = 12;
        } else if (params.intensity == RedactionIntensity.large) {
          blockSize = 40;
        }

        final subImg = img.copyCrop(decoded, x: clampedLeft, y: clampedTop, width: rw, height: rh);
        final smallW = max(1, rw ~/ blockSize);
        final smallH = max(1, rh ~/ blockSize);

        final downscaled = img.copyResize(
          subImg,
          width: smallW,
          height: smallH,
          interpolation: img.Interpolation.nearest,
        );
        final pixelated = img.copyResize(
          downscaled,
          width: rw,
          height: rh,
          interpolation: img.Interpolation.nearest,
        );

        img.compositeImage(
          decoded,
          pixelated,
          dstX: clampedLeft,
          dstY: clampedTop,
        );
        break;

      case RedactionStyle.blur:
        // ASSUMPTION: Blur radius presets: Light = 10px, Medium = 25px, Strong = 50px
        int radius = 25;
        if (params.intensity == RedactionIntensity.small) {
          radius = 10;
        } else if (params.intensity == RedactionIntensity.large) {
          radius = 50;
        }

        // ASSUMPTION: Blur radius capped to <= 40% of the region's shorter side
        final shorterSide = min(rw, rh);
        final maxAllowedRadius = max(1, (shorterSide * 0.40).toInt());
        final effectiveRadius = min(radius, maxAllowedRadius);

        final subImg = img.copyCrop(decoded, x: clampedLeft, y: clampedTop, width: rw, height: rh);
        final blurred = img.gaussianBlur(subImg, radius: effectiveRadius);

        img.compositeImage(
          decoded,
          blurred,
          dstX: clampedLeft,
          dstY: clampedTop,
        );
        break;

      case RedactionStyle.solidBlock:
        final c = Color(params.solidBlockColorValue);
        final fillColor = img.ColorRgb8(
          (c.r * 255.0).round().clamp(0, 255),
          (c.g * 255.0).round().clamp(0, 255),
          (c.b * 255.0).round().clamp(0, 255),
        );

        img.fillRect(

          decoded,
          x1: clampedLeft,
          y1: clampedTop,
          x2: clampedRight - 1,
          y2: clampedBottom - 1,
          color: fillColor,
        );
        break;
    }
  }

  final ext = p.extension(params.sourceFileName).toLowerCase();
  Uint8List encodedBytes;

  switch (ext) {
    case '.jpg':
    case '.jpeg':
      encodedBytes = Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      break;
    case '.png':
      encodedBytes = Uint8List.fromList(img.encodePng(decoded));
      break;
    case '.bmp':
      encodedBytes = Uint8List.fromList(img.encodeBmp(decoded));
      break;
    case '.gif':
      encodedBytes = Uint8List.fromList(img.encodeGif(decoded));
      break;
    case '.tif':
    case '.tiff':
      encodedBytes = Uint8List.fromList(img.encodeTiff(decoded));
      break;
    default:
      encodedBytes = Uint8List.fromList(img.encodePng(decoded));
      break;
  }

  final outFile = File(params.outputPath);
  await outFile.writeAsBytes(encodedBytes);

  return ImageBlurResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
  );
}

class ImageBlurController extends StateNotifier<ImageBlurState> {
  final FileService _fileService;
  int _regionCounter = 0;

  ImageBlurController(this._fileService) : super(const ImageBlurState());

  /// Load and validate selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearOutput: true,
      regions: const [],
    );
    _regionCounter = 0;

    final ext = p.extension(platformFile.name).toLowerCase();
    final allowedExts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tiff', '.webp'];
    if (!allowedExts.contains(ext)) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file type isn't supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF, WebP.",
      );
      return;
    }

    Uint8List? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Could not read '${platformFile.name}': permission denied.",
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image couldn't be read. File may be corrupt.",
      );
      return;
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }

    if (decoded == null) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image couldn't be read. File may be corrupt.",
      );
      return;
    }

    // Bake EXIF orientation for consistent preview & dimension readings
    decoded = img.bakeOrientation(decoded);

    final formatName = ext.replaceAll('.', '').toUpperCase();

    // Create thumbnail
    img.Image thumbImg = decoded;
    if (thumbImg.numFrames > 1) {
      thumbImg = thumbImg.frames.first;
    }
    if (thumbImg.width > 600 || thumbImg.height > 600) {
      thumbImg = thumbImg.width >= thumbImg.height
          ? img.copyResize(thumbImg, width: 600, maintainAspect: true)
          : img.copyResize(thumbImg, height: 600, maintainAspect: true);
    }
    final thumbBytes = Uint8List.fromList(img.encodeJpg(thumbImg, quality: 85));

    state = state.copyWith(
      file: platformFile,
      detectedFormat: formatName,
      originalWidth: decoded.width,
      originalHeight: decoded.height,
      originalSizeBytes: bytes.length,
      thumbnailBytes: thumbBytes,
      isProcessing: false,
    );
  }

  /// Add a new redaction region in source pixel space coordinates.
  /// Validates minimum size (10x10px floor) and clamps to image bounds.
  bool addRegion(Rect regionInSourcePixelSpace) {
    if (!state.isLoaded) return false;

    final clamped = _clampAndValidateRect(regionInSourcePixelSpace);
    if (clamped == null) {
      state = state.copyWith(
        errorMessage: "Region is too small. Minimum region size is 10×10 pixels.",
      );
      return false;
    }

    _regionCounter++;
    final regionId = 'region_$_regionCounter';
    final newRegion = RedactionRegion(id: regionId, rect: clamped);

    state = state.copyWith(
      regions: [...state.regions, newRegion],
      clearError: true,
    );
    return true;
  }

  /// Update an existing redaction region rect by ID.
  bool updateRegion(String regionId, Rect newRect) {
    if (!state.isLoaded) return false;

    final index = state.regions.indexWhere((r) => r.id == regionId);
    if (index == -1) return false;

    final clamped = _clampAndValidateRect(newRect);
    if (clamped == null) {
      state = state.copyWith(
        errorMessage: "Region is too small. Minimum region size is 10×10 pixels.",
      );
      return false;
    }

    final updatedRegions = List<RedactionRegion>.from(state.regions);
    updatedRegions[index] = updatedRegions[index].copyWith(rect: clamped);

    state = state.copyWith(
      regions: updatedRegions,
      clearError: true,
    );
    return true;
  }

  /// Remove a redaction region by ID.
  void removeRegion(String regionId) {
    final updated = state.regions.where((r) => r.id != regionId).toList();
    state = state.copyWith(regions: updated, clearError: true);
  }

  /// Clear all marked regions.
  void clearRegions() {
    state = state.copyWith(regions: const [], clearError: true);
  }

  /// Change active redaction style.
  void setRedactionStyle(RedactionStyle style) {
    if (state.style == style) return;
    state = state.copyWith(style: style, clearError: true);
  }

  /// Change active intensity level.
  void setIntensity(RedactionIntensity intensity) {
    if (state.intensity == intensity) return;
    state = state.copyWith(intensity: intensity, clearError: true);
  }

  /// Change solid block fill color.
  void setSolidBlockColor(Color color) {
    if (state.solidBlockColor == color) return;
    state = state.copyWith(solidBlockColor: color, clearError: true);
  }

  /// Helper to clamp rect within image bounds and enforce 10x10px floor.
  Rect? _clampAndValidateRect(Rect rect) {
    final maxW = state.originalWidth.toDouble();
    final maxH = state.originalHeight.toDouble();

    final left = rect.left.clamp(0.0, maxW);
    final top = rect.top.clamp(0.0, maxH);
    final right = rect.right.clamp(0.0, maxW);
    final bottom = rect.bottom.clamp(0.0, maxH);

    final width = (right - left).abs();
    final height = (bottom - top).abs();

    if (width < 10.0 || height < 10.0) {
      return null;
    }

    return Rect.fromLTWH(
      min(left, right),
      min(top, bottom),
      width,
      height,
    );
  }

  /// Execute pixel redaction via background isolate worker.
  Future<void> apply() async {
    if (state.file == null || !state.isLoaded) return;

    if (!state.hasRegions) {
      state = state.copyWith(
        errorMessage: "Draw at least one region to redact",
      );
      return;
    }

    state = state.copyWith(isProcessing: true, clearError: true, clearOutput: true);

    try {
      Uint8List? inputBytes = state.file!.bytes;
      if (inputBytes == null && state.file!.path != null) {
        inputBytes = await File(state.file!.path!).readAsBytes();
      }

      if (inputBytes == null || inputBytes.isEmpty) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: "This image couldn't be read. File may be corrupt.",
        );
        return;
      }

      final defaultDir =
          await _fileService.getDefaultOutputDirectory(sourceFilePath: state.file!.path);
      final outputDir = defaultDir.path;

      final baseName = p.basenameWithoutExtension(state.file!.name);
      final ext = p.extension(state.file!.name).toLowerCase();
      final defaultOutputPath = p.join(outputDir, '${baseName}_blurred$ext');

      final params = ImageBlurParams(
        inputBytes: inputBytes,
        sourceFileName: state.file!.name,
        regions: state.regions.map((r) => r.rect).toList(),
        style: state.style,
        intensity: state.intensity,
        solidBlockColorValue: state.solidBlockColor.toARGB32(),
        outputPath: defaultOutputPath,
      );

      final result = await compute(isolateImageBlurWorker, params);

      state = state.copyWith(
        isProcessing: false,
        outputPath: result.outputPath,
        outputSizeBytes: result.outputSize,
      );
    } on OutOfMemoryError {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to redact on this device.",
      );
    } on FileSystemException catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
    } catch (e) {
      final msg = e is FormatException ? e.message : "Redaction failed. Please try again.";
      state = state.copyWith(
        isProcessing: false,
        errorMessage: msg,
      );
    }
  }

  /// User action: Save As custom destination.
  Future<void> saveAs() async {
    if (state.outputPath == null) return;
    final file = File(state.outputPath!);
    if (!file.existsSync()) return;

    final bytes = await file.readAsBytes();
    final defaultName = p.basename(state.outputPath!);
    await _fileService.saveFile(
      bytes: bytes,
      defaultFileName: defaultName,
    );
  }

  /// User action: Open containing folder.
  Future<void> openFolder() async {
    if (state.outputPath != null) {
      await _fileService.openFolder(state.outputPath!);
    }
  }

  /// User action: Share output file.
  Future<void> shareFile() async {
    if (state.outputPath != null) {
      await _fileService.shareFile(state.outputPath!);
    }
  }


  /// Clear active error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Reset controller back to initial state.
  void reset() {
    _regionCounter = 0;
    state = const ImageBlurState();
  }
}
