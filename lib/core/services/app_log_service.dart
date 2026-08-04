import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Status of an operation log entry.
enum LogStatus { running, completed, failed }

/// Category of failure for a failed log entry.
enum LogFailureStage {
  filePicker,
  validation,
  processing,
  isolateExecution,
  fileWrite,
  unknown,
}

/// A rich single-operation diagnostic log entry.
class LogEntry {
  final String id;
  final String tool;
  final String toolDisplayName;
  final String action;
  final DateTime startTime;
  DateTime? endTime;
  LogStatus status;

  // File picker / input stage
  int? filePickerLoadTimeMs;
  int? inputFileCount;
  int? inputFilesCombinedSizeBytes;

  // Output stage
  int? outputFileCount;
  int? outputFilesCombinedSizeBytes;

  // User-selected options for this run
  Map<String, dynamic> parameters;

  // Failure detail
  LogFailureStage? failureStage;
  String? errorMessage;
  String? errorDetail;

  // Context
  final String platform;

  LogEntry({
    required this.id,
    required this.tool,
    required this.toolDisplayName,
    required this.action,
    required this.startTime,
    this.endTime,
    required this.status,
    this.filePickerLoadTimeMs,
    this.inputFileCount,
    this.inputFilesCombinedSizeBytes,
    this.outputFileCount,
    this.outputFilesCombinedSizeBytes,
    Map<String, dynamic>? parameters,
    this.failureStage,
    this.errorMessage,
    this.errorDetail,
    required this.platform,
  }) : parameters = parameters ?? {};

  int? get durationMs =>
      endTime?.difference(startTime).inMilliseconds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool,
        'toolDisplayName': toolDisplayName,
        'action': action,
        'startTime': startTime.toIso8601String(),
        if (endTime != null) 'endTime': endTime!.toIso8601String(),
        'status': status.name,
        if (filePickerLoadTimeMs != null)
          'filePickerLoadTimeMs': filePickerLoadTimeMs,
        if (inputFileCount != null) 'inputFileCount': inputFileCount,
        if (inputFilesCombinedSizeBytes != null)
          'inputFilesCombinedSizeBytes': inputFilesCombinedSizeBytes,
        if (outputFileCount != null) 'outputFileCount': outputFileCount,
        if (outputFilesCombinedSizeBytes != null)
          'outputFilesCombinedSizeBytes': outputFilesCombinedSizeBytes,
        'parameters': parameters,
        if (failureStage != null) 'failureStage': failureStage!.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (errorDetail != null) 'errorDetail': errorDetail,
        'platform': platform,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    // Migration safety for legacy log format entries
    final id = json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final tool = json['tool'] as String? ?? 'unknown';
    final action = json['action'] as String? ?? 'action';

    String toolDisplayName = json['toolDisplayName'] as String? ?? '';
    if (toolDisplayName.isEmpty) {
      toolDisplayName = _deriveDisplayName(tool);
    }

    final startTimeStr = json['startTime'] as String? ??
        json['timestamp'] as String? ??
        DateTime.now().toIso8601String();
    final startTime = DateTime.parse(startTimeStr);
    final endTimeStr = json['endTime'] as String?;
    final endTime = endTimeStr != null ? DateTime.parse(endTimeStr) : null;

