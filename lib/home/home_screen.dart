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
              padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 12.0),
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
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primary(brightness),
                                borderRadius: BorderRadius.circular(6.0),
                              ),
                              child: const Icon(
                                Icons.build_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Anvil',
                              style: AppTypography.displayMedium(brightness),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
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
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Select a tool below to process your files locally on your device.',
                      style: AppTypography.bodyMedium(brightness).copyWith(
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 20.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260.0,
                  mainAxisExtent: 118.0,
                  crossAxisSpacing: 12.0,
                  mainAxisSpacing: 12.0,
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
