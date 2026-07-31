import 'package:flutter/material.dart';
import '../../tools/registry.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class ToolCard extends StatefulWidget {
  final ToolMetadata tool;
  final VoidCallback onTap;

  const ToolCard({
    super.key,
    required this.tool,
    required this.onTap,
  });

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isAvailable = widget.tool.isAvailable;
    final isHighlighted = _isHovered || _isFocused;
    final familyAccent = AppColors.familyAccent(widget.tool.category, brightness);

    final borderColor = !isAvailable
        ? AppColors.disabledBorder(brightness)
        : (isHighlighted
            ? familyAccent
            : (brightness == Brightness.dark
                ? AppColors.pegGrey.withValues(alpha: 0.2)
                : AppColors.pegGrey));

    return FocusableActionDetector(
      onShowHoverHighlight: (hovered) => setState(() => _isHovered = hovered),
      onShowFocusHighlight: (focused) => setState(() => _isFocused = focused),
      child: Material(
        color: isAvailable
            ? AppColors.cardBackground(brightness)
            : AppColors.disabledBackground(brightness).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6.0),
        child: InkWell(
          onTap: isAvailable ? widget.onTap : null,
          borderRadius: BorderRadius.circular(6.0),
          hoverColor: familyAccent.withValues(alpha: 0.05),
          splashColor: familyAccent.withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(
                color: borderColor,
                width: isHighlighted && isAvailable ? 1.5 : 1.0,
              ),
            ),
            child: Opacity(
              opacity: isAvailable ? 1.0 : 0.55,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: !isAvailable
                              ? AppColors.disabledBackground(brightness)
                              : (brightness == Brightness.dark
                                  ? AppColors.steelCard
                                  : AppColors.pegGrey.withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(
                            color: !isAvailable
                                ? AppColors.disabledBorder(brightness)
                                : AppColors.pegGrey.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          widget.tool.icon,
                          size: 18,
                          color: isAvailable
                              ? familyAccent
                              : AppColors.disabledText(brightness),
                        ),
                      ),
                      if (!isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.disabledBorder(brightness),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            'SOON',
                            style: AppTypography.labelSmall(brightness).copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.disabledText(brightness),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tool.title,
                        style: AppTypography.titleMedium(brightness).copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isAvailable
                              ? AppColors.text(brightness)
                              : AppColors.disabledText(brightness),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.tool.description,
                        style: AppTypography.bodySmall(brightness).copyWith(
                          fontSize: 11,
                          height: 1.2,
                          color: isAvailable
                              ? AppColors.text(brightness).withValues(alpha: 0.7)
                              : AppColors.disabledText(brightness),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

