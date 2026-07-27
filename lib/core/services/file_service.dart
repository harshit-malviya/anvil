import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class FileService {
  /// Open OS file picker for selecting PDF files.
  Future<List<PlatformFile>> pickPdfFiles({bool allowMultiple = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: allowMultiple,
      withData: true,
      withReadStream: true,
    );

    if (result == null || result.files.isEmpty) {
      return [];
    }
    return result.files;
  }

  /// Open OS save dialog to save a file.
  Future<String?> saveFile({
    required String defaultFileName,
    required List<int> bytes,
  }) async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Merged PDF',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (outputPath == null) return null;

    final file = File(outputPath);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Share file on Android or desktop.
  Future<void> shareFile(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: 'Sharing merged PDF document',
    );
  }

  /// Get temporary directory for transient outputs.
  Future<Directory> getTempDirectory() async {
    return await getTemporaryDirectory();
  }
}
