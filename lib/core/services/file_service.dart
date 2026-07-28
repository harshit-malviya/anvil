import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
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

  /// Open OS file picker for selecting Image files (JPEG, PNG).
  Future<List<PlatformFile>> pickImageFiles({bool allowMultiple = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
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

  /// Share multiple files on Android or desktop.
  Future<void> shareMultipleFiles(List<String> filePaths, {String? text}) async {
    if (filePaths.isEmpty) return;
    await Share.shareXFiles(
      filePaths.map((p) => XFile(p)).toList(),
      text: text ?? 'Sharing split PDF files',
    );
  }

  /// Select a directory location using OS picker.
  Future<String?> pickDirectory({String? dialogTitle}) async {
    return await FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
  }

  /// Get temporary directory for transient outputs.
  Future<Directory> getTempDirectory() async {
    return await getTemporaryDirectory();
  }

  /// Open directory in default system file manager.
  Future<void> openFolder(String folderPath) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [folderPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [folderPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [folderPath]);
      }
    } catch (_) {}
  }

  /// Get default directory for saving output files.
  /// On Android, saves to an accessible 'Anvil' directory in public storage (e.g. Download/Anvil).
  /// On Windows/desktop, uses the parent directory of [sourceFilePath] if available, or system temp directory.
  Future<Directory> getDefaultOutputDirectory({String? sourceFilePath}) async {
    if (Platform.isAndroid) {
      // Direct public storage paths outside restricted Android/data
      final publicPaths = [
        '/storage/emulated/0/Download/Anvil',
        '/storage/emulated/0/Anvil',
        '/storage/emulated/0/Documents/Anvil',
        '/sdcard/Download/Anvil',
        '/sdcard/Anvil',
      ];
      for (final path in publicPaths) {
        try {
          final dir = Directory(path);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          if (dir.existsSync()) {
            return dir;
          }
        } catch (_) {}
      }

      // Fallback only if public paths are blocked by system
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final anvilDir = Directory(p.join(extDir.path, 'Anvil'));
          if (!await anvilDir.exists()) {
            await anvilDir.create(recursive: true);
          }
          return anvilDir;
        }
      } catch (_) {}
    }

    if (sourceFilePath != null && sourceFilePath.isNotEmpty) {
      final parentDir = p.dirname(sourceFilePath);
      if (parentDir.isNotEmpty) {
        final dir = Directory(parentDir);
        if (dir.existsSync()) {
          return dir;
        }
      }
    }

    return Directory.systemTemp;
  }
}

