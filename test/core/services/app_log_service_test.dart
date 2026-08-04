import 'package:flutter_test/flutter_test.dart';
import 'package:anvil/core/services/app_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLogService Unit Tests', () {
    late AppLogService logService;

    setUp(() {
      logService = AppLogService();
    });

    test('logStarted returns unique id and creates running entry', () {
      final id = logService.logStarted(
        'pdf_merge',
        'PDF Merge',
        'merge',
        inputFileCount: 3,
        inputFilesCombinedSizeBytes: 1048576,
        filePickerLoadTimeMs: 120,
        parameters: {'dividerPagesEnabled': true},
      );

      expect(id, startsWith('log_'));
      expect(logService.entryCount, 1);

      final entries = logService.getEntries();
      final entry = entries.first;
      expect(entry.id, id);
      expect(entry.tool, 'pdf_merge');
      expect(entry.toolDisplayName, 'PDF Merge');
      expect(entry.action, 'merge');
      expect(entry.status, LogStatus.running);
      expect(entry.inputFileCount, 3);
      expect(entry.inputFilesCombinedSizeBytes, 1048576);
      expect(entry.filePickerLoadTimeMs, 120);
      expect(entry.parameters['dividerPagesEnabled'], isTrue);
      expect(entry.endTime, isNull);
      expect(entry.durationMs, isNull);
    });

    test('logCompleted updates running entry in place', () {
      final id = logService.logStarted(
        'pdf_split',
        'PDF Split',
        'split',
        inputFileCount: 1,
      );

      logService.logCompleted(
        id,
        outputFileCount: 4,
        outputFilesCombinedSizeBytes: 2048576,
        parameters: {'mode': 'equalParts', 'parts': 4},
      );

      final entries = logService.getEntries();
      expect(entries.length, 1);
      final entry = entries.first;

      expect(entry.id, id);
      expect(entry.status, LogStatus.completed);
      expect(entry.outputFileCount, 4);
      expect(entry.outputFilesCombinedSizeBytes, 2048576);
      expect(entry.parameters['mode'], 'equalParts');
      expect(entry.parameters['parts'], 4);
      expect(entry.endTime, isNotNull);
      expect(entry.durationMs, isNotNull);
    });

    test('logFailed updates running entry with failure stage and error detail', () {
      final id = logService.logStarted(
        'image_compress',
        'Image Compress',
        'compress',
        inputFileCount: 1,
      );

      logService.logFailed(
        id,
        stage: LogFailureStage.isolateExecution,
        errorMessage: 'OutOfMemory error during encoding',
        errorDetail: 'Stack trace details here...',
      );

      final entries = logService.getEntries();
      final entry = entries.first;

      expect(entry.id, id);
      expect(entry.status, LogStatus.failed);
      expect(entry.failureStage, LogFailureStage.isolateExecution);
      expect(entry.errorMessage, 'OutOfMemory error during encoding');
      expect(entry.errorDetail, 'Stack trace details here...');
      expect(entry.endTime, isNotNull);
    });

    test('updateParameters merges new parameters into entry', () {
      final id = logService.logStarted(
        'image_resize',
        'Image Resize',
        'resize',
        parameters: {'mode': 'exact'},
      );

      logService.updateParameters(id, {'width': 1920, 'height': 1080});

      final entry = logService.getEntries().first;
      expect(entry.parameters['mode'], 'exact');
      expect(entry.parameters['width'], 1920);
      expect(entry.parameters['height'], 1080);
    });

    test('JSON serialization and deserialization integrity', () {
      final id = logService.logStarted(
        'pdf_password',
        'PDF Password',
        'add_password',
        inputFileCount: 1,
        inputFilesCombinedSizeBytes: 500000,
        parameters: {'mode': 'add'},
      );

      logService.logCompleted(
        id,
        outputFileCount: 1,
        outputFilesCombinedSizeBytes: 502000,
      );

      final entry = logService.getEntries().first;
      final jsonMap = entry.toJson();
      final deserialized = LogEntry.fromJson(jsonMap);

      expect(deserialized.id, entry.id);
      expect(deserialized.tool, entry.tool);
      expect(deserialized.toolDisplayName, entry.toolDisplayName);
      expect(deserialized.action, entry.action);
      expect(deserialized.status, LogStatus.completed);
      expect(deserialized.inputFileCount, 1);
      expect(deserialized.outputFileCount, 1);
      expect(deserialized.parameters['mode'], 'add');
    });

    test('Legacy log entry migration safety in LogEntry.fromJson', () {
      final legacyJson = {
        'timestamp': '2026-08-04T12:00:00.000Z',
        'tool': 'pdf_merge',
        'action': 'merge',
        'result': 'error',
        'message': 'Failed to merge',
        'errorDetail': 'Invalid file',
      };

      final entry = LogEntry.fromJson(legacyJson);

      expect(entry.tool, 'pdf_merge');
      expect(entry.toolDisplayName, 'PDF Merge');
      expect(entry.action, 'merge');
      expect(entry.status, LogStatus.failed);
      expect(entry.errorMessage, 'Failed to merge');
      expect(entry.errorDetail, 'Invalid file');
      expect(entry.failureStage, LogFailureStage.unknown);
    });

    test('clear resets entry list', () async {
      logService.logStarted('pdf_merge', 'PDF Merge', 'merge');
      expect(logService.entryCount, 1);

      await logService.clear();
      expect(logService.entryCount, 0);
      expect(logService.getEntries(), isEmpty);
    });
  });
}
