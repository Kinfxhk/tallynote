import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

/// The two ways the old code could lose text: saving while a section is folded,
/// and switching sheets before the debounce fires.
void main() {
  Finder editorField() => find.descendant(
    of: find.byType(EditorView),
    matching: find.byType(TextField),
  );

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  Future<Map<String, String>> storedContent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('tallynote.sheets.v1');
    if (raw == null) return {};
    final doc = jsonDecode(raw);
    final sheets = (doc is Map ? doc['sheets'] : doc) as List;
    return {
      for (final s in sheets)
        (s as Map)['id'] as String: s['content'] as String? ?? '',
    };
  }

  testWidgets('saving while folded keeps the hidden lines', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);
    await tester.enterText(editorField(), '# A\n100\n200\n300');
    await tester.pump(const Duration(milliseconds: 600)); // first save

    final foldArrow = find.descendant(
      of: find.byType(EditorView),
      matching: find.byIcon(Icons.keyboard_arrow_down),
    );
    expect(foldArrow, findsOneWidget);
    await tester.tap(foldArrow);
    await tester.pump(const Duration(milliseconds: 100));

    // the visible text is now a projection; Ctrl+S must not persist it
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));

    final stored = (await storedContent()).values.join('\n');
    expect(stored, contains('100'));
    expect(stored, contains('200'));
    expect(stored, contains('300'));
    expect(stored, isNot(contains('⋯')));
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('switching sheets inside the debounce keeps text apart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);
    await tester.enterText(editorField(), 'alpha 111');
    await tester.pump(const Duration(milliseconds: 120)); // still inside 400 ms

    // Ctrl+N: the sidebar's tap also awaits a haptic the test engine never
    // answers, so the shortcut is the dependable way to switch sheets here
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(editorField(), 'beta 222');
    await tester.pump(const Duration(milliseconds: 600));

    final stored = (await storedContent()).values.toList();
    expect(stored, hasLength(2), reason: 'no sheet is invented or merged');
    expect(stored.where((c) => c == 'alpha 111'), hasLength(1));
    expect(stored.where((c) => c == 'beta 222'), hasLength(1));
    await tester.pump(const Duration(seconds: 2));
  });
}
