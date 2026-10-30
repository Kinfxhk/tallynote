import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  const key = 'tallynote.sheets.v1';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder editor() => find.descendant(
    of: find.byType(EditorView),
    matching: find.byType(TextField),
  );

  Future<List<Map<String, dynamic>>> sheets() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(prefs.getString(key)!);
    return (decoded['sheets'] as List).cast<Map<String, dynamic>>();
  }

  testWidgets('switching sheets flushes the outgoing note, not the new one', (
    tester,
  ) async {
    final raw = jsonEncode({
      'v': 2,
      'folders': <Object>[],
      'sheets': [
        {
          'id': 'a',
          'title': 'Alpha',
          'content': 'alpha',
          'customTitle': true,
          'updated': '2026-01-01T00:00:00.000',
        },
        {
          'id': 'b',
          'title': 'Beta',
          'content': 'beta',
          'customTitle': true,
          'updated': '2026-01-02T00:00:00.000',
        },
      ],
    });
    SharedPreferences.setMockInitialValues({
      key: raw,
      'tallynote.active.v1': 'a',
    });
    await boot(tester);

    await tester.enterText(editor(), 'CHANGED');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Beta').first);
    await tester.pump();
    // well past the 400ms debounce; a late timer must not rewrite Alpha
    await tester.pump(const Duration(milliseconds: 500));

    final saved = await sheets();
    final alpha = saved.singleWhere((s) => s['id'] == 'a');
    final beta = saved.singleWhere((s) => s['id'] == 'b');
    expect(alpha['content'], 'CHANGED');
    expect(beta['content'], 'beta');
  });

  testWidgets('a folded section saves the hidden lines', (tester) async {
    await boot(tester);
    await tester.enterText(editor(), '# Section\n100\n200');
    await tester.pump(const Duration(milliseconds: 50));

    final fold = find.descendant(
      of: find.byType(EditorView),
      matching: find.byIcon(Icons.keyboard_arrow_down),
    );
    await tester.tap(fold);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));

    final saved = await sheets();
    final content = saved.single['content'] as String;
    expect(content, contains('# Section'));
    expect(content, contains('100'));
    expect(content, contains('200'));
    expect(content, isNot(contains('⋯')));
  });

  testWidgets('Ctrl+S writes before the debounce', (tester) async {
    await boot(tester);
    await tester.enterText(editor(), '1+1');
    await tester.pump(const Duration(milliseconds: 20));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final saved = await sheets();
    expect(saved.single['content'], '1+1');
  });
}
