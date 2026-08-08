import 'dart:ui';
import 'package:characters/characters.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/graphics/pdf_resources.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_cross_table.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_reference_holder.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';

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
  destinationDoc.compressionLevel = PdfCompressionLevel.best;

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

  // _deduplicateResources(destinationDoc);

  final List<int> mergedBytes = await destinationDoc.save();
  destinationDoc.dispose();
  return Uint8List.fromList(mergedBytes);
}

// ASSUMPTION: Syncfusion Flutter PDF lacks a native importPage API, so pages are merged via createTemplate().
// createTemplate() snapshots resources per page, creating duplicate PdfStream objects for shared images/resources.
// To prevent severe PDF size bloat without raw byte parsing, we walk the internal object model (via internal primitives),
// compute a composite SHA-256 hash key (stream content + Width, Height, BitsPerComponent, ColorSpace, SMask),
// re-point duplicate references to a canonical stream, and set stream.isSkip = true so Syncfusion's save() skips orphaned streams.

class _StreamInfo {
  final PdfStream stream;
  final PdfDictionary parentDict;
  final PdfName name;

  _StreamInfo({
    required this.stream,
    required this.parentDict,
    required this.name,
  });
}

void _deduplicateResources(PdfDocument doc) {
  final allStreams = <_StreamInfo>[];

  void collectXObjectStreams(PdfDictionary dict, Set<int> visited) {
    PdfDictionary? resDict;
    if (dict.containsKey('Resources')) {
      final rp = dict['Resources'];
      if (rp is PdfResources) {
        resDict = rp;
      } else if (rp is PdfDictionary) {
        resDict = rp;
      } else if (rp is PdfReferenceHolder) {
        resDict = PdfCrossTable.dereference(rp) as PdfDictionary?;
      }
    }
    if (resDict == null || !resDict.containsKey('XObject')) return;

    PdfDictionary? xoDict;
    final xop = resDict['XObject'];
    if (xop is PdfDictionary) {
      xoDict = xop;
    } else if (xop is PdfReferenceHolder) {
      xoDict = PdfCrossTable.dereference(xop) as PdfDictionary?;
    }
    if (xoDict == null) return;

    xoDict.items!.forEach((key, value) {
      if (key == null || value == null) return;
      PdfStream? stream;
      if (value is PdfReferenceHolder) {
        final obj = PdfCrossTable.dereference(value);
        if (obj is PdfStream) stream = obj;
      } else if (value is PdfStream) {
        stream = value;
      }
      if (stream == null) return;

      final pdfName = key is PdfName ? key : PdfName(key.toString());
      if (_isImageStream(stream)) {
        allStreams.add(_StreamInfo(
          stream: stream,
          parentDict: xoDict!,
          name: pdfName,
        ));
      }

      final id = identityHashCode(stream);
      if (!visited.contains(id)) {
        visited.add(id);
        collectXObjectStreams(stream, visited);
      }
    });
  }

  for (int i = 0; i < doc.pages.count; i++) {
    final pageHelper = PdfPageHelper.getHelper(doc.pages[i]);
    if (pageHelper.dictionary != null) {
      collectXObjectStreams(pageHelper.dictionary!, <int>{});
    }
  }

  if (allStreams.isEmpty) return;

  final hashGroups = <String, List<_StreamInfo>>{};

  for (final info in allStreams) {
    final data = info.stream.dataStream;
    if (data == null || data.isEmpty) continue;

    final dataHash = sha256.convert(data).toString();

    final width = _getPrimitiveValueString(info.stream['Width']);
    final height = _getPrimitiveValueString(info.stream['Height']);
    final bpc = _getPrimitiveValueString(info.stream['BitsPerComponent']);
    final colorSpace = _getPrimitiveValueString(info.stream['ColorSpace']);

    String sMaskDetail = 'none';
    if (info.stream.containsKey('SMask')) {
      final sMaskPrim = PdfCrossTable.dereference(info.stream['SMask']);
      if (sMaskPrim is PdfStream) {
        final sMaskData = sMaskPrim.dataStream;
        if (sMaskData != null && sMaskData.isNotEmpty) {
          sMaskDetail = 'stream:${sha256.convert(sMaskData)}';
        } else {
          sMaskDetail = 'stream:empty';
        }
      } else if (sMaskPrim is PdfName) {
        sMaskDetail = 'name:${sMaskPrim.name}';
      } else {
        sMaskDetail = 'present:${sMaskPrim.runtimeType}';
      }
    }

    final compositeKey = '$dataHash|W:$width|H:$height|BPC:$bpc|CS:$colorSpace|SMask:$sMaskDetail';
    hashGroups.putIfAbsent(compositeKey, () => []).add(info);
  }

  for (final group in hashGroups.values) {
    if (group.length <= 1) continue;
    final canonical = group.first.stream;
    for (int i = 1; i < group.length; i++) {
      final dup = group[i];
      dup.parentDict[dup.name] = PdfReferenceHolder(canonical);
      dup.stream.isSkip = true;
    }
  }
}

