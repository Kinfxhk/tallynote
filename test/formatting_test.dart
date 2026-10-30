import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/ui/formatting.dart';

void main() {
  group('markers', () {
    test('are stripped before the engine sees the line', () {
      expect(Fmt.stripMarkers('**2000** + 3000'), '2000 + 3000');
      expect(Fmt.stripMarkers('_2000_ + {red}3000{/}'), '2000 + 3000');
      final e = SheetEngine(now: DateTime(2026, 10, 30));
      final plain = Fmt.stripMarkers('**2000** + 3000');
      expect(e.evaluate([plain]).first.display, '5,000');
    });

    test('leave identifiers alone', () {
      expect(Fmt.stripMarkers('my_var + 1'), 'my_var + 1');
    });

    test('produce nested spans', () {
      final spans = Fmt.spans('a **b** c', const TextStyle());
      expect(spans.map((s) => s.text).join(), 'a b c');
      expect(spans.any((s) => s.style?.fontWeight == FontWeight.w700), isTrue);
      expect(spans.first.text, 'a ');
    });

    test('colour spans use the palette', () {
      final spans = Fmt.spans('{red}x{/}', const TextStyle());
      expect(spans.single.text, 'x');
      expect(spans.single.style?.color, Fmt.colours['red']);
    });

    test('wrapping a selection keeps it selected', () {
      const text = '2000 + 3000';
      const sel = TextSelection(baseOffset: 0, extentOffset: 4);
      final (out, newSel) = Fmt.wrap(text, sel, '**', '**');
      expect(out, '**2000** + 3000');
      expect(newSel.textInside(out), '2000');
    });

    test('a line name is painted as a chip', () {
      final spans = Fmt.withReferences(
        [const TextSpan(text: 'lucid * 2', style: TextStyle())],
        const TextStyle(),
        labels: {'lucid'},
        dark: false,
      );
      final chip = spans.whereType<TextSpan>().firstWhere(
        (s) => s.text == 'lucid',
      );
      expect(chip.style?.backgroundColor, isNotNull);
      expect(chip.style?.fontWeight, FontWeight.w600);
      // non-reference words keep their own style
      expect(spans.whereType<TextSpan>().any((s) => s.text == ' * 2'), isTrue);
    });

    test('line N is a chip even without labels', () {
      final spans = Fmt.withReferences(
        [const TextSpan(text: 'line 3 * 2', style: TextStyle())],
        const TextStyle(),
        labels: {'anything'},
        dark: true,
      );
      expect(
        spans.whereType<TextSpan>().any((s) => s.text == 'line 3'),
        isTrue,
      );
    });

    test('a // line is a draft', () {
      expect(Fmt.isDraft('// 想法：下個月加價'), isTrue);
      expect(Fmt.isDraft('  // indented'), isTrue);
      expect(Fmt.isDraft('2000+3000'), isFalse);
    });
  });

  group('engine', () {
    test('// draft lines are not calculated', () {
      final e = SheetEngine(now: DateTime(2026, 10, 30));
      final r = e.evaluate(['// 2000 + 3000', '100 + 20']);
      expect(r[0].display, isNull);
      expect(r[1].display, '120');
    });
  });
}
