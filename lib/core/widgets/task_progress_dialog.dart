import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'task_progress_bar.dart';

Future<T?> showTaskProgressDialog<T>({
  required BuildContext context,
  required String title,
  required String defaultMessage,
  required Future<T?> Function() task,
  String Function()? getMessage,
  double? Function()? getProgressPercent,
}) async {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (dialogContext) {
      return TaskProgressDialog<T>(
        title: title,
        defaultMessage: defaultMessage,
        task: task,
        getMessage: getMessage,
        getProgressPercent: getProgressPercent,
      );
    },
  );
}

class TaskProgressDialog<T> extends StatefulWidget {
  final String title;
  final String defaultMessage;
  final Future<T?> Function() task;
  final String Function()? getMessage;
  final double? Function()? getProgressPercent;

  const TaskProgressDialog({
    super.key,
    required this.title,
    required this.defaultMessage,
    required this.task,
    this.getMessage,
    this.getProgressPercent,
  });

  @override
  State<TaskProgressDialog<T>> createState() => _TaskProgressDialogState<T>();
}

class _TaskProgressDialogState<T> extends State<TaskProgressDialog<T>> {
  bool _isTaskExecuted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _executeTask();
    });
  }

  Future<void> _executeTask() async {
    if (_isTaskExecuted) return;
    _isTaskExecuted = true;

    // Allow modal entrance animation to complete smoothly before launching work
    await Future.delayed(const Duration(milliseconds: 300));

    final startTime = DateTime.now();

    T? result;
    try {
      result = await widget.task();
    } catch (_) {
      result = null;
    }

    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    if (elapsed < 600) {
      await Future.delayed(Duration(milliseconds: 600 - elapsed));
    }

    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        backgroundColor: AppColors.cardBackground(brightness),
        elevation: 12.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: AppColors.primary(brightness).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Icon(
                        Icons.hourglass_top_rounded,
                        color: AppColors.primary(brightness),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: AppTypography.titleMedium(brightness).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TaskProgressBar(
                  isVisible: true,
                  message: widget.getMessage?.call() ?? widget.defaultMessage,
                  progressPercent: widget.getProgressPercent?.call(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
