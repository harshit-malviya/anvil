import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anvil/main.dart';

void main() {
  testWidgets('Anvil app loads home screen and tool cards', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AnvilApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Anvil'), findsOneWidget);
    expect(find.text('Merge PDFs'), findsOneWidget);
    expect(find.text('Page Manager'), findsOneWidget);
  });
}
