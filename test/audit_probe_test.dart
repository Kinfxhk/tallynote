import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/values.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  final eu = SheetEngine(
    now: DateTime(2026, 10, 30, 9),
    format: NumberFormat.eu,
  );
  final us = SheetEngine(now: DateTime(2026, 10, 30, 9));

  void probe(SheetEngine e, String line) {
    final r = e.evaluate([line]).first;
    // ignore: avoid_print
    print(
      '${identical(e, eu) ? 'EU' : 'US'} [${r.display}] err=${r.engineError}/${r.error} '
      '[${switch (r.value) {
        NumValue(:final value) => value,
        MoneyValue(:final value) => value,
        _ => null,
      }}]  <- $line',
    );
  }

  test('eu probe', () {
    for (final l in [
      '9,875+1',
      '1.234,56',
      '1,5',
      '(1,5)',
      '(1,5)+2',
      '2 x (1,5)',
      '2 times (1,5)',
      'min(1,2)',
      'pow(2,8)',
      'root(8,3)',
      '1,5 +',
      '1.23 +',
      '1.2345',
      '2,000,000',
      '3 min * 15 mph',
      '1 h * 10 knot',
      '2 h * 100 km/h',
      '10 m / 2 s',
      '30 km / 0,5 h',
      '1 min * 1 mph',
      '-1,5 +',
      '1/0',
      '5 kg + 2 m',
      r'$1.234,56',
    ]) {
      probe(eu, l);
    }
    // US side unchanged
    probe(us, '2+');
    probe(us, '9,875+1');
    probe(us, '1,234 +');
    probe(us, '1,2345');
    probe(us, '1,23 +');
    probe(us, '-1,234 +');
    probe(us, '3 min * 15 mph');
    probe(us, '1 h * 10 knot');

    for (final d in [
      '10,875',
      '1.234,56',
      '1,5',
      '3,333',
      '-1,5',
      '30 October 2026',
    ]) {
      final p = AnswerParts.parse(d, decimal: ',', group: '.');
      // ignore: avoid_print
      print(
        'PARTS [$d] aligns=${p.aligns} head=[${p.head}] '
        'frac=${p.fraction} tail=[${p.fractionTail}] suffix=[${p.suffix}]',
      );
    }
    // ignore: avoid_print
    print(
      'US parts 1,234.5 -> ${AnswerParts.parse('1,234.5').head} / '
      '${AnswerParts.parse('1,234.5').fraction}',
    );
  });

  testWidgets(
    'engine errors paint in the answer column; a half line does not',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const TallynoteApp());
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      final editor = find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      );
      await tester.enterText(editor, '1/0\n5 kg + 2 m\n2+');
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.text('divide by zero'), findsOneWidget);
      expect(find.text('incompatible values'), findsOneWidget);
      expect(find.textContaining('unexpected'), findsNothing);
    },
  );
}
