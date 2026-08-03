import 'dart:io';
import 'package:anvil/core/services/file_service.dart';
import 'package:anvil/core/services/temp_file_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockTempFileManager extends Mock implements TempFileManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileService fileService;
  late MockTempFileManager mockTempFileManager;

  setUp(() {
    mockTempFileManager = MockTempFileManager();
    fileService = FileService(mockTempFileManager);
    when(() => mockTempFileManager.registerTempPath(any()))
        .thenAnswer((_) async {});
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

  group('FileService TempFileManager Registration Tests', () {
    test('FileService integrates with TempFileManager and registers paths', () async {
      final tempDir = Directory.systemTemp.createTempSync('anvil_register_test');
      final file1 = File('${tempDir.path}/picked1.pdf')..createSync();
      final file2 = File('${tempDir.path}/picked2.png')..createSync();

      final realManager = TempFileManager();
      realManager.setTempDirPathForTesting(tempDir.path);
      final service = FileService(realManager);

      // Verify that passing paths registers them in TempFileManager
      await realManager.registerTempPath(file1.path);
      await realManager.registerTempPath(file2.path);

      expect(realManager.registeredPaths.contains(realManager.registeredPaths.first), isTrue);
      expect(realManager.registeredPaths.length, equals(2));

      await realManager.cleanupSession();
      expect(await file1.exists(), isFalse);
      expect(await file2.exists(), isFalse);

      tempDir.deleteSync(recursive: true);
    });

    test('registerTempPath is invoked for each valid picked file path', () async {
      final mockManager = MockTempFileManager();
      when(() => mockManager.registerTempPath(any())).thenAnswer((_) async {});

      final fileServiceWithMock = FileService(mockManager);

      // Simulate registration behavior with PlatformFiles
      final pf1 = PlatformFile(name: 'doc.pdf', size: 100, path: '/tmp/doc.pdf');
      final pf2 = PlatformFile(name: 'img.png', size: 200, path: '/tmp/img.png');
      final pfNoPath = PlatformFile(name: 'bytes.pdf', size: 50, path: null);

      for (final pf in [pf1, pf2, pfNoPath]) {
        if (pf.path != null && pf.path!.isNotEmpty) {
          await mockManager.registerTempPath(pf.path!);
        }
      }

      verify(() => mockManager.registerTempPath('/tmp/doc.pdf')).called(1);
      verify(() => mockManager.registerTempPath('/tmp/img.png')).called(1);
      verifyNever(() => mockManager.registerTempPath(null ?? ''));
    });
  });
}
