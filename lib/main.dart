import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/services/temp_file_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: AnvilApp(),
    ),
  );
}

class AnvilApp extends ConsumerWidget {
  const AnvilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    // Fire-and-forget orphan sweep on app launch — cleans up temp files left
    // behind by a prior session that was killed before cleanup ran.
    // sweepOrphanedFiles() is idempotent (empty dir = no-op).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tempFileManagerProvider).sweepOrphanedFiles();
    });

    return MaterialApp.router(
      title: 'Anvil — Offline File Workshop',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
