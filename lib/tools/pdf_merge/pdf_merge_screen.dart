import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import '../../core/widgets/task_progress_bar.dart';
import 'pdf_merge_controller.dart';
import 'pdf_merge_state.dart';

class PdfMergeScreen extends ConsumerStatefulWidget {
  const PdfMergeScreen({super.key});

  @override
  ConsumerState<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _PdfMergeScreenState extends ConsumerState<PdfMergeScreen> {
  final FileService _fileService = FileService();

  Future<void> _pickAndAddFiles() async {
    final pickedFiles = await _fileService.pickPdfFiles(allowMultiple: true);
    if (pickedFiles.isNotEmpty && mounted) {
      await ref.read(pdfMergeControllerProvider.notifier).addFiles(pickedFiles);
    }
  }

  Future<void> _handleSaveAs(String currentOutputPath) async {
    final state = ref.read(pdfMergeControllerProvider);

    // Save as dialog
    final savedPath = await _fileService.saveFile(
      defaultFileName: currentOutputPath.split(RegExp(r'[/\\]')).last,
      bytes: state.files.fold<List<int>>([], (prev, elem) => prev), // fallback
    );

    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved to $savedPath'),
          backgroundColor: AppColors.anvilTeal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfMergeControllerProvider);
    final controller = ref.read(pdfMergeControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text(brightness)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Merge PDFs',
          style: AppTypography.displayMedium(brightness),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TaskProgressBar(
                isVisible: state.isProcessing,
                message: state.progressMessage ?? 'Merging PDFs…',
              ),
              if (state.errorMessage != null) _buildErrorBanner(context, state.errorMessage!, controller),
              Expanded(
                child: state.outputPath != null
                    ? _buildSuccessView(context, state, controller)
                    : state.files.isEmpty
                        ? _buildEmptyDropZone(context)
                        : _buildFileList(context, state, controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message, PdfMergeController controller) {
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
          const Icon(Icons.error_outline_rounded, color: AppColors.rustRed, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unable to process file',
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.rustRed,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    color: AppColors.text(brightness),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => controller.clearError(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDropZone(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickAndAddFiles,
          label: 'Drop PDF files here or click to browse',
          sublabel: 'Select 2 or more PDF documents to merge into a single file',
          icon: Icons.picture_as_pdf_outlined,
        ),
      ),
    );
  }

  Widget _buildFileList(BuildContext context, PdfMergeState state, PdfMergeController controller) {
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${state.files.length} ${state.files.length == 1 ? 'file' : 'files'} added',
              style: AppTypography.titleMedium(brightness),
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: state.isProcessing ? null : _pickAndAddFiles,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add More'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary(brightness),
                    side: BorderSide(color: AppColors.primary(brightness)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.0)),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: state.isProcessing ? null : () => controller.removeAll(),
                  child: Text(
                    'Clear All',
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      color: AppColors.rustRed,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              controller.reorderFiles(oldIndex, newIndex);
            },
            itemCount: state.files.length,
            itemBuilder: (context, index) {
              final item = state.files[index];
              return _buildFileRow(context, item, index, controller, brightness, key: ValueKey(item.id));
            },
          ),
        ),
        const SizedBox(height: 16),
        if (state.isProcessing) ...[
          LinearProgressIndicator(
            color: AppColors.primary(brightness),
            backgroundColor: AppColors.pegGrey.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            state.progressMessage ?? 'Merging PDFs…',
            style: AppTypography.mono(brightness),
          ),
          const SizedBox(height: 16),
        ],
        _buildBottomActionBar(context, state, controller, brightness),
      ],
    );
  }

  Widget _buildFileRow(
    BuildContext context,
    PdfMergeItem item,
    int index,
    PdfMergeController controller,
    Brightness brightness, {
    required Key key,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(
          color: AppColors.pegGrey.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'Drag to reorder',
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: AppColors.text(brightness).withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary(brightness).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Icon(
              Icons.picture_as_pdf_rounded,
              color: AppColors.primary(brightness),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.pageCount} ${item.pageCount == 1 ? 'page' : 'pages'} • ${item.formattedSize}',
                  style: AppTypography.mono(brightness).copyWith(
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => controller.removeFile(item.id),
            tooltip: 'Remove file',
          ),
          const SizedBox(width: 8),
          ReorderableDragStartListener(
            index: index,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Tooltip(
                message: 'Drag to reorder',
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(
                    Icons.reorder_rounded,
                    size: 20,
                    color: AppColors.text(brightness).withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(
    BuildContext context,
    PdfMergeState state,
    PdfMergeController controller,
    Brightness brightness,
  ) {
    return Column(
      children: [
        if (state.files.length < 2) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.sparkYellow.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.sparkYellow),
                const SizedBox(width: 8),
                Text(
                  'Add at least 2 PDFs to merge',
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          height: 48,
          child: AppButton(
            label: 'Merge ${state.files.length} PDFs',
            isLoading: state.isProcessing,
            onPressed: state.canMerge ? () => controller.merge() : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    PdfMergeState state,
    PdfMergeController controller,
  ) {
    final brightness = Theme.of(context).brightness;
    final outputPath = state.outputPath!;

    return Center(
      child: MaxWidthContainer(
        maxWidth: 550,
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            color: AppColors.cardBackground(brightness),
            borderRadius: BorderRadius.circular(6.0),
            border: Border.all(
              color: AppColors.primary(brightness).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const StampAnimation(label: 'DONE'),
              const SizedBox(height: 24),
              Text(
                'PDFs Merged Successfully!',
                style: AppTypography.displayMedium(brightness),
                textAlign: TextAlign.center,
              ),
              Text(
                'Saved to:',
                style: AppTypography.labelSmall(brightness),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.pegGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  outputPath,
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  AppButton(
                    label: 'Open Folder',
                    variant: AppButtonVariant.primary,
                    icon: Icons.folder_open_rounded,
                    onPressed: () => _fileService.openFolder(p.dirname(outputPath)),
                  ),
                  AppButton(
                    label: 'Save As',
                    variant: AppButtonVariant.secondary,
                    icon: Icons.save_alt_rounded,
                    onPressed: () => _handleSaveAs(outputPath),
                  ),
                  AppButton(
                    label: 'Share',
                    variant: AppButtonVariant.secondary,
                    icon: Icons.share_rounded,
                    onPressed: () => _fileService.shareFile(outputPath),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => controller.removeAll(),
                child: Text(
                  'Merge Another Batch',
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    color: AppColors.primary(brightness),
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

class MaxWidthContainer extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const MaxWidthContainer({
    super.key,
    required this.maxWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
