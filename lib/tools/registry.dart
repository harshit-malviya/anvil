import 'package:flutter/material.dart';

/// Categories of tools in Anvil.
enum ToolCategory { pdf, image }

/// Metadata definition for tools registered in Anvil.
class ToolMetadata {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final String route;
  final bool isAvailable;
  final List<String> keywords;
  final ToolCategory category;

  const ToolMetadata({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.route,
    this.isAvailable = true,
    this.keywords = const [],
    required this.category,
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
      keywords: ['combine', 'join', 'attach', 'put together', 'one file'],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_page_manager',
      title: 'Page Manager',
      description: 'Reorder, rotate, or remove individual pages from a PDF file.',
      icon: Icons.grid_view_rounded,
      route: '/pdf-page-manager',
      isAvailable: true,
      keywords: [
        'remove page',
        'delete page',
        'rotate',
        'reorder',
        'rearrange',
        'sideways',
        'upside down',
      ],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_split',
      title: 'Split PDF',
      description: 'Break a PDF into smaller files by pages, custom ranges, or equal parts.',
      icon: Icons.call_split_rounded,
      route: '/pdf-split',
      isAvailable: true,
      keywords: ['separate', 'break apart', 'cut', 'divide', 'extract pages'],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_compress',
      title: 'Compress PDF',
      description: 'Reduce PDF file size while preserving text sharpness and document structure.',
      icon: Icons.compress_rounded,
      route: '/pdf-compress',
      isAvailable: true,
      keywords: ['shrink', 'reduce size', 'smaller', 'make smaller', 'file size'],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_to_image',
      title: 'PDF to Image',
      description: 'Convert PDF pages into PNG or JPEG image files with customizable resolution.',
      icon: Icons.image_outlined,
      route: '/pdf-to-image',
      isAvailable: true,
      keywords: [
        'screenshot',
        'jpg',
        'png',
        'picture',
        'export as image',
        'convert to picture',
      ],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_password',
      title: 'Password Protect PDF',
      description: 'Add password protection to secure a PDF, or remove existing protection.',
      icon: Icons.lock_outline_rounded,
      route: '/pdf-password',
      isAvailable: true,
      keywords: ['lock', 'unlock', 'protect', 'encrypt', 'secure', 'remove password'],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_insert_pages',
      title: 'Insert Pages',
      description: 'Insert pages from another PDF at a specific position into your document.',
      icon: Icons.post_add_rounded,
      route: '/pdf-insert-pages',
      isAvailable: true,
      keywords: ['add pages', 'combine part', 'insert'],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'pdf_insert_image_as_page',
      title: 'Insert Image as Page',
      description: 'Insert a single image (JPEG or PNG) into an existing PDF document as a page.',
      icon: Icons.add_photo_alternate_outlined,
      route: '/pdf-insert-image-as-page',
      isAvailable: true,
      keywords: ['add photo', 'add screenshot', 'missing page', 'add picture'],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'images_to_pdf',
      title: 'Images to PDF',
      description: 'Combine photo receipts, scans, or pictures into a single PDF document.',
      icon: Icons.collections_outlined,
      route: '/images-to-pdf',
      isAvailable: true,
      keywords: [
        'photo to pdf',
        'picture to pdf',
        'jpg to pdf',
        'png to pdf',
        'image to pdf',
        'scan',
        'convert images',
        'combine photos',
      ],
      category: ToolCategory.pdf,
    ),
    ToolMetadata(
      id: 'image_convert',
      title: 'Image Format Convert',
      description: 'Convert an image between PNG, JPEG, BMP, GIF, and TIFF formats.',
      icon: Icons.transform_rounded,
      route: '/image-convert',
      isAvailable: true,
      keywords: [
        'convert image',
        'png to jpg',
        'jpg to png',
        'webp to png',
        'format converter',
        'change file type',
        'picture converter',
      ],
      category: ToolCategory.image,
    ),
    ToolMetadata(
      id: 'image_resize',
      title: 'Resize Image',
      description: "Change an image's pixel dimensions by exact size, percentage, or preset.",
      icon: Icons.aspect_ratio_rounded,
      route: '/image-resize',
      isAvailable: true,
      keywords: [
        'resize',
        'scale',
        'dimensions',
        'resolution',
        'shrink photo',
        'upscale',
        'aspect ratio',
        'width',
        'height',
      ],
      category: ToolCategory.image,
    ),
    ToolMetadata(
      id: 'image_compress',
      title: 'Compress Image',
      description: "Reduce image file size while preserving pixel dimensions and format.",
      icon: Icons.compress_rounded,
      route: '/image-compress',
      isAvailable: true,
      keywords: [
        'compress',
        'shrink file size',
        'smaller image',
        'reduce file size',
        'photo compress',
        'jpg compress',
        'png compress',
      ],
      category: ToolCategory.image,
    ),
  ];
}