String _getPrimitiveValueString(dynamic prim) {
  final deref = PdfCrossTable.dereference(prim);
  if (deref == null) return 'null';
  if (deref is PdfNumber) return deref.value.toString();
  if (deref is PdfName) return deref.name ?? 'null';
  if (deref is PdfArray) {
    return deref.elements.map(_getPrimitiveValueString).join(',');
  }
  return deref.toString();
}

bool _isImageStream(PdfStream stream) {
  if (stream.containsKey('Subtype')) {
    final subtype = PdfCrossTable.dereference(stream['Subtype']);
    if (subtype is PdfName) {
      return subtype.name == 'Image';
    }
  }
  return false;
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
    destDoc.compressionLevel = PdfCompressionLevel.best;

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

PdfPageRotateAngle _getRotateAngle(int degrees) {
  switch (degrees % 360) {
    case 90:
      return PdfPageRotateAngle.rotateAngle90;
    case 180:
      return PdfPageRotateAngle.rotateAngle180;
    case 270:
      return PdfPageRotateAngle.rotateAngle270;
    case 0:
    default:
      return PdfPageRotateAngle.rotateAngle0;
  }
}

/// Input: ArrangePagesParams.
/// Output: rearranged PDF bytes.
Future<Uint8List> isolateArrangePages(ArrangePagesParams params) async {
  bool isReordered = false;
  for (int i = 0; i < params.pages.length - 1; i++) {
    if (params.pages[i].originalIndex >= params.pages[i + 1].originalIndex) {
      isReordered = true;
      break;
    }
  }

  if (!isReordered) {
    // FAST PATH: pages remain in original relative order (only deletions and/or rotations).
    // Editing existing document in-place preserves original compression and byte stream.
    final loadedDoc = PdfDocument(inputBytes: params.inputBytes);

    final keptIndices = params.pages.map((p) => p.originalIndex).toSet();

    // Remove non-kept pages in reverse order so indices remain stable
    for (int i = loadedDoc.pages.count - 1; i >= 0; i--) {
      if (!keptIndices.contains(i)) {
        loadedDoc.pages.removeAt(i);
      }
    }

    // Apply rotations to the remaining pages
    for (int i = 0; i < params.pages.length; i++) {
      final rotation = params.pages[i].rotation;
      if (rotation % 360 != 0) {
        final page = loadedDoc.pages[i];
        page.rotation = _getRotateAngle(rotation);
      }
    }

    final List<int> outputBytes = await loadedDoc.save();
    loadedDoc.dispose();
    return Uint8List.fromList(outputBytes);
  }

  // SLOW PATH: pages were reordered. Copy via templates with best compression.
  final sourceDoc = PdfDocument(inputBytes: params.inputBytes);
  final destinationDoc = PdfDocument();
  destinationDoc.compressionLevel = PdfCompressionLevel.best;

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

    section.pageSettings.rotate = _getRotateAngle(item.rotation);

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
  destDoc.compressionLevel = PdfCompressionLevel.best;

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
  destDoc.compressionLevel = PdfCompressionLevel.best;

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
  destinationDoc.compressionLevel = PdfCompressionLevel.best;

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
/// Helper function to construct a multi-page PDF document from image page specs.
Future<Uint8List> buildImagePdfBytes(List<ImagePageSpec> imageSpecs) async {
  final imgPdf = PdfDocument();
  imgPdf.compressionLevel = PdfCompressionLevel.best;

  for (final spec in imageSpecs) {
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
  return Uint8List.fromList(imagePdfBytes);
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
  final Uint8List imagePdfBytes = await buildImagePdfBytes(params.imageSpecs);

  // 2. Splice image pages into target document
  final selectedIndices = List.generate(params.imageSpecs.length, (index) => index);
  final splicedResult = await isolateInsertPages(InsertPagesParams(
    targetBytes: params.targetBytes,
    sourceBytes: imagePdfBytes,
    selectedSourceIndices: selectedIndices,
    insertionPoint: params.insertionPoint,
  ));

  return splicedResult;
}

// ──────────────────────────────────────────────────────────────────────────────
// IMAGES TO PDF (build a new PDF document from multiple images)
// ──────────────────────────────────────────────────────────────────────────────

/// Parameter container for images-to-pdf isolate.
class ImagesToPdfParams {
  final List<ImagePageSpec> imageSpecs;

  const ImagesToPdfParams({
    required this.imageSpecs,
  });
}

/// Input: ImagesToPdfParams.
/// Output: Brand-new PDF document bytes generated from image specs.
Future<Uint8List> isolateImagesToPdf(ImagesToPdfParams params) async {
  if (params.imageSpecs.isEmpty) {
    final emptyDoc = PdfDocument();
    final bytes = await emptyDoc.save();
    emptyDoc.dispose();
    return Uint8List.fromList(bytes);
  }

  return buildImagePdfBytes(params.imageSpecs);
}

