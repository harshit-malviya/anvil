import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import '../../core/widgets/task_progress_bar.dart';
import 'pdf_insert_pages_controller.dart';
import 'pdf_insert_pages_state.dart';

class PdfInsertPagesScreen extends ConsumerStatefulWidget {
  const PdfInsertPagesScreen({super.key});

  @override
  ConsumerState<PdfInsertPagesScreen> createState() => _PdfInsertPagesScreenState();
}

class _PdfInsertPagesScreenState extends ConsumerState<PdfInsertPagesScreen> {
  final FileService _fileService = FileService();
  late final ScrollController _targetScrollController;
  late final ScrollController _sourceScrollController;
  late final TextEditingController _pageInputController;
  bool _isTargetGridExpanded = false;
  bool _isSourceGridExpanded = false;

  @override
  void initState() {
    super.initState();
    _targetScrollController = ScrollController();
    _sourceScrollController = ScrollController();
    _pageInputController = TextEditingController();
  }

  @override
  void dispose() {
    _targetScrollController.dispose();
    _sourceScrollController.dispose();
    _pageInputController.dispose();
    super.dispose();
  }

  void _scrollToTargetIndex(int index, int totalPages) {
    if (!_targetScrollController.hasClients) return;
    const itemWidth = 170.0;
    final targetOffset = ((index + 1) * itemWidth).clamp(0.0, _targetScrollController.position.maxScrollExtent);
    _targetScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pickTargetFile() async {
    final files = await _fileService.pickPdfFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(pdfInsertPagesControllerProvider.notifier).loadTargetDocument(files.first);
    }
  }

