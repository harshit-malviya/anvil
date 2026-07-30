import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart' as pdfx;
import '../../core/services/file_service.dart';
import '../../core/services/pdf_thumbnail_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import '../../core/widgets/task_progress_dialog.dart';
import 'pdf_page_manager_controller.dart';
import 'pdf_page_manager_state.dart';

class PdfPageManagerScreen extends ConsumerStatefulWidget {
  const PdfPageManagerScreen({super.key});

  @override
  ConsumerState<PdfPageManagerScreen> createState() => _PdfPageManagerScreenState();
}

class _PdfPageManagerScreenState extends ConsumerState<PdfPageManagerScreen> {
  final FileService _fileService = FileService();

  Future<void> _handleApplyChanges() async {
    final controller = ref.read(pdfPageManagerControllerProvider.notifier);
    await showTaskProgressDialog<String>(
      context: context,
      title: 'Applying Page Changes',
      defaultMessage: 'Saving changes…',
      getMessage: () => ref.read(pdfPageManagerControllerProvider).progressMessage ?? 'Saving changes…',
      task: () => controller.applyChanges(),
    );
  }

  Future<void> _pickAndLoadFile() async {
    final pickedFiles = await _fileService.pickPdfFiles(allowMultiple: false);
    if (pickedFiles.isNotEmpty && mounted) {
      await ref
          .read(pdfPageManagerControllerProvider.notifier)
          .loadDocument(pickedFiles.first);
    }
  }

