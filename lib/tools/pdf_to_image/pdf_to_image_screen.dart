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
import '../../core/widgets/task_progress_bar.dart';
import 'pdf_to_image_controller.dart';
import 'pdf_to_image_state.dart';

class PdfToImageScreen extends ConsumerStatefulWidget {
  const PdfToImageScreen({super.key});

  @override
  ConsumerState<PdfToImageScreen> createState() => _PdfToImageScreenState();
}

class _PdfToImageScreenState extends ConsumerState<PdfToImageScreen> {
  final FileService _fileService = FileService();

  Future<void> _pickFile() async {
    final files = await _fileService.pickPdfFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(pdfToImageControllerProvider.notifier).loadDocument(files.first);
    }
  }

  Future<void> _handleSaveAs(PdfToImageState state) async {
    if (state.outputPath == null) return;
    final sourcePath = state.outputPath!;

    if (state.isSingleFileExport) {
      final sourceFile = File(sourcePath);
      if (sourceFile.existsSync()) {
        final bytes = await sourceFile.readAsBytes();
        final defaultName = p.basename(sourcePath);
        final savedPath = await _fileService.saveFile(
          defaultFileName: defaultName,
          bytes: bytes,
        );
        if (savedPath != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to $savedPath'),
              backgroundColor: AppColors.anvilTeal,
            ),
          );
        }
      }
    } else {
      final targetDir = await _fileService.pickDirectory(
        dialogTitle: 'Select destination folder for exported images',
      );
      if (targetDir != null && targetDir.isNotEmpty && mounted) {
        try {
          final srcDir = Directory(sourcePath);
          if (srcDir.existsSync()) {
            final destDir = Directory(targetDir);
            if (!destDir.existsSync()) {
              destDir.createSync(recursive: true);
            }
            final files = srcDir.listSync().whereType<File>().toList();
            int copiedCount = 0;
            for (final f in files) {
              final targetPath = p.join(destDir.path, p.basename(f.path));
              f.copySync(targetPath);
              copiedCount++;
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved $copiedCount image files to $targetDir'),
                  backgroundColor: AppColors.anvilTeal,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not save files: $e'),
                backgroundColor: AppColors.rustRed,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _handleShare(PdfToImageState state) async {
    if (state.outputPath == null) return;
    final outputPath = state.outputPath!;

    if (state.isSingleFileExport) {
      if (File(outputPath).existsSync()) {
        await _fileService.shareFile(outputPath);
      }
    } else {
      final dir = Directory(outputPath);
      if (dir.existsSync()) {
        final imgPaths = dir
            .listSync()
            .whereType<File>()
            .where((f) {
              final ext = p.extension(f.path).toLowerCase();
              return ext == '.png' || ext == '.jpeg' || ext == '.jpg';
            })
            .map((f) => f.path)
            .toList();

        if (imgPaths.isNotEmpty) {
          await _fileService.shareMultipleFiles(imgPaths);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = ref.watch(pdfToImageControllerProvider);
    final controller = ref.read(pdfToImageControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'PDF to Image',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(brightness)),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (state.isLoaded)
            IconButton(
              tooltip: 'Reset',
              icon: const Icon(Icons.refresh),
              onPressed: controller.reset,
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
                message: state.progressMessage ?? 'Exporting images…',
                progressPercent: state.progressPercent,
              ),
              if (state.errorMessage != null)
                _buildErrorBanner(context, state.errorMessage!, brightness, controller),
              Expanded(
                child: !state.isLoaded
                    ? _buildEmptyDropZone(brightness)
                    : state.outputPath != null
                        ? _buildSuccessView(context, state, brightness, controller)
                        : _buildMainContent(context, state, brightness, controller),
              ),
              if (state.isLoaded && state.outputPath == null)
                _buildBottomSummaryBar(context, state, brightness, controller),
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
    PdfToImageController controller,
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

  Widget _buildEmptyDropZone(Brightness brightness) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickFile,
          label: 'Drop PDF file here or click to browse',
          sublabel: 'Select a PDF document to convert to images',
          icon: Icons.image_outlined,
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    PdfToImageState state,
    Brightness brightness,
    PdfToImageController controller,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // File Summary Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground(brightness),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary(brightness).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.picture_as_pdf, color: AppColors.primary(brightness), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.file?.name ?? 'Document.pdf',
                            style: AppTypography.titleMedium(brightness),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${state.totalPageCount} ${state.totalPageCount == 1 ? 'page' : 'pages'}',
                            style: AppTypography.labelSmall(brightness),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: state.isProcessing ? null : _pickFile,
                      icon: Icon(Icons.swap_horiz, size: 18, color: AppColors.primary(brightness)),
                      label: Text(
                        'Change file',
                        style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.primary(brightness)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Controls Panel (Format & Resolution options)
              _buildControlsPanel(context, state, controller),
              const SizedBox(height: 24),

              // Page Selection Header & Actions
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Select Pages',
                        style: AppTypography.titleMedium(brightness),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary(brightness).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${state.selectedCount} / ${state.totalPageCount} selected',
                          style: AppTypography.labelSmall(brightness).copyWith(
                            color: AppColors.primary(brightness),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: state.isProcessing ? null : controller.selectAll,
                        child: Text(
                          'Select All',
                          style: AppTypography.labelSmall(brightness).copyWith(
                            color: state.isProcessing
                                ? AppColors.disabledText(brightness)
                                : AppColors.primary(brightness),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: state.isProcessing ? null : controller.selectNone,
                        child: Text(
                          'Select None',
                          style: AppTypography.labelSmall(brightness).copyWith(
                            color: state.isProcessing
                                ? AppColors.disabledText(brightness)
                                : AppColors.text(brightness),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Page Thumbnail Grid
              if (state.isLoadingThumbnails && state.thumbnails.isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary(brightness)),
                  ),
                ),
              ] else ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: state.totalPageCount,
                  itemBuilder: (context, index) {
                    final isSelected = state.selectedPages.contains(index);
                    final thumbBytes = state.thumbnails[index];

                    return InkWell(
                      onTap: state.isProcessing ? null : () => controller.togglePageSelected(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground(brightness),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppColors.primary(brightness) : AppColors.pegGrey.withValues(alpha: 0.5),
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary(brightness).withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Stack(
                          children: [
                            // Thumbnail Content
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: thumbBytes != null
                                    ? Image.memory(thumbBytes, fit: BoxFit.cover)
                                    : Container(
                                        color: AppColors.pegGrey.withValues(alpha: 0.2),
                                        child: Icon(
                                          Icons.image_outlined,
                                          color: AppColors.text(brightness).withValues(alpha: 0.5),
                                          size: 32,
                                        ),
                                      ),
                              ),
                            ),

                            // Selection overlay dimmer if unselected
                            if (!isSelected)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.background(brightness).withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),

                            // Checkbox overlay at top left
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary(brightness)
                                      : AppColors.cardBackground(brightness).withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary(brightness) : AppColors.pegGrey,
                                    width: 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                                    : null,
                              ),
                            ),

                            // Page label badge at bottom
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.cardBackground(brightness).withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  'Page ${index + 1}',
                                  style: AppTypography.labelSmall(brightness).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsPanel(
    BuildContext context,
    PdfToImageState state,
    PdfToImageController controller,
  ) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Format Selector
          Text('Image Format', style: AppTypography.titleMedium(brightness)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: ImageFormat.values.map((fmt) {
              final isSelected = state.format == fmt;
              return InkWell(
                onTap: state.isProcessing ? null : () => controller.setFormat(fmt),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary(brightness) : AppColors.background(brightness),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.primary(brightness) : AppColors.pegGrey.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    fmt.label,
                    style: AppTypography.labelSmall(brightness).copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.text(brightness),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // Helper text for JPEG format
          if (state.format == ImageFormat.jpeg) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppColors.text(brightness).withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "JPEG doesn't support transparency and may soften fine text",
                    style: AppTypography.labelSmall(brightness).copyWith(
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),
          Divider(color: AppColors.pegGrey.withValues(alpha: 0.3), height: 1),
          const SizedBox(height: 20),

          // Resolution Selector
          Text('Output Resolution', style: AppTypography.titleMedium(brightness)),
          const SizedBox(height: 12),

          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              return isNarrow
                  ? Column(
                      children: ExportResolution.values
                          .map((res) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildResolutionCard(context, res, state, controller),
                              ))
                          .toList(),
                    )
                  : Row(
                      children: ExportResolution.values
                          .map((res) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: _buildResolutionCard(context, res, state, controller),
                                ),
                              ))
                          .toList(),
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionCard(
    BuildContext context,
    ExportResolution res,
    PdfToImageState state,
    PdfToImageController controller,
  ) {
    final brightness = Theme.of(context).brightness;
    final isSelected = state.resolution == res;
    final dimensionsText = state.estimatedDimensionsText(res);

    return InkWell(
      onTap: state.isProcessing ? null : () => controller.setResolution(res),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary(brightness).withValues(alpha: 0.1) : AppColors.background(brightness),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary(brightness) : AppColors.pegGrey.withValues(alpha: 0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  res.label,
                  style: AppTypography.titleMedium(brightness).copyWith(
                    color: isSelected ? AppColors.primary(brightness) : AppColors.text(brightness),
                    fontSize: 15,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: AppColors.primary(brightness), size: 18),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              res.sublabel,
              style: AppTypography.labelSmall(brightness),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.cardBackground(brightness),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.5)),
              ),
              child: Text(
                dimensionsText.split(' — ').last,
                style: AppTypography.mono(brightness).copyWith(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSummaryBar(
    BuildContext context,
    PdfToImageState state,
    Brightness brightness,
    PdfToImageController controller,
  ) {
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
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
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
                        state.summaryText,
                        style: AppTypography.bodyMedium(brightness).copyWith(
                          color: state.selectedCount > 0 ? AppColors.text(brightness) : AppColors.rustRed,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (state.isProcessing && state.progressMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          state.progressMessage!,
                          style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.primary(brightness)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AppButton(
                  label: state.isProcessing ? 'Exporting…' : 'Export Images',
                  icon: state.isProcessing ? null : Icons.download_rounded,
                  variant: AppButtonVariant.primary,
                  isLoading: state.isProcessing,
                  onPressed: state.canExport ? () => controller.export() : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    PdfToImageState state,
    Brightness brightness,
    PdfToImageController controller,
  ) {
    final outputPath = state.outputPath!;
    final dirOrFileName = p.basename(outputPath);

    String successMessage;
    if (state.isSingleFileExport) {
      successMessage = '1 image exported to $dirOrFileName';
    } else {
      successMessage = '${state.exportedCount} images exported to $dirOrFileName/';
    }

    String? skippedNote;
    if (state.skippedPages.isNotEmpty) {
      if (state.skippedPages.length == 1) {
        skippedNote =
            '${state.exportedCount} of ${state.selectedCount} pages exported. Page ${state.skippedPages.first} couldn\'t be rendered and was skipped.';
      } else {
        skippedNote =
            '${state.exportedCount} of ${state.selectedCount} pages exported. Pages ${state.skippedPages.join(', ')} couldn\'t be rendered and were skipped.';
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const StampAnimation(label: 'EXPORTED'),
            const SizedBox(height: 24),
            Text(
              'Export Complete',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              successMessage,
              style: AppTypography.bodyMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
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
                outputPath,
                style: AppTypography.mono(brightness).copyWith(
                  fontSize: 12,
                  color: AppColors.text(brightness),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (skippedNote != null) ...[
              const SizedBox(height: 8),
              Text(
                skippedNote,
                style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.sparkYellow),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 28),

            // Final Action Buttons matching all other tools (Open Folder, Save As..., Share, Convert Another PDF)
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
                    final folder = state.isSingleFileExport ? p.dirname(outputPath) : outputPath;
                    _fileService.openFolder(folder);
                  },
                ),
                AppButton(
                  label: 'Save As…',
                  icon: Icons.save_alt_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _handleSaveAs(state),
                ),
                AppButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _handleShare(state),
                ),
                AppButton(
                  label: 'Convert Another PDF',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  onPressed: controller.reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
