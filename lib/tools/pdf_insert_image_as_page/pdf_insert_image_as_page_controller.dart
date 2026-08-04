import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import '../../core/services/image_to_pdf_page_service.dart';
import '../../core/services/pdf_isolate_worker.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import '../../core/services/pdf_validation_service.dart';
import '../../core/services/temp_file_manager.dart';
import '../../core/services/app_log_service.dart';
import 'pdf_insert_image_as_page_state.dart';

final pdfInsertImageAsPageControllerProvider =
    StateNotifierProvider<PdfInsertImageAsPageController, PdfInsertImageAsPageState>((ref) {
  return PdfInsertImageAsPageController(
    logService: ref.read(appLogServiceProvider),
  );
});

class PdfInsertImageAsPageController extends StateNotifier<PdfInsertImageAsPageState> {
  final FileService _fileService;
  final PdfThumbnailService _thumbnailService;
  final ImageToPdfPageService _imageService;
  final PdfValidationService _validationService;
  final TempFileManager _tempFileManager;
  final AppLogService _logService;

  PdfInsertImageAsPageController({
    FileService? fileService,
    PdfThumbnailService? thumbnailService,
    ImageToPdfPageService? imageService,
    PdfValidationService? validationService,
    TempFileManager? tempFileManager,
    AppLogService? logService,
  })  : _fileService = fileService ?? FileService(),
        _thumbnailService = thumbnailService ?? PdfThumbnailService(),
        _imageService = imageService ?? ImageToPdfPageService(),
        _validationService = validationService ?? const PdfValidationService(),
        _tempFileManager = tempFileManager ?? TempFileManager(),
        _logService = logService ?? AppLogService(),
        super(const PdfInsertImageAsPageState());

