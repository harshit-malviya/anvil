import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Hidden developer-only debug log screen.
///
/// Upgraded browsing UI with metric stat cards, tool & status filters, text search,
/// expandable row details with JSON copy, monospace metrics, and responsive layout.
class DebugLogScreen extends ConsumerStatefulWidget {
  const DebugLogScreen({super.key});

  @override
  ConsumerState<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends ConsumerState<DebugLogScreen> {
  final Map<String, bool> _expandedItems = {};
  String _searchQuery = '';
  String _selectedTool = 'all'; // 'all' or tool key
  String _selectedStatus = 'all'; // 'all', 'completed', 'failed', 'running'

  static const List<Map<String, String>> _toolOptions = [
    {'key': 'all', 'label': 'All Tools'},
    {'key': 'pdf_merge', 'label': 'PDF Merge'},
    {'key': 'pdf_page_manager', 'label': 'PDF Page Manager'},
    {'key': 'pdf_split', 'label': 'PDF Split'},
    {'key': 'pdf_compress', 'label': 'PDF Compress'},
    {'key': 'pdf_to_image', 'label': 'PDF to Image'},
    {'key': 'pdf_password', 'label': 'PDF Password'},
    {'key': 'pdf_insert_pages', 'label': 'PDF Insert Pages'},
    {'key': 'pdf_insert_image_as_page', 'label': 'PDF Insert Image as Page'},
    {'key': 'images_to_pdf', 'label': 'Images to PDF'},
    {'key': 'image_convert', 'label': 'Image Format Convert'},
    {'key': 'image_resize', 'label': 'Image Resize'},
    {'key': 'image_compress', 'label': 'Image Compress'},
    {'key': 'image_blur', 'label': 'Image Blur'},
    {'key': 'image_crop_rotate', 'label': 'Image Crop & Rotate'},
  ];

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final logService = ref.watch(appLogServiceProvider);
    final allEntries = logService.getEntries();

    final filteredEntries = allEntries.where((entry) {
      if (_selectedTool != 'all' && entry.tool != _selectedTool) {
        return false;
      }
      if (_selectedStatus != 'all' && entry.status.name != _selectedStatus) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchTool = entry.tool.toLowerCase().contains(query);
        final matchDisplayName =
            entry.toolDisplayName.toLowerCase().contains(query);
        final matchAction = entry.action.toLowerCase().contains(query);
        final matchError =
            (entry.errorMessage ?? '').toLowerCase().contains(query);
        final matchDetail =
            (entry.errorDetail ?? '').toLowerCase().contains(query);
        if (!matchTool &&
            !matchDisplayName &&
            !matchAction &&
            !matchError &&
            !matchDetail) {
          return false;
        }
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground(brightness),
        elevation: 0,
        title: Text(
          'Debug Log Console',
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
            tooltip: 'Copy Filtered Log to Clipboard',
            onPressed: () => _copyToClipboard(filteredEntries, context, brightness),
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
                logService, allEntries.length, context, brightness),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Stat Strip
          _buildStatStrip(allEntries, brightness),

          // Filters & Search Bar
          _buildFilterBar(brightness),

          // Main Entry List
          Expanded(
            child: filteredEntries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.find_in_page_outlined,
                          size: 48,
                          color: AppColors.text(brightness).withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          allEntries.isEmpty
                              ? 'No log entries recorded yet'
                              : 'No entries match current filters',
                          style: AppTypography.bodyMedium(brightness).copyWith(
                            color: AppColors.text(brightness).withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      final isExpanded = _expandedItems[entry.id] ?? false;

                      return _buildEntryRow(entry, isExpanded, brightness);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Top stat strip with 4 metric cards.
  Widget _buildStatStrip(List<LogEntry> entries, Brightness brightness) {
    final totalOps = entries.length;
    final completedOps =
        entries.where((e) => e.status == LogStatus.completed).length;
    final successRate =
        totalOps == 0 ? 100.0 : (completedOps / totalOps) * 100.0;

    final durations = entries
        .where((e) => e.durationMs != null)
        .map((e) => e.durationMs!)
        .toList();
    final avgDuration = durations.isEmpty
        ? 0
        : (durations.reduce((a, b) => a + b) / durations.length).round();

    // Top failed tool calculation
    final failureCounts = <String, int>{};
    for (final e in entries.where((e) => e.status == LogStatus.failed)) {
      failureCounts[e.toolDisplayName] =
          (failureCounts[e.toolDisplayName] ?? 0) + 1;
    }
    String topFailedTool = 'None';
    int maxFailures = 0;
    failureCounts.forEach((tool, count) {
      if (count > maxFailures) {
        maxFailures = count;
        topFailedTool = tool;
      }
    });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        border: Border(
          bottom: BorderSide(
            color: AppColors.pegGrey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceAround,
            children: [
              _buildStatCard('Total Operations', '$totalOps', brightness, isWide),
              _buildStatCard(
                'Success Rate',
                '${successRate.toStringAsFixed(1)}%',
                brightness,
                isWide,
                color: successRate >= 90
                    ? const Color(0xFF4CAF50)
                    : AppColors.rustRed,
              ),
              _buildStatCard(
                'Avg Duration',
                _formatDuration(avgDuration),
                brightness,
                isWide,
              ),
              _buildStatCard(
                'Most Failures',
                topFailedTool,
                brightness,
                isWide,
                color: maxFailures > 0 ? AppColors.rustRed : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, Brightness brightness, bool isWide,
      {Color? color}) {
    return Container(
      width: isWide ? 135 : 160,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.pegGrey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall(brightness).copyWith(
              fontSize: 9,
              color: AppColors.text(brightness).withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono(brightness).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.text(brightness),
            ),
          ),
        ],
      ),
    );
  }

  /// Filter & Search control bar.
  Widget _buildFilterBar(Brightness brightness) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppColors.cardBackground(brightness).withValues(alpha: 0.5),
      child: Column(
        children: [
          Row(
            children: [
              // Free text search input
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: AppTypography.bodySmall(brightness),
                    decoration: InputDecoration(
                      hintText: 'Search tool, action, error message…',
                      hintStyle: AppTypography.bodySmall(brightness).copyWith(
                        color: AppColors.text(brightness).withValues(alpha: 0.4),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppColors.text(brightness).withValues(alpha: 0.4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      filled: true,
                      fillColor: AppColors.background(brightness),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: AppColors.pegGrey.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(
                          color: AppColors.pegGrey.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(
                          color: AppColors.emberCopper,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Tool Filter Dropdown
              DropdownButton<String>(
                value: _selectedTool,
                underline: const SizedBox(),
                dropdownColor: AppColors.cardBackground(brightness),
                style: AppTypography.bodySmall(brightness),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedTool = val);
                },
                items: _toolOptions.map((opt) {
                  return DropdownMenuItem<String>(
                    value: opt['key']!,
                    child: Text(opt['label']!),
                  );
                }).toList(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Status Segmented filter chips
          Row(
            children: [
              _buildStatusChip('all', 'All', brightness),
              const SizedBox(width: 6),
              _buildStatusChip('completed', 'Completed', brightness),
              const SizedBox(width: 6),
              _buildStatusChip('failed', 'Failed', brightness),
              const SizedBox(width: 6),
              _buildStatusChip('running', 'Running', brightness),
            ],
          ),
          const SizedBox(height: 6),
          // Legend strip for Start Time and Time Taken
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  size: 11, color: AppColors.text(brightness).withValues(alpha: 0.5)),
              const SizedBox(width: 3),
              Text(
                'Start: Start Time',
                style: AppTypography.mono(brightness).copyWith(
                    fontSize: 9,
                    color: AppColors.text(brightness).withValues(alpha: 0.5)),
              ),
              const SizedBox(width: 12),
              Icon(Icons.timer_outlined,
                  size: 11, color: AppColors.text(brightness).withValues(alpha: 0.5)),
              const SizedBox(width: 3),
              Text(
                'Took: Time Taken (Duration)',
                style: AppTypography.mono(brightness).copyWith(
                    fontSize: 9,
                    color: AppColors.text(brightness).withValues(alpha: 0.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
      String statusKey, String label, Brightness brightness) {
    final isSelected = _selectedStatus == statusKey;
    return InkWell(
      onTap: () => setState(() => _selectedStatus = statusKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary(brightness)
              : AppColors.background(brightness),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary(brightness)
                : AppColors.pegGrey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall(brightness).copyWith(
            fontSize: 10,
            color: isSelected
                ? Colors.white
                : AppColors.text(brightness).withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }

  /// Single Operation Row.
  Widget _buildEntryRow(
      LogEntry entry, bool isExpanded, Brightness brightness) {
    final isFailed = entry.status == LogStatus.failed;
    final isRunning = entry.status == LogStatus.running;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isFailed
            ? AppColors.rustRed.withValues(alpha: 0.08)
            : AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isFailed
              ? AppColors.rustRed.withValues(alpha: 0.3)
              : AppColors.pegGrey.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        onTap: () {
          setState(() {
            _expandedItems[entry.id] = !isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Status badge, tool name + action, mono start time + duration
              Row(
                children: [
                  _buildStatusBadge(entry.status, brightness),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${entry.toolDisplayName} • ${entry.action}',
                      style: AppTypography.bodyMedium(brightness).copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    'Start: ${_formatTimeString(entry.startTime)}',
                    style: AppTypography.mono(brightness).copyWith(
                      fontSize: 10,
                      color: AppColors.text(brightness).withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Took: ${_formatDuration(entry.durationMs)}',
                    style: AppTypography.mono(brightness).copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isRunning ? AppColors.emberCopper : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.text(brightness).withValues(alpha: 0.4),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Second Row: Input specs (count, size)
              Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 12,
                      color: AppColors.text(brightness).withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    'Inputs: ${entry.inputFileCount ?? 0} file(s) (${_formatBytes(entry.inputFilesCombinedSizeBytes)})',
                    style: AppTypography.mono(brightness).copyWith(
                      fontSize: 10,
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                    ),
                  ),
                  if (entry.outputFileCount != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.output_rounded,
                        size: 12,
                        color:
                            AppColors.text(brightness).withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(
                      'Outputs: ${entry.outputFileCount} file(s) (${_formatBytes(entry.outputFilesCombinedSizeBytes)})',
                      style: AppTypography.mono(brightness).copyWith(
                        fontSize: 10,
                        color:
                            AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
              // Error summary preview if failed
              if (isFailed && entry.errorMessage != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Error: ${entry.errorMessage}',
                  style: AppTypography.bodySmall(brightness).copyWith(
                    fontSize: 11,
                    color: AppColors.rustRed,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              // Expanded detail panel
              if (isExpanded) ...[
                const Divider(height: 16),
                _buildExpandedDetails(entry, brightness),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(LogStatus status, Brightness brightness) {
    Color bg;
    Color fg;
    String text;

    switch (status) {
      case LogStatus.completed:
        bg = const Color(0xFF4CAF50).withValues(alpha: 0.15);
        fg = const Color(0xFF4CAF50);
        text = 'Completed';
        break;
      case LogStatus.failed:
        bg = AppColors.rustRed.withValues(alpha: 0.15);
        fg = AppColors.rustRed;
        text = 'Failed';
        break;
      case LogStatus.running:
        bg = AppColors.emberCopper.withValues(alpha: 0.15);
        fg = AppColors.emberCopper;
        text = 'Running';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall(brightness).copyWith(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  /// Expanded Details view.
  Widget _buildExpandedDetails(LogEntry entry, Brightness brightness) {
    // Build consolidated parameters & operation info map
    final Map<String, String> infoMap = {};

    // 1. Tool parameters first
    for (final e in entry.parameters.entries) {
      infoMap[e.key] = e.value.toString();
    }

    // 2. Timing metrics (Start Time & Time Taken / Duration)
    infoMap['startTime'] = _formatTimeString(entry.startTime);
    infoMap['timeTaken'] = _formatDuration(entry.durationMs);
    if (entry.filePickerLoadTimeMs != null) {
      infoMap['filePickerLoadTime'] = '${entry.filePickerLoadTimeMs} ms';
    }

    // 3. File metrics
    infoMap['inputFiles'] =
        '${entry.inputFileCount} file(s) (${_formatBytes(entry.inputFilesCombinedSizeBytes)})';
    if (entry.outputFileCount != null || entry.outputFilesCombinedSizeBytes != null) {
      infoMap['outputFiles'] =
          '${entry.outputFileCount ?? 0} file(s) (${_formatBytes(entry.outputFilesCombinedSizeBytes ?? 0)})';
    }

    // 4. Platform & Operation ID metadata
    infoMap['platform'] = entry.platform;
    infoMap['operationId'] = entry.id;

    if (entry.status == LogStatus.failed && entry.errorMessage != null) {
      infoMap['errorMessage'] = entry.errorMessage!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parameters & Operation Details:',
          style: AppTypography.labelSmall(brightness).copyWith(
            fontSize: 10,
            color: AppColors.emberCopper,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background(brightness),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.pegGrey.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: infoMap.entries.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        '${e.key}:',
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text(brightness).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        e.value,
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 10,
                          color: AppColors.text(brightness),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        if (entry.status == LogStatus.failed) ...[
          Row(
            children: [
              Text(
                'Failure Stage: ',
                style: AppTypography.labelSmall(brightness)
                    .copyWith(fontSize: 10, color: AppColors.rustRed),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.rustRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.failureStage?.name ?? 'unknown',
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.rustRed,
                  ),
                ),
              ),
            ],
          ),
          if (entry.errorDetail != null && entry.errorDetail!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Error Detail / Stack Trace:',
              style: AppTypography.labelSmall(brightness)
                  .copyWith(fontSize: 10, color: AppColors.rustRed),
            ),
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.background(brightness),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.rustRed.withValues(alpha: 0.3),
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  entry.errorDetail!,
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 10,
                    color: AppColors.rustRed.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _copyEntryJson(entry, context, brightness),
            icon: const Icon(Icons.code_rounded, size: 14),
            label: Text(
              'Copy Entry as JSON',
              style: AppTypography.labelSmall(brightness).copyWith(fontSize: 10),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              side: BorderSide(
                color: AppColors.pegGrey.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _copyEntryJson(
      LogEntry entry, BuildContext context, Brightness brightness) {
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(entry.toJson());
    Clipboard.setData(ClipboardData(text: jsonString));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied entry JSON for ${entry.toolDisplayName}'),
          backgroundColor: AppColors.primary(brightness),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _copyToClipboard(
      List<LogEntry> entries, BuildContext context, Brightness brightness) {
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer.writeln(entry.toFullText());
      buffer.writeln('---');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            entries.isEmpty
                ? 'Log is empty — nothing copied'
                : 'Copied ${entries.length} log entries to clipboard',
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

  static String _formatTimeString(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String _formatDuration(int? ms) {
    if (ms == null) return '—';
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  static String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
