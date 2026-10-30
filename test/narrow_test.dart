import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> bootAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('long answers do not overflow a phone-width layout', (
    tester,
  ) async {
    await bootAt(tester, const Size(360, 720));
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '123456789*987654321\n100/3\n-\$12,345.67');
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.takeException(), isNull);
  });

  testWidgets('answers fit inside the column when it is dragged narrow', (
    tester,
  ) async {
    await bootAt(tester, const Size(1280, 800));
    final editor = find.descendant(
      of: find.byType(EditorView),
      matching: find.byType(TextField),
    );
    await tester.enterText(editor, '123456789*987654321');
    await tester.pump(const Duration(milliseconds: 60));

    // drag the divider far to the right, shrinking the answer column
    final splitter = find.byType(GestureDetector).last;
    await tester.drag(splitter, const Offset(600, 0));
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.takeException(), isNull);
  });
}