  Future<void> _pickSourceFile() async {
    final files = await _fileService.pickPdfFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(pdfInsertPagesControllerProvider.notifier).loadSourceDocument(files.first);
    }
  }

  Future<void> _handleInsert() async {
    final controller = ref.read(pdfInsertPagesControllerProvider.notifier);
    await controller.insertPages();
  }

  Future<void> _openOutputFolder(String filePath) async {
    final dir = p.dirname(filePath);
    await _fileService.openFolder(dir);
  }

  Future<void> _handleSaveAs(String currentFilePath) async {
    final fileName = p.basename(currentFilePath);
    final targetPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save inserted PDF as',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (targetPath != null && mounted) {
      try {
        final src = File(currentFilePath);
        await src.copy(targetPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved file to $targetPath'),
              backgroundColor: AppColors.anvilTeal,
            ),
          );
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = ref.watch(pdfInsertPagesControllerProvider);
    final controller = ref.read(pdfInsertPagesControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Insert Pages',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.hasTarget || state.hasSource)
            IconButton(
              tooltip: 'Reset All',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _pageInputController.clear();
                controller.clearTarget();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TaskProgressBar(
                isVisible: state.isProcessing,
                message: state.progressMessage ?? 'Inserting pages…',
              ),
              if (state.errorMessage != null)
                _buildErrorBanner(context, state.errorMessage!, brightness, controller),
              Expanded(
                child: state.outputPath != null
                    ? _buildSuccessState(context, state, brightness, controller)
                    : _buildMainContent(context, state, brightness, controller),
              ),
              if (state.hasTarget && state.outputPath == null)
                _buildBottomSummaryBar(context, state, brightness),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    String message,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rustRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: AppColors.rustRed, width: 4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.rustRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium(brightness).copyWith(
                color: AppColors.text(brightness),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: controller.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessState(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const StampAnimation(label: 'PAGES INSERTED'),
            const SizedBox(height: 24),
            Text(
              'Pages Inserted Successfully!',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: AppColors.cardBackground(brightness),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: AppColors.pegGrey),
              ),
              child: Column(
                children: [
                  Text(
                    state.targetFile?.name ?? 'Updated PDF Document',
                    style: AppTypography.bodyLarge(brightness).copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Inserted ${state.selectedSourceCount} ${state.selectedSourceCount == 1 ? "page" : "pages"} → ${state.totalResultPageCount} pages total',
                    style: AppTypography.mono(brightness).copyWith(
                      fontSize: 12.0,
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Saved to:',
              style: AppTypography.labelSmall(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxWidth: 520),
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
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                AppButton(
                  label: 'Open Folder',
                  icon: Icons.folder_open_rounded,
                  variant: AppButtonVariant.primary,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _openOutputFolder(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Save As…',
                  icon: Icons.save_alt_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _handleSaveAs(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _fileService.shareFile(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Insert Into Another PDF',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    _pageInputController.clear();
                    controller.clearTarget();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    if (!state.hasTarget) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
          child: FileDropZone(
            onTap: _pickTargetFile,
            label: 'Drop PDF to insert into',
            sublabel: 'Step 1 — Pick target PDF document',
            icon: Icons.post_add_rounded,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // STEP 1: Target Document Header & Grid
          _buildTargetHeader(context, state, brightness, controller),
          const SizedBox(height: 12),
          _buildTargetInsertionBar(context, state, brightness, controller),
          const SizedBox(height: 12),
          SizedBox(
            height: _isTargetGridExpanded ? 380 : 230,
            child: _buildTargetThumbnailGrid(context, state, brightness, controller),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // STEP 2: Source Document Picker / Header & Grid
          if (!state.hasSource)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 180),
                child: FileDropZone(
                  onTap: _pickSourceFile,
                  label: 'Drop PDF to insert pages from',
                  sublabel: 'Step 2 — Pick source PDF containing pages to insert',
                  icon: Icons.library_add_rounded,
                ),
              ),
            )
          else ...[
            _buildSourceHeader(context, state, brightness, controller),
            const SizedBox(height: 12),
            _buildSourceSelectionBar(context, state, brightness, controller),
            const SizedBox(height: 12),
            SizedBox(
              height: _isSourceGridExpanded ? 380 : 230,
              child: _buildSourceThumbnailGrid(context, state, brightness, controller),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetHeader(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.pegGrey),
      ),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf, color: AppColors.primary(brightness)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.emberCopper.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'TARGET PDF',
                        style: AppTypography.labelSmall(brightness).copyWith(
                          fontSize: 10,
                          color: AppColors.emberCopper,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.targetFile?.name ?? 'Target Document',
                        style: AppTypography.bodyLarge(brightness).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.targetPageCount} pages',
                  style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _pickTargetFile,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Change Target'),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInsertionBar(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    final currentVal = state.insertionPoint == -1 ? 0 : state.insertionPoint + 1;
    if (_pageInputController.text != currentVal.toString() && !_pageInputController.selection.isValid) {
      _pageInputController.text = currentVal.toString();
    }

    String positionLabel;
    if (state.insertionPoint == -1) {
      positionLabel = 'At start (before Page 1)';
    } else if (state.insertionPoint == state.targetPageCount - 1) {
      positionLabel = 'At end (after Page ${state.targetPageCount})';
    } else {
      positionLabel = 'After Page ${state.insertionPoint + 1}';
    }

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'INSERTION POINT:',
              style: AppTypography.labelSmall(brightness),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.anvilTeal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.anvilTeal),
              ),
              child: Text(
                positionLabel,
                style: AppTypography.mono(brightness).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.anvilTeal,
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'After Page:',
              style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 13),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 76,
              height: 36,
              child: TextField(
                controller: _pageInputController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: AppTypography.mono(brightness).copyWith(fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (val) {
                  final pageNum = int.tryParse(val.trim());
                  if (pageNum != null) {
                    int targetIdx;
                    if (pageNum <= 0) {
                      targetIdx = -1;
                    } else if (pageNum >= state.targetPageCount) {
                      targetIdx = state.targetPageCount - 1;
                    } else {
                      targetIdx = pageNum - 1;
                    }
                    controller.setInsertionPoint(targetIdx);
                    _scrollToTargetIndex(targetIdx, state.targetPageCount);
                  }
                },
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '(0=Start, ${state.targetPageCount}=End)',
              style: AppTypography.mono(brightness).copyWith(fontSize: 11, color: AppColors.text(brightness).withValues(alpha: 0.6)),
            ),
          ],
        ),
        SegmentedButton<int>(
          segments: [
            const ButtonSegment<int>(
              value: -1,
              label: Text('At Start'),
            ),
            ButtonSegment<int>(
              value: state.targetPageCount - 1,
              label: const Text('At End'),
            ),
          ],
          selected: {
            if (state.insertionPoint == -1)
              -1
            else if (state.insertionPoint == state.targetPageCount - 1)
              state.targetPageCount - 1
            else
              -99
          },
          onSelectionChanged: (Set<int> newSelection) {
            if (newSelection.first != -99) {
              controller.setInsertionPoint(newSelection.first);
              _scrollToTargetIndex(newSelection.first, state.targetPageCount);
            }
          },
        ),
        IconButton(
          tooltip: _isTargetGridExpanded ? 'Collapse to Horizontal Strip' : 'Expand Grid View',
          icon: Icon(_isTargetGridExpanded ? Icons.view_stream_rounded : Icons.grid_view_rounded),
          onPressed: () {
            setState(() {
              _isTargetGridExpanded = !_isTargetGridExpanded;
            });
          },
        ),
      ],
    );
  }

  Widget _buildTargetThumbnailGrid(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    final hasInsertedBlock = state.hasSource && state.selectedSourceCount > 0;
    final totalGridItems = state.targetPageCount + (hasInsertedBlock ? 1 : 0);

    final gridWidget = GridView.builder(
      controller: _targetScrollController,
      scrollDirection: _isTargetGridExpanded ? Axis.vertical : Axis.horizontal,
      gridDelegate: _isTargetGridExpanded
          ? const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            )
          : const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
      itemCount: totalGridItems,
      itemBuilder: (context, index) {
        int targetIdx;
        bool isPreviewBlock = false;

        final insertionIdx = state.insertionPoint; // -1 to targetPageCount - 1

        if (hasInsertedBlock) {
          final blockPositionInGrid = insertionIdx + 1; // 0 for start (-1 + 1)
          if (index == blockPositionInGrid) {
            isPreviewBlock = true;
            targetIdx = -1;
          } else if (index < blockPositionInGrid) {
            targetIdx = index;
          } else {
            targetIdx = index - 1;
          }
        } else {
          targetIdx = index;
        }

        if (isPreviewBlock) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.anvilTeal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.anvilTeal, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.post_add_rounded,
                  color: AppColors.anvilTeal,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  '+${state.selectedSourceCount} Pages',
                  style: AppTypography.mono(brightness).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.anvilTeal,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'from ${state.sourceFile?.name ?? "Source"}',
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      fontSize: 11,
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        }

        final pageNumber = targetIdx + 1;
        final thumbBytes = (targetIdx >= 0 && targetIdx < state.targetThumbnails.length)
            ? state.targetThumbnails[targetIdx]
            : null;
        final isInsertionAnchor = (state.insertionPoint == targetIdx);

        return GestureDetector(
          onTap: () {
            controller.setInsertionPoint(targetIdx);
            _scrollToTargetIndex(targetIdx, state.targetPageCount);
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground(brightness),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isInsertionAnchor ? AppColors.emberCopper : AppColors.pegGrey,
                width: isInsertionAnchor ? 2.5 : 1.0,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: thumbBytes != null
                        ? Image.memory(
                            thumbBytes,
                            fit: BoxFit.contain,
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.description_outlined, color: AppColors.pegGrey, size: 28),
                                const SizedBox(height: 4),
                                Text(
                                  'Page $pageNumber',
                                  style: AppTypography.mono(brightness).copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Page $pageNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (isInsertionAnchor)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.emberCopper,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Insert After',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (_isTargetGridExpanded) {
      return Scrollbar(
        controller: _targetScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: gridWidget,
      );
    }

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent && _targetScrollController.hasClients) {
          final scrollDelta = pointerSignal.scrollDelta.dy != 0
              ? pointerSignal.scrollDelta.dy
              : pointerSignal.scrollDelta.dx;
          final newOffset = (_targetScrollController.offset + scrollDelta)
              .clamp(0.0, _targetScrollController.position.maxScrollExtent);
          _targetScrollController.jumpTo(newOffset);
        }
      },
      child: Scrollbar(
        controller: _targetScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: gridWidget,
      ),
    );
  }

  Widget _buildSourceHeader(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.anvilTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.anvilTeal.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.library_add_rounded, color: AppColors.anvilTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.anvilTeal.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'SOURCE PDF',
                        style: AppTypography.labelSmall(brightness).copyWith(
                          fontSize: 10,
                          color: AppColors.anvilTeal,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.sourceFile?.name ?? 'Source Document',
                        style: AppTypography.bodyLarge(brightness).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.sourcePageCount} total pages',
                  style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove Source File',
            icon: const Icon(Icons.close_rounded, color: AppColors.rustRed),
            onPressed: controller.clearSource,
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSelectionBar(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    return Row(
      children: [
        Text(
          'SELECT PAGES TO INSERT:',
          style: AppTypography.labelSmall(brightness),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: state.selectedSourceCount > 0
                ? AppColors.anvilTeal.withValues(alpha: 0.15)
                : AppColors.rustRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${state.selectedSourceCount} of ${state.sourcePageCount} selected',
            style: AppTypography.mono(brightness).copyWith(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: state.selectedSourceCount > 0 ? AppColors.anvilTeal : AppColors.rustRed,
            ),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: controller.selectAllSource,
          child: const Text('Select All'),
        ),
        TextButton(
          onPressed: controller.selectNoneSource,
          child: const Text('Select None'),
        ),
        IconButton(
          tooltip: _isSourceGridExpanded ? 'Collapse to Horizontal Strip' : 'Expand Grid View',
          icon: Icon(_isSourceGridExpanded ? Icons.view_stream_rounded : Icons.grid_view_rounded),
          onPressed: () {
            setState(() {
              _isSourceGridExpanded = !_isSourceGridExpanded;
            });
          },
        ),
      ],
    );
  }

  Widget _buildSourceThumbnailGrid(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
    PdfInsertPagesController controller,
  ) {
    final gridWidget = GridView.builder(
      controller: _sourceScrollController,
      scrollDirection: _isSourceGridExpanded ? Axis.vertical : Axis.horizontal,
      gridDelegate: _isSourceGridExpanded
          ? const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            )
          : const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 1,
              mainAxisSpacing: 12,
              childAspectRatio: 1.3,
            ),
      itemCount: state.sourcePageCount,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final isSelected = state.selectedSourcePageIndices.contains(index);
        final thumbBytes = (index >= 0 && index < state.sourceThumbnails.length)
            ? state.sourceThumbnails[index]
            : null;

        return GestureDetector(
          onTap: () => controller.togglePageSelected(index),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground(brightness),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? AppColors.anvilTeal : AppColors.pegGrey,
                width: isSelected ? 2.5 : 1.0,
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: thumbBytes != null
                        ? Image.memory(
                            thumbBytes,
                            fit: BoxFit.contain,
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.description_outlined, color: AppColors.pegGrey, size: 28),
                                const SizedBox(height: 4),
                                Text(
                                  'Page $pageNumber',
                                  style: AppTypography.mono(brightness).copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),

                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.anvilTeal.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),

                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Page $pageNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.anvilTeal : Colors.black.withValues(alpha: 0.46),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isSelected ? Icons.check : Icons.add,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (_isSourceGridExpanded) {
      return Scrollbar(
        controller: _sourceScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: gridWidget,
      );
    }

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent && _sourceScrollController.hasClients) {
          final scrollDelta = pointerSignal.scrollDelta.dy != 0
              ? pointerSignal.scrollDelta.dy
              : pointerSignal.scrollDelta.dx;
          final newOffset = (_sourceScrollController.offset + scrollDelta)
              .clamp(0.0, _sourceScrollController.position.maxScrollExtent);
          _sourceScrollController.jumpTo(newOffset);
        }
      },
      child: Scrollbar(
        controller: _sourceScrollController,
        thumbVisibility: true,
        trackVisibility: true,
        child: gridWidget,
      ),
    );
  }

  Widget _buildBottomSummaryBar(
    BuildContext context,
    PdfInsertPagesState state,
    Brightness brightness,
  ) {
    String summaryText;
    if (!state.hasSource) {
      summaryText = 'Target has ${state.targetPageCount} pages. Load a source PDF to select pages to insert.';
    } else if (state.selectedSourceCount == 0) {
      summaryText = 'Select at least one page from source PDF to insert.';
    } else {
      final pos = state.insertionPoint == -1
          ? 'at start'
          : (state.insertionPoint == state.targetPageCount - 1
              ? 'at end'
              : 'after Page ${state.insertionPoint + 1}');
      summaryText = 'Inserting ${state.selectedSourceCount} pages $pos → Result: ${state.totalResultPageCount} total pages.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SUMMARY',
                  style: AppTypography.labelSmall(brightness),
                ),
                const SizedBox(height: 2),
                Text(
                  summaryText,
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          AppButton(
            label: 'Insert Pages',
            icon: Icons.post_add_rounded,
            variant: AppButtonVariant.primary,
            isLoading: state.isProcessing,
            onPressed: state.canSubmit ? _handleInsert : null,
          ),
        ],
      ),
    );
  }
}
