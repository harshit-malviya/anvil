import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../theme/theme_provider.dart';

/// A button for toggling between System, Light, and Dark themes.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final brightness = Theme.of(context).brightness;

    IconData icon;
    String label;

    switch (themeMode) {
      case ThemeMode.system:
        icon = Icons.brightness_auto_rounded;
        label = 'Theme: System';
        break;
      case ThemeMode.light:
        icon = Icons.light_mode_rounded;
        label = 'Theme: Light';
        break;
      case ThemeMode.dark:
        icon = Icons.dark_mode_rounded;
        label = 'Theme: Dark';
        break;
    }

    return Tooltip(
      message: '$label (Click to cycle)',
      child: IconButton(
        icon: Icon(
          icon,
          color: AppColors.text(brightness),
          size: 20,
        ),
        onPressed: () {
          ref.read(themeModeProvider.notifier).toggleTheme();
        },
      ),
    );
  }
}
