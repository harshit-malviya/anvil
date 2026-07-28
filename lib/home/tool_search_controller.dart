import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../tools/registry.dart';

/// Pure function to filter tools based on a search query string.
///
/// Matching behavior:
/// - Leading and trailing whitespace is trimmed.
/// - Empty/whitespace-only query returns all tools (unfiltered).
/// - Query is split on whitespace into words.
/// - A tool matches if ALL query words are found (case-insensitive substring)
///   anywhere across its title, description, or keyword list.
/// - Original registry ordering is preserved.
List<ToolMetadata> filterTools(String query, List<ToolMetadata> tools) {
  final trimmedQuery = query.trim().toLowerCase();
  if (trimmedQuery.isEmpty) {
    return tools;
  }

  final words = trimmedQuery.split(RegExp(r'\s+'));

  return tools.where((tool) {
    final titleLower = tool.title.toLowerCase();
    final descLower = tool.description.toLowerCase();
    final keywordsLower = tool.keywords.map((k) => k.toLowerCase()).toList();

    return words.every((word) {
      if (titleLower.contains(word)) return true;
      if (descLower.contains(word)) return true;
      if (keywordsLower.any((k) => k.contains(word))) return true;
      return false;
    });
  }).toList();
}

/// Provider holding the current transient search query string.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Derived provider computing the filtered list of tools based on [searchQueryProvider].
final filteredToolsProvider = Provider<List<ToolMetadata>>((ref) {
  final query = ref.watch(searchQueryProvider);
  return filterTools(query, ToolRegistry.tools);
});
