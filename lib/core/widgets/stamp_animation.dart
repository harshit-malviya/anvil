import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class StampAnimation extends StatefulWidget {
  final String label;
  final VoidCallback? onComplete;
  final Color? color;

  const StampAnimation({
    super.key,
    this.label = 'DONE',
    this.onComplete,
    this.color,
  });

  @override
  State<StampAnimation> createState() => _StampAnimationState();
}

class _StampAnimationState extends State<StampAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 2.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _rotationAnimation = Tween<double>(begin: -0.15, end: -0.05).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 0.9).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _controller.forward().then((_) {
      if (widget.onComplete != null) {
        widget.onComplete!();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion = mediaQuery.accessibleNavigation || mediaQuery.disableAnimations;
    final brightness = Theme.of(context).brightness;
    final stampColor = widget.color ?? AppColors.primary(brightness);

    if (reduceMotion) {
      return Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: stampColor, width: 3),
        ),
        alignment: Alignment.center,
        child: Text(
          widget.label,
          style: AppTypography.titleMedium(brightness).copyWith(
            color: stampColor,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Transform.rotate(
            angle: _rotationAnimation.value * math.pi,
            child: Opacity(
              opacity: _opacityAnimation.value,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: stampColor, width: 3.5),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: stampColor.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check, size: 28, color: stampColor),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.label,
                            softWrap: false,
                            style: AppTypography.labelSmall(brightness).copyWith(
                              color: stampColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
