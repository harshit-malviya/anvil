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
import '../../tools/registry.dart';
import 'image_convert_controller.dart';
import 'image_convert_state.dart';

class ImageConvertScreen extends ConsumerStatefulWidget {
  const ImageConvertScreen({super.key});

  @override
  ConsumerState<ImageConvertScreen> createState() => _ImageConvertScreenState();
}

class _ImageConvertScreenState extends ConsumerState<ImageConvertScreen> {
  final FileService _fileService = FileService();

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickFile() async {
    final files = await _fileService.pickImageFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(imageConvertControllerProvider.notifier).loadImage(files.first);
    }
  }

  Future<void> _handleConvert() async {
    final controller = ref.read(imageConvertControllerProvider.notifier);
    await showTaskProgressDialog<void>(
      context: context,
      title: 'Converting Image',
      defaultMessage: 'Encoding image format…',
      task: () => controller.convert(),
    );
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
                content: Text('File saved to $savedPath'),
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

  Future<void> _handleShare(String currentOutputPath) async {
    await _fileService.shareFile(currentOutputPath);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final familyAccent = AppColors.familyAccent(ToolCategory.image, brightness);
    final state = ref.watch(imageConvertControllerProvider);
    final controller = ref.read(imageConvertControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Image Format Convert',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text(brightness)),
          onPressed: () => context.go('/'),
        ),
        actions: [
          if (state.hasFile)
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.errorMessage != null)
                _buildErrorBanner(state.errorMessage!, brightness),
              Expanded(
                child: !state.hasFile
                    ? _buildEmptyDropZone(brightness)
                    : state.isSuccess
                        ? _buildSuccessView(state, controller, brightness, familyAccent)
                        : _buildConvertForm(state, controller, brightness, familyAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDropZone(Brightness brightness) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickFile,
          label: 'Drop image file here or click to browse',
          sublabel: 'Supports PNG, JPEG, BMP, GIF, TIFF, and WebP images',
          icon: Icons.transform_rounded,
        ),
      ),
    );
  }

  Widget _buildConvertForm(
      ImageConvertState state, ImageConvertController controller, Brightness brightness, Color familyAccent) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSourceCard(state, controller, brightness),
              const SizedBox(height: 24),
              _buildTargetFormatSection(state, controller, brightness, familyAccent),
              if (state.targetFormat == ImageOutputFormat.jpeg) ...[
                const SizedBox(height: 24),
                _buildJpegQualitySection(state, controller, brightness, familyAccent),
              ],
              if (state.hasAlpha && state.targetFormat == ImageOutputFormat.jpeg) ...[
                const SizedBox(height: 16),
                _buildNoticeBanner(
                  icon: Icons.info_outline_rounded,
                  color: AppColors.sparkYellow,
                  message:
                      'JPEG does not support transparency. Transparent areas will become white.',
                  brightness: brightness,
                ),
              ],
              if (state.isAnimated) ...[
                const SizedBox(height: 16),
                _buildNoticeBanner(
                  icon: Icons.motion_photos_on_rounded,
                  color: AppColors.sparkYellow,
                  message:
                      'This is an animated image — only the first frame will be converted.',
                  brightness: brightness,
                ),
              ],
              const SizedBox(height: 24),
              _buildSummaryCard(state, brightness, familyAccent),
              const SizedBox(height: 32),
              AppButton(
                label: 'Convert Image',
                icon: Icons.transform_rounded,
                variant: AppButtonVariant.primary,
                color: familyAccent,
                isLoading: state.isProcessing,
                onPressed: state.isProcessing ? null : _handleConvert,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard(
      ImageConvertState state, ImageConvertController controller, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.pegGrey),
      ),
      child: Row(
        children: [
          if (state.thumbnailBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                state.thumbnailBytes!,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.file?.name ?? 'Selected Image',
                  style: AppTypography.bodyLarge(brightness).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Format: ${state.detectedFormat ?? "Unknown"}',
                      style: AppTypography.mono(brightness).copyWith(
                        fontSize: 12,
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      '${state.width} × ${state.height} px',
                      style: AppTypography.mono(brightness).copyWith(
                        fontSize: 12,
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      _formatBytes(state.fileSize),
                      style: AppTypography.mono(brightness).copyWith(
                        fontSize: 12,
                        color: AppColors.text(brightness).withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: state.isProcessing ? null : _pickFile,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetFormatSection(
      ImageConvertState state, ImageConvertController controller, Brightness brightness, Color familyAccent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.pegGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TARGET FORMAT',
            style: AppTypography.labelSmall(brightness),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ImageOutputFormat.values.map((format) {
              final isSource = state.detectedFormat != null &&
                  state.detectedFormat!.toUpperCase() == format.displayName.toUpperCase();
              final isSelected = state.targetFormat == format;

              return Tooltip(
                message: isSource ? 'Already this format' : 'Convert to ${format.displayName}',
                child: ChoiceChip(
                  label: Text(format.displayName),
                  selected: isSelected,
                  disabledColor: AppColors.disabledBackground(brightness),
                  selectedColor: familyAccent,
                  backgroundColor: AppColors.cardBackground(brightness),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (isSource
                            ? AppColors.disabledText(brightness)
                            : AppColors.text(brightness)),
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: isSource || state.isProcessing
                      ? null
                      : (selected) {
                          if (selected) {
                            controller.setTargetFormat(format);
                          }
                        },
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildJpegQualitySection(
      ImageConvertState state, ImageConvertController controller, Brightness brightness, Color familyAccent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.pegGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'JPEG QUALITY',
                style: AppTypography.labelSmall(brightness),
              ),
              Text(
                '${state.jpegQuality}%',
                style: AppTypography.mono(brightness).copyWith(
                  fontWeight: FontWeight.bold,
                  color: familyAccent,
                ),
              ),
            ],
          ),
          Slider(
            value: state.jpegQuality.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            activeColor: familyAccent,
            inactiveColor: AppColors.disabledBorder(brightness),
            label: '${state.jpegQuality}%',
            onChanged: state.isProcessing
                ? null
                : (val) => controller.setJpegQuality(val.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeBanner({
    required IconData icon,
    required Color color,
    required String message,
    required Brightness brightness,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message, Brightness brightness) {
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
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ImageConvertState state, Brightness brightness, Color familyAccent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.pegGrey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Convert ${state.file?.name ?? ""} (${_formatBytes(state.fileSize)})',
            style: AppTypography.bodyMedium(brightness),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: familyAccent),
          ),
          Text(
            state.targetFormat.displayName,
            style: AppTypography.bodyMedium(brightness).copyWith(
              fontWeight: FontWeight.bold,
              color: familyAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(
      ImageConvertState state, ImageConvertController controller, Brightness brightness, Color familyAccent) {
    final fileName = p.basename(state.outputPath!);
    final originalSizeStr = _formatBytes(state.fileSize);
    final outputSizeStr = _formatBytes(state.outputSize ?? 0);

    final double sizeDiff = ((state.outputSize ?? 0) - state.fileSize).toDouble();
    final double percentChange =
        state.fileSize > 0 ? (sizeDiff / state.fileSize) * 100 : 0.0;
    final bool isSmaller = sizeDiff < 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StampAnimation(label: 'CONVERTED', color: familyAccent),
            const SizedBox(height: 24),
            Text(
              'Image Conversion Complete!',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Size & File Info Comparison Card matching PDF tools
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground(brightness),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.pegGrey),
              ),
              child: Column(
                children: [
                  Text(
                    fileName,
                    style: AppTypography.bodyLarge(brightness).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        originalSizeStr,
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 16,
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
                        outputSizeStr,
                        style: AppTypography.mono(brightness).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: familyAccent,
                        ),
                      ),
                    ],
                  ),
                  if (sizeDiff != 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isSmaller ? familyAccent : AppColors.emberCopper)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${percentChange.abs().toStringAsFixed(0)}% ${isSmaller ? "smaller" : "larger"}',
                        style: AppTypography.mono(brightness).copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSmaller ? familyAccent : AppColors.emberCopper,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (state.outputPath != null) ...[
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

            // Final Action Buttons matching all PDF tools (Open Folder, Save As..., Share, Convert Another Image)
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
                  onPressed: () {
                    if (state.outputPath != null) {
                      _handleShare(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Convert Another Image',
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