    LogStatus status = LogStatus.completed;
    if (json['status'] != null) {
      status = LogStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => LogStatus.completed,
      );
    } else if (json['result'] != null) {
      final legacyResult = json['result'] as String;
      if (legacyResult == 'error') {
        status = LogStatus.failed;
      } else if (legacyResult == 'started') {
        status = LogStatus.running;
      } else {
        status = LogStatus.completed;
      }
    }

    LogFailureStage? failureStage;
    if (json['failureStage'] != null) {
      failureStage = LogFailureStage.values.firstWhere(
        (s) => s.name == json['failureStage'],
        orElse: () => LogFailureStage.unknown,
      );
    } else if (status == LogStatus.failed) {
      failureStage = LogFailureStage.unknown;
    }

    return LogEntry(
      id: id,
      tool: tool,
      toolDisplayName: toolDisplayName,
      action: action,
      startTime: startTime,
      endTime: endTime,
      status: status,
      filePickerLoadTimeMs: json['filePickerLoadTimeMs'] as int?,
      inputFileCount: json['inputFileCount'] as int?,
      inputFilesCombinedSizeBytes: json['inputFilesCombinedSizeBytes'] as int?,
      outputFileCount: json['outputFileCount'] as int?,
      outputFilesCombinedSizeBytes:
          json['outputFilesCombinedSizeBytes'] as int?,
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
      failureStage: failureStage,
      errorMessage: json['errorMessage'] as String? ?? json['message'] as String?,
      errorDetail: json['errorDetail'] as String?,
      platform: json['platform'] as String? ??
          (kIsWeb
              ? 'web'
              : Platform.isWindows
                  ? 'windows'
                  : Platform.isAndroid
                      ? 'android'
                      : 'other'),
    );
  }

  static String _deriveDisplayName(String tool) {
    switch (tool) {
      case 'pdf_merge':
        return 'PDF Merge';
      case 'pdf_page_manager':
        return 'PDF Page Manager';
      case 'pdf_split':
        return 'PDF Split';
      case 'pdf_compress':
        return 'PDF Compress';
      case 'pdf_to_image':
        return 'PDF to Image';
      case 'pdf_password':
        return 'PDF Password';
      case 'pdf_insert_pages':
        return 'PDF Insert Pages';
      case 'pdf_insert_image_as_page':
        return 'PDF Insert Image as Page';
      case 'images_to_pdf':
        return 'Images to PDF';
      case 'image_convert':
        return 'Image Format Convert';
      case 'image_resize':
        return 'Image Resize';
      case 'image_compress':
        return 'Image Compress';
      case 'image_blur':
        return 'Image Blur';
      case 'image_crop_rotate':
        return 'Image Crop & Rotate';
      default:
        return tool;
    }
  }

  String toDisplayLine() {
    final ts = '${startTime.hour.toString().padLeft(2, '0')}:'
        '${startTime.minute.toString().padLeft(2, '0')}:'
        '${startTime.second.toString().padLeft(2, '0')}';
    final tag = status == LogStatus.failed
        ? '✖'
        : status == LogStatus.completed
            ? '✔'
            : '▸';
    final dur = durationMs != null ? ' (${durationMs}ms)' : '';
    final msg = errorMessage ?? '$toolDisplayName — $action';
    return '$ts $tag $toolDisplayName.$action$dur — $msg';
  }

  String toFullText() {
    final buffer = StringBuffer();
    buffer.writeln(toDisplayLine());
    if (filePickerLoadTimeMs != null) {
      buffer.writeln('  File Picker Load Time: ${filePickerLoadTimeMs}ms');
    }
    if (inputFileCount != null || inputFilesCombinedSizeBytes != null) {
      buffer.writeln(
          '  Inputs: ${inputFileCount ?? 0} file(s), ${inputFilesCombinedSizeBytes ?? 0} bytes');
    }
    if (outputFileCount != null || outputFilesCombinedSizeBytes != null) {
      buffer.writeln(
          '  Outputs: ${outputFileCount ?? 0} file(s), ${outputFilesCombinedSizeBytes ?? 0} bytes');
    }
    if (parameters.isNotEmpty) {
      buffer.writeln('  Parameters: $parameters');
    }
    if (failureStage != null) {
      buffer.writeln('  Failure Stage: ${failureStage!.name}');
    }
    if (errorDetail != null && errorDetail!.isNotEmpty) {
      buffer.writeln('  Error Detail:\n$errorDetail');
    }
    return buffer.toString();
  }
}

/// Retention cap updated to 2000 entries per TASK_debug_log_enrichment.md Part 6.
const int _maxEntries = 2000;

class AppLogService extends ChangeNotifier {
  final List<LogEntry> _entries = [];
  File? _logFile;
  bool _initialized = false;
  int _idCounter = 0;

  AppLogService() {
    _init();
  }

  Future<void> _init() async {
    try {
      await _getLogFile();
    } catch (_) {}
  }

