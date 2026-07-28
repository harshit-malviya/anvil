import 'dart:io';
import 'package:anvil/core/services/file_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileService fileService;

  setUp(() {
    fileService = FileService();
  });

  group('FileService Output Directory Tests', () {
    test('getDefaultOutputDirectory returns valid directory', () async {
      final dir = await fileService.getDefaultOutputDirectory();
      expect(dir, isNotNull);
      expect(dir.path, isNotEmpty);
    });

    test('getDefaultOutputDirectory with source file path on Desktop', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_file_service_test');
      final sourceFile = File('${tempDir.path}${Platform.pathSeparator}input.pdf');
      sourceFile.writeAsStringSync('dummy');

      final dir = await fileService.getDefaultOutputDirectory(sourceFilePath: sourceFile.path);
      expect(dir, isNotNull);
      if (!Platform.isAndroid) {
        expect(dir.path, equals(tempDir.path));
      }

      tempDir.deleteSync(recursive: true);
    });
  });
}
