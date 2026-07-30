import 'dart:typed_data';
import 'package:anvil/tools/pdf_page_manager/pdf_page_manager_controller.dart';
import 'package:anvil/tools/pdf_page_manager/pdf_page_manager_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> createSamplePdf() async {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    'Page 1 Content',
    PdfStandardFont(PdfFontFamily.helvetica, 14),
  );
  final page2 = document.pages.add();
  page2.graphics.drawString(
    'Page 2 Content',
    PdfStandardFont(PdfFontFamily.helvetica, 14),
  );
  final bytes = Uint8List.fromList(await document.save());
  document.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PdfPageManagerScreen opens page preview dialog when preview button is tapped',
      (WidgetTester tester) async {
    final pdfBytes = await createSamplePdf();
    final container = ProviderContainer();
    final controller = container.read(pdfPageManagerControllerProvider.notifier);

    final pf = PlatformFile(name: 'test_doc.pdf', size: pdfBytes.length, bytes: pdfBytes);
    await controller.loadDocument(pf, overrideBytes: pdfBytes);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PdfPageManagerScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify grid cards are loaded
    expect(find.text('PAGE 1'), findsOneWidget);
    expect(find.text('PAGE 2'), findsOneWidget);

    // Tap preview button on Page 1 card
    final previewButtons = find.byTooltip('Preview page content');
    expect(previewButtons, findsAtLeastNWidgets(1));

    await tester.tap(previewButtons.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify preview modal opens displaying "Page 1 of 2"
    expect(find.text('Page 1 of 2'), findsOneWidget);
    expect(find.text('Pinch or scroll to zoom • Use arrow keys to navigate'), findsOneWidget);

    // Tap Next Page button in preview modal
    final nextPageBtn = find.byTooltip('Next Page (Right Arrow)');
    expect(nextPageBtn, findsOneWidget);
    await tester.tap(nextPageBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify preview navigates to Page 2
    expect(find.text('Page 2 of 2'), findsOneWidget);

    // Close preview dialog
    final closeBtn = find.byTooltip('Close preview (Esc)');
    expect(closeBtn, findsOneWidget);
    await tester.tap(closeBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify preview dialog closed
    expect(find.text('Page 2 of 2'), findsNothing);
  });
}
