import 'package:flutter/material.dart';

/// Metadata definition for tools registered in Anvil.
class ToolMetadata {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final bool isAvailable;

  const ToolMetadata({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    this.isAvailable = true,
  });
}

/// Central tool registry — single source of truth for all tools in Anvil.
class ToolRegistry {
  static const List<ToolMetadata> tools = [
    ToolMetadata(
      id: 'pdf_merge',
      title: 'Merge PDFs',
      description: 'Combine multiple PDF documents into a single file in your chosen order.',
      icon: Icons.picture_as_pdf_outlined,
      route: '/pdf-merge',
      isAvailable: true,
    ),
    ToolMetadata(
      id: 'pdf_page_manager',
      title: 'Page Manager',
      description: 'Reorder, rotate, or remove individual pages from a PDF file.',
      icon: Icons.grid_view_rounded,
      route: '/pdf-page-manager',
      isAvailable: true,
    ),
    ToolMetadata(
      id: 'pdf_split',
      title: 'Split PDF',
      description: 'Break a PDF into smaller files by pages, custom ranges, or equal parts.',
      icon: Icons.call_split_rounded,
      route: '/pdf-split',
      isAvailable: true,
    ),
    ToolMetadata(
      id: 'pdf_compress',
      title: 'Compress PDF',
      description: 'Reduce PDF file size while preserving text sharpness and document structure.',
      icon: Icons.compress_rounded,
      route: '/pdf-compress',
      isAvailable: true,
    ),
    ToolMetadata(
      id: 'pdf_to_image',
      title: 'PDF to Image',
      description: 'Convert PDF pages into PNG or JPEG image files with customizable resolution.',
      icon: Icons.image_outlined,
      route: '/pdf-to-image',
      isAvailable: true,
    ),
    ToolMetadata(
      id: 'pdf_password',
      title: 'Password Protect PDF',
      description: 'Add password protection to secure a PDF, or remove existing protection.',
      icon: Icons.lock_outline_rounded,
      route: '/pdf-password',
      isAvailable: true,
    ),
  ];
}
