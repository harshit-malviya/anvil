import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../tools/registry.dart';
import 'image_resize_controller.dart';
import 'image_resize_state.dart';

class ImageResizeScreen extends ConsumerStatefulWidget {
  const ImageResizeScreen({super.key});

  @override
  ConsumerState<ImageResizeScreen> createState() => _ImageResizeScreenState();
}

class _ImageResizeScreenState extends ConsumerState<ImageResizeScreen> {
  final FileService _fileService = FileService();

  late TextEditingController _widthTextController;
  late TextEditingController _heightTextController;
  late TextEditingController _percentageTextController;

  @override
  void initState() {
    super.initState();
    _widthTextController = TextEditingController();
    _heightTextController = TextEditingController();
    _percentageTextController = TextEditingController();
  }

  @override
  void dispose() {
    _widthTextController.dispose();
    _heightTextController.dispose();
    _percentageTextController.dispose();
    super.dispose();
  }

  void _syncTextFields(ImageResizeState state) {
    if (state.isSourceLoaded) {
      final wStr = state.targetWidth.toString();
      final hStr = state.targetHeight.toString();
      final pctStr = state.percentage.toStringAsFixed(0);

      if (_widthTextController.text != wStr) {
        _widthTextController.value = TextEditingValue(
          text: wStr,
          selection: TextSelection.collapsed(offset: wStr.length),
        );
      }
      if (_heightTextController.text != hStr) {
        _heightTextController.value = TextEditingValue(
          text: hStr,
          selection: TextSelection.collapsed(offset: hStr.length),
        );
      }
      if (_percentageTextController.text != pctStr) {
        _percentageTextController.value = TextEditingValue(
          text: pctStr,
          selection: TextSelection.collapsed(offset: pctStr.length),
        );
      }
    }
  }

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
      ref.read(imageResizeControllerProvider.notifier).loadImage(files.first);
    }
  }

  Future<void> _handleResize(Color familyAccent) async {
    final controller = ref.read(imageResizeControllerProvider.notifier);
    await showTaskProgressDialog<void>(
      context: context,
      title: 'Resizing Image',
      defaultMessage: 'Applying new dimensions…',
      color: familyAccent,
      task: () => controller.resize(),
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
    final state = ref.watch(imageResizeControllerProvider);
    final controller = ref.read(imageResizeControllerProvider.notifier);

    _syncTextFields(state);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        backgroundColor: AppColors.cardBackground(brightness),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text(brightness)),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Resize Image',
          style: AppTypography.displayMedium(brightness).copyWith(fontSize: 20),
        ),
        actions: [
          if (state.isSourceLoaded)
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: !state.isSourceLoaded
                    ? _buildEmptyDropZone(familyAccent)
                    : state.outputPath != null
                        ? _buildSuccessView(context, state, controller, familyAccent, brightness)
                        : SingleChildScrollView(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 800),
                                child: _buildMainView(context, state, controller, familyAccent, brightness),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyDropZone(Color familyAccent) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickFile,
          label: 'Drop image file here or click to browse',
          sublabel: 'Supports PNG, JPEG, BMP, GIF, TIFF, and WebP images',
          icon: Icons.aspect_ratio_rounded,
          color: familyAccent,
        ),
      ),
    );
  }

  Widget _buildMainView(
    BuildContext context,
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Source Image Header Card
        _buildSourceCard(state, controller, familyAccent, brightness),
        const SizedBox(height: 24),

        // Mode Selector
        _buildModeSelector(state, controller, familyAccent, brightness),
        const SizedBox(height: 24),

        // Mode Controls Panel
        _buildModeControls(state, controller, familyAccent, brightness),
        const SizedBox(height: 24),

        // Info / Warnings
        _buildWarningsAndNotes(state, brightness),
        const SizedBox(height: 16),

        // Live Numeric Preview Readout
        _buildLiveReadout(state, familyAccent, brightness),
        const SizedBox(height: 24),

        // Error banner if any
        if (state.errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.rustRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.rustRed.withValues(alpha: 0.3)),
            ),
            child: Text(
              state.errorMessage!,
              style: AppTypography.bodySmall(brightness).copyWith(
                color: AppColors.rustRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Primary Resize Button
        AppButton(
          label: state.isProcessing ? 'Resizing…' : 'Resize Image',
          icon: Icons.aspect_ratio_rounded,
          variant: AppButtonVariant.primary,
          color: familyAccent,
          isLoading: state.isProcessing,
          onPressed: (state.isProcessing || !state.isValidDimensions)
              ? null
              : () => _handleResize(familyAccent),
        ),
      ],
    );
  }

  Widget _buildSourceCard(
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 80,
              height: 80,
              color: AppColors.pegGrey.withValues(alpha: 0.2),
              child: state.thumbnailBytes != null
                  ? Image.memory(
                      state.thumbnailBytes!,
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.image_outlined, size: 40),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.file?.name ?? 'Source Image',
                  style: AppTypography.titleMedium(brightness),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (state.detectedFormat != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: familyAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          state.detectedFormat!,
                          style: AppTypography.labelSmall(brightness).copyWith(
                            color: familyAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      '${state.sourceWidth} × ${state.sourceHeight} px · ${_formatBytes(state.sourceFileSize ?? 0)}',
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
          IconButton(
            icon: Icon(Icons.close_rounded, color: AppColors.text(brightness).withValues(alpha: 0.6)),
            tooltip: 'Remove Image',
            onPressed: () => controller.reset(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.pegGrey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildModeTab('Exact Dimensions', ResizeMode.exactDimensions, state, controller, familyAccent, brightness),
          _buildModeTab('Percentage', ResizeMode.percentage, state, controller, familyAccent, brightness),
          _buildModeTab('Presets', ResizeMode.preset, state, controller, familyAccent, brightness),
        ],
      ),
    );
  }

  Widget _buildModeTab(
    String label,
    ResizeMode mode,
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    final isSelected = state.mode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => controller.setMode(mode),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.cardBackground(brightness) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall(brightness).copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? familyAccent : AppColors.text(brightness).withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeControls(
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    switch (state.mode) {
      case ResizeMode.exactDimensions:
        return _buildExactDimensionsPanel(state, controller, familyAccent, brightness);
      case ResizeMode.percentage:
        return _buildPercentagePanel(state, controller, familyAccent, brightness);
      case ResizeMode.preset:
        return _buildPresetsPanel(state, controller, familyAccent, brightness);
    }
  }

  Widget _buildExactDimensionsPanel(
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Width Input
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Width (px)',
                  style: AppTypography.labelSmall(brightness),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _widthTextController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: familyAccent, width: 2),
                    ),
                  ),
                  style: AppTypography.mono(brightness),
                  onChanged: (val) {
                    final parsed = int.tryParse(val) ?? 0;
                    controller.setWidth(parsed);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Aspect Ratio Lock Toggle Button
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Tooltip(
              message: state.aspectRatioLocked ? 'Aspect Ratio Locked' : 'Aspect Ratio Unlocked',
              child: InkWell(
                onTap: () => controller.toggleAspectRatioLock(),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: state.aspectRatioLocked
                        ? familyAccent.withValues(alpha: 0.15)
                        : AppColors.pegGrey.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: state.aspectRatioLocked
                          ? familyAccent
                          : AppColors.pegGrey.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    state.aspectRatioLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    color: state.aspectRatioLocked ? familyAccent : AppColors.text(brightness).withValues(alpha: 0.6),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Height Input
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Height (px)',
                  style: AppTypography.labelSmall(brightness),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _heightTextController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: familyAccent, width: 2),
                    ),
                  ),
                  style: AppTypography.mono(brightness),
                  onChanged: (val) {
                    final parsed = int.tryParse(val) ?? 0;
                    controller.setHeight(parsed);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPercentagePanel(
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Scale Percentage:',
                style: AppTypography.titleMedium(brightness),
              ),
              const SizedBox(width: 8),
              Text(
                '${state.percentage.toStringAsFixed(0)}%',
                style: AppTypography.mono(brightness).copyWith(
                  fontWeight: FontWeight.bold,
                  color: familyAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: familyAccent,
              thumbColor: familyAccent,
              overlayColor: familyAccent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: state.percentage.clamp(10.0, 200.0),
              min: 10.0,
              max: 200.0,
              divisions: 190,
              onChanged: (val) => controller.setPercentage(val),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [25, 50, 75, 100].map((pct) {
              final isSelected = (state.percentage - pct).abs() < 1.0;
              return ChoiceChip(
                label: Text('$pct%'),
                selected: isSelected,
                selectedColor: familyAccent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: isSelected ? familyAccent : AppColors.text(brightness),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) => controller.setPercentage(pct.toDouble()),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsPanel(
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Preset:',
                style: AppTypography.titleMedium(brightness),
              ),
              Row(
                children: [
                  Text(
                    'Lock Ratio:',
                    style: AppTypography.labelSmall(brightness),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: state.aspectRatioLocked,
                    activeColor: familyAccent,
                    onChanged: (_) => controller.toggleAspectRatioLock(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ImagePreset.values.map((preset) {
              final isSelected = state.selectedPreset == preset;
              return ChoiceChip(
                label: Text('${preset.label} (${preset.width}×${preset.height})'),
                selected: isSelected,
                selectedColor: familyAccent.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: isSelected ? familyAccent : AppColors.text(brightness),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (_) => controller.selectPreset(preset),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningsAndNotes(ImageResizeState state, Brightness brightness) {
    return Column(
      children: [
        if (!state.aspectRatioLocked) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.emberCopper.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.emberCopper.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.emberCopper),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unlocking may stretch or squash the image',
                    style: AppTypography.bodySmall(brightness).copyWith(
                      color: AppColors.emberCopper,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (state.isUpscaling) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.pegGrey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.text(brightness).withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Upscaling beyond the original size may reduce quality',
                    style: AppTypography.bodySmall(brightness).copyWith(
                      color: AppColors.text(brightness).withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (state.isBelowMinFloor) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.rustRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: AppColors.rustRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Minimum size is 10×10px',
                    style: AppTypography.bodySmall(brightness).copyWith(
                      color: AppColors.rustRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLiveReadout(ImageResizeState state, Color familyAccent, Brightness brightness) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'New size: ',
            style: AppTypography.bodyMedium(brightness).copyWith(
              color: AppColors.text(brightness).withValues(alpha: 0.7),
            ),
          ),
          Text(
            '${state.targetWidth} × ${state.targetHeight} px',
            style: AppTypography.mono(brightness).copyWith(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: familyAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    ImageResizeState state,
    ImageResizeController controller,
    Color familyAccent,
    Brightness brightness,
  ) {
    final origSize = _formatBytes(state.sourceFileSize ?? 0);
    final newSize = _formatBytes(state.outputSize ?? 0);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StampAnimation(label: 'RESIZED', color: familyAccent),
              const SizedBox(height: 24),

              Text(
                'Image Resized Successfully!',
                style: AppTypography.displayMedium(brightness),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Comparison Details Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground(brightness),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.pegGrey),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            Text('Original', style: AppTypography.labelSmall(brightness)),
                            const SizedBox(height: 4),
                            Text(
                              '${state.sourceWidth}×${state.sourceHeight}',
                              style: AppTypography.mono(brightness).copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(origSize, style: AppTypography.bodySmall(brightness)),
                          ],
                        ),
                        Icon(Icons.arrow_forward_rounded, color: familyAccent),
                        Column(
                          children: [
                            Text('Resized', style: AppTypography.labelSmall(brightness)),
                            const SizedBox(height: 4),
                            Text(
                              '${state.targetWidth}×${state.targetHeight}',
                              style: AppTypography.mono(brightness).copyWith(
                                fontWeight: FontWeight.bold,
                                color: familyAccent,
                              ),
                            ),
                            Text(newSize, style: AppTypography.bodySmall(brightness)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Saved to path container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pegGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved to:',
                      style: AppTypography.labelSmall(brightness),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      state.outputPath ?? '',
                      style: AppTypography.mono(brightness).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Wrap action buttons per Rule #8
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
                    onPressed: () => controller.openFolder(),
                  ),
                  AppButton(
                    label: 'Save As…',
                    icon: Icons.save_alt_rounded,
                    variant: AppButtonVariant.secondary,
                    color: familyAccent,
                    onPressed: () => _handleSaveAs(state.outputPath!, familyAccent),
                  ),
                  AppButton(
                    label: 'Share',
                    icon: Icons.share_rounded,
                    variant: AppButtonVariant.secondary,
                    color: familyAccent,
                    onPressed: () => _handleShare(state.outputPath!),
                  ),
                  AppButton(
                    label: 'Resize Another Image',
                    icon: Icons.refresh_rounded,
                    variant: AppButtonVariant.secondary,
                    color: familyAccent,
                    onPressed: () => controller.reset(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
