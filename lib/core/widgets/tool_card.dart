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
            padding: const EdgeInsets.all(16.0),
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
                      width: 40,
                      height: 40,
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
                        size: 22,
                        color: AppColors.primary(brightness),
                      ),
                    ),
                    if (!widget.tool.isAvailable)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.pegGrey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'SOON',
                          style: AppTypography.labelSmall(brightness).copyWith(
                            fontSize: 10,
                            color: AppColors.text(brightness).withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.tool.title,
                      style: AppTypography.titleMedium(brightness),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.tool.description,
                      style: AppTypography.bodyMedium(brightness).copyWith(
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
