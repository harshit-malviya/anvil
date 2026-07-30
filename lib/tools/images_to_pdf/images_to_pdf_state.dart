import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class ImageFileItem {
  final String id;
  final PlatformFile file;
  final Uint8List bytes;
  final Uint8List thumbnail;
  final int width;
  final int height;

  const ImageFileItem({
    required this.id,
    required this.file,
    required this.bytes,
    required this.thumbnail,
    required this.width,
    required this.height,
  });

  String get fileName => file.name;
  int get fileSizeBytes => file.size;
}

class ImagesToPdfState {
  final List<ImageFileItem> images;
  final bool isProcessing;
  final String? progressMessage;
  final String? outputPath;
  final String? errorMessage;

  const ImagesToPdfState({
    this.images = const [],
    this.isProcessing = false,
    this.progressMessage,
    this.outputPath,
    this.errorMessage,
  });

  bool get hasImages => images.isNotEmpty;
  int get totalImages => images.length;
  bool get canSubmit => hasImages && !isProcessing;

  ImagesToPdfState copyWith({
    List<ImageFileItem>? images,
    bool? isProcessing,
    String? progressMessage,
    bool resetProgressMessage = false,
    String? outputPath,
    bool resetOutput = false,
    String? errorMessage,
    bool resetError = false,
  }) {
    return ImagesToPdfState(
      images: images ?? this.images,
      isProcessing: isProcessing ?? this.isProcessing,
      progressMessage: resetProgressMessage ? null : (progressMessage ?? this.progressMessage),
      outputPath: resetOutput ? null : (outputPath ?? this.outputPath),
      errorMessage: resetError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
