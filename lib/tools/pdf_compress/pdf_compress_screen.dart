import 'dart:io';
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
import 'pdf_compress_controller.dart';
import 'pdf_compress_state.dart';

class PdfCompressScreen extends ConsumerStatefulWidget {
  const PdfCompressScreen({super.key});

  @override
  ConsumerState<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends ConsumerState<PdfCompressScreen> {
  final FileService _fileService = FileService();

  Future<void> _handleCompress(Color familyAccent) async {
    final controller = ref.read(pdfCompressControllerProvider.notifier);
    await showTaskProgressDialog<String>(
      context: context,
      title: 'Compressing PDF',
      defaultMessage: 'Reducing file size…',
      color: familyAccent,
      getMessage: () => ref.read(pdfCompressControllerProvider).progressMessage ?? 'Reducing file size…',
      task: () => controller.compress(),
    );
  }

  Future<void> _pickFile() async {
    final files = await _fileService.pickPdfFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(pdfCompressControllerProvider.notifier).loadDocument(files.first);
    }
  }

  Future<void> _handleSaveAs(String currentOutputPath, Color familyAccent) async {
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
                backgroundColor: familyAccent,
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final familyAccent = AppColors.familyAccent(ToolCategory.pdf, brightness);
    final state = ref.watch(pdfCompressControllerProvider);
    final controller = ref.read(pdfCompressControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Compress PDF',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.isLoaded)
            IconButton(
              tooltip: 'Reset',
              icon: const Icon(Icons.refresh),
              onPressed: controller.reset,
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
                child: !state.isLoaded
                    ? _buildEmptyDropZone(brightness, familyAccent)
                    : state.outputPath != null
                        ? _buildSuccessView(context, state, brightness, controller, familyAccent)
                        : _buildCompressForm(context, state, brightness, controller, familyAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message,
      Brightness brightness, PdfCompressController controller) {
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

  Widget _buildEmptyDropZone(Brightness brightness, Color familyAccent) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickFile,
          label: 'Drop PDF file here or click to browse',
          sublabel: 'Select a PDF document to shrink file size',
          icon: Icons.compress_rounded,
          color: familyAccent,
        ),
      ),
    );
  }

  Widget _buildCompressForm(BuildContext context, PdfCompressState state,
      Brightness brightness, PdfCompressController controller, Color familyAccent) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Current File Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground(brightness),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.pegGrey),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: familyAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf,
                        size: 32,
                        color: familyAccent,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.file?.name ?? 'Document',
                            style: AppTypography.bodyLarge(brightness).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Original Size: ${state.formattedOriginalSize}',
                            style: AppTypography.mono(brightness).copyWith(
                              color: AppColors.text(brightness).withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Change'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Compression Level Selector
              Text(
                'COMPRESSION LEVEL',
                style: AppTypography.labelSmall(brightness),
              ),
              const SizedBox(height: 8),
              SegmentedButton<CompressionLevel>(
                segments: const [
                  ButtonSegment<CompressionLevel>(
                    value: CompressionLevel.low,
                    label: Text('Low'),
                    icon: Icon(Icons.image_outlined),
                  ),
                  ButtonSegment<CompressionLevel>(
                    value: CompressionLevel.medium,
                    label: Text('Medium'),
                    icon: Icon(Icons.tune),
                  ),
                  ButtonSegment<CompressionLevel>(
                    value: CompressionLevel.high,
                    label: Text('High'),
                    icon: Icon(Icons.compress),
                  ),
                ],
                selected: {state.level},
                onSelectionChanged: (Set<CompressionLevel> newSelection) {
                  controller.setCompressionLevel(newSelection.first);
                },
              ),

              const SizedBox(height: 12),
              Text(
                'Compression reduces embedded image quality. Text stays sharp and selectable.',
                style: AppTypography.bodyMedium(brightness).copyWith(
                  fontSize: 12,
                  color: AppColors.text(brightness).withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Compress Action Button
              AppButton(
                label: 'Compress PDF',
                icon: Icons.compress_rounded,
                variant: AppButtonVariant.primary,
                color: familyAccent,
                isLoading: state.isProcessing,
                onPressed: state.isProcessing ? null : () => _handleCompress(familyAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context, PdfCompressState state,
      Brightness brightness, PdfCompressController controller, Color familyAccent) {
    final isMinimal = state.resultType == CompressionResultType.minimalReduction;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StampAnimation(label: 'COMPRESSED', color: familyAccent),
            const SizedBox(height: 24),
            Text(
              'PDF Compression Complete!',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Before -> After Size Comparison Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground(brightness),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: familyAccent.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.formattedOriginalSize,
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 18,
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.text(brightness).withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: familyAccent,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        state.formattedCompressedSize,
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: familyAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: familyAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${state.reductionPercentage.toStringAsFixed(0)}% smaller',
                      style: AppTypography.mono(brightness).copyWith(
                        fontWeight: FontWeight.bold,
                        color: familyAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (isMinimal) ...[
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxWidth: 480),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.sparkYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.sparkYellow),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.sparkYellow),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This PDF is already efficient — there wasn\'t much to compress.',
                        style: AppTypography.bodyMedium(brightness).copyWith(
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (state.outputPath != null) ...[
              const SizedBox(height: 16),
              Text(
                'Saved to:',
                style: AppTypography.labelSmall(brightness),
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
                  state.outputPath!,
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Action Buttons
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
                      _fileService.openFolder(p.dirname(state.outputPath!));
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
                  label: 'Compress Another PDF',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  color: familyAccent,
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
