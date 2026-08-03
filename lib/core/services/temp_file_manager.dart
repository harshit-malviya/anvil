import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Singleton Riverpod provider for [TempFileManager].
final tempFileManagerProvider = Provider<TempFileManager>((ref) {
  return TempFileManager();
});

/// Manages temp-file lifecycle to prevent cache bloat on Android.
///
/// Tracks files created or copied during tool sessions (e.g. file_picker cache
/// copies, intermediate renders) and deletes them when the session completes.
/// Also provides a startup sweep to clean orphaned files from prior sessions
/// that were killed before cleanup ran.
///
/// Registration is centralized inside [FileService]'s pick methods — controllers
/// only need to call [cleanupSession] at their lifecycle endpoints.
class TempFileManager {
  /// Paths registered in the current tool session.
  final Set<String> _registeredPaths = {};

  /// Cached temp directory path, resolved lazily.
  String? _tempDirPath;

  /// Register a temp file for cleanup at end of session.
  ///
  /// Guard: only accepts paths that are actually inside the app's temp
  /// directory. This prevents accidentally registering a user's chosen
  /// output file for deletion.
  Future<void> registerTempFile(File file) async {
    await registerTempPath(file.path);
  }

  /// Register a temp file path for cleanup at end of session.
  ///
  /// Guard: only accepts paths inside the app's temp directory.
  Future<void> registerTempPath(String path) async {
    final tempDir = await _getTempDirPath();
    final normalizedPath = _normalizePath(path);
    final normalizedTempDir = _normalizePath(tempDir);

    if (normalizedPath.startsWith(normalizedTempDir)) {
      _registeredPaths.add(normalizedPath);
    }
    // Silently ignore paths outside temp dir — guard against bad registrations.
  }

  /// Delete all files registered in the current session.
  ///
  /// Call this on:
  /// - successful completion of an operation
  /// - operation failure/cancellation
  /// - reset/navigate-away
  ///
  /// Never throws — locked/missing files are silently skipped.
  Future<void> cleanupSession() async {
    final paths = Set<String>.from(_registeredPaths);
    _registeredPaths.clear();

    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Silently skip — cleanup failures must never surface as user-facing errors.
        debugPrint('TempFileManager: could not delete $path — $e');
      }
    }
  }

  /// Delete everything inside the app's temp directory from prior sessions.
  ///
  /// Run fire-and-forget on app launch. Deletes all files not registered in the
  /// current session (which at startup is empty, so this sweeps everything).
  /// Never throws or surfaces UI errors.
  Future<void> sweepOrphanedFiles() async {
    try {
      final tempDir = Directory(await _getTempDirPath());
      if (!await tempDir.exists()) return;

      final normalizedRegistered = _registeredPaths.map(_normalizePath).toSet();

      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          final normalizedPath = _normalizePath(entity.path);
          if (!normalizedRegistered.contains(normalizedPath)) {
            try {
              await entity.delete();
            } catch (_) {
              // Skip locked/in-use files silently.
            }
          }
        }
      }
    } catch (e) {
      // Sweep failures are invisible maintenance — never surface to user.
      debugPrint('TempFileManager: sweep failed — $e');
    }
  }

  /// Returns total bytes used by the app's temp directory.
  ///
  /// Hook for a future Settings screen "Clear Cache" display — not required by
  /// this task, just don't block it.
  Future<int> cacheDirectorySize() async {
    try {
      final tempDir = Directory(await _getTempDirPath());
      if (!await tempDir.exists()) return 0;

      int totalBytes = 0;
      await for (final entity in tempDir.list(recursive: true)) {
        if (entity is File) {
          try {
            totalBytes += await entity.length();
          } catch (_) {}
        }
      }
      return totalBytes;
    } catch (_) {
      return 0;
    }
  }

  /// Returns the set of currently registered temp file paths.
  @visibleForTesting
  Set<String> get registeredPaths => Set.unmodifiable(_registeredPaths);

  /// Resolve and cache the temp directory path.
  Future<String> _getTempDirPath() async {
    if (_tempDirPath != null) return _tempDirPath!;
    final dir = await getTemporaryDirectory();
    _tempDirPath = dir.path;
    return _tempDirPath!;
  }

  /// Normalize path separators for consistent comparison.
  String _normalizePath(String path) {
    return path.replaceAll('\\', '/');
  }

  /// Override the temp directory path (for testing only).
  @visibleForTesting
  void setTempDirPathForTesting(String path) {
    _tempDirPath = path;
  }
}