  Future<void> _handleSaveAs(String currentOutputPath) async {
    final savedPath = await _fileService.saveFile(
      defaultFileName: p.basename(currentOutputPath),
      bytes: [],
    );

    if (savedPath != null && mounted) {
      try {
        final src = File(currentOutputPath);
        if (src.existsSync()) {
          await src.copy(savedPath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved to $savedPath'),
                backgroundColor: AppColors.anvilTeal,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save file: $e'),
              backgroundColor: AppColors.rustRed,
            ),
          );
        }
      }
    }
  }

  Future<bool> _onWillPop() async {
    final state = ref.read(pdfPageManagerControllerProvider);
    if (state.file != null && state.outputPath == null) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final brightness = Theme.of(ctx).brightness;
          return AlertDialog(
            backgroundColor: AppColors.cardBackground(brightness),
            title: Text('Discard unsaved changes?', style: AppTypography.titleMedium(brightness)),
            content: Text(
              'You have an open document with page edits. Leaving now will lose your page arrangement.',
              style: AppTypography.bodyMedium(brightness),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Keep Editing',
                  style: AppTypography.bodyMedium(brightness).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              AppButton(
                label: 'Discard',
                variant: AppButtonVariant.destructive,
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          );
        },
      );
      return shouldDiscard ?? false;
    }
    return true;
  }

  void _showPagePreview(BuildContext context, int initialIndex) {
    showDialog(
      context: context,
      builder: (context) => _PdfPagePreviewDialog(initialIndex: initialIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfPageManagerControllerProvider);
    final controller = ref.read(pdfPageManagerControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background(brightness),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: AppColors.text(brightness)),
            onPressed: () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                context.pop();
              }
            },
          ),
          title: Text(
            'Page Manager',
            style: AppTypography.displayMedium(brightness),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.errorMessage != null)
                  _buildErrorBanner(context, state.errorMessage!, controller),
                Expanded(
                  child: state.outputPath != null
                      ? _buildSuccessView(context, state, controller)
                      : state.file == null
                          ? _buildDropZoneView(context)
                          : _buildPageGridView(context, state, controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
      BuildContext context, String message, PdfPageManagerController controller) {
    final brightness = Theme.of(context).brightness;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.rustRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6.0),
        border: const Border(
          left: BorderSide(color: AppColors.rustRed, width: 4.0),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.rustRed),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium(brightness).copyWith(
                color: AppColors.text(brightness),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppColors.text(brightness).withValues(alpha: 0.6)),
            onPressed: controller.clearError,
            tooltip: 'Dismiss error',
          ),
        ],
      ),
    );
  }

  Widget _buildDropZoneView(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickAndLoadFile,
          label: 'Drop PDF file here or click to browse',
          sublabel: 'Select a PDF to delete, reorder, or rotate pages',
        ),
      ),
    );
  }

  Widget _buildPageGridView(
      BuildContext context, PdfPageManagerState state, PdfPageManagerController controller) {
    final brightness = Theme.of(context).brightness;
    final screenWidth = MediaQuery.of(context).size.width;

    int crossAxisCount = 2;
    if (screenWidth >= 1200) {
      crossAxisCount = 5;
    } else if (screenWidth >= 900) {
      crossAxisCount = 4;
    } else if (screenWidth >= 600) {
      crossAxisCount = 3;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // File header bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: AppColors.cardBackground(brightness),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: AppColors.pegGrey),
          ),
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, color: AppColors.anvilTeal),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.file?.name ?? '',
                      style: AppTypography.titleMedium(brightness),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${state.originalPageCount} pages loaded • Click page or zoom button to preview',
                      style: AppTypography.labelSmall(brightness).copyWith(
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Change File',
                variant: AppButtonVariant.secondary,
                onPressed: controller.reset,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),

        // Virtualized thumbnail grid
        Expanded(
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 0.72,
            ),
            itemCount: state.pages.length,
            itemBuilder: (context, index) {
              final page = state.pages[index];
              return _buildPageCard(context, index, page, state, controller);
            },
          ),
        ),

        const SizedBox(height: 16.0),

        // Bottom Action Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          decoration: BoxDecoration(
            color: AppColors.cardBackground(brightness),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: AppColors.pegGrey),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  state.summaryText,
                  style: AppTypography.titleMedium(brightness).copyWith(
                    color: AppColors.secondary(brightness),
                  ),
                ),
              ),
              AppButton(
                label: 'Apply Changes',
                variant: AppButtonVariant.primary,
                icon: Icons.check_circle_outline_rounded,
                isLoading: state.isProcessing,
                onPressed: state.canApply ? _handleApplyChanges : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPageCard(
    BuildContext context,
    int index,
    PageItem page,
    PdfPageManagerState state,
    PdfPageManagerController controller,
  ) {
    final brightness = Theme.of(context).brightness;

    final cardContent = Card(
      elevation: page.isDeleted ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: BorderSide(
          color: page.isDeleted
              ? AppColors.rustRed.withValues(alpha: 0.4)
              : AppColors.pegGrey,
          width: page.isDeleted ? 1.5 : 1.0,
        ),
      ),
      color: page.isDeleted
          ? AppColors.rustRed.withValues(alpha: 0.05)
          : AppColors.cardBackground(brightness),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // Top Page Badge & Reorder hints
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: AppColors.background(brightness),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        'PAGE ${page.originalIndex + 1}',
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (index > 0)
                          InkWell(
                            onTap: () => controller.reorderPage(index, index - 1),
                            child: Icon(Icons.arrow_left_rounded,
                                size: 20, color: AppColors.text(brightness).withValues(alpha: 0.6)),
                          ),
                        if (index < state.pages.length - 1)
                          InkWell(
                            onTap: () => controller.reorderPage(index, index + 2),
                            child: Icon(Icons.arrow_right_rounded,
                                size: 20, color: AppColors.text(brightness).withValues(alpha: 0.6)),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),

                // Page Thumbnail Preview (Clickable to open high-res preview)
                Expanded(
                  child: Tooltip(
                    message: 'Click to preview page content',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () => _showPagePreview(context, index),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.0),
                          child: Transform.rotate(
                            angle: page.rotation * (math.pi / 180),
                            child: Container(
                              width: double.infinity,
                              color: Colors.white,
                              child: page.thumbnailBytes != null
                                  ? Image.memory(
                                      page.thumbnailBytes!,
                                      fit: BoxFit.contain,
                                    )
                                  : page.hasThumbnailError
                                      ? Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.insert_drive_file_outlined,
                                                size: 36, color: AppColors.pegGrey),
                                            const SizedBox(height: 4.0),
                                            Text(
                                              'Preview unavailable',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        )
                                      : const Center(
                                          child: CircularProgressIndicator(strokeWidth: 2.0),
                                        ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),

                // Action Bar: Preview, Rotate & Delete
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.zoom_in_rounded),
                      tooltip: 'Preview page content',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      color: page.isDeleted
                          ? AppColors.disabledText(brightness)
                          : AppColors.anvilTeal,
                      onPressed: () => _showPagePreview(context, index),
                    ),
                    IconButton(
                      icon: const Icon(Icons.rotate_right_rounded),
                      tooltip: 'Rotate 90° (${page.rotation}°)',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      color: page.isDeleted ? AppColors.disabledText(brightness) : AppColors.anvilTeal,
                      onPressed: page.isDeleted ? null : () => controller.rotatePage(index),
                    ),
                    IconButton(
                      icon: Icon(
                        page.isDeleted ? Icons.undo_rounded : Icons.delete_outline_rounded,
                      ),
                      tooltip: page.isDeleted ? 'Undo deletion' : 'Delete page',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      color: page.isDeleted ? AppColors.anvilTeal : AppColors.rustRed,
                      onPressed: () => controller.togglePageDeleted(index),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Struck-through Deleted Overlay
          if (page.isDeleted)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.block_rounded, color: Colors.white, size: 36),
                    const SizedBox(height: 8.0),
                    Text(
                      'DELETED',
                      style: AppTypography.mono(brightness).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    AppButton(
                      label: 'Undo',
                      variant: AppButtonVariant.secondary,
                      icon: Icons.undo_rounded,
                      onPressed: () => controller.togglePageDeleted(index),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) {
        controller.reorderPage(details.data, index > details.data ? index + 1 : index);
      },
      builder: (context, candidateData, rejectedData) {
        final isTargeting = candidateData.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8.0),
            child: SizedBox(
              width: 180,
              height: 240,
              child: cardContent,
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: cardContent,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              border: isTargeting
                  ? Border.all(color: AppColors.anvilTeal, width: 2.5)
                  : null,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: cardContent,
          ),
        );
      },
    );
  }

  Widget _buildSuccessView(
      BuildContext context, PdfPageManagerState state, PdfPageManagerController controller) {
    final brightness = Theme.of(context).brightness;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: AppColors.cardBackground(brightness),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: AppColors.pegGrey),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StampAnimation(
                label: 'ARRANGED',
              ),
              const SizedBox(height: 24.0),
              Text(
                'Page changes applied successfully!',
                style: AppTypography.displayMedium(brightness),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12.0),
              Text(
                'Saved to:',
                style: AppTypography.labelSmall(brightness),
              ),
              const SizedBox(height: 6.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.pegGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  state.outputPath ?? '',
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32.0),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  AppButton(
                    label: 'Open Folder',
                    variant: AppButtonVariant.primary,
                    icon: Icons.folder_open_rounded,
                    onPressed: () {
                      if (state.outputPath != null) {
                        _fileService.openFolder(p.dirname(state.outputPath!));
                      }
                    },
                  ),
                  AppButton(
                    label: 'Save As…',
                    variant: AppButtonVariant.secondary,
                    icon: Icons.save_alt_rounded,
                    onPressed: () => _handleSaveAs(state.outputPath!),
                  ),
                  AppButton(
                    label: 'Share',
                    variant: AppButtonVariant.secondary,
                    icon: Icons.share_rounded,
                    onPressed: () {
                      if (state.outputPath != null) {
                        _fileService.shareFile(state.outputPath!);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              TextButton(
                onPressed: controller.reset,
                child: Text(
                  'Arrange Another PDF',
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    color: AppColors.secondary(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfPagePreviewDialog extends ConsumerStatefulWidget {
  final int initialIndex;

  const _PdfPagePreviewDialog({required this.initialIndex});

  @override
  ConsumerState<_PdfPagePreviewDialog> createState() => _PdfPagePreviewDialogState();
}

class _PdfPagePreviewDialogState extends ConsumerState<_PdfPagePreviewDialog> {
  late int _currentIndex;
  Uint8List? _highResImage;
  bool _isLoadingHighRes = false;
  final PdfThumbnailService _thumbnailService = PdfThumbnailService();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _loadHighResPage();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHighResPage() async {
    final state = ref.read(pdfPageManagerControllerProvider);
    if (state.fileBytes == null || _currentIndex < 0 || _currentIndex >= state.pages.length) return;

    final page = state.pages[_currentIndex];
    setState(() {
      _isLoadingHighRes = true;
      _highResImage = null;
    });

    try {
      final highRes = await _thumbnailService.renderPage(
        state.fileBytes!,
        page.originalIndex,
        targetDpi: 150,
        format: pdfx.PdfPageImageFormat.jpeg,
      );
      if (mounted) {
        setState(() {
          _highResImage = highRes;
          _isLoadingHighRes = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingHighRes = false;
        });
      }
    }
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
      _loadHighResPage();
    }
  }

  void _goToNext() {
    final state = ref.read(pdfPageManagerControllerProvider);
    if (_currentIndex < state.pages.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _loadHighResPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfPageManagerControllerProvider);
    final controller = ref.read(pdfPageManagerControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;

    if (_currentIndex >= state.pages.length) {
      _currentIndex = math.max(0, state.pages.length - 1);
    }
    if (state.pages.isEmpty) {
      return const SizedBox.shrink();
    }

    final page = state.pages[_currentIndex];
    final displayImage = _highResImage ?? page.thumbnailBytes;

    return Dialog(
      backgroundColor: AppColors.background(brightness),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side: const BorderSide(color: AppColors.pegGrey, width: 1.0),
      ),
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _goToPrevious();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _goToNext();
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
            }
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // Dialog Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10.0,
                        runSpacing: 6.0,
                        children: [
                          const Icon(Icons.preview_rounded, color: AppColors.anvilTeal),
                          Text(
                            'Page ${_currentIndex + 1} of ${state.pages.length}',
                            style: AppTypography.titleMedium(brightness).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground(brightness),
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: AppColors.pegGrey),
                            ),
                            child: Text(
                              'ORIGINAL PAGE ${page.originalIndex + 1}',
                              style: AppTypography.mono(brightness).copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (page.isDeleted)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                              decoration: BoxDecoration(
                                color: AppColors.rustRed.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4.0),
                                border: Border.all(color: AppColors.rustRed),
                              ),
                              child: Text(
                                'DELETED',
                                style: AppTypography.mono(brightness).copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.rustRed,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close preview (Esc)',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24, thickness: 1, color: AppColors.pegGrey),

                // Preview Body
                Expanded(
                  child: Row(
                    children: [
                      // Previous Page Navigation Button
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 40),
                        tooltip: 'Previous Page (Left Arrow)',
                        color: _currentIndex > 0
                            ? AppColors.text(brightness)
                            : AppColors.disabledText(brightness),
                        onPressed: _currentIndex > 0 ? _goToPrevious : null,
                      ),
                      const SizedBox(width: 8.0),

                      // Main Interactive Zoomable Preview Area
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.5)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 4.0,
                                  child: Center(
                                    child: displayImage != null
                                        ? Transform.rotate(
                                            angle: page.rotation * (math.pi / 180),
                                            child: Image.memory(
                                              displayImage,
                                              fit: BoxFit.contain,
                                            ),
                                          )
                                        : Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.insert_drive_file_outlined,
                                                  size: 48, color: AppColors.pegGrey),
                                              const SizedBox(height: 8.0),
                                              Text(
                                                'Page preview unavailable',
                                                style: AppTypography.bodyMedium(brightness),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                if (_isLoadingHighRes)
                                  Positioned(
                                    top: 16,
                                    right: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.7),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Loading HD...',
                                            style: AppTypography.labelSmall(Brightness.dark).copyWith(
                                              fontSize: 11,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8.0),

                      // Next Page Navigation Button
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 40),
                        tooltip: 'Next Page (Right Arrow)',
                        color: _currentIndex < state.pages.length - 1
                            ? AppColors.text(brightness)
                            : AppColors.disabledText(brightness),
                        onPressed: _currentIndex < state.pages.length - 1 ? _goToNext : null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16.0),

                // Toolbar Actions inside Modal
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12.0,
                  runSpacing: 12.0,
                  children: [
                    Text(
                      'Pinch or scroll to zoom • Use arrow keys to navigate',
                      style: AppTypography.labelSmall(brightness).copyWith(
                        color: AppColors.text(brightness).withValues(alpha: 0.6),
                      ),
                    ),
                    Wrap(
                      spacing: 12.0,
                      runSpacing: 8.0,
                      children: [
                        AppButton(
                          label: 'Rotate (${page.rotation}°)',
                          variant: AppButtonVariant.secondary,
                          icon: Icons.rotate_right_rounded,
                          onPressed: () => controller.rotatePage(_currentIndex),
                        ),
                        AppButton(
                          label: page.isDeleted ? 'Undo Deletion' : 'Delete Page',
                          variant: page.isDeleted
                              ? AppButtonVariant.secondary
                              : AppButtonVariant.destructive,
                          icon: page.isDeleted
                              ? Icons.undo_rounded
                              : Icons.delete_outline_rounded,
                          onPressed: () => controller.togglePageDeleted(_currentIndex),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

