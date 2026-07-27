import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class FileDropZone extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  final String sublabel;
  final IconData icon;
  final bool isDragOver;

  const FileDropZone({
    super.key,
    required this.onTap,
    this.label = 'Drop files here or click to browse',
    this.sublabel = 'Supports PDF files',
    this.icon = Icons.cloud_upload_outlined,
    this.isDragOver = false,
  });

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final active = widget.isDragOver || _isHovered;

    final borderColor = active ? AppColors.primary(brightness) : AppColors.pegGrey;
    final backgroundColor = active
        ? AppColors.primary(brightness).withValues(alpha: 0.05)
        : AppColors.cardBackground(brightness);

    return InkWell(
      onTap: widget.onTap,
      onHover: (hovered) => setState(() => _isHovered = hovered),
      borderRadius: BorderRadius.circular(6.0),
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: borderColor,
          strokeWidth: 1.5,
          gap: 6.0,
          dash: 6.0,
          borderRadius: 6.0,
          isSolid: active,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary(brightness).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 32,
                  color: AppColors.primary(brightness),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.label,
                style: AppTypography.bodyMedium(brightness).copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.sublabel,
                style: AppTypography.bodyMedium(brightness).copyWith(
                  color: AppColors.text(brightness).withValues(alpha: 0.6),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double dash;
  final double borderRadius;
  final bool isSolid;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
    required this.dash,
    required this.borderRadius,
    required this.isSolid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );

    if (isSolid) {
      canvas.drawRRect(rrect, paint);
      return;
    }

    final Path path = Path()..addRRect(rrect);
    final Path dashPath = Path();

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double end = distance + dash;
        dashPath.addPath(
          metric.extractPath(distance, end > metric.length ? metric.length : end),
          Offset.zero,
        );
        distance += dash + gap;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.isSolid != isSolid ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
