import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/marked_controller.dart';
import 'package:tallynote/ui/theme.dart';

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

  Finder editor() => find.descendant(
    of: find.byType(EditorView),
    matching: find.byType(TextField),
  );

  testWidgets('engine errors show in the answer column; a half line does not', (
    tester,
  ) async {
    await boot(tester);
    await tester.enterText(editor(), '1/0\n5 kg + 2 m\n2+');
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('divide by zero'), findsOneWidget);
    expect(find.text('incompatible values'), findsOneWidget);
    expect(find.textContaining('unexpected'), findsNothing);
  });

  testWidgets('bold markers do not push the next answer down a wrap', (
    tester,
  ) async {
    final c = MarkedController(text: '**abcdef**\n1+1', dark: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 430,
            height: 400,
            child: EditorView(
              controller: c,
              dark: false,
              showSteps: false,
              showLineNumbers: false,
              results: const [
                LineResult(text: '**abcdef**'),
                LineResult(text: '1+1', display: '2'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    const textWidth = 430.0 - 212 - 54 - 48;
    const strut = StrutStyle(
      fontFamily: monoFamily,
      fontSize: 15,
      height: 28 / 15,
      forceStrutHeight: true,
    );
    final style = editorStyle(false);

    double line2(String source) {
      final painter = TextPainter(
        text: TextSpan(text: source, style: style),
        textDirection: TextDirection.ltr,
        strutStyle: strut,
      )..layout(maxWidth: textWidth);
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: source.indexOf('\n') + 1),
        Rect.zero,
      );
      painter.dispose();
      return caret.dy;
    }

    final painted = line2('abcdef\n1+1');
    final raw = line2('**abcdef**\n1+1');
    expect(raw, greaterThan(painted + 10));

    final answer = tester.getTopLeft(
      find.byWidgetPredicate((w) => w is AnswerReadout && w.display == '2'),
    );
    final field = tester.getTopLeft(find.byType(EditableText));
    expect(answer.dy - field.dy, closeTo(painted, 8));
  });
}
