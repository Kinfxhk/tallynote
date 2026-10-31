import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import 'theme.dart';

/// One line of the cheat sheet: what you type, and what it answers.
///
/// [answer] is null when the line needs the lines above it (`sum`, `line 3`)
/// or when the answer is not fixed (a currency rate). A row that shows an
/// answer must show the real one: `test/cheat_sheet_test.dart` runs every
/// example through the engine, so the table cannot drift into a lie.
class CheatRow {
  final String input;
  final String? answer;
  const CheatRow(this.input, [this.answer]);
}

class CheatGroup {
  final String titleKey;
  final List<CheatRow> rows;
  const CheatGroup(this.titleKey, this.rows);
}

const cheatSheet = <CheatGroup>[
  CheatGroup('cheatArithmetic', [
    CheatRow('12 + 30', '42'),
    CheatRow('12 − 30', '-18'),
    CheatRow('12 × 3', '36'),
    CheatRow('12 ÷ 3', '4'),
    CheatRow('2 ^ 10', '1,024'),
    CheatRow('2(3+4)', '14'),
    CheatRow('100 加 20', '120'),
    CheatRow('1100減30', '1,070'),
    CheatRow('30乘3', '90'),
    CheatRow('100除以4', '25'),
    CheatRow('4300 x 30%', '1,290'),
  ]),
  CheatGroup('cheatPercent', [
    CheatRow('15% of 300', '45'),
    CheatRow('100 的 10%', '10'),
    CheatRow('300 + 15%', '345'),
    CheatRow('300 - 15%', '255'),
    CheatRow('25% off 159.99', '119.9925'),
    CheatRow('20 is what % of 80', '25%'),
    CheatRow('5% of what is 150', '3,000'),
    CheatRow('20是80的百分之幾', '25%'),
  ]),
  CheatGroup('cheatTotals', [
    CheatRow('sum'),
    CheatRow('average'),
    CheatRow('count'),
    CheatRow('min'),
    CheatRow('max'),
    CheatRow('total of #food'),
    CheatRow('合共'),
  ]),
  CheatGroup('cheatUnits', [
    CheatRow('5 kg + 3 lb', '6.36077711 kg'),
    CheatRow('3 min * 15 mph', '0.75 mi'),
    CheatRow('32 f in c', '0 °C'),
    CheatRow('100 mb in gb', '0.1 GB'),
    CheatRow('100 USD in HKD'),
  ]),
  CheatGroup('cheatDates', [
    CheatRow('2026-01-01 + 2 weeks', '15 January 2026'),
    CheatRow('2026-01-30 + 3 workdays', '4 February 2026'),
    CheatRow('30 days from 2026-01-01', '31 January 2026'),
    CheatRow('2026-01-01 to 2026-12-31', '364 days'),
    CheatRow('2h 30m + 45m', '3 h 15 min'),
    CheatRow('2026-01-01 15:00 HKT in New York', '1 January 2026 at 2:00 AM'),
  ]),
  CheatGroup('cheatOther', [
    CheatRow('rent = 2500', '2,500'),
    CheatRow('line 1 + line 2'),
    CheatRow('prev'),
    CheatRow('if 5 > 3 then 10 else 20', '10'),
    CheatRow('9 is to 16 as 27 is to what', '48'),
    CheatRow('compound interest 1000 at 10% for 2 years', '1,210'),
    CheatRow('sqrt 16', '4'),
    CheatRow('round 3.14159 2', '3.14'),
    CheatRow('max(1, 9, 4)', '9'),
    CheatRow('1e3', '1,000'),
    CheatRow('// 註釋', null),
    CheatRow('# 標題', null),
    CheatRow('lunch 120 #food', '120'),
  ]),
];

/// The reference tab in Settings: one scrollable list, no prose to translate
/// beyond the group titles.
class CheatSheetView extends StatelessWidget {
  final bool dark;
  final String locale;

  const CheatSheetView({super.key, required this.dark, required this.locale});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final group in cheatSheet) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
          child: Text(
            T.of(locale, group.titleKey),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
              color: Palette.faint(dark),
            ),
          ),
        ),
      );
      for (final row in group.rows) {
        rows.add(_CheatLine(row: row, dark: dark));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 12), children: rows);
  }
}

class _CheatLine extends StatelessWidget {
  final CheatRow row;
  final bool dark;

  const _CheatLine({required this.row, required this.dark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              row.input,
              style: TextStyle(
                fontFamily: monoFamily,
                fontSize: 12.5,
                color: Palette.fg(dark),
              ),
            ),
          ),
          if (row.answer != null)
            Text(
              row.answer!,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: monoFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Palette.answer(dark),
              ),
            ),
        ],
      ),
    );
  }
}
