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
    final isHighlighted = _isHovered || _isFocused;

    final borderColor = isHighlighted
        ? AppColors.primary(brightness)
        : (brightness == Brightness.dark
            ? AppColors.pegGrey.withValues(alpha: 0.2)
            : AppColors.pegGrey);

    return FocusableActionDetector(
      onShowHoverHighlight: (hovered) => setState(() => _isHovered = hovered),
      onShowFocusHighlight: (focused) => setState(() => _isFocused = focused),
      child: Material(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6.0),
        child: InkWell(
          onTap: widget.tool.isAvailable ? widget.onTap : null,
          borderRadius: BorderRadius.circular(6.0),
          hoverColor: AppColors.primary(brightness).withValues(alpha: 0.05),
          splashColor: AppColors.primary(brightness).withValues(alpha: 0.1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6.0),
              border: Border.all(
                color: borderColor,
                width: isHighlighted ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: brightness == Brightness.dark
                            ? AppColors.steelCard
                            : AppColors.pegGrey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6.0),
                        border: Border.all(
                          color: AppColors.pegGrey.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Icon(
                        widget.tool.icon,
                        size: 18,
                        color: AppColors.primary(brightness),
                      ),
                    ),
                    if (!widget.tool.isAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.pegGrey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'SOON',
                          style: AppTypography.labelSmall(brightness).copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text(brightness).withValues(alpha: 0.6),
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
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
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
    );
  }
}

