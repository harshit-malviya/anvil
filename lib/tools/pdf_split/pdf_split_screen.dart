import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/file_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import 'pdf_split_controller.dart';
import 'pdf_split_state.dart';

class PdfSplitScreen extends ConsumerStatefulWidget {
  const PdfSplitScreen({super.key});

  @override
  ConsumerState<PdfSplitScreen> createState() => _PdfSplitScreenState();
}

class _PdfSplitScreenState extends ConsumerState<PdfSplitScreen> {
  final FileService _fileService = FileService();
  late TextEditingController _rangeTextController;

  @override
  void initState() {
    super.initState();
    _rangeTextController = TextEditingController();
  }

  @override
  void dispose() {
    _rangeTextController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final files = await _fileService.pickPdfFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(pdfSplitControllerProvider.notifier).loadDocument(files.first);
    }
  }

  Future<void> _handleSplit(PdfSplitState state) async {
    final controller = ref.read(pdfSplitControllerProvider.notifier);
    final ranges = state.calculatedRanges;

    // High split count confirmation guard (> 50 files)
    if (ranges.length > 50) {
      final confirmHigh = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Large Batch Confirmation'),
          content: Text(
            'This will create ${ranges.length} separate files. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmHigh != true) return;
    }

    // Gap confirmation guard (uncovered pages)
    if (state.uncoveredPages.isNotEmpty) {
      final missingText = state.uncoveredPages.length == 1
          ? 'Page ${state.uncoveredPages.first}'
          : 'Pages ${state.uncoveredPages.first}-${state.uncoveredPages.last}';
      final confirmGap = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uncovered Pages'),
          content: Text(
            '$missingText aren\'t included in any range — they\'ll be left out. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmGap != true) return;

      await controller.split(overrideGapCheck: true);
      return;
    }

    await controller.split();
  }

  Future<void> _openOutputFolder(String folderPath) async {
    await _fileService.openFolder(folderPath);
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = ref.watch(pdfSplitControllerProvider);
    final controller = ref.read(pdfSplitControllerProvider.notifier);

    // Keep text field in sync if changed from marker taps
    if (state.mode == SplitMode.customRanges &&
        _rangeTextController.text != state.customRangeText &&
        !_rangeTextController.selection.isValid) {
      _rangeTextController.text = state.customRangeText;
    }

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Split PDF',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.isLoaded)
            IconButton(
              tooltip: 'Reset',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _rangeTextController.clear();
                controller.reset();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.errorMessage != null)
              _buildErrorBanner(context, state.errorMessage!, brightness, controller),
            Expanded(
              child: !state.isLoaded
                  ? _buildEmptyState(brightness)
                  : state.outputFolderPath != null
                      ? _buildSuccessState(context, state, brightness, controller)
                      : _buildMainContent(context, state, brightness, controller),
            ),
            if (state.isLoaded && state.outputFolderPath == null)
              _buildBottomSummaryBar(context, state, brightness),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message,
      Brightness brightness, PdfSplitController controller) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Widget _buildEmptyState(Brightness brightness) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
        child: FileDropZone(
          onTap: _pickFile,
          label: 'Drop PDF file here or click to browse',
          sublabel: 'Select a PDF document to split into smaller files',
          icon: Icons.call_split_rounded,
        ),
      ),
    );
  }

  Widget _buildSuccessState(BuildContext context, PdfSplitState state,
      Brightness brightness, PdfSplitController controller) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const StampAnimation(label: 'SPLIT'),
            const SizedBox(height: 24),
            Text(
              'PDF Split Successfully!',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${state.outputCreatedFileCount} files created in output folder:',
              style: AppTypography.bodyMedium(brightness).copyWith(
                color: AppColors.text(brightness).withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBackground(brightness),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.pegGrey),
              ),
              child: Text(
                state.outputFolderPath ?? '',
                style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                AppButton(
                  label: 'Open Folder',
                  icon: Icons.folder_open,
                  variant: AppButtonVariant.primary,
                  onPressed: () {
                    if (state.outputFolderPath != null) {
                      _openOutputFolder(state.outputFolderPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Split Another PDF',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    _rangeTextController.clear();
                    controller.reset();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, PdfSplitState state,
      Brightness brightness, PdfSplitController controller) {
    return Column(
      children: [
        // Source File info header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: AppColors.cardBackground(brightness),
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf, color: AppColors.primary(brightness)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.file?.name ?? 'Document',
                      style: AppTypography.bodyLarge(brightness)
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${state.totalPageCount} pages',
                      style: AppTypography.mono(brightness).copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Change File'),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Split Mode Selector
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPLIT MODE',
                style: AppTypography.labelSmall(brightness),
              ),
              const SizedBox(height: 8),
              SegmentedButton<SplitMode>(
                segments: const [
                  ButtonSegment<SplitMode>(
                    value: SplitMode.everyPage,
                    label: Text('Every Page'),
                    icon: Icon(Icons.description_outlined),
                  ),
                  ButtonSegment<SplitMode>(
                    value: SplitMode.customRanges,
                    label: Text('Custom Ranges'),
                    icon: Icon(Icons.linear_scale),
                  ),
                  ButtonSegment<SplitMode>(
                    value: SplitMode.equalParts,
                    label: Text('Equal Parts'),
                    icon: Icon(Icons.view_headline),
                  ),
                ],
                selected: {state.mode},
                onSelectionChanged: (Set<SplitMode> newSelection) {
                  controller.setSplitMode(newSelection.first);
                },
              ),
            ],
          ),
        ),

        // Mode specific inputs / controls
        if (state.mode == SplitMode.customRanges) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _rangeTextController,
                  decoration: InputDecoration(
                    labelText: 'Ranges (e.g. 1-3, 4-10, 11-15)',
                    hintText: 'Enter page ranges or tap between thumbnails below',
                    border: const OutlineInputBorder(),
                    errorText: state.rangeValidationError,
                    suffixIcon: _rangeTextController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _rangeTextController.clear();
                              controller.setRangesFromText('');
                            },
                          )
                        : null,
                  ),
                  onChanged: (val) {
                    controller.setRangesFromText(val);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap between page thumbnails below to insert or remove split lines.',
                  style: AppTypography.bodyMedium(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness).withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ] else if (state.mode == SplitMode.equalParts) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Split into',
                  style: AppTypography.bodyLarge(brightness),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    controller: TextEditingController(
                      text: state.equalPartsCount.toString(),
                    ),
                    onSubmitted: (val) {
                      final n = int.tryParse(val) ?? 2;
                      controller.setEqualPartsCount(n);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'equal parts',
                  style: AppTypography.bodyLarge(brightness),
                ),
              ],
            ),
          ),
          if (state.rangeValidationError != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(
                state.rangeValidationError!,
                style: AppTypography.bodyMedium(brightness).copyWith(
                  color: AppColors.rustRed,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],

        if (state.isSinglePage)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
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
                    'This PDF only has one page — nothing to split.',
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          // Page Thumbnail List with Split Markers
          Expanded(
            child: _buildThumbnailGrid(context, state, brightness, controller),
          ),
      ],
    );
  }

  Widget _buildThumbnailGrid(BuildContext context, PdfSplitState state,
      Brightness brightness, PdfSplitController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = (constraints.maxWidth / 130).floor().clamp(2, 6);
          final items = state.thumbnails;

          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.75,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final thumbnail = items[index];
              final isLast = index == items.length - 1;
              final hasMarkerAfter = state.rangeMarkers.contains(index);

              return _buildThumbnailCard(
                context,
                index,
                thumbnail,
                hasMarkerAfter,
                isLast,
                state.mode == SplitMode.customRanges,
                brightness,
                controller,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildThumbnailCard(
    BuildContext context,
    int index,
    PdfSplitThumbnail thumbnail,
    bool hasMarkerAfter,
    bool isLast,
    bool interactiveMarkers,
    Brightness brightness,
    PdfSplitController controller,
  ) {
    final pageNumber = index + 1;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground(brightness),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasMarkerAfter ? AppColors.primary(brightness) : AppColors.pegGrey,
          width: hasMarkerAfter ? 2.0 : 1.0,
        ),
      ),
      child: Stack(
        children: [
          // Page Image or Placeholder
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: thumbnail.thumbnailBytes != null
                  ? Image.memory(
                      thumbnail.thumbnailBytes!,
                      fit: BoxFit.contain,
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 32,
                            color: AppColors.pegGrey,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Page $pageNumber',
                            style: AppTypography.mono(brightness)
                                .copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
            ),
          ),

          // Page Number Badge
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$pageNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Split Marker Overlay Button (on right side of thumbnail if customRanges)
          if (interactiveMarkers && !isLast)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 32,
              child: GestureDetector(
                onTap: () => controller.toggleRangeMarker(index),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  color: hasMarkerAfter
                      ? AppColors.primary(brightness).withValues(alpha: 0.2)
                      : Colors.transparent,
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: hasMarkerAfter
                          ? AppColors.primary(brightness)
                          : AppColors.pegGrey.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.call_split,
                      size: 14,
                      color: hasMarkerAfter ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomSummaryBar(
      BuildContext context, PdfSplitState state, Brightness brightness) {
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUMMARY',
                      style: AppTypography.labelSmall(brightness),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.summaryText,
                      style: AppTypography.bodyMedium(brightness).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AppButton(
                label: 'Split PDF',
                icon: Icons.call_split,
                variant: AppButtonVariant.primary,
                isLoading: state.isProcessing,
                onPressed: state.isSinglePage ||
                        state.rangeValidationError != null ||
                        state.calculatedRanges.isEmpty
                    ? null
                    : () => _handleSplit(state),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
