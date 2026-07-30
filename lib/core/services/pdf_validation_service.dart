import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';

enum PdfValidationResult {
  valid,
  passwordProtected,
  corrupted,
}

class PdfValidationInfo {
  final PdfValidationResult result;
  final int pageCount;
  final String? errorDetail;

  const PdfValidationInfo({
    required this.result,
    this.pageCount = 0,
    this.errorDetail,
  });

  bool get isValid => result == PdfValidationResult.valid;
  bool get isPasswordProtected => result == PdfValidationResult.passwordProtected;
  bool get isCorrupted => result == PdfValidationResult.corrupted;
}

class PdfValidationService {
  /// Validates a PDF byte array.
  /// Returns [PdfValidationInfo] indicating whether the PDF is valid, password-protected, or corrupted.
  static PdfValidationInfo validate(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return const PdfValidationInfo(
        result: PdfValidationResult.corrupted,
        errorDetail: 'File is empty or unreadable.',
      );
    }

    try {
      final doc = PdfDocument(inputBytes: bytes);
      final pageCount = doc.pages.count;
      doc.dispose();

      return PdfValidationInfo(
        result: PdfValidationResult.valid,
        pageCount: pageCount,
      );
    } catch (e) {
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('password') ||
          errStr.contains('encrypted') ||
          errStr.contains('security')) {
        return PdfValidationInfo(
          result: PdfValidationResult.passwordProtected,
          errorDetail: e.toString(),
        );
      } else {
        return PdfValidationInfo(
          result: PdfValidationResult.corrupted,
          errorDetail: e.toString(),
        );
      }
    }
  }
}
