import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

enum PdfPasswordMode {
  add,
  remove,
}

class PdfPasswordState {
  final PlatformFile? file;
  final Uint8List? fileBytes;
  final int fileSizeBytes;
  final bool isProtected;
  final PdfPasswordMode mode;

  // Add Mode fields
  final String password;
  final String confirmPassword;

  // Remove Mode fields
  final String removalPassword;

  final bool isProcessing;
  final String? progressMessage;
  final String? errorMessage;
  final String? outputPath;

  const PdfPasswordState({
    this.file,
    this.fileBytes,
    this.fileSizeBytes = 0,
    this.isProtected = false,
    this.mode = PdfPasswordMode.add,
    this.password = '',
    this.confirmPassword = '',
    this.removalPassword = '',
    this.isProcessing = false,
    this.progressMessage,
    this.errorMessage,
    this.outputPath,
  });

  bool get isLoaded => file != null && fileBytes != null && fileBytes!.isNotEmpty;

  static const int minPasswordLength = 6;

  bool get isPasswordTooShort => password.length < minPasswordLength;
  bool get passwordsMatch => password == confirmPassword;

  bool get canSubmitAdd =>
      isLoaded &&
      password.isNotEmpty &&
      !isPasswordTooShort &&
      passwordsMatch &&
      !isProcessing;

  bool get canSubmitRemove =>
      isLoaded && removalPassword.isNotEmpty && !isProcessing;

  String get formattedFileSize => formatBytes(fileSizeBytes);

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = (log(bytes) / log(1024)).floor();
    if (i >= suffixes.length) i = suffixes.length - 1;
    final num = bytes / pow(1024, i);
    return '${num.toStringAsFixed(num < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
  }

  PdfPasswordState copyWith({
    PlatformFile? file,
    Uint8List? fileBytes,
    int? fileSizeBytes,
    bool? isProtected,
    PdfPasswordMode? mode,
    String? password,
    String? confirmPassword,
    String? removalPassword,
    bool? isProcessing,
    String? progressMessage,
    bool resetProgressMessage = false,
    String? errorMessage,
    bool resetError = false,
    String? outputPath,
    bool resetOutput = false,
  }) {
    return PdfPasswordState(
      file: file ?? this.file,
      fileBytes: fileBytes ?? this.fileBytes,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      isProtected: isProtected ?? this.isProtected,
      mode: mode ?? this.mode,
      password: password ?? this.password,
      confirmPassword: confirmPassword ?? this.confirmPassword,
      removalPassword: removalPassword ?? this.removalPassword,
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage
          ? null
          : (progressMessage ?? this.progressMessage),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
    );
  }
}
