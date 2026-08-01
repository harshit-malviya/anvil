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
import 'image_crop_rotate_controller.dart';
import 'image_crop_rotate_state.dart';

class ImageCropRotateScreen extends ConsumerStatefulWidget {
  const ImageCropRotateScreen({super.key});

  @override
  ConsumerState<ImageCropRotateScreen> createState() =>
      _ImageCropRotateScreenState();
}

class _ImageCropRotateScreenState
    extends ConsumerState<ImageCropRotateScreen> {
  final FileService _fileService = FileService();

  Future<void> _pickImage() async {
    final files = await _fileService.pickImageFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(imageCropRotateControllerProvider.notifier).loadImage(files.first);
    }
  }

  Future<bool> _confirmDiscardUnsavedChanges() async {
    final state = ref.read(imageCropRotateControllerProvider);
    if (!state.hasUnsavedChanges || state.isSuccess) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final brightness = Theme.of(context).brightness;
        return AlertDialog(
          backgroundColor: AppColors.cardBackground(brightness),
          title: Text(
            'Discard unsaved changes?',
            style: AppTypography.titleMedium(brightness),
          ),
          content: Text(
            'You have unapplied crop or rotation changes. Navigating away will discard them.',
            style: AppTypography.bodyMedium(brightness),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.text(brightness).withValues(alpha: 0.6)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.rustRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = ref.watch(imageCropRotateControllerProvider);
    final notifier = ref.read(imageCropRotateControllerProvider.notifier);
    final accentColor =
        AppColors.familyAccent(ToolCategory.image, brightness);

    return PopScope(
      canPop: !state.hasUnsavedChanges || state.isSuccess,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardUnsavedChanges();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background(brightness),
        appBar: AppBar(
          backgroundColor: AppColors.background(brightness),
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: AppColors.text(brightness)),
            onPressed: () async {
              if (await _confirmDiscardUnsavedChanges()) {
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
          title: Text(
            'Crop & Rotate Image',
            style: AppTypography.titleMedium(brightness),
          ),
          actions: [
            const ThemeToggleButton(),
            if (state.isLoaded && !state.isSuccess)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset Image',
                onPressed: notifier.reset,
              ),
          ],
        ),
        body: Column(
          children: [
            if (state.errorMessage != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: AppColors.rustRed.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.rustRed, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        state.errorMessage!,
                        style: TextStyle(
                          color: AppColors.rustRed,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.rustRed, size: 18),
                      onPressed: notifier.clearError,
                    ),
                  ],
                ),
              ),

            Expanded(
              child: state.isSuccess
                  ? _buildSuccessView(context, state, notifier, brightness)
                  : !state.isLoaded
                      ? _buildDropZone(context, brightness, accentColor)
                      : _buildEditorView(context, state, notifier, brightness, accentColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropZone(
    BuildContext context,
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
                  onTap: _pickImage,
                  label: 'Drop image here or click to browse',
                  sublabel: 'Supports PNG, JPEG, BMP, GIF, TIFF, and WebP',
                  icon: Icons.crop_rotate_rounded,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorView(
    BuildContext context,
    ImageCropRotateState state,
    ImageCropRotateController notifier,
    Brightness brightness,
    Color accentColor,
  ) {
    return Column(
      children: [
        // Top Toolbar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.cardBackground(brightness),
            border: Border(
              bottom: BorderSide(
                color: AppColors.pegGrey.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Rotate Button
                  AppButton(
                    label: 'Rotate (${state.rotation}°)',
                    icon: Icons.rotate_right_rounded,
                    variant: AppButtonVariant.secondary,
                    color: accentColor,
                    onPressed: notifier.rotate,
                  ),
                  const SizedBox(width: 16),

                  // Aspect Ratio Label
                  Text(
                    'Ratio:',
                    style: AppTypography.labelSmall(brightness),
                  ),
                  const SizedBox(width: 8),

                  // Aspect Ratio Selector Chips
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: AspectRatioPreset.values.map((preset) {
                          final isSelected = state.aspectRatioPreset == preset;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: ChoiceChip(
                              label: Text(preset.label),
                              selected: isSelected,
                              selectedColor: accentColor.withValues(alpha: 0.2),
                              side: BorderSide(
                                color: isSelected
                                    ? accentColor
                                    : AppColors.pegGrey.withValues(alpha: 0.4),
                              ),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? accentColor
                                    : AppColors.text(brightness),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              onSelected: (_) => notifier.setAspectRatioPreset(preset),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Reset Selection Button
                  IconButton(
                    icon: const Icon(Icons.center_focus_weak_rounded),
                    tooltip: 'Reset Selection',
                    onPressed: () {
                      notifier.setCropRect(
                        Rect.fromLTWH(
                          0,
                          0,
                          state.currentWidth.toDouble(),
                          state.currentHeight.toDouble(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              if (state.rotationResetNoticeVisible) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Changing rotation resets your crop selection.',
                          style: TextStyle(
                            fontSize: 12,
                            color: brightness == Brightness.dark
                                ? Colors.amber[200]
                                : Colors.amber[900],
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: notifier.dismissRotationResetNotice,
                        child: const Icon(Icons.close, size: 14, color: Colors.amber),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Middle Canvas Interactive Crop Area
        Expanded(
          child: Container(
            color: brightness == Brightness.dark
                ? const Color(0xFF141619)
                : const Color(0xFFE5E5E5),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _CropCanvasOverlay(
                state: state,
                accentColor: accentColor,
                onCropChanged: (newRect) {
                  notifier.setCropRect(newRect);
                },
              ),
            ),
          ),
        ),

        // Bottom Readout & Apply Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.cardBackground(brightness),
            border: Border(
              top: BorderSide(
                color: AppColors.pegGrey.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'OUTPUT DIMENSIONS',
                        style: AppTypography.labelSmall(brightness),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${state.outputWidth} × ${state.outputHeight} px',
                        style: AppTypography.titleMedium(brightness).copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                AppButton(
                  label: state.isProcessing ? 'Applying…' : 'Apply',
                  icon: Icons.crop_rotate_rounded,
                  variant: AppButtonVariant.primary,
                  color: accentColor,
                  onPressed: state.isProcessing ? null : notifier.apply,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    ImageCropRotateState state,
    ImageCropRotateController notifier,
    Brightness brightness,
  ) {
    final accentColor = AppColors.familyAccent(ToolCategory.image, brightness);
    String formatBytes(int bytes) {
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StampAnimation(label: 'EXPORTED', color: accentColor),
            const SizedBox(height: 20),
            Text(
              'Image Edited Successfully',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Summary Card
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground(brightness),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.pegGrey.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Original Dimensions:',
                            style: AppTypography.bodyMedium(brightness)),
                        Text('${state.originalWidth} × ${state.originalHeight} px',
                            style: AppTypography.bodyMedium(brightness)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Output Dimensions:',
                            style: AppTypography.bodyMedium(brightness)),
                        Text(
                          '${state.outputWidth} × ${state.outputHeight} px',
                          style: AppTypography.bodyMedium(brightness).copyWith(
                            color: accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Output Size:',
                            style: AppTypography.bodyMedium(brightness)),
                        Text(formatBytes(state.outputSizeBytes ?? 0),
                            style: AppTypography.bodyMedium(brightness)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Saved to path container
            if (state.outputPath != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Container(
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
                        state.outputPath!,
                        style: AppTypography.bodySmall(brightness),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Actions
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
                  onPressed: notifier.openFolder,
                ),
                AppButton(
                  label: 'Save As…',
                  icon: Icons.save_alt_rounded,
                  variant: AppButtonVariant.secondary,
                  color: accentColor,
                  onPressed: notifier.saveAs,
                ),
                AppButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  variant: AppButtonVariant.secondary,
                  color: accentColor,
                  onPressed: notifier.shareFile,
                ),
                AppButton(
                  label: 'Edit Another Image',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  color: accentColor,
                  onPressed: notifier.reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive Canvas Overlay widget for crop rectangle dragging and handle resizing.
class _CropCanvasOverlay extends StatefulWidget {
  final ImageCropRotateState state;
  final Color accentColor;
  final ValueChanged<Rect> onCropChanged;

  const _CropCanvasOverlay({
    required this.state,
    required this.accentColor,
    required this.onCropChanged,
  });

  @override
  State<_CropCanvasOverlay> createState() => _CropCanvasOverlayState();
}

enum _DragHandle { none, body, topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right }

class _CropCanvasOverlayState extends State<_CropCanvasOverlay> {
  _DragHandle _activeHandle = _DragHandle.none;
  Offset? _dragStartOffset;
  Rect? _initialCropRect;
  MouseCursor _hoverCursor = SystemMouseCursors.basic;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.thumbnailBytes == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final currentW = state.currentWidth.toDouble();
        final currentH = state.currentHeight.toDouble();

        if (currentW == 0 || currentH == 0) return const SizedBox.shrink();

        // Calculate maximum fitted dimensions for image in available space
        final maxDisplayW = constraints.maxWidth;
        final maxDisplayH = constraints.maxHeight;

        final imageAspect = currentW / currentH;
        final containerAspect = maxDisplayW / maxDisplayH;

        double displayW;
        double displayH;

        if (containerAspect > imageAspect) {
          displayH = maxDisplayH;
          displayW = displayH * imageAspect;
        } else {
          displayW = maxDisplayW;
          displayH = displayW / imageAspect;
        }

        final scale = displayW / currentW; // Screen pixels per source image pixel

        // Convert cropRect from source pixel space to screen display space
        final displayCrop = Rect.fromLTWH(
          state.cropRect.left * scale,
          state.cropRect.top * scale,
          state.cropRect.width * scale,
          state.cropRect.height * scale,
        );

        return Container(
          width: displayW,
          height: displayH,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Display image (rotated visually per state.rotation)
              Positioned.fill(
                child: RotatedBox(
                  quarterTurns: state.rotation ~/ 90,
                  child: Image.memory(
                    state.thumbnailBytes!,
                    fit: BoxFit.fill,
                  ),
                ),
              ),

              // 2. Translucent darkened mask outside crop box
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropMaskPainter(cropRect: displayCrop),
                ),
              ),

              // 3. Crop Rectangle Border & Grid Lines
              Positioned.fromRect(
                rect: displayCrop,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: widget.accentColor, width: 2),
                  ),
                  child: CustomPaint(
                    painter: _GridLinesPainter(accentColor: widget.accentColor),
                  ),
                ),
              ),

              // 4. Visual Corner & Edge Handles (wrapped in IgnorePointer so gestures pass through to top layer)
              IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: _buildHandleVisuals(displayCrop, widget.accentColor),
                ),
              ),

              // 5. TOP-MOST Gesture & Mouse Hover Controller Layer
              Positioned.fill(
                child: MouseRegion(
                  cursor: _hoverCursor,
                  onHover: (event) {
                    final cursor = _getCursorForPosition(event.localPosition, displayCrop);
                    if (cursor != _hoverCursor) {
                      setState(() {
                        _hoverCursor = cursor;
                      });
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) {
                      _onPanStart(details.localPosition, displayCrop);
                    },
                    onPanUpdate: (details) {
                      _onPanUpdate(details.localPosition, scale);
                    },
                    onPanEnd: (_) {
                      setState(() {
                        _activeHandle = _DragHandle.none;
                        _dragStartOffset = null;
                        _initialCropRect = null;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  MouseCursor _getCursorForPosition(Offset pos, Rect displayCrop) {
    const touchRadius = 24.0;

    if ((pos - displayCrop.topLeft).distance < touchRadius) {
      return SystemMouseCursors.resizeUpLeft;
    } else if ((pos - displayCrop.topRight).distance < touchRadius) {
      return SystemMouseCursors.resizeUpRight;
    } else if ((pos - displayCrop.bottomLeft).distance < touchRadius) {
      return SystemMouseCursors.resizeDownLeft;
    } else if ((pos - displayCrop.bottomRight).distance < touchRadius) {
      return SystemMouseCursors.resizeDownRight;
    } else if ((pos - displayCrop.topCenter).distance < touchRadius) {
      return SystemMouseCursors.resizeUp;
    } else if ((pos - displayCrop.bottomCenter).distance < touchRadius) {
      return SystemMouseCursors.resizeDown;
    } else if ((pos - displayCrop.centerLeft).distance < touchRadius) {
      return SystemMouseCursors.resizeLeft;
    } else if ((pos - displayCrop.centerRight).distance < touchRadius) {
      return SystemMouseCursors.resizeRight;
    } else if (displayCrop.contains(pos)) {
      return SystemMouseCursors.move;
    }
    return SystemMouseCursors.basic;
  }

  List<Widget> _buildHandleVisuals(Rect displayCrop, Color color) {
    const handleSize = 16.0;
    const half = handleSize / 2;

    Widget makeHandle(double left, double top) {
      return Positioned(
        left: left - half,
        top: top - half,
        child: Container(
          width: handleSize,
          height: handleSize,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      );
    }

    return [
      // 4 corners
      makeHandle(displayCrop.left, displayCrop.top),
      makeHandle(displayCrop.right, displayCrop.top),
      makeHandle(displayCrop.left, displayCrop.bottom),
      makeHandle(displayCrop.right, displayCrop.bottom),

      // 4 edges
      makeHandle(displayCrop.centerLeft.dx, displayCrop.centerLeft.dy),
      makeHandle(displayCrop.centerRight.dx, displayCrop.centerRight.dy),
      makeHandle(displayCrop.topCenter.dx, displayCrop.topCenter.dy),
      makeHandle(displayCrop.bottomCenter.dx, displayCrop.bottomCenter.dy),
    ];
  }

  void _onPanStart(Offset pos, Rect displayCrop) {
    const touchRadius = 24.0;

    _DragHandle hit = _DragHandle.none;

    if ((pos - displayCrop.topLeft).distance < touchRadius) {
      hit = _DragHandle.topLeft;
    } else if ((pos - displayCrop.topRight).distance < touchRadius) {
      hit = _DragHandle.topRight;
    } else if ((pos - displayCrop.bottomLeft).distance < touchRadius) {
      hit = _DragHandle.bottomLeft;
    } else if ((pos - displayCrop.bottomRight).distance < touchRadius) {
      hit = _DragHandle.bottomRight;
    } else if ((pos - displayCrop.topCenter).distance < touchRadius) {
      hit = _DragHandle.top;
    } else if ((pos - displayCrop.bottomCenter).distance < touchRadius) {
      hit = _DragHandle.bottom;
    } else if ((pos - displayCrop.centerLeft).distance < touchRadius) {
      hit = _DragHandle.left;
    } else if ((pos - displayCrop.centerRight).distance < touchRadius) {
      hit = _DragHandle.right;
    } else if (displayCrop.contains(pos)) {
      hit = _DragHandle.body;
    }

    setState(() {
      _activeHandle = hit;
      _dragStartOffset = pos;
      _initialCropRect = widget.state.cropRect;
    });
  }

  void _onPanUpdate(Offset pos, double scale) {
    if (_activeHandle == _DragHandle.none ||
        _dragStartOffset == null ||
        _initialCropRect == null) {
      return;
    }

    final deltaScreen = pos - _dragStartOffset!;
    final deltaPixel = deltaScreen / scale;

    final init = _initialCropRect!;
    final maxW = widget.state.currentWidth.toDouble();
    final maxH = widget.state.currentHeight.toDouble();
    final targetRatio = widget.state.aspectRatioPreset.getRatio(maxW, maxH);

    // Free Mode or Body Move
    if (targetRatio == null || _activeHandle == _DragHandle.body) {
      double left = init.left;
      double top = init.top;
      double right = init.right;
      double bottom = init.bottom;

      switch (_activeHandle) {
        case _DragHandle.body:
          final w = init.width;
          final h = init.height;
          left = (init.left + deltaPixel.dx).clamp(0.0, maxW - w);
          top = (init.top + deltaPixel.dy).clamp(0.0, maxH - h);
          right = left + w;
          bottom = top + h;
          break;

        case _DragHandle.topLeft:
          left = (init.left + deltaPixel.dx).clamp(0.0, init.right - 10);
          top = (init.top + deltaPixel.dy).clamp(0.0, init.bottom - 10);
          break;

        case _DragHandle.topRight:
          right = (init.right + deltaPixel.dx).clamp(init.left + 10, maxW);
          top = (init.top + deltaPixel.dy).clamp(0.0, init.bottom - 10);
          break;

        case _DragHandle.bottomLeft:
          left = (init.left + deltaPixel.dx).clamp(0.0, init.right - 10);
          bottom = (init.bottom + deltaPixel.dy).clamp(init.top + 10, maxH);
          break;

        case _DragHandle.bottomRight:
          right = (init.right + deltaPixel.dx).clamp(init.left + 10, maxW);
          bottom = (init.bottom + deltaPixel.dy).clamp(init.top + 10, maxH);
          break;

        case _DragHandle.top:
          top = (init.top + deltaPixel.dy).clamp(0.0, init.bottom - 10);
          break;

        case _DragHandle.bottom:
          bottom = (init.bottom + deltaPixel.dy).clamp(init.top + 10, maxH);
          break;

        case _DragHandle.left:
          left = (init.left + deltaPixel.dx).clamp(0.0, init.right - 10);
          break;

        case _DragHandle.right:
          right = (init.right + deltaPixel.dx).clamp(init.left + 10, maxW);
          break;

        case _DragHandle.none:
          break;
      }

      widget.onCropChanged(Rect.fromLTRB(left, top, right, bottom));
      return;
    }

    // Aspect Ratio Locked Mode for all 8 Handles
    final R = targetRatio;
    Rect newRect = init;

    switch (_activeHandle) {
      case _DragHandle.top:
        double newH = (init.height - deltaPixel.dy).clamp(10.0, init.bottom);
        double newW = newH * R;
        if (newW > maxW) {
          newW = maxW;
          newH = newW / R;
        }
        final newTop = init.bottom - newH;
        final newLeft = (init.center.dx - newW / 2).clamp(0.0, maxW - newW);
        newRect = Rect.fromLTWH(newLeft, newTop, newW, newH);
        break;

      case _DragHandle.bottom:
        double newH = (init.height + deltaPixel.dy).clamp(10.0, maxH - init.top);
        double newW = newH * R;
        if (newW > maxW) {
          newW = maxW;
          newH = newW / R;
        }
        final newLeft = (init.center.dx - newW / 2).clamp(0.0, maxW - newW);
        newRect = Rect.fromLTWH(newLeft, init.top, newW, newH);
        break;

      case _DragHandle.left:
        double newW = (init.width - deltaPixel.dx).clamp(10.0, init.right);
        double newH = newW / R;
        if (newH > maxH) {
          newH = maxH;
          newW = newH * R;
        }
        final newTop = (init.center.dy - newH / 2).clamp(0.0, maxH - newH);
        newRect = Rect.fromLTWH(init.right - newW, newTop, newW, newH);
        break;

      case _DragHandle.right:
        double newW = (init.width + deltaPixel.dx).clamp(10.0, maxW - init.left);
        double newH = newW / R;
        if (newH > maxH) {
          newH = maxH;
          newW = newH * R;
        }
        final newTop = (init.center.dy - newH / 2).clamp(0.0, maxH - newH);
        newRect = Rect.fromLTWH(init.left, newTop, newW, newH);
        break;

      case _DragHandle.bottomRight:
        double candW = (init.width + deltaPixel.dx).clamp(10.0, maxW - init.left);
        double candH = (init.height + deltaPixel.dy).clamp(10.0, maxH - init.top);
        double w = candW;
        double h = w / R;
        if (h > candH) {
          h = candH;
          w = h * R;
        }
        newRect = Rect.fromLTWH(init.left, init.top, w, h);
        break;

      case _DragHandle.bottomLeft:
        double candW = (init.width - deltaPixel.dx).clamp(10.0, init.right);
        double candH = (init.height + deltaPixel.dy).clamp(10.0, maxH - init.top);
        double w = candW;
        double h = w / R;
        if (h > candH) {
          h = candH;
          w = h * R;
        }
        newRect = Rect.fromLTRB(init.right - w, init.top, init.right, init.top + h);
        break;

      case _DragHandle.topLeft:
        double candW = (init.width - deltaPixel.dx).clamp(10.0, init.right);
        double candH = (init.height - deltaPixel.dy).clamp(10.0, init.bottom);
        double w = candW;
        double h = w / R;
        if (h > candH) {
          h = candH;
          w = h * R;
        }
        newRect = Rect.fromLTRB(init.right - w, init.bottom - h, init.right, init.bottom);
        break;

      case _DragHandle.topRight:
        double candW = (init.width + deltaPixel.dx).clamp(10.0, maxW - init.left);
        double candH = (init.height - deltaPixel.dy).clamp(10.0, init.bottom);
        double w = candW;
        double h = w / R;
        if (h > candH) {
          h = candH;
          w = h * R;
        }
        newRect = Rect.fromLTRB(init.left, init.bottom - h, init.left + w, init.bottom);
        break;

      default:
        break;
    }

    widget.onCropChanged(newRect);
  }
}

class _CropMaskPainter extends CustomPainter {
  final Rect cropRect;

  _CropMaskPainter({required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final outerPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final innerPath = Path()..addRect(cropRect);
    final combined = Path.combine(PathOperation.difference, outerPath, innerPath);

    canvas.drawPath(combined, paint);
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}

class _GridLinesPainter extends CustomPainter {
  final Color accentColor;

  _GridLinesPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw 3x3 rule-of-thirds grid lines
    final w = size.width;
    final h = size.height;

    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), paint);
    canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), paint);

    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), paint);
    canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), paint);
  }

  @override
  bool shouldRepaint(covariant _GridLinesPainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }
}
