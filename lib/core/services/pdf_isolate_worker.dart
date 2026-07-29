import 'dart:ui';
import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// ──────────────────────────────────────────────────────────────────────────────
// MERGE
// ──────────────────────────────────────────────────────────────────────────────

/// Parameter container for merge isolate.
class MergeParams {
  final List<Uint8List> fileBytesList;
  final List<String> fileNames;
  final bool insertDividers;
  final double dividerFontSize;
  final bool dividerIsBold;
  final Uint8List? fontBytes;

  /// Pre-rendered PNG image bytes per divider page (for source files 2..N).
  final List<Uint8List>? dividerImages;

  const MergeParams({
    required this.fileBytesList,
    this.fileNames = const [],
    this.insertDividers = false,
    this.dividerFontSize = 14.0,
    this.dividerIsBold = false,
    this.fontBytes,
    this.dividerImages,
  });
}

/// Input: MergeParams.
/// Output: merged PDF bytes.
Future<Uint8List> isolateMergePdfs(MergeParams params) async {
  final destinationDoc = PdfDocument();

  for (int k = 0; k < params.fileBytesList.length; k++) {
    final fileBytes = params.fileBytesList[k];
    final sourceDoc = PdfDocument(inputBytes: fileBytes);

    if (params.insertDividers && k > 0 && sourceDoc.pages.count > 0) {
      final firstPageSize = sourceDoc.pages[0].size;
      final dividerWidth = firstPageSize.width;
      const dividerHeight = 72.0; // 1 inch = 72 pt

      final dividerSection = destinationDoc.sections!.add();
      dividerSection.pageSettings.size = Size(dividerWidth, dividerHeight);
      dividerSection.pageSettings.margins.all = 0;
      if (dividerWidth > dividerHeight) {
        dividerSection.pageSettings.orientation = PdfPageOrientation.landscape;
      } else {
        dividerSection.pageSettings.orientation = PdfPageOrientation.portrait;
      }

      final dividerPage = dividerSection.pages.add();

      // Check if a pre-rendered HarfBuzz-shaped PNG image is provided for this divider
      final dividerImgIndex = k - 1;
      if (params.dividerImages != null &&
          dividerImgIndex < params.dividerImages!.length &&
          params.dividerImages![dividerImgIndex].isNotEmpty) {
        final pdfImage = PdfBitmap(params.dividerImages![dividerImgIndex]);
        dividerPage.graphics.drawImage(
          pdfImage,
          Rect.fromLTWH(0, 0, dividerWidth, dividerHeight),
        );
      } else {
        // Fallback: draw background and text directly
        dividerPage.graphics.drawRectangle(
          brush: PdfSolidBrush(PdfColor(255, 255, 255)),
          bounds: Rect.fromLTWH(0, 0, dividerWidth, dividerHeight),
        );

        final fileName = params.fileNames.length > k ? params.fileNames[k] : '';
        if (fileName.isNotEmpty) {
          PdfFont font;
          final fontSize = params.dividerFontSize;
          final isBold = params.dividerIsBold;
          if (params.fontBytes != null && params.fontBytes!.isNotEmpty) {
            try {
              font = PdfTrueTypeFont(params.fontBytes!, fontSize);
            } catch (_) {
              font = PdfStandardFont(
                PdfFontFamily.courier,
                fontSize,
                style: isBold ? PdfFontStyle.bold : PdfFontStyle.regular,
              );
            }
          } else {
            font = PdfStandardFont(
              PdfFontFamily.courier,
              fontSize,
              style: isBold ? PdfFontStyle.bold : PdfFontStyle.regular,
            );
          }

          final textBrush = PdfSolidBrush(PdfColor(0x1E, 0x22, 0x26));
          final maxAllowedWidth = dividerWidth * 0.9;

          String displayText = fileName;
          Size textSize = font.measureString(displayText);

          if (textSize.width > maxAllowedWidth) {
            while (displayText.isNotEmpty && font.measureString('$displayText...').width > maxAllowedWidth) {
              displayText = displayText.characters.skipLast(1).toString();
            }
            displayText = '$displayText...';
            textSize = font.measureString(displayText);
          }

          final textX = (dividerWidth - textSize.width) / 2;
          final textY = (dividerHeight - textSize.height) / 2;

          dividerPage.graphics.drawString(
            displayText,
            font,
            brush: textBrush,
            bounds: Rect.fromLTWH(textX, textY, textSize.width, textSize.height),
          );
        }
      }
    }

    for (int i = 0; i < sourceDoc.pages.count; i++) {
      final page = sourceDoc.pages[i];
      final section = destinationDoc.sections!.add();
      section.pageSettings.size = page.size;
      section.pageSettings.margins.all = 0;
      if (page.size.width > page.size.height) {
        section.pageSettings.orientation = PdfPageOrientation.landscape;
      } else {
        section.pageSettings.orientation = PdfPageOrientation.portrait;
      }

      final template = page.createTemplate();
      final newPage = section.pages.add();
      newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), page.size);
    }
    sourceDoc.dispose();
  }

  final List<int> mergedBytes = await destinationDoc.save();
  destinationDoc.dispose();
  return Uint8List.fromList(mergedBytes);
}

