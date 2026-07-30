import 'dart:io';
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
import '../../core/widgets/task_progress_dialog.dart';
import 'images_to_pdf_controller.dart';
import 'images_to_pdf_state.dart';

class ImagesToPdfScreen extends ConsumerStatefulWidget {
  const ImagesToPdfScreen({super.key});

  @override
  ConsumerState<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends ConsumerState<ImagesToPdfScreen> {
  final FileService _fileService = FileService();

  Future<void> _handleCreatePdf() async {
    final controller = ref.read(imagesToPdfControllerProvider.notifier);
    await showTaskProgressDialog<String>(
      context: context,
      title: 'Creating PDF',
      defaultMessage: 'Creating PDF from images…',
      getMessage: () => ref.read(imagesToPdfControllerProvider).progressMessage ?? 'Creating PDF from images…',
      task: () => controller.createPdf(),
    );
  }

  Future<void> _pickAndAddImages() async {
    final pickedFiles = await _fileService.pickImageFiles(allowMultiple: true);
    if (pickedFiles.isNotEmpty && mounted) {
      await ref.read(imagesToPdfControllerProvider.notifier).addImages(pickedFiles);
    }
  }

  Future<void> _handleSaveAs(String currentOutputPath) async {
    final state = ref.read(imagesToPdfControllerProvider);
    final bytes = state.images.isNotEmpty ? state.images.first.bytes : <int>[];

    final savedPath = await _fileService.saveFile(
      defaultFileName: p.basename(currentOutputPath),
      bytes: bytes,
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imagesToPdfControllerProvider);
    final controller = ref.read(imagesToPdfControllerProvider.notifier);
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
          'Images to PDF',
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
                    : state.images.isEmpty
                        ? _buildEmptyDropZone(context)
                        : _buildImageList(context, state, controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String errorMessage, ImagesToPdfController controller) {
    final brightness = Theme.of(context).brightness;
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: AppColors.emberCopper.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: AppColors.emberCopper.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.emberCopper),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              errorMessage,
              style: AppTypography.bodySmall(brightness).copyWith(color: AppColors.emberCopper),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18.0),
            color: AppColors.text(brightness).withValues(alpha: 0.6),
            onPressed: () => controller.clearError(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDropZone(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
        child: FileDropZone(
          onTap: _pickAndAddImages,
          label: 'Drop images here or click to browse',
          sublabel: 'Supports JPG, JPEG, and PNG images',
          icon: Icons.add_photo_alternate_outlined,
        ),
      ),
    );
  }

  Widget _buildImageList(BuildContext context, ImagesToPdfState state, ImagesToPdfController controller) {
    final brightness = Theme.of(context).brightness;

    return Column(
      children: [
        // List Header Bar
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${state.images.length} ${state.images.length == 1 ? "Image" : "Images"}',
                style: AppTypography.titleMedium(brightness),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _pickAndAddImages,
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 18.0),
                    label: const Text('Add Images'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondary(brightness),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  TextButton.icon(
                    onPressed: () => controller.clearImages(),
                    icon: const Icon(Icons.clear_all_rounded, size: 18.0),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.text(brightness).withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Virtualized Reorderable List
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBackground(brightness),
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: AppColors.pegGrey),
            ),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.all(8.0),
              itemCount: state.images.length,
              onReorderItem: (oldIndex, newIndex) => controller.reorderImages(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = state.images[index];
                return Container(
                  key: ValueKey(item.id),
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  decoration: BoxDecoration(
                    color: AppColors.background(brightness),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: AppColors.pegGrey),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: AppColors.text(brightness).withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6.0),
                          child: Image.memory(
                            item.thumbnail,
                            width: 48.0,
                            height: 48.0,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      item.fileName,
                      style: AppTypography.bodyMedium(brightness),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${item.width} × ${item.height} px • ${_formatBytes(item.fileSizeBytes)}',
                      style: AppTypography.mono(brightness).copyWith(fontSize: 12.0),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20.0),
                      color: AppColors.text(brightness).withValues(alpha: 0.6),
                      onPressed: () => controller.removeImage(item.id),
                      tooltip: 'Remove image',
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 16.0),

        // Action Bar
        SizedBox(
          width: double.infinity,
          height: 48.0,
          child: AppButton(
            label: state.images.length == 1
                ? 'Create PDF'
                : 'Create PDF from ${state.images.length} Images',
            onPressed: state.canSubmit ? _handleCreatePdf : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView(BuildContext context, ImagesToPdfState state, ImagesToPdfController controller) {
    final brightness = Theme.of(context).brightness;
    final outputPath = state.outputPath!;
    final fileName = p.basename(outputPath);

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32.0),
          const StampAnimation(
            label: 'CREATED',
          ),
          const SizedBox(height: 24.0),
          Text(
            'PDF Document Created Successfully',
            style: AppTypography.displayMedium(brightness),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12.0),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: AppColors.cardBackground(brightness),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: AppColors.pegGrey),
            ),
            child: Column(
              children: [
                Text(
                  fileName,
                  style: AppTypography.bodyMedium(brightness).copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4.0),
                Text(
                  outputPath,
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 12.0,
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32.0),
          Wrap(
            spacing: 12.0,
            runSpacing: 12.0,
            alignment: WrapAlignment.center,
            children: [
              AppButton(
                label: 'Save As...',
                icon: Icons.save_alt_rounded,
                onPressed: () => _handleSaveAs(outputPath),
              ),
              AppButton(
                label: 'Open Folder',
                icon: Icons.folder_open_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () => _fileService.openFolder(p.dirname(outputPath)),
              ),
              if (Platform.isAndroid || Platform.isIOS)
                AppButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _fileService.shareFile(outputPath),
                ),
              AppButton(
                label: 'Convert More Images',
                icon: Icons.refresh_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () => controller.clearImages(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
