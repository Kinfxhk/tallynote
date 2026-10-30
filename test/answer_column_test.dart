import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/ui/answer_column.dart';
import 'package:tallynote/ui/editor_view.dart';
import 'package:tallynote/ui/theme.dart';

/// Widths that are deliberately not one-em-per-glyph, so a character-count
/// pad cannot land on the same decimal x.
double uneven(String text) {
  var w = 0.0;
  for (final code in text.runes) {
    final c = String.fromCharCode(code);
    w += switch (c) {
      ',' => 3,
      '.' => 3,
      ' ' => 4,
      '-' => 5,
      '\$' => 7,
      '¥' => 12,
      '%' => 8,
      _ => 10,
    };
  }
  return w;
}

void main() {
  test('a single number keeps its head, fraction, and suffix', () {
    final money = AnswerParts.parse(r'-$12.50');
    expect(money.aligns, isTrue);
    expect(money.head, r'-$12');
    expect(money.fraction, '50');
    expect(money.suffix, isEmpty);

    final pct = AnswerParts.parse('12.5%');
    expect(pct.head, '12');
    expect(pct.fraction, '5');
    expect(pct.suffix, '%');
    expect(pct.fractionTail, '.5%');

    final unit = AnswerParts.parse('3.5 km');
    expect(unit.head, '3');
    expect(unit.fraction, '5');
    expect(unit.suffix, ' km');

    final whole = AnswerParts.parse('1,000');
    expect(whole.fraction, isNull);
    expect(whole.head, '1,000');
  });

  test('dates, lists, and exponents are not forced onto the decimal grid', () {
    expect(AnswerParts.parse('30 October 2026').aligns, isFalse);
    expect(AnswerParts.parse('6.36 kg, 2 m').aligns, isFalse);
    expect(AnswerParts.parse('1.23e+6').aligns, isFalse);
    expect(AnswerParts.parse('NaN').aligns, isFalse);
  });

  test('decimals share an x when glyphs are not tabular', () {
    const displays = ['¥1,234.5', r'-$12.50', '100', '3.333', '12.5%'];
    final metrics = measureAnswers(displays, uneven);

    // The yen head is wider than a character-count pad of the dollar head
    // would assume, because `¥` and `,` are not digit-width.
    expect(uneven('¥1,234'), greaterThan(uneven(r'-$12')));
    expect(metrics.headW, closeTo(uneven('¥1,234'), 0.001));

    // Fractions longer than two places still reserve their real width.
    expect(metrics.fracW, closeTo(uneven('.333'), 0.001));
    expect(metrics.fracW, greaterThan(uneven('.50')));

    for (final raw in displays) {
      final p = AnswerParts.parse(raw);
      expect(p.aligns, isTrue, reason: raw);
      // Right-aligning the head in a box of headW puts every decimal at
      // the same x, even though the heads have different pixel widths.
      expect(uneven(p.head), lessThanOrEqualTo(metrics.headW + 0.001));
    }

    // The column is wider than the integer heads: short fractions are not
    // right-aligned under the last digit.
    expect(metrics.numericW, greaterThan(metrics.headW + uneven('.5')));
  });

  test('an integer lines up with the decimal, not the right edge', () {
    final metrics = measureAnswers(['1,000', '28.5', '3.333'], uneven);
    final blockRight = metrics.numericW;
    // Implied decimal of the integer is headW from the left of the block,
    // short of the right edge by the longest fraction.
    expect(metrics.headW, lessThan(blockRight - uneven('.333') + 0.001));
    expect(
      blockRight - metrics.headW,
      greaterThanOrEqualTo(uneven('.333') - 0.001),
    );
  });

  testWidgets('scaled answers still share a decimal and are not clipped', (
    tester,
  ) async {
    final c = TextEditingController(text: '1\n2');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorView(
            controller: c,
            dark: false,
            scale: 2,
            showSteps: false,
            results: const [
              LineResult(text: '1', display: '1,000'),
              LineResult(text: '2', display: '1.5'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final cell = find.byWidgetPredicate(
      (w) => w is AnswerReadout && w.display == '1,000',
    );
    final head = find.descendant(of: cell, matching: find.text('1,000'));
    final painter = TextPainter(
      text: TextSpan(text: '1,000', style: answerStyle(false, scale: 2)),
      textDirection: TextDirection.ltr,
    )..layout();
    // The head box was measured at the painted size, so the glyphs fit.
    expect(
      tester.getSize(head).width,
      greaterThanOrEqualTo(painter.width - 0.5),
    );

    final dot = find.text('.5');
    expect(
      tester.getTopLeft(dot).dx,
      closeTo(tester.getTopRight(head).dx, 0.6),
    );
  });
}