// ──────────────────────────────────────────────────────────────────────────────
// COMPRESS
// ──────────────────────────────────────────────────────────────────────────────

/// Parameter container for compress isolate.
class CompressParams {
  final Uint8List inputBytes;

  /// 0 = low (normal), 1 = medium (best), 2 = high (best)
  final int levelIndex;

  const CompressParams({required this.inputBytes, required this.levelIndex});
}

/// Input: CompressParams.
/// Output: compressed PDF bytes.
Future<Uint8List> isolateCompressPdf(CompressParams params) async {
  final sourceDoc = PdfDocument(inputBytes: params.inputBytes);
  final destDoc = PdfDocument();

  switch (params.levelIndex) {
    case 0:
      destDoc.compressionLevel = PdfCompressionLevel.normal;
      break;
    case 1:
    case 2:
      destDoc.compressionLevel = PdfCompressionLevel.best;
      break;
    default:
      destDoc.compressionLevel = PdfCompressionLevel.best;
  }

  for (int i = 0; i < sourceDoc.pages.count; i++) {
    final sourcePage = sourceDoc.pages[i];
    final section = destDoc.sections!.add();
    section.pageSettings.size = sourcePage.size;
    section.pageSettings.margins.all = 0;
    if (sourcePage.size.width > sourcePage.size.height) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    } else {
      section.pageSettings.orientation = PdfPageOrientation.portrait;
    }

    final template = sourcePage.createTemplate();
    final newPage = section.pages.add();
    newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
  }

  sourceDoc.dispose();

  final List<int> compressedBytes = await destDoc.save();
  destDoc.dispose();
  return Uint8List.fromList(compressedBytes);
}

// ──────────────────────────────────────────────────────────────────────────────
// SPLIT
// ──────────────────────────────────────────────────────────────────────────────

/// One page range for splitting (1-indexed, inclusive).
class SplitRange {
  final int startPage;
  final int endPage;
  const SplitRange({required this.startPage, required this.endPage});
}

/// Parameter container for split isolate.
class SplitParams {
  final Uint8List inputBytes;
  final List<SplitRange> ranges;
  const SplitParams({required this.inputBytes, required this.ranges});
}

/// Input: SplitParams.
/// Output: list of Uint8List (one per split file).
Future<List<Uint8List>> isolateSplitPdf(SplitParams params) async {
  final sourceDoc = PdfDocument(inputBytes: params.inputBytes);
  final List<Uint8List> results = [];

  for (final range in params.ranges) {
    final destDoc = PdfDocument();

    for (int pIdx = range.startPage - 1; pIdx < range.endPage; pIdx++) {
      final sourcePage = sourceDoc.pages[pIdx];
      final section = destDoc.sections!.add();
      section.pageSettings.size = sourcePage.size;
      section.pageSettings.margins.all = 0;
      if (sourcePage.size.width > sourcePage.size.height) {
        section.pageSettings.orientation = PdfPageOrientation.landscape;
      } else {
        section.pageSettings.orientation = PdfPageOrientation.portrait;
      }

      final template = sourcePage.createTemplate();
      final newPage = section.pages.add();
      newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
    }

    final List<int> pdfBytes = await destDoc.save();
    destDoc.dispose();
    results.add(Uint8List.fromList(pdfBytes));
  }

  sourceDoc.dispose();
  return results;
}

// ──────────────────────────────────────────────────────────────────────────────
// ARRANGE PAGES (Page Manager)
// ──────────────────────────────────────────────────────────────────────────────

/// Describes one page in the arrangement: its original index and rotation.
class ArrangedPage {
  final int originalIndex;

  /// Rotation in degrees: 0, 90, 180, 270.
  final int rotation;

  const ArrangedPage({required this.originalIndex, required this.rotation});
}

/// Parameter container for page arrange isolate.
class ArrangePagesParams {
  final Uint8List inputBytes;
  final List<ArrangedPage> pages;
  const ArrangePagesParams({required this.inputBytes, required this.pages});
}

