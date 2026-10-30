import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/theme.dart';
import 'package:tallynote/ui/sidebar.dart';

/// Answers are Text widgets; the editor's EditableText is not one.
Finder answerText(String needle) =>
    find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(needle));

Finder answerExact(String value) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').replaceAll('\u00A0', ' ').trim() == value,
);

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

    expect(find.textContaining('14'), findsOneWidget);
  });

  testWidgets('variables and sum work through the UI', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, 'rent = 2500\nfood = 400\nsum');
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('2,500'), findsOneWidget);
    expect(find.textContaining('2,900'), findsOneWidget);
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

  testWidgets('complex answers expose their steps', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '(1+2)*3');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('9'), findsOneWidget);

    final chevron = find.descendant(
      of: find.byType(EditorView),
      matching: find.byIcon(Icons.chevron_right),
    );
    expect(chevron, findsOneWidget);

    // the whole answer cell is the target, not the 16px glyph
    await tester.tap(find.textContaining('9'));
    await tester.pumpAndSettle();
    expect(find.text('Steps'), findsOneWidget);
    expect(find.textContaining('1 + 2 = 3'), findsOneWidget);
  });

  testWidgets('answers share one right edge and width (decimal grid)', (
    tester,
  ) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '2000+3000\n9.5*3\n1234.5*2');
    await tester.pump(const Duration(milliseconds: 60));

    Rect rectOf(String needle) => tester.getRect(answerText(needle).first);

    final a = rectOf('5,000');
    final b = rectOf('28.5');
    final c = rectOf('2,469');
    for (final r in [b, c]) {
      expect(r.width, closeTo(a.width, 0.6));
      expect(r.right, closeTo(a.right, 0.6));
    }
  });

  testWidgets('negative answers are red, positive green', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '5-10\n2+3');
    await tester.pump(const Duration(milliseconds: 60));

    expect(
      tester.widget<Text>(answerExact('-5')).style?.color,
      Palette.negative(false),
    );
    expect(
      tester.widget<Text>(answerExact('5')).style?.color,
      Palette.positive(false),
    );
  });

  testWidgets(
    'line numbers show and a dragged answer becomes a live reference',
    (tester) async {
      await boot(tester);
      final editorFinder = find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      );
      await tester.enterText(editorFinder, '2000+3000');
      await tester.pump(const Duration(milliseconds: 60));

      // gutter
      expect(find.byKey(const ValueKey('gutter-1')), findsOneWidget);

      // drag the answer onto the editor
      final answer = find.textContaining('5,000').first;
      await tester.drag(answer, Offset.zero); // no-op sanity
      final g = await tester.startGesture(tester.getCenter(answer));
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveBy(const Offset(-40, 20));
      await tester.pump();
      await g.moveTo(tester.getCenter(editorFinder));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(editorFinder);
      expect(field.controller!.text, contains('line 1'));
      // the reference evaluates to the same number (answers + any drag chip)
      expect(find.textContaining('5,000'), findsAtLeastNWidgets(2));
    },
  );

  testWidgets('money keeps its cents on the same line', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(
      editor,
      r'$4,036.29'
      '\n'
      r'$1,251.90',
    );
    await tester.pump(const Duration(milliseconds: 80));

    // cents are part of the answer text, never a separate fragment
    expect(answerText(r'$4,036.29'), findsOneWidget);
    expect(answerText(r'$1,251.90'), findsOneWidget);

    Rect rectOf(String needle) => tester.getRect(answerText(needle).first);
    final a = rectOf(r'$4,036.29');
    final b = rectOf(r'$1,251.90');
    expect(b.width, closeTo(a.width, 0.6));
    expect(b.top, closeTo(a.top + a.height, 40)); // next line, not merged
  });

  testWidgets('answers can be hidden from settings', (tester) async {
    await boot(tester);
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '2+3*4');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('14'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Answers'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('14'), findsNothing);
  });
}
