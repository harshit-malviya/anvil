import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../home/home_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/pdf-merge',
      builder: (context, state) => const _ToolPlaceholderScreen(toolName: 'PDF Merge'),
    ),
    GoRoute(
      path: '/pdf-page-manager',
      builder: (context, state) => const _ToolPlaceholderScreen(toolName: 'Page Manager'),
    ),
  ],
);

class _ToolPlaceholderScreen extends StatelessWidget {
  final String toolName;

  const _ToolPlaceholderScreen({required this.toolName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(toolName),
      ),
      body: Center(
        child: Text('$toolName feature is coming in next phase.'),
      ),
    );
  }
}
