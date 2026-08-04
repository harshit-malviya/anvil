import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/image_resize_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'image_compress_state.dart';

/// Provider for ImageCompressController.
final imageCompressControllerProvider =
    StateNotifierProvider.autoDispose<ImageCompressController, ImageCompressState>(
  (ref) => ImageCompressController(
    FileService(),
    null,
    ref.read(appLogServiceProvider),
  ),
);

/// Parameters passed to background isolate worker for image compression.
class ImageCompressParams {
  final Uint8List inputBytes;
  final String sourceFileName;
  final CompressionMode mode;
  final CompressionLevel level;
  final int minSizeBytes;
  final int maxSizeBytes;
  final String outputPath;
  final bool allowDimensionFallback;

  ImageCompressParams({
    required this.inputBytes,
    required this.sourceFileName,
    required this.mode,
    required this.level,
    required this.minSizeBytes,
    required this.maxSizeBytes,
    required this.outputPath,
    this.allowDimensionFallback = false,
  });
}

/// Result returned from background isolate compression worker.
class ImageCompressResult {
  final String outputPath;
  final int outputSize;
  final int outputWidth;
  final int outputHeight;
  final bool landedInRange;
  final bool bothFloorsHit;

  ImageCompressResult({
    required this.outputPath,
    required this.outputSize,
    required this.outputWidth,
    required this.outputHeight,
    this.landedInRange = false,
    this.bothFloorsHit = false,
  });
}

/// Top-level isolate worker for CPU-bound image compression.
Future<ImageCompressResult> isolateImageCompressWorker(ImageCompressParams params) async {
  img.Image? decoded = img.decodeImage(params.inputBytes);
  if (decoded == null) {
    throw const FormatException("This image couldn't be read. File may be corrupt.");
  }

  decoded = img.bakeOrientation(decoded);

  if (decoded.numFrames > 1) {
    decoded = decoded.frames.first;
  }

  final origW = decoded.width;
  final origH = decoded.height;

  final ext = p.extension(params.sourceFileName).toLowerCase();

  Uint8List encodedBytes;
  bool landedInRange = false;
  bool bothFloorsHit = false;
  int outputW = origW;
  int outputH = origH;

  if (params.mode == CompressionMode.qualityLevel) {
    encodedBytes = _encodeByQualityLevel(decoded, ext, params.level);
  } else {
    var currentImg = decoded;
    var searchResult = _encodeByTargetRange(
      currentImg,
      ext,
      params.minSizeBytes,
      params.maxSizeBytes,
    );
    encodedBytes = searchResult.bytes;
    landedInRange = searchResult.landedInRange;
    outputW = currentImg.width;
    outputH = currentImg.height;

    if (!landedInRange && params.allowDimensionFallback) {
      Uint8List bestBytes = searchResult.bytes;
      int bestW = currentImg.width;
      int bestH = currentImg.height;
      int bestDistance = searchResult.distance;

      while (true) {
        final nextDim = ImageResizeService.calculateNextStepDimensions(
          currentWidth: currentImg.width,
          currentHeight: currentImg.height,
          originalWidth: origW,
          originalHeight: origH,
          stepFactor: 0.9,
          floorFactor: 0.5,
        );

        if (nextDim == null) {
          bothFloorsHit = true;
          break;
        }

        final stepImg = ImageResizeService.resize(
          decoded,
          targetWidth: nextDim.width,
          targetHeight: nextDim.height,
          interpolation: img.Interpolation.cubic,
          maintainAspect: true,
        );

        final stepResult = _encodeByTargetRange(
          stepImg,
          ext,
          params.minSizeBytes,
          params.maxSizeBytes,
        );

        if (stepResult.landedInRange) {
          encodedBytes = stepResult.bytes;
          landedInRange = true;
          outputW = stepImg.width;
          outputH = stepImg.height;
          bothFloorsHit = false;
          break;
        }

        if (stepResult.distance < bestDistance) {
          bestDistance = stepResult.distance;
          bestBytes = stepResult.bytes;
          bestW = stepImg.width;
          bestH = stepImg.height;
        }

        currentImg = stepImg;
      }

      if (!landedInRange) {
        encodedBytes = bestBytes;
        outputW = bestW;
        outputH = bestH;
      }
    }
  }

  final outFile = File(params.outputPath);
  await outFile.writeAsBytes(encodedBytes);

  return ImageCompressResult(
    outputPath: params.outputPath,
    outputSize: encodedBytes.length,
    outputWidth: outputW,
    outputHeight: outputH,
    landedInRange: landedInRange,
    bothFloorsHit: bothFloorsHit,
  );
}

