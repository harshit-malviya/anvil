import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/tool_card.dart';
import '../tools/registry.dart';
import 'tool_search_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    ref.read(searchQueryProvider.notifier).state = query;
  }

  void _clearQuery() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final searchQuery = ref.watch(searchQueryProvider);
    final filteredTools = ref.watch(filteredToolsProvider);
    final trimmedQuery = searchQuery.trim();

    final List<Widget> slivers = [
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
                      color: AppColors.secondary(brightness).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(
                        color: AppColors.secondary(brightness).withValues(alpha: 0.3),
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
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onQueryChanged,
                style: AppTypography.bodyMedium(brightness),
                cursorColor: AppColors.primary(brightness),
                decoration: InputDecoration(
                  hintText: 'Search tools...',
                  hintStyle: AppTypography.bodyMedium(brightness).copyWith(
                    color: AppColors.text(brightness).withValues(alpha: 0.7),
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                  ),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: _clearQuery,
                          tooltip: 'Clear search',
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: AppColors.cardBackground(brightness),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6.0),
                    borderSide: const BorderSide(
                      color: AppColors.pegGrey,
                      width: 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6.0),
                    borderSide: BorderSide(
                      color: AppColors.primary(brightness),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
    ];

    if (filteredTools.isEmpty && trimmedQuery.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 40.0),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    size: 48,
                    color: AppColors.text(brightness).withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "No tools match '$trimmedQuery'",
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      for (final category in ToolCategory.values) {
        final categoryTools = filteredTools.where((t) => t.category == category).toList();
        if (categoryTools.isEmpty) continue;

        final String sectionTitle = category == ToolCategory.pdf ? 'PDF TOOLS' : 'IMAGE TOOLS';

        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 12.0),
            sliver: SliverToBoxAdapter(
              child: Text(
                sectionTitle,
                style: AppTypography.labelSmall(brightness).copyWith(
                  color: brightness == Brightness.dark
                      ? AppColors.pegGrey
                      : AppColors.text(brightness).withValues(alpha: 0.6),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        );

        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260.0,
                mainAxisExtent: 124.0,
                crossAxisSpacing: 12.0,
                mainAxisSpacing: 12.0,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final tool = categoryTools[index];
                  return ToolCard(
                    tool: tool,
                    onTap: () {
                      context.push(tool.route);
                    },
                  );
                },
                childCount: categoryTools.length,
              ),
            ),
          ),
        );
      }

      slivers.add(
        const SliverPadding(
          padding: EdgeInsets.only(bottom: 24.0),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: slivers,
        ),
      ),
    );
  }
}
