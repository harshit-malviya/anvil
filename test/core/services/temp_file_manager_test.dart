import 'dart:io';
import 'package:anvil/core/services/temp_file_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TempFileManager tempFileManager;
  late Directory mockTempDir;
  late Directory mockOtherDir;

  setUp(() async {
    tempFileManager = TempFileManager();
    mockTempDir = await Directory.systemTemp.createTemp('anvil_temp_test_');
    mockOtherDir = await Directory.systemTemp.createTemp('anvil_other_test_');
    tempFileManager.setTempDirPathForTesting(mockTempDir.path);
  });

  tearDown(() async {
    if (await mockTempDir.exists()) {
      await mockTempDir.delete(recursive: true);
    }
    if (await mockOtherDir.exists()) {
      await mockOtherDir.delete(recursive: true);
    }
  });

  test('registerTempFile + cleanupSession deletes registered file inside temp dir', () async {
    final file = File('${mockTempDir.path}/test1.tmp');
    await file.writeAsString('hello world');
    expect(await file.exists(), isTrue);

    await tempFileManager.registerTempFile(file);
    expect(tempFileManager.registeredPaths.length, equals(1));

    await tempFileManager.cleanupSession();
    expect(await file.exists(), isFalse);
    expect(tempFileManager.registeredPaths.isEmpty, isTrue);
  });

  test('cleanupSession on empty session does not throw', () async {
    expect(() async => await tempFileManager.cleanupSession(), returnsNormally);
  });

  test('registerTempPath rejects files outside the temp directory (path guard)', () async {
    final fileOutside = File('${mockOtherDir.path}/outside.pdf');
    await fileOutside.writeAsString('user data file');

    await tempFileManager.registerTempFile(fileOutside);
    expect(tempFileManager.registeredPaths, isEmpty);

    await tempFileManager.cleanupSession();
    expect(await fileOutside.exists(), isTrue);
  });

  test('sweepOrphanedFiles deletes unregistered files in temp dir', () async {
    final registeredFile = File('${mockTempDir.path}/registered.tmp');
    await registeredFile.writeAsString('stay');
    final orphanFile = File('${mockTempDir.path}/orphan.tmp');
    await orphanFile.writeAsString('go away');

    await tempFileManager.registerTempFile(registeredFile);
    await tempFileManager.sweepOrphanedFiles();

    expect(await registeredFile.exists(), isTrue);
    expect(await orphanFile.exists(), isFalse);
  });

  test('missing file during cleanupSession does not throw', () async {
    final nonExistentFile = File('${mockTempDir.path}/ghost.tmp');
    await tempFileManager.registerTempFile(nonExistentFile);

    expect(() async => await tempFileManager.cleanupSession(), returnsNormally);
  });

  test('double registration of same file is handled gracefully', () async {
    final file = File('${mockTempDir.path}/dup.tmp');
    await file.writeAsString('test');

    await tempFileManager.registerTempFile(file);
    await tempFileManager.registerTempFile(file);
    expect(tempFileManager.registeredPaths.length, equals(1));

    await tempFileManager.cleanupSession();
    expect(await file.exists(), isFalse);
  });

  test('cacheDirectorySize returns correct total byte count', () async {
    final file1 = File('${mockTempDir.path}/f1.tmp');
    final file2 = File('${mockTempDir.path}/f2.tmp');
    await file1.writeAsBytes([1, 2, 3, 4, 5]); // 5 bytes
    await file2.writeAsBytes([10, 20, 30]); // 3 bytes

    final totalSize = await tempFileManager.cacheDirectorySize();
    expect(totalSize, equals(8));
  });
}