Uint8List _encodeByQualityLevel(img.Image decoded, String ext, CompressionLevel level) {
  switch (ext) {
    case '.jpg':
    case '.jpeg':
      int quality;
      switch (level) {
        case CompressionLevel.low:
          quality = 85;
          break;
        case CompressionLevel.medium:
          quality = 65;
          break;
        case CompressionLevel.high:
          quality = 40;
          break;
      }
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    case '.png':
      int zlibLevel;
      switch (level) {
        case CompressionLevel.low:
          zlibLevel = 3;
          break;
        case CompressionLevel.medium:
          zlibLevel = 6;
          break;
        case CompressionLevel.high:
          zlibLevel = 9;
          break;
      }
      return Uint8List.fromList(img.encodePng(decoded, level: zlibLevel));
    case '.bmp':
      return Uint8List.fromList(img.encodeBmp(decoded));
    case '.gif':
      return Uint8List.fromList(img.encodeGif(decoded));
    case '.tif':
    case '.tiff':
      return Uint8List.fromList(img.encodeTiff(decoded));
    default:
      return Uint8List.fromList(img.encodePng(decoded));
  }
}

class _RangeSearchResult {
  final Uint8List bytes;
  final bool landedInRange;
  final int distance;

  _RangeSearchResult(this.bytes, this.landedInRange, [this.distance = 0]);
}

const int jpegQualityFloor = 30;
const int pngPaletteFloor = 64;

_RangeSearchResult _encodeByTargetRange(
  img.Image decoded,
  String ext,
  int minSizeBytes,
  int maxSizeBytes,
) {
  if (ext == '.jpg' || ext == '.jpeg') {
    int low = jpegQualityFloor;
    int high = 100;
    Uint8List? bestBytes;
    int bestDistance = 999999999;
    bool foundInRange = false;

    for (int iter = 0; iter < 8; iter++) {
      if (low > high) break;
      final mid = (low + high) ~/ 2;
      final bytes = Uint8List.fromList(img.encodeJpg(decoded, quality: mid));
      final size = bytes.length;

      if (size >= minSizeBytes && size <= maxSizeBytes) {
        bestBytes = bytes;
        foundInRange = true;
        bestDistance = 0;
        break;
      }

      int dist;
      if (size < minSizeBytes) {
        dist = minSizeBytes - size;
        low = mid + 1;
      } else {
        dist = size - maxSizeBytes;
        high = mid - 1;
      }

      if (bestBytes == null || dist < bestDistance) {
        bestDistance = dist;
        bestBytes = bytes;
      }
    }

    bestBytes ??= Uint8List.fromList(img.encodeJpg(decoded, quality: 50));
    return _RangeSearchResult(bestBytes, foundInRange, bestDistance);
  } else if (ext == '.png') {
    final colorCounts = [256, 128, 64];
    Uint8List? bestBytes;
    int bestDistance = 999999999;
    bool foundInRange = false;

    int attempts = 0;
    for (final numColors in colorCounts) {
      if (attempts >= 8) break;
      attempts++;

      final quantized = img.quantize(
        decoded,
        numberOfColors: numColors,
        dither: img.DitherKernel.floydSteinberg,
      );
      final bytes = Uint8List.fromList(img.encodePng(quantized, level: 9));
      final size = bytes.length;

      if (size >= minSizeBytes && size <= maxSizeBytes) {
        bestBytes = bytes;
        foundInRange = true;
        bestDistance = 0;
        break;
      }

      int dist;
      if (size < minSizeBytes) {
        dist = minSizeBytes - size;
      } else {
        dist = size - maxSizeBytes;
      }

      if (bestBytes == null || dist < bestDistance) {
        bestDistance = dist;
        bestBytes = bytes;
      }
    }

    bestBytes ??= Uint8List.fromList(img.encodePng(decoded, level: 9));
    return _RangeSearchResult(bestBytes, foundInRange, bestDistance);
  } else {
    final bytes = _encodeByQualityLevel(decoded, ext, CompressionLevel.medium);
    final size = bytes.length;
    final inRange = size >= minSizeBytes && size <= maxSizeBytes;
    int dist = 0;
    if (!inRange) {
      dist = size < minSizeBytes ? minSizeBytes - size : size - maxSizeBytes;
    }
    return _RangeSearchResult(bytes, inRange, dist);
  }
}