/// Input: ArrangePagesParams.
/// Output: rearranged PDF bytes.
Future<Uint8List> isolateArrangePages(ArrangePagesParams params) async {
  final sourceDoc = PdfDocument(inputBytes: params.inputBytes);
  final destinationDoc = PdfDocument();

  for (final item in params.pages) {
    final sourcePage = sourceDoc.pages[item.originalIndex];
    final section = destinationDoc.sections!.add();
    section.pageSettings.size = sourcePage.size;
    section.pageSettings.margins.all = 0;

    if (sourcePage.size.width > sourcePage.size.height) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    } else {
      section.pageSettings.orientation = PdfPageOrientation.portrait;
    }

    switch (item.rotation % 360) {
      case 90:
        section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle90;
        break;
      case 180:
        section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle180;
        break;
      case 270:
        section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle270;
        break;
      case 0:
      default:
        section.pageSettings.rotate = PdfPageRotateAngle.rotateAngle0;
        break;
    }

    final template = sourcePage.createTemplate();
    final newPage = section.pages.add();
    newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
  }

  sourceDoc.dispose();

  final List<int> outputBytes = await destinationDoc.save();
  destinationDoc.dispose();
  return Uint8List.fromList(outputBytes);
}

// ──────────────────────────────────────────────────────────────────────────────
// PASSWORD — ADD
// ──────────────────────────────────────────────────────────────────────────────

/// Parameter container for add-password isolate.
class AddPasswordParams {
  final Uint8List inputBytes;
  final String password;
  const AddPasswordParams({required this.inputBytes, required this.password});
}

/// Input: AddPasswordParams.
/// Output: password-protected PDF bytes.
Future<Uint8List> isolateAddPassword(AddPasswordParams params) async {
  final sourceDoc = PdfDocument(inputBytes: params.inputBytes);
  final destDoc = PdfDocument();

  destDoc.security.userPassword = params.password;
  destDoc.security.ownerPassword = params.password;

  for (int i = 0; i < sourceDoc.pages.count; i++) {
    final sourcePage = sourceDoc.pages[i];
    final section = destDoc.sections!.add();
    section.pageSettings.size = sourcePage.size;
    section.pageSettings.margins.all = 0;
    if (sourcePage.size.width > sourcePage.size.height) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    } else {
      section.pageSettings.orientation = PdfPageOrientation.portrait;
    }

    final template = sourcePage.createTemplate();
    final newPage = section.pages.add();
    newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
  }

  sourceDoc.dispose();

  final List<int> protectedBytes = await destDoc.save();
  destDoc.dispose();
  return Uint8List.fromList(protectedBytes);
}

// ──────────────────────────────────────────────────────────────────────────────
// PASSWORD — REMOVE
// ──────────────────────────────────────────────────────────────────────────────

/// Parameter container for remove-password isolate.
class RemovePasswordParams {
  final Uint8List inputBytes;
  final String password;
  const RemovePasswordParams({required this.inputBytes, required this.password});
}

/// Input: RemovePasswordParams.
/// Output: unprotected PDF bytes.
Future<Uint8List> isolateRemovePassword(RemovePasswordParams params) async {
  final sourceDoc = PdfDocument(
    inputBytes: params.inputBytes,
    password: params.password,
  );
  final destDoc = PdfDocument();

  for (int i = 0; i < sourceDoc.pages.count; i++) {
    final sourcePage = sourceDoc.pages[i];
    final section = destDoc.sections!.add();
    section.pageSettings.size = sourcePage.size;
    section.pageSettings.margins.all = 0;
    if (sourcePage.size.width > sourcePage.size.height) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    } else {
      section.pageSettings.orientation = PdfPageOrientation.portrait;
    }

    final template = sourcePage.createTemplate();
    final newPage = section.pages.add();
    newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), sourcePage.size);
  }

  sourceDoc.dispose();

  final List<int> unprotectedBytes = await destDoc.save();
  destDoc.dispose();
  return Uint8List.fromList(unprotectedBytes);
}

// ──────────────────────────────────────────────────────────────────────────────
// INSERT PAGES (splice source pages into target)
// ──────────────────────────────────────────────────────────────────────────────

/// Parameter container for insert-pages isolate.
class InsertPagesParams {
  final Uint8List targetBytes;
  final Uint8List sourceBytes;
  final List<int> selectedSourceIndices;

  /// -1 means at start, 0..N-1 means after that target page index.
  final int insertionPoint;

  const InsertPagesParams({
    required this.targetBytes,
    required this.sourceBytes,
    required this.selectedSourceIndices,
    required this.insertionPoint,
  });
}

