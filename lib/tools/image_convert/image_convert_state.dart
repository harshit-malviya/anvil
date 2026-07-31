import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

/// Supported target output image formats for Image Convert tool.
/// Note: WebP is excluded as a target format because package:image 4.x does not support WebP encoding.
enum ImageOutputFormat {
  png('PNG', '.png'),
  jpeg('JPEG', '.jpg'),
  bmp('BMP', '.bmp'),
  gif('GIF', '.gif'),
  tiff('TIFF', '.tiff');

  final String displayName;
  final String extension;

  const ImageOutputFormat(this.displayName, this.extension);
}

/// State model for Image Format Convert feature.
class ImageConvertState {
  final PlatformFile? file;
  final String? detectedFormat;
  final int width;
  final int height;
  final int fileSize;
  final bool hasAlpha;
  final bool isAnimated;
  final ImageOutputFormat targetFormat;
  final int jpegQuality;
  final String? outputPath;
  final int? outputSize;
  final bool isProcessing;
  final String? errorMessage;
  final Uint8List? thumbnailBytes;

  const ImageConvertState({
    this.file,
    this.detectedFormat,
    this.width = 0,
    this.height = 0,
    this.fileSize = 0,
    this.hasAlpha = false,
    this.isAnimated = false,
    this.targetFormat = ImageOutputFormat.jpeg,
    this.jpegQuality = 90,
    this.outputPath,
    this.outputSize,
    this.isProcessing = false,
    this.errorMessage,
    this.thumbnailBytes,
  });

  bool get hasFile => file != null && thumbnailBytes != null && errorMessage == null;
  bool get isSuccess => outputPath != null && errorMessage == null;
  bool get isSameFormat =>
      detectedFormat != null &&
      detectedFormat!.toUpperCase() == targetFormat.displayName.toUpperCase();

  ImageConvertState copyWith({
    PlatformFile? file,
    String? detectedFormat,
    int? width,
    int? height,
    int? fileSize,
    bool? hasAlpha,
    bool? isAnimated,
    ImageOutputFormat? targetFormat,
    int? jpegQuality,
    String? outputPath,
    int? outputSize,
    bool? isProcessing,
    String? errorMessage,
    Uint8List? thumbnailBytes,
    bool clearFile = false,
    bool clearError = false,
    bool clearResult = false,
  }) {
    return ImageConvertState(
      file: clearFile ? null : (file ?? this.file),
      detectedFormat: clearFile ? null : (detectedFormat ?? this.detectedFormat),
      width: clearFile ? 0 : (width ?? this.width),
      height: clearFile ? 0 : (height ?? this.height),
      fileSize: clearFile ? 0 : (fileSize ?? this.fileSize),
      hasAlpha: clearFile ? false : (hasAlpha ?? this.hasAlpha),
      isAnimated: clearFile ? false : (isAnimated ?? this.isAnimated),
      targetFormat: targetFormat ?? this.targetFormat,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      outputPath: clearResult ? null : (outputPath ?? this.outputPath),
      outputSize: clearResult ? null : (outputSize ?? this.outputSize),
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      thumbnailBytes: clearFile ? null : (thumbnailBytes ?? this.thumbnailBytes),
    );
  }
}
