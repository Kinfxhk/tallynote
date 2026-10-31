import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';

/// The README's example blocks are the product's front page: every line there
/// has to be the answer the engine really gives. This test reads them out of
/// README.md and evaluates each block as a note, so a docs example cannot drift
/// away from the engine again (0.3.8 shipped a `total of #trip` example that
/// never worked: headings do not create tags, only line-end `#tag` does).
void main() {
  test('README example blocks match the engine', () {
    final readme = File('README.md').readAsStringSync();
    final blocks = RegExp(r'```[a-z]*\r?\n([\s\S]*?)```')
        .allMatches(readme)
        .map((m) => m.group(1)!.split(RegExp(r'\r?\n')))
        .where((lines) => lines.any((l) => l.contains('→')))
        .toList();
    expect(blocks, isNotEmpty, reason: 'no example block found in README.md');

    // The examples read dates, so they are pinned to the day they were written.
    final engine = SheetEngine(now: DateTime(2026, 10, 30, 9));

    for (final lines in blocks) {
      final note = <String>[];
      final expected = <String>[];
      for (final line in lines) {
        final at = line.indexOf('→');
        if (at < 0) {
          note.add(line);
          expected.add('');
        } else {
          note.add(line.substring(0, at).trimRight());
          expected.add(line.substring(at + 1).trim());
        }
      }

      final results = engine.evaluate(note);
      for (var i = 0; i < note.length; i++) {
        if (expected[i].isEmpty) continue;
        expect(results[i].display, expected[i], reason: 'README line: ${note[i]}');
      }
    }
  });
}
