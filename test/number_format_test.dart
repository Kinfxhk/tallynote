import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

/// The US/EU setting has to reach the engine, not just the settings dialog.
void main() {
  testWidgets('EU number format changes what a comma means', (tester) async {
    SharedPreferences.setMockInitialValues({'tallynote.numberFormat': 'eu'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 80));

    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '9,875+1');
    await tester.pump(const Duration(milliseconds: 80));

    // 9.875 + 1, displayed with EU separators
    expect(find.textContaining('10,875'), findsWidgets);
    expect(find.textContaining('9,876'), findsNothing);
  });

  testWidgets('US stays the default', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 80));

    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '9,875+1');
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.textContaining('9,876'), findsWidgets);
  });
}
