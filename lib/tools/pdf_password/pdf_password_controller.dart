import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../core/services/file_service.dart';
import 'pdf_password_state.dart';

final pdfPasswordControllerProvider =
    StateNotifierProvider<PdfPasswordController, PdfPasswordState>((ref) {
  return PdfPasswordController();
});

class PdfPasswordController extends StateNotifier<PdfPasswordState> {
  final FileService _fileService;

  PdfPasswordController({FileService? fileService})
      : _fileService = fileService ?? FileService(),
        super(const PdfPasswordState());

  /// Load and inspect a PDF file to detect password protection.
  Future<void> loadDocument(
    PlatformFile platformFile, {
    Uint8List? overrideBytes,
  }) async {
    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Inspecting PDF…",
      resetError: true,
      resetOutput: true,
    );

    Uint8List? bytes = overrideBytes ?? platformFile.bytes;
    if (bytes == null && platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) {
        try {
          bytes = await f.readAsBytes();
        } catch (e) {
          state = state.copyWith(
            isProcessing: false,
            resetProgressMessage: true,
            errorMessage:
                "Could not read '${platformFile.name}': permission denied or unreadable file.",
          );
          return;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "File '${platformFile.name}' is empty or unreadable.",
      );
      return;
    }

    bool isProtected = false;
    int pageCount = 0;

    try {
      final doc = PdfDocument(inputBytes: bytes);
      pageCount = doc.pages.count;
      doc.dispose();
      isProtected = false;
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('password') ||
          errStr.contains('encrypted') ||
          errStr.contains('security')) {
        isProtected = true;
      } else {
        state = state.copyWith(
          isProcessing: false,
          resetProgressMessage: true,
          errorMessage:
              "File '${platformFile.name}' appears corrupted or unreadable.",
        );
        return;
      }
    }

    if (!isProtected && pageCount == 0) {
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "This file doesn't contain readable PDF content.",
      );
      return;
    }

    state = state.copyWith(
      file: platformFile,
      fileBytes: bytes,
      fileSizeBytes: bytes.length,
      isProtected: isProtected,
      mode: isProtected ? PdfPasswordMode.remove : PdfPasswordMode.add,
      password: '',
      confirmPassword: '',
      removalPassword: '',
      isProcessing: false,
      resetProgressMessage: true,
      resetError: true,
      resetOutput: true,
    );
  }

  /// Set the password in Add mode.
  void setPassword(String password) {
    state = state.copyWith(
      password: password,
      resetError: true,
    );
  }

  /// Set the confirmation password in Add mode.
  void setConfirmPassword(String confirmPassword) {
    state = state.copyWith(
      confirmPassword: confirmPassword,
      resetError: true,
    );
  }

  /// Set the password in Remove mode.
  void setRemovalPassword(String password) {
    state = state.copyWith(
      removalPassword: password,
      resetError: true,
    );
  }

  /// Clear any error banner.
  void clearError() {
    state = state.copyWith(resetError: true);
  }

  /// Reset the controller to initial state.
  void reset() {
    state = const PdfPasswordState();
  }

  /// Submit the action (Add Password or Remove Password).
  Future<String?> submit({String? customOutputPath}) async {
    if (!state.isLoaded) {
      state = state.copyWith(errorMessage: "No PDF document loaded.");
      return null;
    }

    if (state.mode == PdfPasswordMode.add) {
      return _addPassword(customOutputPath: customOutputPath);
    } else {
      return _removePassword(customOutputPath: customOutputPath);
    }
  }

  Future<String?> _addPassword({String? customOutputPath}) async {
    if (!state.canSubmitAdd) return null;

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Protecting PDF…",
      resetError: true,
      resetOutput: true,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final sourceDoc = PdfDocument(inputBytes: state.fileBytes!);
      final destDoc = PdfDocument();

      destDoc.security.userPassword = state.password;
      destDoc.security.ownerPassword = state.password;
      for (int i = 0; i < sourceDoc.pages.count; i++) {
        state = state.copyWith(
          progressMessage: "Encrypting page ${i + 1} of ${sourceDoc.pages.count}…",
        );
        await Future.delayed(const Duration(milliseconds: 15));

        final sourcePage = sourceDoc.pages[i];
        final section = destDoc.sections!.add();
        section.pageSettings.size = sourcePage.size;
        section.pageSettings.margins.all = 0;
        if (sourcePage.size.width > sourcePage.size.height) {
          section.pageSettings.orientation = PdfPageOrientation.landscape;
        } else {
          section.pageSettings.orientation = PdfPageOrientation.portrait;
        }

        final template = sourcePage.createTemplate();
        final newPage = section.pages.add();
        newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
      }

      sourceDoc.dispose();

      final List<int> protectedBytes = await destDoc.save();
      destDoc.dispose();

      final targetPath = await _resolveOutputPath(
        suffix: 'protected',
        customOutputPath: customOutputPath,
      );

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(protectedBytes, flush: true);

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputPath: targetPath,
      );

      return targetPath;
    } catch (e) {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Failed to protect PDF: $e",
      );
      return null;
    }
  }

  Future<String?> _removePassword({String? customOutputPath}) async {
    if (!state.canSubmitRemove) return null;

    final startTime = DateTime.now();

    state = state.copyWith(
      isProcessing: true,
      progressMessage: "Removing protection…",
      resetError: true,
      resetOutput: true,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    PdfDocument sourceDoc;
    try {
      sourceDoc = PdfDocument(
        inputBytes: state.fileBytes!,
        password: state.removalPassword,
      );
    } catch (e) {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Incorrect password — the file wasn't changed.",
      );
      return null;
    }

    try {
      final destDoc = PdfDocument();

      for (int i = 0; i < sourceDoc.pages.count; i++) {
        state = state.copyWith(
          progressMessage: "Decrypting page ${i + 1} of ${sourceDoc.pages.count}…",
        );
        await Future.delayed(const Duration(milliseconds: 15));

        final sourcePage = sourceDoc.pages[i];
        final section = destDoc.sections!.add();
        section.pageSettings.size = sourcePage.size;
        section.pageSettings.margins.all = 0;
        if (sourcePage.size.width > sourcePage.size.height) {
          section.pageSettings.orientation = PdfPageOrientation.landscape;
        } else {
          section.pageSettings.orientation = PdfPageOrientation.portrait;
        }

        final template = sourcePage.createTemplate();
        final newPage = section.pages.add();
        newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
      }

      sourceDoc.dispose();

      final List<int> unprotectedBytes = await destDoc.save();
      destDoc.dispose();

      final targetPath = await _resolveOutputPath(
        suffix: 'unprotected',
        customOutputPath: customOutputPath,
      );

      final outputFile = File(targetPath);
      await outputFile.writeAsBytes(unprotectedBytes, flush: true);

      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }

      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        outputPath: targetPath,
      );

      return targetPath;
    } catch (e) {
      sourceDoc.dispose();
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsedMs));
      }
      state = state.copyWith(
        isProcessing: false,
        resetProgressMessage: true,
        errorMessage: "Failed to remove protection: $e",
      );
      return null;
    }
  }

  Future<String> _resolveOutputPath({
    required String suffix,
    String? customOutputPath,
  }) async {
    if (customOutputPath != null && customOutputPath.isNotEmpty) {
      return customOutputPath;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final defaultFileName = 'document_${suffix}_$timestamp.pdf';

    final sourceFilePath = state.file?.path;
    final outputDir = await _fileService.getDefaultOutputDirectory(sourceFilePath: sourceFilePath);
    return p.join(outputDir.path, defaultFileName);
  }

  @visibleForTesting
  PdfPasswordState get testState => state;
}
