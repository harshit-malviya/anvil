import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anvil/home/tool_search_controller.dart';
import 'package:anvil/tools/registry.dart';

void main() {
  final sampleTools = [
    const ToolMetadata(
      id: 'pdf_merge',
      title: 'Merge PDFs',
      description: 'Combine multiple PDF documents into a single file in your chosen order.',
      icon: Icons.picture_as_pdf,
      route: '/pdf-merge',
      keywords: ['combine', 'join', 'attach', 'put together', 'one file'],
    ),
    const ToolMetadata(
      id: 'pdf_compress',
      title: 'Compress PDF',
      description: 'Reduce PDF file size while preserving text sharpness.',
      icon: Icons.compress,
      route: '/pdf-compress',
      keywords: ['shrink', 'reduce size', 'smaller', 'make smaller', 'file size'],
    ),
    const ToolMetadata(
      id: 'custom_tool',
      title: 'Custom Utility',
      description: 'A special feature for advanced file manipulation.',
      icon: Icons.build,
      route: '/custom-tool',
      keywords: [], // Empty keywords list edge case
    ),
  ];

  group('ToolSearchController - filterTools', () {
    test('empty query returns all tools', () {
      final results = filterTools('', sampleTools);
      expect(results, equals(sampleTools));
    });

    test('whitespace-only query is treated as empty', () {
      final results = filterTools('   \t  ', sampleTools);
      expect(results, equals(sampleTools));
    });

    test('single-word match on title', () {
      final results = filterTools('Merge', sampleTools);
      expect(results.length, equals(1));
      expect(results.first.id, equals('pdf_merge'));
    });

    test('single-word match on keyword-only term', () {
      final results = filterTools('shrink', sampleTools);
      expect(results.length, equals(1));
      expect(results.first.id, equals('pdf_compress'));
    });

    test('single-word match on description-only text', () {
      final results = filterTools('sharpness', sampleTools);
      expect(results.length, equals(1));
      expect(results.first.id, equals('pdf_compress'));
    });

    test('multi-word query requiring all words to match', () {
      // "shrink pdf" -> 'shrink' in keyword, 'pdf' in title/description of compress
      final compressMatch = filterTools('shrink pdf', sampleTools);
      expect(compressMatch.length, equals(1));
      expect(compressMatch.first.id, equals('pdf_compress'));

      // "shrink merge" -> no single tool has both words
      final noMatch = filterTools('shrink merge', sampleTools);
      expect(noMatch, isEmpty);
    });

    test('query matching zero tools returns empty list', () {
      final results = filterTools('nonexistentterm123', sampleTools);
      expect(results, isEmpty);
    });

    test('tool with empty keywords list matches on title and description without error', () {
      final titleMatch = filterTools('Custom', sampleTools);
      expect(titleMatch.length, equals(1));
      expect(titleMatch.first.id, equals('custom_tool'));

      final descMatch = filterTools('manipulation', sampleTools);
      expect(descMatch.length, equals(1));
      expect(descMatch.first.id, equals('custom_tool'));
    });

    test('case-insensitive matching across uppercase and lowercase inputs', () {
      final uppercaseMatch = filterTools('SHRINK', sampleTools);
      expect(uppercaseMatch.length, equals(1));
      expect(uppercaseMatch.first.id, equals('pdf_compress'));
    });
  });

  group('ToolSearchController - Registry integration', () {
    test('filters actual ToolRegistry.tools correctly with defined keywords', () {
      final compress = filterTools('file size', ToolRegistry.tools);
      expect(compress.any((t) => t.id == 'pdf_compress'), isTrue);

      final split = filterTools('cut', ToolRegistry.tools);
      expect(split.any((t) => t.id == 'pdf_split'), isTrue);

      final image = filterTools('screenshot', ToolRegistry.tools);
      expect(image.any((t) => t.id == 'pdf_to_image'), isTrue);
    });
  });
}
