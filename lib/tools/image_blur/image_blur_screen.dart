import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/file_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import '../../core/widgets/theme_toggle_button.dart';
import '../registry.dart';
import 'image_blur_controller.dart';
import 'image_blur_state.dart';

class ImageBlurScreen extends ConsumerStatefulWidget {
  const ImageBlurScreen({super.key});

  @override
  ConsumerState<ImageBlurScreen> createState() => _ImageBlurScreenState();
}

class _ImageBlurScreenState extends ConsumerState<ImageBlurScreen> {
  final FileService _fileService = FileService();

  // Drag-to-draw state
  Offset? _dragStartScreen;
  Offset? _dragCurrentScreen;
  String? _activeDragRegionId;
  _DragHandleType? _activeHandleType;
  Rect? _initialRegionRect;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageBlurControllerProvider);
    final controller = ref.read(imageBlurControllerProvider.notifier);
    final brightness = Theme.of(context).brightness;
    final accentColor = AppColors.familyAccent(ToolCategory.image, brightness);

    return PopScope(
      canPop: !state.hasRegions || state.outputPath != null,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Discard unsaved regions?'),
            content: const Text(
              'You have marked redaction regions that will be lost if you leave without applying.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.rustRed,
                ),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (shouldDiscard == true && context.mounted) {
          controller.reset();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background(brightness),
        appBar: AppBar(
          backgroundColor: AppColors.background(brightness),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (state.hasRegions && state.outputPath == null) {
                final shouldDiscard = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Discard unsaved regions?'),
                    content: const Text(
                      'You have marked redaction regions that will be lost if you leave without applying.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.rustRed,
                        ),
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                );
                if (shouldDiscard == true && context.mounted) {
                  controller.reset();
                  Navigator.of(context).pop();
                }
              } else {
                controller.reset();
                Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            'Blur / Redact Image',
            style: AppTypography.displayMedium(brightness),
          ),
          actions: const [
            ThemeToggleButton(),
            SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (state.outputPath != null)
                _buildSuccessView(context, state, controller, brightness, accentColor)
              else if (!state.isLoaded)
                _buildDropZone(context, controller, brightness, accentColor)
              else
                _buildWorkspaceView(context, state, controller, brightness, accentColor),

              if (state.isProcessing)
                Container(
                  color: Colors.black45,
                  child: Center(
                    child: Card(
                      color: AppColors.cardBackground(brightness),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: accentColor),
                            const SizedBox(height: 16),
                            Text(
                              'Redacting image off UI thread…',
                              style: AppTypography.bodyMedium(brightness),
                            ),
                          ],
                        ),
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

  Widget _buildDropZone(
    BuildContext context,
    ImageBlurController controller,
    Brightness brightness,
    Color accentColor,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 300),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FileDropZone(
                  onTap: () async {
                    final files = await _fileService.pickImageFiles(allowMultiple: false);
                    if (files.isNotEmpty) {
                      controller.loadImage(files.first);
                    }
                  },
                  label: 'Drop image here or click to browse',
                  sublabel: 'Supports PNG, JPEG, BMP, GIF, TIFF, and WebP',
                  icon: Icons.blur_on_rounded,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Note: Manually mark sensitive regions (faces, license plates, text). No ML auto-detection is performed, keeping processing 100% offline.',
                style: AppTypography.bodySmall(brightness).copyWith(
                  color: AppColors.text(brightness).withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkspaceView(
    BuildContext context,
    ImageBlurState state,
    ImageBlurController controller,
    Brightness brightness,
    Color accentColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final canvasWidget = _buildInteractiveCanvas(state, controller, brightness, accentColor);
        final controlsWidget = _buildControlsPanel(state, controller, brightness, accentColor);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: canvasWidget,
                ),
              ),
              Container(
                width: 360,
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: AppColors.pegGrey.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: controlsWidget,
              ),
            ],
          );
        } else {
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: canvasWidget,
                ),
              ),
              SizedBox(
                height: 320,
                child: controlsWidget,
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildInteractiveCanvas(
    ImageBlurState state,
    ImageBlurController controller,
    Brightness brightness,
    Color accentColor,
  ) {
    if (state.thumbnailBytes == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, containerConstraints) {
        final availWidth = containerConstraints.maxWidth;
        final availHeight = containerConstraints.maxHeight;

        final origW = state.originalWidth.toDouble();
        final origH = state.originalHeight.toDouble();

        if (origW <= 0 || origH <= 0) return const SizedBox.shrink();

        final scaleX = availWidth / origW;
        final scaleY = availHeight / origH;
        final scale = min(scaleX, scaleY);

        final dispW = origW * scale;
        final dispH = origH * scale;

        return Center(
          child: Container(
            width: dispW,
            height: dispH,
            decoration: BoxDecoration(
              color: AppColors.cardBackground(brightness),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      state.thumbnailBytes!,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),

                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (details) {
                    final localPos = details.localPosition;
                    final hit = _hitTestRegions(localPos, state.regions, scale);

                    if (hit != null) {
                      setState(() {
                        _activeDragRegionId = hit.regionId;
                        _activeHandleType = hit.handleType;
                        _dragStartScreen = localPos;
                        final region = state.regions.firstWhere((r) => r.id == hit.regionId);
                        _initialRegionRect = region.rect;
                      });
                    } else {
                      setState(() {
                        _activeDragRegionId = null;
                        _activeHandleType = null;
                        _dragStartScreen = localPos;
                        _dragCurrentScreen = localPos;
                      });
                    }
                  },
                  onPanUpdate: (details) {
                    final localPos = details.localPosition;

                    if (_activeDragRegionId != null && _initialRegionRect != null) {
                      final dxSource = (localPos.dx - _dragStartScreen!.dx) / scale;
                      final dySource = (localPos.dy - _dragStartScreen!.dy) / scale;

                      final initRect = _initialRegionRect!;
                      Rect updatedRect = initRect;

                      switch (_activeHandleType) {
                        case _DragHandleType.body:
                          updatedRect = initRect.shift(Offset(dxSource, dySource));
                          break;
                        case _DragHandleType.topLeft:
                          updatedRect = Rect.fromLTRB(
                            initRect.left + dxSource,
                            initRect.top + dySource,
                            initRect.right,
                            initRect.bottom,
                          );
                          break;
                        case _DragHandleType.topRight:
                          updatedRect = Rect.fromLTRB(
                            initRect.left,
                            initRect.top + dySource,
                            initRect.right + dxSource,
                            initRect.bottom,
                          );
                          break;
                        case _DragHandleType.bottomLeft:
                          updatedRect = Rect.fromLTRB(
                            initRect.left + dxSource,
                            initRect.top,
                            initRect.right,
                            initRect.bottom + dySource,
                          );
                          break;
                        case _DragHandleType.bottomRight:
                          updatedRect = Rect.fromLTRB(
                            initRect.left,
                            initRect.top,
                            initRect.right + dxSource,
                            initRect.bottom + dySource,
                          );
                          break;
                        default:
                          break;
                      }

                      controller.updateRegion(_activeDragRegionId!, updatedRect);
                    } else if (_dragStartScreen != null) {
                      setState(() {
                        _dragCurrentScreen = localPos;
                      });
                    }
                  },
                  onPanEnd: (details) {
                    if (_activeDragRegionId == null &&
                        _dragStartScreen != null &&
                        _dragCurrentScreen != null) {
                      final l = min(_dragStartScreen!.dx, _dragCurrentScreen!.dx);
                      final t = min(_dragStartScreen!.dy, _dragCurrentScreen!.dy);
                      final r = max(_dragStartScreen!.dx, _dragCurrentScreen!.dx);
                      final b = max(_dragStartScreen!.dy, _dragCurrentScreen!.dy);

                      final screenRect = Rect.fromLTRB(l, t, r, b);
                      final sourceRect = Rect.fromLTRB(
                        screenRect.left / scale,
                        screenRect.top / scale,
                        screenRect.right / scale,
                        screenRect.bottom / scale,
                      );

                      controller.addRegion(sourceRect);
                    }

                    setState(() {
                      _dragStartScreen = null;
                      _dragCurrentScreen = null;
                      _activeDragRegionId = null;
                      _activeHandleType = null;
                      _initialRegionRect = null;
                    });
                  },
                  child: Stack(
                    children: [
                      for (final region in state.regions)
                        _buildRegionOverlay(region, state, controller, scale, accentColor),

                      if (_activeDragRegionId == null &&
                          _dragStartScreen != null &&
                          _dragCurrentScreen != null)
                        Positioned(
                          left: min(_dragStartScreen!.dx, _dragCurrentScreen!.dx),
                          top: min(_dragStartScreen!.dy, _dragCurrentScreen!.dy),
                          width: (_dragCurrentScreen!.dx - _dragStartScreen!.dx).abs(),
                          height: (_dragCurrentScreen!.dy - _dragStartScreen!.dy).abs(),
                          child: Container(
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.2),
                              border: Border.all(color: accentColor, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRegionOverlay(
    RedactionRegion region,
    ImageBlurState state,
    ImageBlurController controller,
    double scale,
    Color accentColor,
  ) {
    final leftScreen = region.rect.left * scale;
    final topScreen = region.rect.top * scale;
    final widthScreen = region.rect.width * scale;
    final heightScreen = region.rect.height * scale;

    return Positioned(
      left: leftScreen,
      top: topScreen,
      width: max(1, widthScreen),
      height: max(1, heightScreen),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: state.style == RedactionStyle.solidBlock
                    ? state.solidBlockColor.withValues(alpha: 0.85)
                    : accentColor.withValues(alpha: 0.35),
                border: Border.all(
                  color: state.style == RedactionStyle.blur
                      ? AppColors.rustRed
                      : accentColor,
                  width: 2,
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    state.style == RedactionStyle.pixelate
                        ? 'PIXELATE'
                        : (state.style == RedactionStyle.blur ? 'BLUR' : 'SOLID'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            right: -10,
            top: -10,
            child: GestureDetector(
              onTap: () => controller.removeRegion(region.id),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppColors.rustRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          _buildCornerHandle(Alignment.topLeft),
          _buildCornerHandle(Alignment.topRight),
          _buildCornerHandle(Alignment.bottomLeft),
          _buildCornerHandle(Alignment.bottomRight),
        ],
      ),
    );
  }

  Widget _buildCornerHandle(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildControlsPanel(
    ImageBlurState state,
    ImageBlurController controller,
    Brightness brightness,
    Color accentColor,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Redaction Style',
            style: AppTypography.titleMedium(brightness),
          ),
          const SizedBox(height: 8),
          SegmentedButton<RedactionStyle>(
            segments: const [
              ButtonSegment<RedactionStyle>(
                value: RedactionStyle.pixelate,
                label: Text('Pixelate'),
                icon: Icon(Icons.grid_on_rounded, size: 16),
              ),
              ButtonSegment<RedactionStyle>(
                value: RedactionStyle.blur,
                label: Text('Blur'),
                icon: Icon(Icons.blur_on_rounded, size: 16),
              ),
              ButtonSegment<RedactionStyle>(
                value: RedactionStyle.solidBlock,
                label: Text('Solid'),
                icon: Icon(Icons.square_rounded, size: 16),
              ),
            ],
            selected: {state.style},
            onSelectionChanged: (selected) {
              if (selected.isNotEmpty) {
                controller.setRedactionStyle(selected.first);
              }
            },
          ),
          const SizedBox(height: 12),

          if (state.isBlurStyle)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rustRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.rustRed.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.rustRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Blur can sometimes be partially reversed for sensitive content like faces or text. Pixelate or Solid Block is safer for anything truly private.',
                      style: AppTypography.bodySmall(brightness).copyWith(
                        color: AppColors.rustRed,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (state.isBlurStyle) const SizedBox(height: 12),

          if (state.style == RedactionStyle.solidBlock) ...[
            Text(
              'Fill Color',
              style: AppTypography.titleMedium(brightness),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildColorSwatch(Colors.black, 'Black', state, controller, accentColor),
                const SizedBox(width: 8),
                _buildColorSwatch(Colors.white, 'White', state, controller, accentColor),
                const SizedBox(width: 8),
                _buildColorSwatch(Colors.red.shade700, 'Red', state, controller, accentColor),
                const SizedBox(width: 8),
                _buildColorSwatch(Colors.blue.shade700, 'Blue', state, controller, accentColor),
                const SizedBox(width: 8),
                _buildColorSwatch(Colors.grey.shade700, 'Grey', state, controller, accentColor),
              ],
            ),
          ] else ...[
            Text(
              state.style == RedactionStyle.pixelate ? 'Block Size' : 'Blur Strength',
              style: AppTypography.titleMedium(brightness),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: Text(state.style == RedactionStyle.pixelate ? 'Small' : 'Light'),
                    selected: state.intensity == RedactionIntensity.small,
                    selectedColor: accentColor.withValues(alpha: 0.2),
                    onSelected: (_) => controller.setIntensity(RedactionIntensity.small),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Medium'),
                    selected: state.intensity == RedactionIntensity.medium,
                    selectedColor: accentColor.withValues(alpha: 0.2),
                    onSelected: (_) => controller.setIntensity(RedactionIntensity.medium),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: Text(state.style == RedactionStyle.pixelate ? 'Large' : 'Strong'),
                    selected: state.intensity == RedactionIntensity.large,
                    selectedColor: accentColor.withValues(alpha: 0.2),
                    onSelected: (_) => controller.setIntensity(RedactionIntensity.large),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${state.regionCount} region${state.regionCount == 1 ? '' : 's'} marked',
                style: AppTypography.bodyMedium(brightness).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (state.hasRegions)
                TextButton(
                  onPressed: controller.clearRegions,
                  style: TextButton.styleFrom(foregroundColor: accentColor),
                  child: const Text('Clear All'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.rustRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state.errorMessage!,
                  style: AppTypography.bodySmall(brightness).copyWith(color: AppColors.rustRed),
                ),
              ),
            ),

          AppButton(
            label: 'Apply Redaction',
            icon: Icons.blur_on_rounded,
            variant: AppButtonVariant.primary,
            color: accentColor,
            onPressed: state.hasRegions ? controller.apply : null,
          ),
        ],
      ),
    );
  }

  Widget _buildColorSwatch(
    Color color,
    String label,
    ImageBlurState state,
    ImageBlurController controller,
    Color accentColor,
  ) {
    final isSelected = state.solidBlockColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => controller.setSolidBlockColor(color),
      child: Tooltip(
        message: label,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? accentColor : AppColors.pegGrey,
              width: isSelected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    ImageBlurState state,
    ImageBlurController controller,
    Brightness brightness,
    Color accentColor,
  ) {
    final formattedOriginal = _formatBytes(state.originalSizeBytes);
    final formattedOutput = _formatBytes(state.outputSizeBytes);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              StampAnimation(
                label: 'REDACTED',
                color: accentColor,
              ),
              const SizedBox(height: 16),
              Text(
                'Image Redacted Successfully',
                style: AppTypography.displayMedium(brightness),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Card(
                color: AppColors.cardBackground(brightness),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.pegGrey),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Regions Redacted:', style: AppTypography.bodyMedium(brightness)),
                          Text(
                            '${state.regionCount}',
                            style: AppTypography.bodyMedium(brightness).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Style Applied:', style: AppTypography.bodyMedium(brightness)),
                          Text(
                            state.style == RedactionStyle.pixelate
                                ? 'Pixelate'
                                : (state.style == RedactionStyle.blur ? 'Blur' : 'Solid Block'),
                            style: AppTypography.bodyMedium(brightness).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('File Size:', style: AppTypography.bodyMedium(brightness)),
                          Text(
                            '$formattedOriginal → $formattedOutput',
                            style: AppTypography.mono(brightness),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Saved to:', style: AppTypography.labelSmall(brightness)),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  state.outputPath ?? '',
                  style: AppTypography.mono(brightness),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "The original file wasn't changed — the redacted version is a new file. Once applied, redacted regions can't be un-redacted from this file, so keep the original if you might need the unredacted image again.",
                style: AppTypography.bodySmall(brightness).copyWith(
                  color: AppColors.text(brightness).withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  AppButton(
                    label: 'Open Folder',
                    icon: Icons.folder_open_rounded,
                    variant: AppButtonVariant.primary,
                    color: accentColor,
                    onPressed: controller.openFolder,
                  ),
                  AppButton(
                    label: 'Save As…',
                    icon: Icons.save_alt_rounded,
                    variant: AppButtonVariant.secondary,
                    color: accentColor,
                    onPressed: () async {
                      await controller.saveAs();
                      if (context.mounted && state.outputPath != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('File saved to ${state.outputPath!}'),
                            backgroundColor: accentColor,
                          ),
                        );
                      }
                    },
                  ),
                  AppButton(
                    label: 'Share',
                    icon: Icons.share_rounded,
                    variant: AppButtonVariant.secondary,
                    color: accentColor,
                    onPressed: controller.shareFile,
                  ),
                  AppButton(
                    label: 'Redact Another Image',
                    icon: Icons.refresh,
                    variant: AppButtonVariant.secondary,
                    color: accentColor,
                    onPressed: controller.reset,
                  ),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }

  _HitTestResult? _hitTestRegions(Offset pos, List<RedactionRegion> regions, double scale) {
    for (final region in regions.reversed) {
      final l = region.rect.left * scale;
      final t = region.rect.top * scale;
      final r = region.rect.right * scale;
      final b = region.rect.bottom * scale;

      const handleSize = 14.0;

      if ((pos.dx - l).abs() <= handleSize && (pos.dy - t).abs() <= handleSize) {
        return _HitTestResult(region.id, _DragHandleType.topLeft);
      }
      if ((pos.dx - r).abs() <= handleSize && (pos.dy - t).abs() <= handleSize) {
        return _HitTestResult(region.id, _DragHandleType.topRight);
      }
      if ((pos.dx - l).abs() <= handleSize && (pos.dy - b).abs() <= handleSize) {
        return _HitTestResult(region.id, _DragHandleType.bottomLeft);
      }
      if ((pos.dx - r).abs() <= handleSize && (pos.dy - b).abs() <= handleSize) {
        return _HitTestResult(region.id, _DragHandleType.bottomRight);
      }

      if (pos.dx >= l && pos.dx <= r && pos.dy >= t && pos.dy <= b) {
        return _HitTestResult(region.id, _DragHandleType.body);
      }
    }
    return null;
  }
}

enum _DragHandleType {
  body,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class _HitTestResult {
  final String regionId;
  final _DragHandleType handleType;

  _HitTestResult(this.regionId, this.handleType);
}