/// Helper to copy a single page into a destination document.
void _copyPageToDestination(PdfPage page, PdfDocument destinationDoc) {
  final section = destinationDoc.sections!.add();
  section.pageSettings.size = page.size;
  section.pageSettings.margins.all = 0;
  if (page.size.width > page.size.height) {
    section.pageSettings.orientation = PdfPageOrientation.landscape;
  } else {
    section.pageSettings.orientation = PdfPageOrientation.portrait;
  }

  final template = page.createTemplate();
  final newPage = section.pages.add();
  newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), page.size);
}

/// Input: InsertPagesParams.
/// Output: spliced PDF bytes.
Future<Uint8List> isolateInsertPages(InsertPagesParams params) async {
  final targetDoc = PdfDocument(inputBytes: params.targetBytes);
  final sourceDoc = PdfDocument(inputBytes: params.sourceBytes);
  final destinationDoc = PdfDocument();

  // 1. Copy target pages from index 0 up to insertionPoint (inclusive)
  if (params.insertionPoint >= 0) {
    for (int i = 0; i <= params.insertionPoint && i < targetDoc.pages.count; i++) {
      _copyPageToDestination(targetDoc.pages[i], destinationDoc);
    }
  }

  // 2. Copy selected source pages in chosen order
  for (final srcIdx in params.selectedSourceIndices) {
    if (srcIdx >= 0 && srcIdx < sourceDoc.pages.count) {
      _copyPageToDestination(sourceDoc.pages[srcIdx], destinationDoc);
    }
  }

  // 3. Copy remaining target pages from insertionPoint + 1 to end
  for (int i = params.insertionPoint + 1; i < targetDoc.pages.count; i++) {
    if (i >= 0) {
      _copyPageToDestination(targetDoc.pages[i], destinationDoc);
    }
  }

  targetDoc.dispose();
  sourceDoc.dispose();

  final List<int> resultBytes = await destinationDoc.save();
  destinationDoc.dispose();
  return Uint8List.fromList(resultBytes);
}

// ──────────────────────────────────────────────────────────────────────────────
// INSERT IMAGE(S) AS PAGE(S)
// ──────────────────────────────────────────────────────────────────────────────

/// Single image page specification for isolate processing.
class ImagePageSpec {
  final Uint8List imageBytes;
  final double pageWidth;
  final double pageHeight;
  final double imgLeft;
  final double imgTop;
  final double imgWidth;
  final double imgHeight;

  const ImagePageSpec({
    required this.imageBytes,
    required this.pageWidth,
    required this.pageHeight,
    required this.imgLeft,
    required this.imgTop,
    required this.imgWidth,
    required this.imgHeight,
  });
}

/// Parameter container for insert-image-pages isolate.
class InsertImagePagesParams {
  final Uint8List targetBytes;
  final List<ImagePageSpec> imageSpecs;
  final int insertionPoint;

  const InsertImagePagesParams({
    required this.targetBytes,
    required this.imageSpecs,
    required this.insertionPoint,
  });
}

/// Input: InsertImagePagesParams.
/// Output: PDF bytes with image page(s) inserted.
Future<Uint8List> isolateInsertImagePages(InsertImagePagesParams params) async {
  if (params.imageSpecs.isEmpty) {
    return params.targetBytes;
  }

  // 1. Create multi-page PDF containing all images
  final imgPdf = PdfDocument();

  for (final spec in params.imageSpecs) {
    final section = imgPdf.sections!.add();
    final pageSize = Size(spec.pageWidth, spec.pageHeight);
    section.pageSettings.size = pageSize;
    section.pageSettings.margins.all = 0;
    if (pageSize.width > pageSize.height) {
      section.pageSettings.orientation = PdfPageOrientation.landscape;
    } else {
      section.pageSettings.orientation = PdfPageOrientation.portrait;
    }

    final page = section.pages.add();

    // Draw white background to flatten PNG transparency
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(255, 255, 255)),
      bounds: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
    );

    final pdfImage = PdfBitmap(spec.imageBytes);
    page.graphics.drawImage(
      pdfImage,
      Rect.fromLTWH(spec.imgLeft, spec.imgTop, spec.imgWidth, spec.imgHeight),
    );
  }

  final List<int> imagePdfBytes = await imgPdf.save();
  imgPdf.dispose();

  // 2. Splice image pages into target document
  final selectedIndices = List.generate(params.imageSpecs.length, (index) => index);
  final splicedResult = await isolateInsertPages(InsertPagesParams(
    targetBytes: params.targetBytes,
    sourceBytes: Uint8List.fromList(imagePdfBytes),
    selectedSourceIndices: selectedIndices,
    insertionPoint: params.insertionPoint,
  ));

  return splicedResult;
}
