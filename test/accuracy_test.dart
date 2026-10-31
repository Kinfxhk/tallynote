import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/values.dart';

/// Answers that used to be blank, or quietly wrong. Each case here was run
/// against the real engine before the fix: `2026-10-31 - 2026-01-01` answered
/// -43, `today + 3 workdays` answered "3 workdays" and an undefined
/// `rent * 12` answered 12.
void main() {
  late SheetEngine engine;

  setUp(() {
    engine = SheetEngine(now: DateTime(2026, 10, 31, 9));
  });

  String? one(String line) => engine.evaluate([line]).first.display;

  test('a date minus a date is the gap between them', () {
    expect(one('2026-10-31 - 2026-01-01'), '303 days');
    expect(one('2026-01-01 - 2026-10-31'), '-303 days');
    expect(one('2026-01-01 to 2026-10-31'), '303 days');
  });

  test('workdays skip the weekend', () {
    // 31 October 2026 is a Saturday: three working days later is Wednesday.
    final v = engine.evaluate(['today + 3 workdays']).first.value as DateValue;
    expect(v.date.weekday, DateTime.wednesday);
    expect(v.date.day, 4);
    // Five working days back from the Saturday is Monday the 26th.
    final back = engine
        .evaluate(['today - 5 workdays'])
        .first
        .value as DateValue;
    expect(back.date.weekday, DateTime.monday);
    expect(back.date.day, 26);
  });

  test('a day count from or before a date', () {
    expect(one('30 days from today'), '30 November 2026');
    expect(one('3 weeks ago'), '10 October 2026');
    expect(one('10 days before 2026-12-25'), '15 December 2026');
  });

  test('time written the way it is spoken', () {
    expect(one('2h 30m'), '2 h 30 min');
    expect(one('2h 30m + 45m'), '3 h 15 min');
    expect(one('3 hours 20 minutes in minutes'), '200 min');
    expect(one('1h - 20m'), '40 min');
  });

  test('a lone m stays metres, not minutes', () {
    expect(one('45m'), '45 m');
    expect(one('5 m + 3 m'), '8 m');
  });

  test('a bare number beside an operator is not answered', () {
    // An undefined name plus an operator must not surface the other number.
    expect(one('rent * 12'), isNull);
    expect(one('unknown + 30'), isNull);
    // Prose with one number still answers, signed numbers included.
    expect(one('午餐 120'), '120');
    expect(one(r'Topstep: -$10,408.52'), r'-$10,408.52');
  });

  test('scientific notation', () {
    expect(one('1e3'), '1,000');
    expect(one('2.5e-3'), '0.0025');
    expect(one('1e3 + 1'), '1,001');
  });

  test('a defined variable still multiplies', () {
    final r = engine.evaluate(['rent = 2500', 'rent * 12']);
    expect(r.last.display, '30,000');
  });

  test('a clock time in front of a note is a label, not maths', () {
    // Measured from a real note: "14:00 Tradeify 全帳號 1000+2000" had no answer.
    expect(one('14:00 Tradeify 全帳號 1000+2000'), '3,000');
    expect(one('14:00 開倉 500 x 2'), '1,000');
    // The guards still hold: a leading number that is not a clock, and a unit
    // after a number, behave exactly as before.
    expect(one('4300 X 30%'), isNull);
    expect(one('3 kg'), '3 kg');
    expect(one('14:00'), contains('2:00 PM'));
  });

  test('a reference to a line with no answer stays unanswered', () {
    // `line 3` on a one-line sheet used to answer 3.
    expect(one('line 3'), isNull);
    final r = engine.evaluate(['100', '200', 'line 1 + line 2']);
    expect(r.last.display, '300');
  });

  test('an ISO date still takes a duration', () {
    // The dashes inside the date used to win: "2026-01-01 + 2 weeks" was 2,026 weeks.
    expect(one('2026-01-01 + 2 weeks'), '15 January 2026');
    expect(one('2026-01-01 - 30 days'), '2 December 2025');
  });

  test('temperature converts exactly, and a sign belongs to the number', () {
    expect(one('32 f in c'), '0 °C');
    expect(one('0 c in f'), '32 °F');
    // -40 °F is -40 °C, not -(40 °F -> 4.44 °C).
    expect(one('-40 f in c'), '-40 °C');
    expect(one('-5 c in f'), '23 °F');
  });
}