class ImageCompressController extends StateNotifier<ImageCompressState> {
  final FileService _fileService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;
  int? _pickerLoadTimeMs;

  ImageCompressController(
    this._fileService, [
    TempFileManager? tempFileManager,
    AppLogService? logService,
  ])  : _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const ImageCompressState());

  /// Load and validate selected image file.
  Future<void> loadImage(PlatformFile platformFile) async {
    final stopwatch = Stopwatch()..start();
    state = state.copyWith(isProcessing: true, clearError: true, clearOutput: true, clearResultType: true);

    final ext = p.extension(platformFile.name).toLowerCase();
    if (ext == '.webp') {
      stopwatch.stop();
      _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "WebP format compression is not supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF.",
      );
      return;
    }

    final allowedExts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.tiff'];
    if (!allowedExts.contains(ext)) {
      stopwatch.stop();
      _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This file type isn't supported. Supported formats: PNG, JPEG, BMP, GIF, TIFF.",
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
          stopwatch.stop();
          _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Could not read '${platformFile.name}': permission denied.",
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      stopwatch.stop();
      _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;
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

    stopwatch.stop();
    _pickerLoadTimeMs = stopwatch.elapsedMilliseconds;

    if (decoded == null) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image couldn't be read. File may be corrupt.",
      );
      return;
    }

    decoded = img.bakeOrientation(decoded);

    final formatName = ext.replaceAll('.', '').toUpperCase();

    img.Image thumbImg = decoded;
    if (thumbImg.numFrames > 1) {
      thumbImg = thumbImg.frames.first;
    }
    if (thumbImg.width > 400 || thumbImg.height > 400) {
      thumbImg = thumbImg.width >= thumbImg.height
          ? img.copyResize(thumbImg, width: 400, maintainAspect: true)
          : img.copyResize(thumbImg, height: 400, maintainAspect: true);
    }
    final thumbBytes = Uint8List.fromList(img.encodeJpg(thumbImg, quality: 80));

    state = state.copyWith(
      file: platformFile,
      detectedFormat: formatName,
      originalWidth: decoded.width,
      originalHeight: decoded.height,
      originalSizeBytes: bytes.length,
      compressedWidth: decoded.width,
      compressedHeight: decoded.height,
      thumbnailBytes: thumbBytes,
      isProcessing: false,
      isDimensionFallbackEnabled: false,
      bothFloorsHit: false,
      qualityOnlyCompressedSizeBytes: 0,
      qualityOnlyOutputPath: null,
      qualityOnlyResultType: null,
      qualityOnlyWidth: 0,
      qualityOnlyHeight: 0,
    );
  }

  /// Change active compression mode.
  void setMode(CompressionMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode, clearError: true);
  }

  /// Change active compression level (Quality Level mode).
  void setCompressionLevel(CompressionLevel level) {
    if (state.level == level) return;
    state = state.copyWith(level: level, clearError: true);
  }

  /// Set minimum target size (Target Size Range mode). Enforces 5 KB floor.
  void setMinSize(double value, SizeUnit unit) {
    double clampedValue = value;
    if (unit == SizeUnit.kb && value < 5.0) {
      clampedValue = 5.0;
    } else if (unit == SizeUnit.mb && value < (5.0 / 1024.0)) {
      clampedValue = 5.0 / 1024.0;
    }

    state = state.copyWith(
      minSizeValue: clampedValue,
      minSizeUnit: unit,
      clearError: true,
    );
  }

  /// Set maximum target size (Target Size Range mode).
  void setMaxSize(double value, SizeUnit unit) {
    state = state.copyWith(
      maxSizeValue: value,
      maxSizeUnit: unit,
      clearError: true,
    );
  }

  /// Toggle dimension fallback checkbox state.
  void setDimensionFallbackEnabled(bool enabled) {
    if (state.isDimensionFallbackEnabled == enabled) return;

    if (!enabled && state.qualityOnlyResultType != null && state.isDimensionReduced) {
      state = state.copyWith(
        isDimensionFallbackEnabled: false,
        compressedSizeBytes: state.qualityOnlyCompressedSizeBytes,
        compressedWidth: state.qualityOnlyWidth,
        compressedHeight: state.qualityOnlyHeight,
        outputPath: state.qualityOnlyOutputPath,
        resultType: state.qualityOnlyResultType,
        bothFloorsHit: false,
        clearError: true,
      );
    } else {
      state = state.copyWith(
        isDimensionFallbackEnabled: enabled,
        clearError: true,
      );
    }
  }

  /// Explicit user action: Retry search with dimension reduction allowed.
  Future<void> retryWithDimensionReduction() async {
    state = state.copyWith(isDimensionFallbackEnabled: true);
    await compress();
  }

  /// Perform image compression via background isolate worker.
  Future<void> compress() async {
    if (state.file == null || !state.isLoaded) return;

    state = state.copyWith(isProcessing: true, clearError: true, clearOutput: true, clearResultType: true);

    final Map<String, dynamic> compParams = state.mode == CompressionMode.qualityLevel
        ? {'mode': 'qualityLevel', 'level': state.level.name}
        : {
            'mode': 'targetSizeRange',
            'minKb': (state.minSizeBytes / 1024).round(),
            'maxKb': (state.maxSizeBytes / 1024).round(),
            'dimensionFallback': state.isDimensionFallbackEnabled,
          };

    final logId = _logService.logStarted(
      'image_compress',
      'Image Compress',
      'compress',
      inputFileCount: 1,
      inputFilesCombinedSizeBytes: state.originalSizeBytes,
      filePickerLoadTimeMs: _pickerLoadTimeMs,
      parameters: compParams,
    );

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
        _logService.logFailed(
          logId,
          stage: LogFailureStage.validation,
          errorMessage: "Image file empty or unreadable",
        );
        return;
      }

      if (state.mode == CompressionMode.targetSizeRange) {
        if (state.minSizeBytes < ImageCompressState.minFloorBytes) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Minimum can't be set below 5 KB",
          );
          _logService.logFailed(
            logId,
            stage: LogFailureStage.validation,
            errorMessage: "Minimum size below 5 KB floor",
          );
          return;
        }

        if (!state.isRangeValid) {
          state = state.copyWith(
            isProcessing: false,
            errorMessage: "Maximum must be greater than minimum",
          );
          _logService.logFailed(
            logId,
            stage: LogFailureStage.validation,
            errorMessage: "Maximum size less than minimum size",
          );
          return;
        }

        if (state.originalSizeBytes < state.minSizeBytes) {
          state = state.copyWith(
            isProcessing: false,
            resultType: CompressionResultType.smallerThanMin,
          );
          _logService.logFailed(
            logId,
            stage: LogFailureStage.validation,
            errorMessage: "Original size smaller than target minimum",
          );
          return;
        }

        if (state.originalSizeBytes >= state.minSizeBytes &&
            state.originalSizeBytes <= state.maxSizeBytes) {
          state = state.copyWith(
            isProcessing: false,
            compressedSizeBytes: state.originalSizeBytes,
            compressedWidth: state.originalWidth,
            compressedHeight: state.originalHeight,
            resultType: CompressionResultType.alreadyInRange,
          );
          _logService.logCompleted(
            logId,
            outputFileCount: 1,
            outputFilesCombinedSizeBytes: state.originalSizeBytes,
            message: "Original file already in target range",
          );
          return;
        }
      }

      final defaultDir =
          await _fileService.getDefaultOutputDirectory(sourceFilePath: state.file!.path);
      final outputDir = defaultDir.path;

      final baseName = p.basenameWithoutExtension(state.file!.name);
      final ext = p.extension(state.file!.name).toLowerCase();
      final defaultOutputPath = p.join(outputDir, '${baseName}_compressed$ext');

      final params = ImageCompressParams(
        inputBytes: inputBytes,
        sourceFileName: state.file!.name,
        mode: state.mode,
        level: state.level,
        minSizeBytes: state.minSizeBytes,
        maxSizeBytes: state.maxSizeBytes,
        outputPath: defaultOutputPath,
        allowDimensionFallback: state.isDimensionFallbackEnabled,
      );

      final result = await compute(isolateImageCompressWorker, params);

      CompressionResultType resultType;
      if (state.mode == CompressionMode.targetSizeRange) {
        if (result.landedInRange) {
          resultType = CompressionResultType.inRangeSuccess;
        } else {
          resultType = CompressionResultType.closestEffort;
        }
      } else {
        if (result.outputSize >= state.originalSizeBytes) {
          resultType = CompressionResultType.outputLarger;
        } else {
          final diff = state.originalSizeBytes - result.outputSize;
          final pct = (diff / state.originalSizeBytes * 100);
          if (pct < 5.0) {
            resultType = CompressionResultType.minimalReduction;
          } else {
            resultType = CompressionResultType.normalSuccess;
          }
        }
      }

      int qOnlySize = state.qualityOnlyCompressedSizeBytes;
      String? qOnlyPath = state.qualityOnlyOutputPath;
      CompressionResultType? qOnlyRes = state.qualityOnlyResultType;
      int qOnlyW = state.qualityOnlyWidth;
      int qOnlyH = state.qualityOnlyHeight;

      if (!state.isDimensionFallbackEnabled && resultType == CompressionResultType.closestEffort) {
        qOnlySize = result.outputSize;
        qOnlyPath = result.outputPath;
        qOnlyRes = CompressionResultType.closestEffort;
        qOnlyW = result.outputWidth;
        qOnlyH = result.outputHeight;
      }

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        compressedSizeBytes: result.outputSize,
        compressedWidth: result.outputWidth,
        compressedHeight: result.outputHeight,
        resultType: resultType,
        bothFloorsHit: result.bothFloorsHit,
        outputPath: result.outputPath,
        qualityOnlyCompressedSizeBytes: qOnlySize,
        qualityOnlyOutputPath: qOnlyPath,
        qualityOnlyResultType: qOnlyRes,
        qualityOnlyWidth: qOnlyW,
        qualityOnlyHeight: qOnlyH,
      );

      _logService.logCompleted(
        logId,
        outputFileCount: 1,
        outputFilesCombinedSizeBytes: result.outputSize,
        message: 'result: ${resultType.name}, output: ${p.basename(result.outputPath)}',
      );
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "This image is too large to compress on this device.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.isolateExecution,
        errorMessage: "Out of memory during image compression",
      );
      return;
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      state = state.copyWith(
        isProcessing: false,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.fileWrite,
        errorMessage: "File system error: ${e.message}",
        errorDetail: e.toString(),
      );
      return;
    } catch (e) {
      await _tempFileManager.cleanupSession();
      final msg = e is FormatException ? e.message : "Compression failed. Please try again.";
      state = state.copyWith(
        isProcessing: false,
        errorMessage: msg,
      );
      _logService.logFailed(
        logId,
        stage: LogFailureStage.processing,
        errorMessage: msg,
        errorDetail: e.toString(),
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

  /// Clear active error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Reset controller back to initial state.
  void reset() {
    _tempFileManager.cleanupSession();
    state = const ImageCompressState();
  }
}
