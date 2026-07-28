import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class TaskProgressBar extends StatefulWidget {
  final bool isVisible;
  final String? message;
  final double? progressPercent;

  const TaskProgressBar({
    super.key,
    required this.isVisible,
    this.message,
    this.progressPercent,
  });

  @override
  State<TaskProgressBar> createState() => _TaskProgressBarState();
}

class _TaskProgressBarState extends State<TaskProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final primaryColor = AppColors.primary(brightness);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: widget.isVisible
          ? Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12.0),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(5.0)),
                    child: SizedBox(
                      height: 4.0,
                      child: widget.progressPercent != null
                          ? LinearProgressIndicator(
                              value: widget.progressPercent,
                              color: primaryColor,
                              backgroundColor: AppColors.pegGrey.withValues(alpha: 0.3),
                            )
                          : AnimatedBuilder(
                              animation: _pulseController,
                              builder: (context, child) {
                                return LinearProgressIndicator(
                                  color: Color.lerp(
                                    primaryColor,
                                    AppColors.anvilTeal,
                                    _pulseController.value,
                                  ),
                                  backgroundColor: AppColors.pegGrey.withValues(alpha: 0.3),
                                );
                              },
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.message ?? 'Processing task…',
                            style: AppTypography.mono(brightness).copyWith(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text(brightness),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