  /// Start logging an operation and return its unique ID.
  String logStarted(
    String tool,
    String toolDisplayName,
    String action, {
    int? inputFileCount,
    int? inputFilesCombinedSizeBytes,
    int? filePickerLoadTimeMs,
    Map<String, dynamic>? parameters,
  }) {
    _idCounter++;
    final id =
        'log_${DateTime.now().microsecondsSinceEpoch}_${_idCounter.toString().padLeft(4, '0')}';
    final platform = kIsWeb
        ? 'web'
        : Platform.isWindows
            ? 'windows'
            : Platform.isAndroid
                ? 'android'
                : 'other';

    final entry = LogEntry(
      id: id,
      tool: tool,
      toolDisplayName: toolDisplayName,
      action: action,
      startTime: DateTime.now(),
      status: LogStatus.running,
      filePickerLoadTimeMs: filePickerLoadTimeMs,
      inputFileCount: inputFileCount,
      inputFilesCombinedSizeBytes: inputFilesCombinedSizeBytes,
      parameters: parameters,
      platform: platform,
    );

    _addEntry(entry);
    return id;
  }

  /// Mark an active log entry as completed.
  void logCompleted(
    String id, {
    int? outputFileCount,
    int? outputFilesCombinedSizeBytes,
    String? message,
    Map<String, dynamic>? parameters,
  }) {
    final entry = _findEntry(id);
    if (entry == null) return;

    entry.endTime = DateTime.now();
    entry.status = LogStatus.completed;
    if (outputFileCount != null) entry.outputFileCount = outputFileCount;
    if (outputFilesCombinedSizeBytes != null) {
      entry.outputFilesCombinedSizeBytes = outputFilesCombinedSizeBytes;
    }
    if (parameters != null) {
      entry.parameters.addAll(parameters);
    }

    _notifyAndUpdate();
  }

  /// Mark an active log entry as failed.
  void logFailed(
    String id, {
    required LogFailureStage stage,
    required String errorMessage,
    String? errorDetail,
    Map<String, dynamic>? parameters,
  }) {
    final entry = _findEntry(id);
    if (entry == null) return;

    entry.endTime = DateTime.now();
    entry.status = LogStatus.failed;
    entry.failureStage = stage;
    entry.errorMessage = errorMessage;
    entry.errorDetail = errorDetail;
    if (parameters != null) {
      entry.parameters.addAll(parameters);
    }

    _notifyAndUpdate();
  }

  /// Convenience method to update or merge parameters on an active entry.
  void updateParameters(String id, Map<String, dynamic> parameters) {
    final entry = _findEntry(id);
    if (entry == null) return;
    entry.parameters.addAll(parameters);
    _notifyAndUpdate();
  }

  LogEntry? _findEntry(String id) {
    for (int i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].id == id) return _entries[i];
    }
    return null;
  }

  List<LogEntry> getEntries() => _entries.reversed.toList();

  int get entryCount => _entries.length;

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        await file.writeAsString('', flush: true);
      }
    } catch (_) {}
  }

  Future<File> exportAsFile() async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final exportFile = File(p.join(dir.path, 'anvil_debug_log_$timestamp.txt'));
    final buffer = StringBuffer();
    for (final entry in _entries.reversed) {
      buffer.writeln(entry.toFullText());
    }
    await exportFile.writeAsString(buffer.toString(), flush: true);
    return exportFile;
  }

  void _addEntry(LogEntry entry) {
    _entries.add(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
    notifyListeners();
    _rewriteFileAsync();
  }

  void _notifyAndUpdate() {
    notifyListeners();
    _rewriteFileAsync();
  }

  Future<void> _rewriteFileAsync() async {
    try {
      final file = await _getLogFile();
      final buffer = StringBuffer();
      for (final entry in _entries) {
        buffer.writeln(jsonEncode(entry.toJson()));
      }
      await file.writeAsString(buffer.toString(), flush: true);
    } catch (_) {}
  }

  Future<File> _getLogFile() async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationSupportDirectory();
    _logFile = File(p.join(dir.path, 'debug_log.jsonl'));
    if (!_initialized) {
      _initialized = true;
      await _loadExistingEntries();
    }
    return _logFile!;
  }

  Future<void> _loadExistingEntries() async {
    try {
      final file = _logFile!;
      if (!await file.exists()) return;
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          _entries.add(LogEntry.fromJson(json));
        } catch (_) {}
      }
      while (_entries.length > _maxEntries) {
        _entries.removeAt(0);
      }
      notifyListeners();
    } catch (_) {}
  }
}

final appLogServiceProvider = ChangeNotifierProvider<AppLogService>((ref) {
  return AppLogService();
});
