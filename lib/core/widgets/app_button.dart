import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum AppButtonVariant {
  primary,
  secondary,
  destructive,
}

class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;

  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDisabled = onPressed == null && !isLoading;
    final textAndIconColor = _getTextAndIconColor(brightness, isDisabled);

    Widget buttonChild = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                variant == AppButtonVariant.primary ? Colors.white : AppColors.primary(brightness),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (icon != null) ...[
          Icon(icon, size: 18, color: textAndIconColor),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: AppTypography.bodyMedium(brightness).copyWith(
            fontWeight: FontWeight.w600,
            color: textAndIconColor,
          ),
        ),
      ],
    );

    switch (variant) {
      case AppButtonVariant.primary:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary(brightness),
            foregroundColor: Colors.white,
            disabledBackgroundColor: isLoading
                ? AppColors.primary(brightness)
                : AppColors.disabledBackground(brightness),
            disabledForegroundColor: AppColors.disabledText(brightness),
            minimumSize: const Size(120, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.0),
            ),
            elevation: 0,
          ),
          child: buttonChild,
        );

      case AppButtonVariant.secondary:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.secondary(brightness),
            disabledForegroundColor: AppColors.disabledText(brightness),
            side: BorderSide(
              color: isDisabled
                  ? AppColors.disabledBorder(brightness)
                  : AppColors.secondary(brightness),
              width: 1.5,
            ),
            minimumSize: const Size(120, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.0),
            ),
          ),
          child: buttonChild,
        );

      case AppButtonVariant.destructive:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.rustRed,
            disabledForegroundColor: AppColors.disabledText(brightness),
            side: BorderSide(
              color: isDisabled
                  ? AppColors.disabledBorder(brightness)
                  : AppColors.rustRed,
              width: 1.5,
            ),
            minimumSize: const Size(120, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.0),
            ),
          ),
          child: buttonChild,
        );
    }
  }

  Color _getTextAndIconColor(Brightness brightness, bool isDisabled) {
    if (isDisabled) {
      return AppColors.disabledText(brightness);
    }
    switch (variant) {
      case AppButtonVariant.primary:
        return Colors.white;
      case AppButtonVariant.secondary:
        return AppColors.secondary(brightness);
      case AppButtonVariant.destructive:
        return AppColors.rustRed;
    }
  }
}
