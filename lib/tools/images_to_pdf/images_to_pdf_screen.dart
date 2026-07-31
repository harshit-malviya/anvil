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
import '../../core/widgets/theme_toggle_button.dart';
import '../registry.dart';
import 'images_to_pdf_controller.dart';
import 'images_to_pdf_state.dart';

class ImagesToPdfScreen extends ConsumerStatefulWidget {
  const ImagesToPdfScreen({super.key});

  @override
  ConsumerState<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends ConsumerState<ImagesToPdfScreen> {
  final FileService _fileService = FileService();

  Future<void> _handleConvert(Color familyAccent) async {
    final controller = ref.read(imagesToPdfControllerProvider.notifier);
    await showTaskProgressDialog<String>(
      context: context,
      title: 'Creating PDF',
      defaultMessage: 'Combining images into a single PDF document…',
      color: familyAccent,
      getMessage: () => ref.read(imagesToPdfControllerProvider).progressMessage ?? 'Combining images…',
      task: () => controller.createPdf(),
    );
  }

  Future<void> _pickAndAddImages() async {
    final pickedFiles = await _fileService.pickImageFiles(allowMultiple: true);
    if (pickedFiles.isNotEmpty && mounted) {
      ref.read(imagesToPdfControllerProvider.notifier).addImages(pickedFiles);
    }
  }

  Future<void> _handleSaveAs(String currentOutputPath, Color familyAccent) async {
    final bytes = <int>[];
    try {
      final f = File(currentOutputPath);
      if (f.existsSync()) {
        bytes.addAll(await f.readAsBytes());
      }
    } catch (_) {}

    final savedPath = await _fileService.saveFile(
      defaultFileName: p.basename(currentOutputPath),
      bytes: bytes,
    );

    if (savedPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File saved to $savedPath'),
          backgroundColor: familyAccent,
        ),
      );
    }
  }

  void _showImagePreviewDialog(BuildContext context, ImageFileItem item) {
    final brightness = Theme.of(context).brightness;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.background(brightness),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        insetPadding: const EdgeInsets.all(24.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          style: AppTypography.titleMedium(brightness).copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          '${item.width} × ${item.height} px • ${_formatBytes(item.fileSizeBytes)}',
                          style: AppTypography.mono(brightness).copyWith(
                            fontSize: 12,
                            color: AppColors.text(brightness).withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24.0),

              // Image Preview Area
              Expanded(
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.memory(
                      item.bytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16.0),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Close Preview',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imagesToPdfControllerProvider);
    final controller = ref.read(imagesToPdfControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final familyAccent = AppColors.familyAccent(ToolCategory.pdf, brightness);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
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
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
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
                    ? _buildSuccessView(context, state, controller, familyAccent)
                    : state.images.isEmpty
                        ? _buildEmptyDropZone(context, familyAccent)
                        : _buildImageGridView(context, state, controller, familyAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String errorMessage, ImagesToPdfController controller) {
    final brightness = Theme.of(context).brightness;
    final primaryColor = AppColors.primary(brightness);
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: primaryColor),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              errorMessage,
              style: AppTypography.bodySmall(brightness).copyWith(color: primaryColor),
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

  Widget _buildEmptyDropZone(BuildContext context, Color familyAccent) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickAndAddImages,
          label: 'Drop image files here or click to browse',
          sublabel: 'Select one or more image files to combine into a single PDF',
          icon: Icons.add_photo_alternate_outlined,
          color: familyAccent,
        ),
      ),
    );
  }

  Widget _buildImageGridView(BuildContext context, ImagesToPdfState state, ImagesToPdfController controller, Color familyAccent) {
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
                      foregroundColor: familyAccent,
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

        // Grid View of Image Cards
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: state.images.length,
            itemBuilder: (context, index) {
              final item = state.images[index];
              return _buildImageCard(context, index, item, state, brightness, controller, familyAccent);
            },
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
            color: familyAccent,
            onPressed: state.canSubmit ? () => _handleConvert(familyAccent) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildImageCard(
    BuildContext context,
    int index,
    ImageFileItem item,
    ImagesToPdfState state,
    Brightness brightness,
    ImagesToPdfController controller,
    Color familyAccent,
  ) {
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
            // Top Badge & Move Controls
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
                    'PAGE ${index + 1}',
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
                        borderRadius: BorderRadius.circular(4.0),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(Icons.arrow_left_rounded,
                              size: 20, color: AppColors.text(brightness).withValues(alpha: 0.7)),
                        ),
                      ),
                    if (index < state.images.length - 1)
                      InkWell(
                        onTap: () => controller.reorderImages(index, index + 2),
                        borderRadius: BorderRadius.circular(4.0),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Icon(Icons.arrow_right_rounded,
                              size: 20, color: AppColors.text(brightness).withValues(alpha: 0.7)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6.0),

            // Image Thumbnail Preview with Clickable Preview Action
            Expanded(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => _showImagePreviewDialog(context, item),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6.0),
                      child: Container(
                        width: double.infinity,
                        color: Colors.black12,
                        child: Image.memory(
                          item.thumbnail,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4.0),
                      child: InkWell(
                        onTap: () => _showImagePreviewDialog(context, item),
                        borderRadius: BorderRadius.circular(4.0),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.visibility_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6.0),

            // File Info
            Text(
              item.fileName,
              style: AppTypography.bodyMedium(brightness).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            Text(
              '${item.width} × ${item.height} px • ${_formatBytes(item.fileSizeBytes)}',
              style: AppTypography.mono(brightness).copyWith(
                fontSize: 10,
                color: AppColors.text(brightness).withValues(alpha: 0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6.0),

            // Remove Button
            InkWell(
              onTap: () => controller.removeImage(item.id),
              borderRadius: BorderRadius.circular(4.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                decoration: BoxDecoration(
                  color: AppColors.rustRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.close_rounded, size: 14, color: AppColors.rustRed),
                    const SizedBox(width: 4),
                    Text(
                      'Remove',
                      style: AppTypography.bodySmall(brightness).copyWith(
                        fontSize: 11,
                        color: AppColors.rustRed,
                        fontWeight: FontWeight.w500,
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

  Widget _buildSuccessView(BuildContext context, ImagesToPdfState state, ImagesToPdfController controller, Color familyAccent) {
    final brightness = Theme.of(context).brightness;
    final outputPath = state.outputPath!;
    final fileName = p.basename(outputPath);

    return Center(
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32.0),
              StampAnimation(
                label: 'CREATED',
                color: familyAccent,
              ),
              const SizedBox(height: 24.0),
              Text(
                'PDF Created Successfully!',
                style: AppTypography.displayMedium(brightness),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16.0),
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
                      fileName,
                      style: AppTypography.bodyMedium(brightness).copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Created from ${state.images.length} ${state.images.length == 1 ? "image" : "images"}',
                      style: AppTypography.mono(brightness).copyWith(
                        fontSize: 12.0,
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              Text(
                'Saved to:',
                style: AppTypography.labelSmall(brightness),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6.0),
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
                  outputPath,
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 12.0,
                    color: AppColors.text(brightness),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28.0),
              Wrap(
                spacing: 12.0,
                runSpacing: 12.0,
                alignment: WrapAlignment.center,
                children: [
                  AppButton(
                    label: 'Open Folder',
                    icon: Icons.folder_open_rounded,
                    variant: AppButtonVariant.primary,
                    color: familyAccent,
                    onPressed: () => _fileService.openFolder(p.dirname(outputPath)),
                  ),
                  AppButton(
                    label: 'Save As…',
                    icon: Icons.save_alt_rounded,
                    variant: AppButtonVariant.secondary,
                    color: familyAccent,
                    onPressed: () => _handleSaveAs(outputPath, familyAccent),
                  ),
                  AppButton(
                    label: 'Share',
                    icon: Icons.share_rounded,
                    variant: AppButtonVariant.secondary,
                    color: familyAccent,
                    onPressed: () => _fileService.shareFile(outputPath),
                  ),
                  AppButton(
                    label: 'Create Another PDF',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    color: familyAccent,
                    onPressed: () => controller.clearImages(),
                  ),
                ],
              ),
              const SizedBox(height: 32.0),
            ],
          ),
        ),
      ),
    );
  }

}
