import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Hidden developer-only debug log screen.
///
/// Accessible by tapping the "OFFLINE WORKSHOP" tagline 7 times within 3 seconds.
/// Shows a reverse-chronological list of tool operation log entries in a
/// utilitarian monospace style. Intentionally unpolished — this is a dev tool.
class DebugLogScreen extends ConsumerStatefulWidget {
  const DebugLogScreen({super.key});

  @override
  ConsumerState<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends ConsumerState<DebugLogScreen> {
  final Map<int, bool> _expandedItems = {};

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final logService = ref.watch(appLogServiceProvider);
    final entries = logService.getEntries();

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground(brightness),
        title: Text(
          'Debug Log',
          style: AppTypography.titleMedium(brightness),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: AppColors.text(brightness)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.copy_rounded,
                color: AppColors.text(brightness), size: 20),
            tooltip: 'Copy to Clipboard',
            onPressed: () => _copyToClipboard(entries, context, brightness),
          ),
          IconButton(
            icon: Icon(Icons.share_rounded,
                color: AppColors.text(brightness), size: 20),
            tooltip: 'Share Log File',
            onPressed: () => _shareLogFile(logService, context, brightness),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded,
                color: AppColors.rustRed, size: 20),
            tooltip: 'Clear Log',
            onPressed: () => _confirmClear(
                logService, entries.length, context, brightness),
          ),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    size: 48,
                    color: AppColors.text(brightness).withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No log entries yet',
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      color: AppColors.text(brightness).withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tool operations will appear here',
                    style: AppTypography.bodySmall(brightness).copyWith(
                      color: AppColors.text(brightness).withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final hasDetail = entry.errorDetail != null &&
                    entry.errorDetail!.isNotEmpty;
                final isExpanded = _expandedItems[index] ?? false;

                return InkWell(
                  onTap: hasDetail
                      ? () {
                          setState(() {
                            _expandedItems[index] = !isExpanded;
                          });
                        }
                      : null,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: AppColors.pegGrey.withValues(alpha: 0.3),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildResultIcon(entry.result, brightness),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                entry.toDisplayLine(),
                                style: AppTypography.mono(brightness).copyWith(
                                  fontSize: 11,
                                  color: entry.result == LogResult.error
                                      ? AppColors.rustRed
                                      : AppColors.text(brightness)
                                          .withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                            if (hasDetail)
                              Icon(
                                isExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                size: 16,
                                color: AppColors.text(brightness)
                                    .withValues(alpha: 0.4),
                              ),
                          ],
                        ),
                        if (isExpanded && hasDetail)
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 22, top: 4),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.cardBackground(brightness),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color:
                                      AppColors.pegGrey.withValues(alpha: 0.3),
                                ),
                              ),
                              child: SelectableText(
                                entry.errorDetail!,
                                style:
                                    AppTypography.mono(brightness).copyWith(
                                  fontSize: 10,
                                  color: AppColors.rustRed.withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildResultIcon(LogResult result, Brightness brightness) {
    switch (result) {
      case LogResult.started:
        return Icon(Icons.play_arrow_rounded,
            size: 14,
            color: AppColors.text(brightness).withValues(alpha: 0.5));
      case LogResult.success:
        return const Icon(Icons.check_circle_rounded,
            size: 14, color: Color(0xFF4CAF50));
      case LogResult.error:
        return const Icon(Icons.error_rounded,
            size: 14, color: AppColors.rustRed);
    }
  }

  void _copyToClipboard(
      List<LogEntry> entries, BuildContext context, Brightness brightness) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln(entry.toFullText());
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            entries.isEmpty
                ? 'Log is empty — nothing copied'
                : 'Copied ${entries.length} entries to clipboard',
          ),
          backgroundColor: AppColors.primary(brightness),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _shareLogFile(
      AppLogService logService, BuildContext context, Brightness brightness) async {
    try {
      final file = await logService.exportAsFile();
      await Share.shareXFiles(
        [XFile(file.path)],
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not share log file'),
            backgroundColor: AppColors.rustRed,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _confirmClear(AppLogService logService, int count,
      BuildContext context, Brightness brightness) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackground(brightness),
        title: Text('Clear Log', style: AppTypography.titleMedium(brightness)),
        content: Text(
          'Clear all $count log entries? This can\'t be undone.',
          style: AppTypography.bodyMedium(brightness),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.text(brightness))),
          ),
          TextButton(
            onPressed: () {
              logService.clear();
              Navigator.of(ctx).pop();
              setState(() {
                _expandedItems.clear();
              });
            },
            child:
                const Text('Clear', style: TextStyle(color: AppColors.rustRed)),
          ),
        ],
      ),
    );
  }
}
