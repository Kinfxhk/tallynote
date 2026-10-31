import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/ui/cheat_sheet.dart';

/// The Settings reference tab is only worth having if it is true. Every row
/// that advertises an answer is evaluated here, so an engine change that
/// rewords or breaks an example fails the suite instead of quietly shipping a
/// cheat sheet that lies. Rows without an answer (`sum`, `line 1 + line 2`,
/// `prev`, live currency) are context-dependent by design and are skipped.
void main() {
  test('every cheat-sheet answer is the real answer', () {
    final engine = SheetEngine(now: DateTime(2026, 10, 31, 9));
    final failures = <String>[];
    for (final group in cheatSheet) {
      for (final row in group.rows) {
        if (row.answer == null) continue;
        final got = engine.evaluate([row.input]).first.display;
        if (got != row.answer) {
          failures.add('${row.input}  => $got  (table says ${row.answer})');
        }
      }
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  test('a row with no answer must really have none', () {
    final engine = SheetEngine(now: DateTime(2026, 10, 31, 9));
    for (final group in cheatSheet) {
      for (final row in group.rows) {
        if (row.answer != null) continue;
        // `sum` and friends need lines above them, so a one-line sheet is the
        // wrong context: only the reference rows are checked here.
        if (row.input.startsWith('line ') || row.input == 'prev') {
          expect(engine.evaluate([row.input]).first.display, isNull,
              reason: row.input);
        }
      }
    }
  });

  test('every group has a title key and at least one row', () {
    expect(cheatSheet, isNotEmpty);
    for (final group in cheatSheet) {
      expect(group.titleKey, startsWith('cheat'));
      expect(group.rows, isNotEmpty);
    }
  });
}
