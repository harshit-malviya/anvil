import 'dart:io';
import 'package:file_picker/file_picker.dart';
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
    final sourceFile = File(sourcePath);

    if (state.isSingleFileExport && sourceFile.existsSync()) {
      final ext = state.format.fileExtension;
      final bytes = await sourceFile.readAsBytes();
      final defaultName = p.basename(sourcePath);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Exported Image',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (savedPath != null) {
        final targetFile = File(savedPath);
        await targetFile.writeAsBytes(bytes, flush: true);
      }
    } else {
      final targetDir = await _fileService.pickDirectory(dialogTitle: 'Select Output Directory');
      if (targetDir != null && Directory(sourcePath).existsSync()) {
        final sourceDir = Directory(sourcePath);
        final files = sourceDir.listSync();
        final destFolder = Directory(p.join(targetDir, p.basename(sourcePath)));
        await destFolder.create(recursive: true);

        for (final entity in files) {
          if (entity is File) {
            final destFile = File(p.join(destFolder.path, p.basename(entity.path)));
            await destFile.writeAsBytes(await entity.readAsBytes());
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pdfToImageControllerProvider);
    final controller = ref.read(pdfToImageControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground(brightness),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text(brightness)),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'PDF to Image',
          style: AppTypography.displayMedium(brightness),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Subtitle
                      Text(
                        'Convert PDF pages into high-resolution PNG or JPEG images.',
                        style: AppTypography.bodyMedium(brightness),
                      ),
                      const SizedBox(height: 24),

                      // Error banner
                      if (state.errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.rustRed.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.rustRed.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.rustRed, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  state.errorMessage!,
                                  style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.rustRed),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppColors.rustRed, size: 18),
                                onPressed: () => controller.clearError(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // SUCCESS VIEW
                      if (state.outputPath != null) ...[
                        _buildSuccessCard(context, state, controller),
                      ]
                      // NO FILE LOADED: Drop Zone
                      else if (!state.isLoaded) ...[
                        FileDropZone(
                          onTap: _pickFile,
                          label: 'Drop PDF file here or click to browse',
                          sublabel: 'Supports PDF document files',
                        ),
                      ]
                      // FILE LOADED VIEW
                      else ...[
                        _buildLoadedView(context, state, controller),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom summary bar when file loaded and not success state
          if (state.isLoaded && state.outputPath == null)
            _buildBottomBar(context, state, controller),
        ],
      ),
    );
  }

  Widget _buildLoadedView(
    BuildContext context,
    PdfToImageState state,
    PdfToImageController controller,
  ) {
    final brightness = Theme.of(context).brightness;

    return Column(
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

              // Change file button
              TextButton.icon(
                onPressed: state.isProcessing ? null : _pickFile,
                icon: Icon(Icons.swap_horiz, size: 18, color: AppColors.primary(brightness)),
                label: Text('Change file', style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.primary(brightness))),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Controls Panel (Format & Resolution options)
        _buildControlsPanel(context, state, controller),
        const SizedBox(height: 24),

        // Page Selection Header & Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
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
              children: [
                TextButton(
                  onPressed: state.isProcessing ? null : controller.selectAll,
                  child: Text('Select All', style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.primary(brightness))),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: state.isProcessing ? null : controller.selectNone,
                  child: Text('Select None', style: AppTypography.labelSmall(brightness)),
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
                            color: isSelected ? AppColors.primary(brightness) : AppColors.cardBackground(brightness).withValues(alpha: 0.9),
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
          Row(
            children: ImageFormat.values.map((fmt) {
              final isSelected = state.format == fmt;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
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

  Widget _buildBottomBar(
    BuildContext context,
    PdfToImageState state,
    PdfToImageController controller,
  ) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        border: Border(top: BorderSide(color: AppColors.pegGrey.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Row(
              children: [
                // Live summary text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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

                // Primary Export Button
                AppButton(
                  label: state.isProcessing ? 'Exporting…' : 'Export',
                  icon: state.isProcessing ? null : Icons.download_rounded,
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

  Widget _buildSuccessCard(
    BuildContext context,
    PdfToImageState state,
    PdfToImageController controller,
  ) {
    final brightness = Theme.of(context).brightness;
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

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.5)),
      ),
      child: Column(
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
          if (skippedNote != null) ...[
            const SizedBox(height: 8),
            Text(
              skippedNote,
              style: AppTypography.labelSmall(brightness).copyWith(color: AppColors.sparkYellow),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),

          // Primary & Secondary Actions
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              AppButton(
                label: 'Open Folder',
                icon: Icons.folder_open_rounded,
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
                label: 'Convert Another PDF',
                icon: Icons.refresh_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: controller.reset,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
