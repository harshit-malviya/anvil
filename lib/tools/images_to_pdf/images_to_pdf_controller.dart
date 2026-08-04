import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/services/image_to_pdf_page_service.dart';
import '../../core/services/pdf_isolate_worker.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'images_to_pdf_state.dart';

final imagesToPdfControllerProvider =
    StateNotifierProvider<ImagesToPdfController, ImagesToPdfState>((ref) {
  return ImagesToPdfController(
    logService: ref.read(appLogServiceProvider),
  );
});

class ImagesToPdfController extends StateNotifier<ImagesToPdfState> {
  final FileService _fileService;
  final ImageToPdfPageService _imageService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;

  ImagesToPdfController({
    FileService? fileService,
    ImageToPdfPageService? imageService,
    TempFileManager? tempFileManager,
    AppLogService? logService,
  })  : _fileService = fileService ?? FileService(),
        _imageService = imageService ?? ImageToPdfPageService(),
        _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const ImagesToPdfState());

  /// Add and validate image files to convert into PDF pages.
  Future<void> addImages(List<PlatformFile> platformFiles) async {
    if (platformFiles.isEmpty) return;

    final newImages = List<ImageFileItem>.from(state.images);
    final errors = <String>[];
    int counter = DateTime.now().microsecondsSinceEpoch;

    for (final platformFile in platformFiles) {
      try {
        final result = await _imageService.processImageFile(platformFile);
        final id = '${counter++}_${platformFile.name}';
        newImages.add(ImageFileItem(
          id: id,
          file: platformFile,
          bytes: result.bytes,
          thumbnail: result.thumbnail,
          width: result.width,
          height: result.height,
        ));
      } on FormatException catch (e) {
        final ext = p.extension(platformFile.name).toLowerCase();
        if (ext != '.jpg' && ext != '.jpeg' && ext != '.png') {
          errors.add("Unsupported format — PNG and JPEG images only.");
        } else if (e.message.contains("permission denied")) {
          if (platformFiles.length == 1) {
            errors.add("Could not read '${platformFile.name}': permission denied or file unreadable.");
          } else {
            errors.add("This image couldn't be read and wasn't added: ${platformFile.name}.");
          }
        } else {
          if (platformFiles.length == 1) {
            errors.add("This image couldn't be read. Try a different file.");
          } else {
            errors.add("This image couldn't be read and wasn't added: ${platformFile.name}.");
          }
        }
      }
    }

    state = state.copyWith(
      images: newImages,
      errorMessage: errors.isNotEmpty ? errors.join('\n') : null,
      resetError: errors.isEmpty,
      resetOutput: true,
    );
  }

  /// Reorder image files in the list.
  void reorderImages(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.images.length) return;
    if (newIndex < 0 || newIndex > state.images.length) return;

    final list = List<ImageFileItem>.from(state.images);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);

    state = state.copyWith(
      images: list,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Remove image by ID.
  void removeImage(String imageId) {
    final updated = state.images.where((img) => img.id != imageId).toList();
    state = state.copyWith(
      images: updated,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Clear all added images returning state to initial empty drop zone.
  void clearImages() {
    _tempFileManager.cleanupSession();
    state = const ImagesToPdfState();
  }

  /// Dismiss error message banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Convert loaded images to a single PDF document.
  Future<String?> createPdf({String? customOutputPath}) async {
    if (!state.canSubmit) {
      if (!state.hasImages) {
        state = state.copyWith(errorMessage: "Select image file(s) to convert.");
      }
      return null;
    }

    final startTime = DateTime.now();
    final imageCount = state.images.length;
    final msg = imageCount == 1
        ? "Creating PDF from 1 image…"
        : "Creating PDF from $imageCount images…";

    state = state.copyWith(
      isProcessing: true,
      progressMessage: msg,
      resetError: true,
      resetOutput: true,
    );

    _logService.logStarted('images_to_pdf', 'create',
        message: '$imageCount images');

    try {
      // 1. Build image specs for isolate
      final imageSpecs = <ImagePageSpec>[];
      for (final imgItem in state.images) {
        final width = imgItem.width.toDouble();
        final height = imgItem.height.toDouble();
        imageSpecs.add(ImagePageSpec(
          imageBytes: imgItem.bytes,
          pageWidth: width,
          pageHeight: height,
          imgLeft: 0,
          imgTop: 0,
          imgWidth: width,
          imgHeight: height,
        ));
      }

      // 2. Compute PDF construction in background isolate
      final Uint8List resultBytes = await compute(
        isolateImagesToPdf,
        ImagesToPdfParams(imageSpecs: imageSpecs),
      );

      // 3. Determine output file path
      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final defaultFileName = 'images_to_pdf_$timestamp.pdf';
        final firstFilePath = state.images.first.file.path;
        final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: firstFilePath);
        targetPath = p.join(outputDir.path, defaultFileName);
      }

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(resultBytes, flush: true);

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      await _tempFileManager.cleanupSession();

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputPath: targetPath,
      );

      _logService.logSuccess('images_to_pdf', 'create',
          message: 'output: ${p.basename(targetPath)}');

      return targetPath;
    } on OutOfMemoryError {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This operation is too large to process on this device.",
      );
      _logService.logError('images_to_pdf', 'create',
          message: 'out of memory');
      return null;
    } on FileSystemException catch (e) {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Couldn't save the file — ${e.message}. Try a different location.",
      );
      _logService.logError('images_to_pdf', 'create',
          message: 'file system error', errorDetail: e.toString());
      return null;
    } catch (e) {
      await _tempFileManager.cleanupSession();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Couldn't create PDF from images. One or more image files may be damaged.",
      );
      _logService.logError('images_to_pdf', 'create',
          message: 'create failed', errorDetail: e.toString());
      return null;
    }
  }

  @visibleForTesting
  ImagesToPdfState get testState => state;
}
