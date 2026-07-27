import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/tool_card.dart';
import '../tools/registry.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24.0, 32.0, 24.0, 16.0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary(brightness),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: const Icon(
                                Icons.build_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Anvil',
                              style: AppTypography.displayLarge(brightness),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.anvilTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(
                              color: AppColors.anvilTeal.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            'OFFLINE WORKSHOP',
                            style: AppTypography.labelSmall(brightness).copyWith(
                              color: AppColors.secondary(brightness),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select a tool below to process your files locally on your device.',
                      style: AppTypography.bodyLarge(brightness).copyWith(
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(24.0),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  int crossAxisCount = 1;
                  if (width >= 900) {
                    crossAxisCount = 3;
                  } else if (width >= 550) {
                    crossAxisCount = 2;
                  }

                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16.0,
                      mainAxisSpacing: 16.0,
                      childAspectRatio: 1.5,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final tool = ToolRegistry.tools[index];
                        return ToolCard(
                          tool: tool,
                          onTap: () {
                            context.push(tool.route);
                          },
                        );
                      },
                      childCount: ToolRegistry.tools.length,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
