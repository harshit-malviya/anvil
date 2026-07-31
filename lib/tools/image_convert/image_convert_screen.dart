import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import 'image_convert_controller.dart';
import 'image_convert_state.dart';

class ImageConvertScreen extends ConsumerStatefulWidget {
  const ImageConvertScreen({super.key});

  @override
  ConsumerState<ImageConvertScreen> createState() => _ImageConvertScreenState();
}

class _ImageConvertScreenState extends ConsumerState<ImageConvertScreen> {
  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'bmp', 'gif', 'tiff', 'webp'],
      allowMultiple: false,
      withData: false,
    );
    if (result != null && result.files.isNotEmpty) {
      ref.read(imageConvertControllerProvider.notifier).loadImage(result.files.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = ref.watch(imageConvertControllerProvider);
    final controller = ref.read(imageConvertControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Image Format Convert',
          style: AppTypography.titleMedium(brightness),
        ),
        backgroundColor: AppColors.background(brightness),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text(brightness)),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!state.hasFile && !state.isSuccess) ...[
                Expanded(
                  child: FileDropZone(
                    onTap: _pickFile,
                    label: 'Drop image file here or click to browse',
                    sublabel: 'Supports PNG, JPEG, BMP, GIF, TIFF, WebP',
                    icon: Icons.image_outlined,
                  ),
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorBanner(state.errorMessage!, brightness),
                ],
              ] else if (state.isSuccess) ...[
                Expanded(child: _buildSuccessView(state, controller, brightness)),
              ] else ...[
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSourceCard(state, controller, brightness),
                        const SizedBox(height: 24),
                        _buildTargetFormatSection(state, controller, brightness),
                        if (state.targetFormat == ImageOutputFormat.jpeg) ...[
                          const SizedBox(height: 24),
                          _buildJpegQualitySection(state, controller, brightness),
                        ],
                        if (state.hasAlpha &&
                            state.targetFormat == ImageOutputFormat.jpeg) ...[
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
                        if (state.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          _buildErrorBanner(state.errorMessage!, brightness),
                        ],
                        const SizedBox(height: 24),
                        _buildSummaryCard(state, brightness),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Convert Image',
                  isLoading: state.isProcessing,
                  onPressed: state.isProcessing ? null : () => controller.convert(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceCard(
      ImageConvertState state, ImageConvertController controller, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.disabledBorder(brightness)),
      ),
      child: Row(
        children: [
          if (state.thumbnailBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                state.thumbnailBytes!,
                width: 72,
                height: 72,
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
                  style: AppTypography.titleMedium(brightness),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Format: ${state.detectedFormat ?? "Unknown"}',
                      style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                    ),
                    Text(
                      '${state.width} × ${state.height} px',
                      style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                    ),
                    Text(
                      _formatBytes(state.fileSize),
                      style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.swap_horiz_rounded, color: AppColors.primary(brightness)),
            tooltip: 'Choose a different image',
            onPressed: state.isProcessing ? null : _pickFile,
          ),
        ],
      ),
    );
  }

  Widget _buildTargetFormatSection(
      ImageConvertState state, ImageConvertController controller, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.disabledBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Target Format', style: AppTypography.titleMedium(brightness)),
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
                  selectedColor: AppColors.primary(brightness),
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
      ImageConvertState state, ImageConvertController controller, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.disabledBorder(brightness)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('JPEG Quality', style: AppTypography.titleMedium(brightness)),
              Text(
                '${state.jpegQuality}%',
                style: AppTypography.mono(brightness).copyWith(
                  color: AppColors.primary(brightness),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: state.jpegQuality.toDouble(),
            min: 10,
            max: 100,
            divisions: 18,
            activeColor: AppColors.primary(brightness),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall(brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rustRed.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.rustRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.rustRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall(brightness).copyWith(
                color: AppColors.rustRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ImageConvertState state, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.disabledBackground(brightness),
        borderRadius: BorderRadius.circular(8),
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
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.primary(brightness)),
          ),
          Text(
            state.targetFormat.displayName,
            style: AppTypography.titleMedium(brightness).copyWith(color: AppColors.primary(brightness)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(
      ImageConvertState state, ImageConvertController controller, Brightness brightness) {
    final fileName = p.basename(state.outputPath!);
    final originalSizeStr = _formatBytes(state.fileSize);
    final outputSizeStr = _formatBytes(state.outputSize ?? 0);

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          const StampAnimation(label: 'CONVERTED'),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBackground(brightness),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.disabledBorder(brightness)),
            ),
            child: Column(
              children: [
                Text(fileName, style: AppTypography.displayMedium(brightness)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Size: $originalSizeStr → $outputSizeStr',
                      style: AppTypography.mono(brightness),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton(
                label: 'Open Folder',
                icon: Icons.folder_open_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () => controller.openFolder(),
              ),
              const SizedBox(width: 16),
              AppButton(
                label: 'Save As...',
                icon: Icons.save_alt_rounded,
                variant: AppButtonVariant.primary,
                onPressed: () => controller.saveAs(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => controller.reset(),
            icon: Icon(Icons.refresh_rounded, color: AppColors.primary(brightness)),
            label: Text(
              'Convert Another Image',
              style: AppTypography.bodyMedium(brightness).copyWith(color: AppColors.primary(brightness)),
            ),
          ),
        ],
      ),
    );
  }
}
