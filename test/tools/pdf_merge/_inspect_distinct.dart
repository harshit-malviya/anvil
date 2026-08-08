import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:anvil/core/services/pdf_isolate_worker.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pages/pdf_page.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_reference_holder.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_cross_table.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/io/pdf_main_object_collection.dart';
import 'package:crypto/crypto.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Perform deduplication with identical guard on 17MB file and measure output size', () async {
    final file17mb = File(r'C:\Users\harsh\Downloads\AHC\3 - Polity\06 - Constituent Assembly\merged_1786120641086.pdf');
    final bytes17 = file17mb.readAsBytesSync();
    final doc17 = PdfDocument(inputBytes: bytes17);
    final dest = PdfDocument()..compressionLevel = PdfCompressionLevel.best;

    for (int i = 0; i < doc17.pages.count; i++) {
      final page = doc17.pages[i];
      final sec = dest.sections!.add();
      sec.pageSettings.size = page.size;
      sec.pageSettings.margins.all = 0;
      sec.pages.add().graphics.drawPdfTemplate(page.createTemplate(), Offset.zero, page.size);
    }
    doc17.dispose();

    final allStreams = <Map<String, dynamic>>[];
    void collectXObjectStreams(PdfDictionary dict, int pageIdx, String path, Set<int> visited) {
      PdfDictionary? resDict;
      if (dict.containsKey('Resources')) {
        final rp = dict['Resources'];
        if (rp is PdfDictionary) {
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
          allStreams.add({
            'stream': stream,
            'parentDict': xoDict,
            'name': pdfName,
            'pageIdx': pageIdx,
            'path': '$path/${pdfName.name}',
          });
        }

        final id = identityHashCode(stream);
        if (!visited.contains(id)) {
          visited.add(id);
          collectXObjectStreams(stream, pageIdx, '$path/${pdfName.name}', visited);
        }
      });
    }

    for (int i = 0; i < dest.pages.count; i++) {
      final pageHelper = PdfPageHelper.getHelper(dest.pages[i]);
      if (pageHelper.dictionary != null) {
        collectXObjectStreams(pageHelper.dictionary!, i, 'p$i', <int>{});
      }
    }

    final hashGroups = <String, List<Map<String, dynamic>>>{};
    for (final item in allStreams) {
      final stream = item['stream'] as PdfStream;
      final data = stream.dataStream;
      if (data == null || data.isEmpty) continue;
      final dataHash = sha256.convert(data).toString();
      final w = _getPrimitiveValueString(stream['Width']);
      final h = _getPrimitiveValueString(stream['Height']);
      final bpc = _getPrimitiveValueString(stream['BitsPerComponent']);
      final cs = _getPrimitiveValueString(stream['ColorSpace']);
      final compositeKey = '$dataHash|W:$w|H:$h|BPC:$bpc|CS:$cs';
      hashGroups.putIfAbsent(compositeKey, () => []).add(item);
    }

    int repointedCount = 0;
    int skippedIdenticalCount = 0;

    for (final group in hashGroups.values) {
      if (group.length <= 1) continue;
      final canonical = group.first['stream'] as PdfStream;
      for (int i = 1; i < group.length; i++) {
        final dup = group[i];
        final pDict = dup['parentDict'] as PdfDictionary;
        final pName = dup['name'] as PdfName;
        final dStream = dup['stream'] as PdfStream;
        if (identical(canonical, dStream)) {
          skippedIdenticalCount++;
          continue;
        }
        pDict[pName] = PdfReferenceHolder(canonical);
        dStream.isSkip = true;
        repointedCount++;
      }
    }

    print('Skipped identical instances: $skippedIdenticalCount');
    print('Repointed distinct instances: $repointedCount');

    final outBytes = await dest.save();
    dest.dispose();

    print('Dedup ON with Guard output size: ${outBytes.length} bytes (${(outBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');
  });
}
