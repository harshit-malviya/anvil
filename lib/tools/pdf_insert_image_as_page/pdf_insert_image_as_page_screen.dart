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
import '../../core/widgets/task_progress_dialog.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../registry.dart';
import 'pdf_insert_image_as_page_controller.dart';
import 'pdf_insert_image_as_page_state.dart';

class PdfInsertImageAsPageScreen extends ConsumerStatefulWidget {
  const PdfInsertImageAsPageScreen({super.key});

  @override
  ConsumerState<PdfInsertImageAsPageScreen> createState() => _PdfInsertImageAsPageScreenState();
}

class _PdfInsertImageAsPageScreenState extends ConsumerState<PdfInsertImageAsPageScreen> {
  final FileService _fileService = FileService();
  late final ScrollController _targetScrollController;
  late final ScrollController _imageScrollController;
  bool _isTargetGridExpanded = false;

  @override
  void initState() {
    super.initState();
    _targetScrollController = ScrollController();
    _imageScrollController = ScrollController();
  }

  @override
  void dispose() {
    _targetScrollController.dispose();
    _imageScrollController.dispose();
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
      ref.read(pdfInsertImageAsPageControllerProvider.notifier).loadTargetDocument(files.first);
    }
  }

  Future<void> _pickImageFiles() async {
    final files = await _fileService.pickImageFiles(allowMultiple: true);
    if (files.isNotEmpty) {
      ref.read(pdfInsertImageAsPageControllerProvider.notifier).addImages(files);
    }
  }

  Future<void> _handleInsert(Color familyAccent) async {
    final state = ref.read(pdfInsertImageAsPageControllerProvider);
    final count = state.imageCount;
    final defaultMsg = count <= 1
        ? 'Inserting image page into document…'
        : 'Inserting $count image pages into document…';

    await showTaskProgressDialog<String?>(
      context: context,
      title: 'Inserting Images',
      defaultMessage: defaultMsg,
      color: familyAccent,
      task: () => ref.read(pdfInsertImageAsPageControllerProvider.notifier).insertImagePages(),
      getMessage: () => ref.read(pdfInsertImageAsPageControllerProvider).progressMessage ?? defaultMsg,
    );
  }

  Future<void> _openOutputFolder(String filePath) async {
    final dir = p.dirname(filePath);
    await _fileService.openFolder(dir);
  }

  Future<void> _handleSaveAs(String currentFilePath, Color familyAccent) async {
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
              backgroundColor: familyAccent,
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
    final familyAccent = AppColors.familyAccent(ToolCategory.pdf, brightness);
    final state = ref.watch(pdfInsertImageAsPageControllerProvider);
    final controller = ref.read(pdfInsertImageAsPageControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Insert Image as Page',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.hasTarget || state.hasImages)
            IconButton(
              tooltip: 'Reset All',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                controller.clearTarget();
              },
            ),
          const ThemeToggleButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.errorMessage != null)
                _buildErrorBanner(context, state.errorMessage!, brightness, controller),
              Expanded(
                child: state.outputPath != null
                    ? _buildSuccessState(context, state, brightness, controller, familyAccent)
                    : _buildMainContent(context, state, brightness, controller, familyAccent),
              ),
              if (state.hasTarget && state.outputPath == null)
                _buildBottomSummaryBar(context, state, brightness, familyAccent),
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
    PdfInsertImageAsPageController controller,
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
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
    final stampLabel = state.imageCount <= 1 ? 'PAGE INSERTED' : 'PAGES INSERTED';
    final successTitle = state.imageCount <= 1
        ? 'Image Inserted Successfully!'
        : 'Images Inserted Successfully!';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StampAnimation(label: stampLabel, color: familyAccent),
            const SizedBox(height: 24),
            Text(
              successTitle,
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
                border: Border.all(color: familyAccent.withValues(alpha: 0.35)),
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
                    'Inserted ${state.imageCount} ${state.imageCount == 1 ? "image page" : "image pages"} → ${state.totalResultPageCount} pages total',
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
                  color: familyAccent,
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
                  color: familyAccent,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _handleSaveAs(state.outputPath!, familyAccent);
                    }
                  },
                ),
                AppButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  variant: AppButtonVariant.secondary,
                  color: familyAccent,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _fileService.shareFile(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Insert More Images',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  color: familyAccent,
                  onPressed: () {
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
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
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
            color: familyAccent,
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
          _buildTargetHeader(context, state, brightness, controller, familyAccent),
          const SizedBox(height: 12),
          _buildTargetInsertionBar(context, state, brightness, controller, familyAccent),
          const SizedBox(height: 12),
          SizedBox(
            height: _isTargetGridExpanded ? 380 : 230,
            child: _buildTargetThumbnailGrid(context, state, brightness, controller, familyAccent),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // STEP 2: Image Picker / Controls Panel
          if (!state.hasImages)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 180),
                child: FileDropZone(
                  onTap: _pickImageFiles,
                  label: 'Drop image(s) to insert (JPEG or PNG)',
                  sublabel: 'Step 2 — Pick image file(s) to add as page(s)',
                  icon: Icons.add_photo_alternate_rounded,
                  color: familyAccent,
                ),
              ),
            )
          else ...[
            _buildImageSectionHeader(context, state, brightness, controller, familyAccent),
            const SizedBox(height: 12),
            _buildImageCardGrid(context, state, brightness, controller, familyAccent),
            const SizedBox(height: 20),
            _buildPageFitControls(context, state, brightness, controller, familyAccent),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetHeader(
    BuildContext context,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
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
          Icon(Icons.picture_as_pdf, color: familyAccent),
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
                        color: familyAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'TARGET PDF',
                        style: AppTypography.labelSmall(brightness).copyWith(
                          fontSize: 10,
                          color: familyAccent,
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
            icon: Icon(Icons.swap_horiz, size: 18, color: familyAccent),
            label: Text('Change Target', style: TextStyle(color: familyAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInsertionBar(
    BuildContext context,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
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
                color: familyAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: familyAccent),
              ),
              child: Text(
                positionLabel,
                style: AppTypography.mono(brightness).copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: familyAccent,
                ),
              ),
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
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
    final hasInsertedBlock = state.hasImages;
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
          final countLabel = state.imageCount == 1 ? '+1 Image Page' : '+${state.imageCount} Image Pages';
          final firstThumbnail = state.images.isNotEmpty ? state.images.first.thumbnail : null;

          return Container(
            decoration: BoxDecoration(
              color: familyAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: familyAccent, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (firstThumbnail != null) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          firstThumbnail,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: familyAccent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      countLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.add_photo_alternate_rounded,
                    color: familyAccent,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    countLabel,
                    style: AppTypography.mono(brightness).copyWith(
                      fontWeight: FontWeight.bold,
                      color: familyAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
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
                color: isInsertionAnchor ? familyAccent : AppColors.pegGrey,
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
                        color: familyAccent,
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

  Widget _buildImageSectionHeader(
    BuildContext context,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: familyAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: familyAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: familyAccent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'IMAGES TO INSERT',
              style: AppTypography.labelSmall(brightness).copyWith(
                fontSize: 10,
                color: familyAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${state.imageCount} image${state.imageCount == 1 ? '' : 's'})',
            style: AppTypography.mono(brightness).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: familyAccent,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _pickImageFiles,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Images'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: controller.clearImages,
            icon: const Icon(Icons.clear_all, size: 18),
            label: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCardGrid(
    BuildContext context,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: state.images.length,
      itemBuilder: (context, index) {
        final item = state.images[index];
        return _buildImageCard(context, index, item, state, brightness, controller, familyAccent);
      },
    );
  }

  Widget _buildImageCard(
    BuildContext context,
    int index,
    ImageItemState item,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
    final fileSizeKb = (item.file.size / 1024).toStringAsFixed(1);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
        side: const BorderSide(color: AppColors.pegGrey, width: 1.0),
      ),
      color: AppColors.cardBackground(brightness),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Top Badge & Reorder Arrows
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: familyAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    'IMAGE ${index + 1}',
                    style: AppTypography.mono(brightness).copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: familyAccent,
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (index > 0)
                      InkWell(
                        onTap: () => controller.reorderImages(index, index - 1),
                        child: Icon(Icons.arrow_left_rounded,
                            size: 20, color: AppColors.text(brightness).withValues(alpha: 0.6)),
                      ),
                    if (index < state.images.length - 1)
                      InkWell(
                        onTap: () => controller.reorderImages(index, index + 2),
                        child: Icon(Icons.arrow_right_rounded,
                            size: 20, color: AppColors.text(brightness).withValues(alpha: 0.6)),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6.0),

            // Image Thumbnail Preview
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: Image.memory(
                    item.thumbnail,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6.0),

            // File Info
            Text(
              item.file.name,
              style: AppTypography.bodyMedium(brightness).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            Text(
              '${item.width} × ${item.height} px ($fileSizeKb KB)',
              style: AppTypography.mono(brightness).copyWith(
                fontSize: 10,
                color: AppColors.text(brightness).withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6.0),

            // Remove Action Button
            InkWell(
              onTap: () => controller.removeImage(item.id),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.rustRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delete_outline_rounded, size: 14, color: AppColors.rustRed),
                    const SizedBox(width: 4),
                    Text(
                      'Remove',
                      style: AppTypography.labelSmall(brightness).copyWith(
                        fontSize: 10,
                        color: AppColors.rustRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageFitControls(
    BuildContext context,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    PdfInsertImageAsPageController controller,
    Color familyAccent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PAGE FIT MODE',
          style: AppTypography.labelSmall(brightness),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildFitOptionCard(
                context,
                title: 'Match neighboring page',
                subtitle: 'Adopt page size/orientation of neighbor page and scale images to fit (centered, un-distorted).',
                isSelected: state.fitMode == PageFitMode.matchNeighboringPage,
                icon: Icons.aspect_ratio_rounded,
                brightness: brightness,
                familyAccent: familyAccent,
                onTap: () => controller.setPageFitMode(PageFitMode.matchNeighboringPage),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFitOptionCard(
                context,
                title: 'Fit to image',
                subtitle: 'Derive new page dimensions directly from image resolution and aspect ratio.',
                isSelected: state.fitMode == PageFitMode.fitToImage,
                icon: Icons.crop_original_rounded,
                brightness: brightness,
                familyAccent: familyAccent,
                onTap: () => controller.setPageFitMode(PageFitMode.fitToImage),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFitOptionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool isSelected,
    required IconData icon,
    required Brightness brightness,
    required VoidCallback onTap,
    required Color familyAccent,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? familyAccent.withValues(alpha: 0.1)
              : AppColors.cardBackground(brightness),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? familyAccent : AppColors.pegGrey,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? familyAccent : AppColors.text(brightness).withValues(alpha: 0.6),
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? familyAccent : AppColors.text(brightness),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      fontSize: 11,
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSummaryBar(
    BuildContext context,
    PdfInsertImageAsPageState state,
    Brightness brightness,
    Color familyAccent,
  ) {
    String summaryText;
    if (state.insertionPoint == -1) {
      summaryText = 'Inserting at start (before Page 1)';
    } else {
      summaryText = 'Inserting after Page ${state.insertionPoint + 1}';
    }

    final buttonLabel = state.imageCount <= 1
        ? 'Insert Page'
        : 'Insert ${state.imageCount} Pages';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.pegGrey),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.hasImages ? summaryText : 'Select image file(s) to insert as page(s)',
                  style: AppTypography.bodyLarge(brightness).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Output total: ${state.totalResultPageCount} pages',
                  style: AppTypography.mono(brightness).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          AppButton(
            label: buttonLabel,
            icon: Icons.add_photo_alternate_rounded,
            variant: AppButtonVariant.primary,
            color: familyAccent,
            onPressed: state.canSubmit ? () => _handleInsert(familyAccent) : null,
          ),
        ],
      ),
    );
  }
}