  /// Load and validate target PDF document into which image pages will be inserted.
  Future<void> loadTargetDocument(PlatformFile platformFile) async {
    Uint8List? bytes = platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (_) {
          state = state.copyWith(
            errorMessage: "Could not read '${platformFile.name}': permission denied or file unreadable.",
            resetError: false,
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        errorMessage: "File '${platformFile.name}' is empty or unreadable.",
        resetError: false,
      );
      return;
    }

    final valInfo = _validationService.validate(bytes);
    if (valInfo.isPasswordProtected) {
      state = state.copyWith(
        errorMessage: "This file is password-protected and can't be modified. Remove the password first.",
        resetError: false,
      );
      return;
    } else if (valInfo.isCorrupted) {
      state = state.copyWith(
        errorMessage: "File '${platformFile.name}' appears corrupted or unreadable.",
        resetError: false,
      );
      return;
    }

    final pageCount = valInfo.pageCount;
    if (pageCount == 0) {
      state = state.copyWith(
        errorMessage: "File '${platformFile.name}' contains no pages.",
        fitMode: PageFitMode.fitToImage,
        resetError: false,
      );
      return;
    }

    final thumbnails = await _thumbnailService.generateThumbnails(bytes);

    // Default insertion point is 'at the end' (after the last target page)
    final defaultInsertionPoint = pageCount - 1;

    state = state.copyWith(
      targetFile: platformFile,
      targetBytes: bytes,
      targetThumbnails: thumbnails,
      targetPageCount: pageCount,
      insertionPoint: defaultInsertionPoint,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Load single image (convenience wrapper around [addImages]).
  Future<void> loadImage(PlatformFile platformFile) async {
    await addImages([platformFile]);
  }

  /// Add and validate image files to insert as pages.
  Future<void> addImages(List<PlatformFile> platformFiles) async {
    if (platformFiles.isEmpty) return;

    final newImages = List<ImageItemState>.from(state.images);
    final errors = <String>[];
    int counter = DateTime.now().microsecondsSinceEpoch;

    for (final platformFile in platformFiles) {
      try {
        final result = await _imageService.processImageFile(platformFile);
        final id = '${counter++}_${platformFile.name}';
        newImages.add(ImageItemState(
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
          if (platformFiles.length == 1) {
            errors.add("Only JPEG and PNG images are supported.");
          } else {
            errors.add("Only JPEG and PNG images are supported: ${platformFile.name} wasn't added.");
          }
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

  /// Remove image from batch by ID.
  void removeImage(String imageId) {
    final updated = state.images.where((img) => img.id != imageId).toList();
    state = state.copyWith(
      images: updated,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Reorder images in the batch list.
  void reorderImages(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= state.images.length) return;
    if (newIndex < 0 || newIndex > state.images.length) return;

    final list = List<ImageItemState>.from(state.images);
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

  /// Change page fit mode (Match neighboring page vs Fit to image).
  void setPageFitMode(PageFitMode mode) {
    if (mode == PageFitMode.matchNeighboringPage && state.targetPageCount == 0) {
      state = state.copyWith(fitMode: PageFitMode.fitToImage);
      return;
    }
    state = state.copyWith(fitMode: mode);
  }

  /// Set target insertion point index (`-1` = at start, `0` to `targetPageCount - 1`).
  void setInsertionPoint(int afterTargetPageIndex) {
    if (afterTargetPageIndex < -1 || afterTargetPageIndex >= state.targetPageCount) return;
    state = state.copyWith(insertionPoint: afterTargetPageIndex);
  }

  /// Clear target PDF document.
  void clearTarget() {
    _tempFileManager.cleanupSession();
    state = const PdfInsertImageAsPageState();
  }

  /// Clear loaded image files.
  void clearImages() {
    state = state.copyWith(
      resetImages: true,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Alias for [clearImages].
  void clearImage() => clearImages();

  /// Dismiss error message banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Alias for [insertImagePages].
  Future<String?> insertImagePage({String? customOutputPath}) =>
      insertImagePages(customOutputPath: customOutputPath);

  /// Convert loaded images to single-page PDFs and splice into target PDF.
  Future<String?> insertImagePages({String? customOutputPath}) async {
    if (!state.canSubmit) {
      if (!state.hasTarget) {
        state = state.copyWith(errorMessage: "Select a target PDF document first.");
      } else if (!state.hasImages) {
        state = state.copyWith(errorMessage: "Select image file(s) to insert.");
      }
      return null;
    }

    final startTime = DateTime.now();

    final msg = state.images.length == 1
        ? "Inserting image as page into document…"
        : "Inserting ${state.images.length} images as pages into document…";

    state = state.copyWith(
      isProcessing: true,
      progressMessage: msg,
      resetError: true,
      resetOutput: true,
    );

    _logService.logStarted('pdf_insert_image_page', 'insert',
        message: '${state.images.length} images, fit: ${state.fitMode.name}');

    try {
      // 1. Batch-level neighbor page resolution (resolved once for the whole batch)
      Size? neighborSize;
      if (state.fitMode == PageFitMode.matchNeighboringPage && state.targetPageCount > 0) {
        int neighborIdx;
        if (state.insertionPoint == -1) {
          neighborIdx = 0;
        } else if (state.insertionPoint == state.targetPageCount - 1) {
          neighborIdx = state.targetPageCount - 1;
        } else {
          neighborIdx = state.insertionPoint; // Page immediately before insertion point
        }

        final targetDoc = PdfDocument(inputBytes: state.targetBytes!);
        if (neighborIdx >= 0 && neighborIdx < targetDoc.pages.count) {
          neighborSize = targetDoc.pages[neighborIdx].size;
        }
        targetDoc.dispose();
      }

      // 2. Build specs for each image in the batch
      final imageSpecs = <ImagePageSpec>[];
      for (final imgItem in state.images) {
        Size pageSize;
        Rect imgRect;

        if (neighborSize != null) {
          pageSize = neighborSize;
          final double scale = min(pageSize.width / imgItem.width, pageSize.height / imgItem.height);
          final double sw = imgItem.width * scale;
          final double sh = imgItem.height * scale;
          final double dx = (pageSize.width - sw) / 2.0;
          final double dy = (pageSize.height - sh) / 2.0;
          imgRect = Rect.fromLTWH(dx, dy, sw, sh);
        } else {
          pageSize = Size(imgItem.width.toDouble(), imgItem.height.toDouble());
          imgRect = Rect.fromLTWH(0, 0, pageSize.width, pageSize.height);
        }

        imageSpecs.add(ImagePageSpec(
          imageBytes: imgItem.bytes,
          pageWidth: pageSize.width,
          pageHeight: pageSize.height,
          imgLeft: imgRect.left,
          imgTop: imgRect.top,
          imgWidth: imgRect.width,
          imgHeight: imgRect.height,
        ));
      }

      // 3. Run heavy PDF work on background isolate
      final Uint8List resultBytes = await compute(
        isolateInsertImagePages,
        InsertImagePagesParams(
          targetBytes: state.targetBytes!,
          imageSpecs: imageSpecs,
          insertionPoint: state.insertionPoint,
        ),
      );

      String targetPath;
      if (customOutputPath != null && customOutputPath.isNotEmpty) {
        targetPath = customOutputPath;
      } else {
        final targetFileName = state.targetFile?.name ?? 'document.pdf';
        final baseName = p.basenameWithoutExtension(targetFileName);
        final defaultFileName = '${baseName}_inserted.pdf';

        final firstFilePath = state.targetFile?.path;
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

      _logService.logSuccess('pdf_insert_image_page', 'insert',
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
        errorMessage: "This insertion is too large to process on this device.",
      );
      _logService.logError('pdf_insert_image_page', 'insert',
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
      _logService.logError('pdf_insert_image_page', 'insert',
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
        errorMessage: "Couldn't insert image as a page — the target PDF or image may be damaged. Try different files.",
      );
      _logService.logError('pdf_insert_image_page', 'insert',
          message: 'insert failed', errorDetail: e.toString());
      return null;
    }
  }

  @visibleForTesting
  PdfInsertImageAsPageState get testState => state;
}
