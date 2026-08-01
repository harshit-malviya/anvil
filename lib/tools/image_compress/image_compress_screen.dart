import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'image_compress_controller.dart';
import 'image_compress_state.dart';

class ImageCompressScreen extends ConsumerStatefulWidget {
  const ImageCompressScreen({super.key});

  @override
  ConsumerState<ImageCompressScreen> createState() => _ImageCompressScreenState();
}

class _ImageCompressScreenState extends ConsumerState<ImageCompressScreen> {
  final FileService _fileService = FileService();
  final TextEditingController _minController = TextEditingController(text: '100');
  final TextEditingController _maxController = TextEditingController(text: '500');

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  Future<void> _handleCompress(Color familyAccent, ImageCompressState state) async {
    final controller = ref.read(imageCompressControllerProvider.notifier);
    final isRangeMode = state.mode == CompressionMode.targetSizeRange;

    await showTaskProgressDialog<void>(
      context: context,
      title: isRangeMode ? 'Finding Right Size' : 'Compressing Image',
      defaultMessage: isRangeMode ? 'Finding the right size…' : 'Reducing file size…',
      color: familyAccent,
      getMessage: () => isRangeMode ? 'Finding the right size…' : 'Reducing file size…',
      task: () => controller.compress(),
    );
  }

  Future<void> _pickFile() async {
    final files = await _fileService.pickImageFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(imageCompressControllerProvider.notifier).loadImage(files.first);
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final familyAccent = AppColors.familyAccent(ToolCategory.image, brightness);
    final state = ref.watch(imageCompressControllerProvider);
    final controller = ref.read(imageCompressControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Compress Image',
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
                    : state.resultType != null
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
      Brightness brightness, ImageCompressController controller) {
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
          label: 'Drop image here or click to browse',
          sublabel: 'Supports PNG, JPEG, BMP, GIF, and TIFF',
          icon: Icons.compress_rounded,
          color: familyAccent,
        ),
      ),
    );
  }

  Widget _buildCompressForm(BuildContext context, ImageCompressState state,
      Brightness brightness, ImageCompressController controller, Color familyAccent) {
    final isRangeMode = state.mode == CompressionMode.targetSizeRange;
    final isButtonEnabled = !state.isProcessing && (!isRangeMode || state.isRangeValid);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview File Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground(brightness),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.pegGrey),
                ),
                child: Row(
                  children: [
                    if (state.thumbnailBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          state.thumbnailBytes!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: familyAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(Icons.image, size: 32, color: familyAccent),
                      ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.file?.name ?? 'Image',
                            style: AppTypography.bodyLarge(brightness).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${state.originalWidth} × ${state.originalHeight} px',
                                style: AppTypography.mono(brightness).copyWith(
                                  fontSize: 12,
                                  color: AppColors.text(brightness).withValues(alpha: 0.7),
                                ),
                              ),
                              Text(
                                '•',
                                style: AppTypography.mono(brightness).copyWith(
                                  fontSize: 12,
                                  color: AppColors.text(brightness).withValues(alpha: 0.5),
                                ),
                              ),
                              Text(
                                state.detectedFormat ?? '',
                                style: AppTypography.mono(brightness).copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: familyAccent,
                                ),
                              ),
                              Text(
                                '•',
                                style: AppTypography.mono(brightness).copyWith(
                                  fontSize: 12,
                                  color: AppColors.text(brightness).withValues(alpha: 0.5),
                                ),
                              ),
                              Text(
                                state.formattedOriginalSize,
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
                      onPressed: _pickFile,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Change'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Compression Mode Selector
              Text(
                'COMPRESSION MODE',
                style: AppTypography.labelSmall(brightness),
              ),
              const SizedBox(height: 8),
              SegmentedButton<CompressionMode>(
                segments: const [
                  ButtonSegment<CompressionMode>(
                    value: CompressionMode.qualityLevel,
                    label: Text('Quality Level'),
                    icon: Icon(Icons.tune),
                  ),
                  ButtonSegment<CompressionMode>(
                    value: CompressionMode.targetSizeRange,
                    label: Text('Target Size Range'),
                    icon: Icon(Icons.line_weight),
                  ),
                ],
                selected: {state.mode},
                onSelectionChanged: (Set<CompressionMode> newSelection) {
                  controller.setMode(newSelection.first);
                },
              ),

              const SizedBox(height: 20),

              if (state.mode == CompressionMode.qualityLevel) ...[
                // Quality Level Preset Cards
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
                  'Compression reduces image quality to save space. Dimensions and format stay the same.',
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                // Target Size Range Form
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MINIMUM SIZE',
                            style: AppTypography.labelSmall(brightness),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _minController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: familyAccent),
                                    ),
                                  ),
                                  onChanged: (val) {
                                    final d = double.tryParse(val) ?? 0;
                                    controller.setMinSize(d, state.minSizeUnit);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<SizeUnit>(
                                value: state.minSizeUnit,
                                items: SizeUnit.values
                                    .map((u) => DropdownMenuItem(
                                          value: u,
                                          child: Text(u.displayName),
                                        ))
                                    .toList(),
                                onChanged: (u) {
                                  if (u != null) {
                                    controller.setMinSize(state.minSizeValue, u);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MAXIMUM SIZE',
                            style: AppTypography.labelSmall(brightness),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _maxController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: familyAccent),
                                    ),
                                  ),
                                  onChanged: (val) {
                                    final d = double.tryParse(val) ?? 0;
                                    controller.setMaxSize(d, state.maxSizeUnit);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<SizeUnit>(
                                value: state.maxSizeUnit,
                                items: SizeUnit.values
                                    .map((u) => DropdownMenuItem(
                                          value: u,
                                          child: Text(u.displayName),
                                        ))
                                    .toList(),
                                onChanged: (u) {
                                  if (u != null) {
                                    controller.setMaxSize(state.maxSizeValue, u);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (state.isMinBelowFloor) ...[
                  const SizedBox(height: 6),
                  Text(
                    "Minimum can't be set below 5 KB",
                    style: AppTypography.bodySmall(brightness).copyWith(
                      color: AppColors.sparkYellow,
                      fontSize: 12,
                    ),
                  ),
                ],

                if (!state.isRangeValid) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Maximum must be greater than minimum',
                    style: AppTypography.bodySmall(brightness).copyWith(
                      color: AppColors.rustRed,
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Text(
                  "We'll find the compression level that lands your image inside this size range.",
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 28),

              // Compress Primary Button
              AppButton(
                label: isRangeMode ? 'Compress to Target Size' : 'Compress Image',
                icon: Icons.compress_rounded,
                variant: AppButtonVariant.primary,
                color: familyAccent,
                isLoading: state.isProcessing,
                onPressed: isButtonEnabled ? () => _handleCompress(familyAccent, state) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(BuildContext context, ImageCompressState state,
      Brightness brightness, ImageCompressController controller, Color familyAccent) {
    final res = state.resultType;
    final isOutputLarger = res == CompressionResultType.outputLarger;
    final isMinimal = res == CompressionResultType.minimalReduction;
    final isAlreadyInRange = res == CompressionResultType.alreadyInRange;
    final isSmallerThanMin = res == CompressionResultType.smallerThanMin;
    final isClosestEffort = res == CompressionResultType.closestEffort;
    final isNoOutputFile = isAlreadyInRange || isSmallerThanMin;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StampAnimation(
              label: isNoOutputFile ? 'INFO' : 'COMPRESSED',
              color: familyAccent,
            ),
            const SizedBox(height: 24),
            Text(
              isNoOutputFile ? 'Target Range Evaluation' : 'Image Compression Complete!',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            if (isOutputLarger) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.sparkYellow.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.sparkYellow),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.sparkYellow, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        "Compression didn't reduce the size for this file. Your original hasn't been changed.",
                        style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isAlreadyInRange) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: familyAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: familyAccent),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: familyAccent, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Your image is already within your target range (${state.formattedOriginalSize}, target ${state.formattedMinTargetSize}–${state.formattedMaxTargetSize}) — no changes needed.',
                        style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isSmallerThanMin) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.rustRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.rustRed),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.rustRed, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'This image is already smaller than your minimum size (${state.formattedOriginalSize}, target min ${state.formattedMinTargetSize}). Lower the minimum or use the original file.',
                        style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: familyAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        res == CompressionResultType.inRangeSuccess
                            ? 'Compressed to ${state.formattedCompressedSize} — within your ${state.formattedMinTargetSize}–${state.formattedMaxTargetSize} target'
                            : '${state.reductionPercentage.toStringAsFixed(0)}% smaller',
                        style: AppTypography.mono(brightness).copyWith(
                          fontWeight: FontWeight.bold,
                          color: familyAccent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              if (isClosestEffort) ...[
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
                          "Couldn't land in your target range without visibly degrading the image — closest safe result is ${state.formattedCompressedSize} (target was ${state.formattedMinTargetSize}–${state.formattedMaxTargetSize}).",
                          style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

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
                          "This image is already efficient — there wasn't much to compress.",
                          style: AppTypography.bodyMedium(brightness).copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            if (state.outputPath != null && !isOutputLarger && !isNoOutputFile) ...[
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

            // Standard Action Buttons Set
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (!isOutputLarger && !isNoOutputFile) ...[
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
                ],
                AppButton(
                  label: 'Compress Another Image',
                  icon: Icons.refresh,
                  variant: (isOutputLarger || isNoOutputFile) ? AppButtonVariant.primary : AppButtonVariant.secondary,
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
