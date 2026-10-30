import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/sidebar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('typing a calculation shows its answer', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    expect(editor, findsOneWidget);

    await tester.enterText(editor, '2+3*4');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('14'), findsOneWidget);
  });

  testWidgets('variables and sum work through the UI', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, 'rent = 2500\nfood = 400\nsum');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('2,500'), findsOneWidget);
    expect(find.text('2,900'), findsOneWidget);
  });

  testWidgets('sidebar collapses and comes back', (tester) async {
    await boot(tester);
    expect(find.byType(Sidebar), findsOneWidget);

    await tester.tap(find.byTooltip('Sheets  ⌘\\').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Sidebar), findsNothing);

    await tester.tap(find.byTooltip('Sheets  ⌘\\').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(Sidebar), findsOneWidget);
  });

  testWidgets('answers can be hidden', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '2+3*4');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('14'), findsOneWidget);

    await tester.tap(find.byTooltip('Answers  ⌘⇧A').first);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('14'), findsNothing);
  });
}
