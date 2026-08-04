import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Result type for a log entry.
enum LogResult { started, success, error }

/// A single structured log entry.
class LogEntry {
  final DateTime timestamp;
  final String tool;
  final String action;
  final LogResult result;
  final String message;
  final String? errorDetail;

  const LogEntry({
    required this.timestamp,
    required this.tool,
    required this.action,
    required this.result,
    required this.message,
    this.errorDetail,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'tool': tool,
        'action': action,
        'result': result.name,
        'message': message,
        if (errorDetail != null) 'errorDetail': errorDetail,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        tool: json['tool'] as String,
        action: json['action'] as String,
        result: LogResult.values.firstWhere((r) => r.name == json['result']),
        message: json['message'] as String,
        errorDetail: json['errorDetail'] as String?,
      );

  /// Single-line display for the debug log screen.
  String toDisplayLine() {
    final ts = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
    final tag = result == LogResult.error
        ? '✖'
        : result == LogResult.success
            ? '✔'
            : '▸';
    return '$ts $tag $tool.$action — $message';
  }

  /// Full text representation including optional error detail.
  String toFullText() {
    final base = toDisplayLine();
    if (errorDetail != null && errorDetail!.isNotEmpty) {
      return '$base\n    $errorDetail';
    }
    return base;
  }
}

/// Maximum number of log entries retained.
const int _maxEntries = 500;

/// Developer-only diagnostic log service.
///
/// Stores structured log entries as JSON Lines in the app's local storage
/// directory. All writes are async and fail silently — logging must never
/// crash or interrupt the actual tool operation it describes.
class AppLogService extends ChangeNotifier {
  final List<LogEntry> _entries = [];
  File? _logFile;
  bool _initialized = false;

  AppLogService() {
    _init();
  }

  Future<void> _init() async {
    await _getLogFile();
  }

  /// Log a "started" event.
  void logStarted(String tool, String action, {String? message}) {
    _addEntry(LogEntry(
      timestamp: DateTime.now(),
      tool: tool,
      action: action,
      result: LogResult.started,
      message: message ?? '$action started',
    ));
  }

  /// Log a "success" event.
  void logSuccess(String tool, String action, {String? message}) {
    _addEntry(LogEntry(
      timestamp: DateTime.now(),
      tool: tool,
      action: action,
      result: LogResult.success,
      message: message ?? '$action completed',
    ));
  }

  /// Log an "error" event.
  void logError(String tool, String action,
      {required String message, String? errorDetail}) {
    _addEntry(LogEntry(
      timestamp: DateTime.now(),
      tool: tool,
      action: action,
      result: LogResult.error,
      message: message,
      errorDetail: errorDetail,
    ));
  }

  /// Get all entries, most recent first.
  List<LogEntry> getEntries() => _entries.reversed.toList();

  /// Number of stored entries.
  int get entryCount => _entries.length;

  /// Clear all log entries (both in-memory and on disk).
  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        await file.writeAsString('', flush: true);
      }
    } catch (_) {
      // Fail silently — clearing is best-effort
    }
  }

  /// Export the current log to a shareable temp file.
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

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _addEntry(LogEntry entry) {
    _entries.add(entry);

    // Enforce retention cap
    while (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }

    notifyListeners();

    // Persist async, fire-and-forget
    _persistEntry(entry);
  }

  Future<void> _persistEntry(LogEntry entry) async {
    try {
      final file = await _getLogFile();
      final line = '${jsonEncode(entry.toJson())}\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Fail silently — logging failures must never surface as user-facing errors
    }
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
        } catch (_) {
          // Skip malformed lines
        }
      }
      // Trim to cap
      while (_entries.length > _maxEntries) {
        _entries.removeAt(0);
      }
      notifyListeners();
    } catch (_) {
      // Fail silently
    }
  }
}

/// Singleton Riverpod provider for the app-wide debug log service.
final appLogServiceProvider = ChangeNotifierProvider<AppLogService>((ref) {
  return AppLogService();
});
