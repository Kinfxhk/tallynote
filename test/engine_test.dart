import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/engine/engine.dart';

/// Golden cases mirrored from a real Soulver 4.0.4 run, plus Numi-only cases.
void main() {
  late SheetEngine engine;

  setUp(() {
    engine = SheetEngine(now: DateTime(2026, 10, 30, 9));
  });

  String? one(String line) => engine.evaluate([line]).first.display;

  test('arithmetic and precedence', () {
    expect(one('(2.5+7.5)*1.11/10-15^2'), '-223.89');
    expect(one('2+3*4'), '14');
    expect(one('2(3+4)'), '14');
  });

  test('units', () {
    expect(one('5 kg + 3 lb'), startsWith('6.3607'));
    expect(one('2 GB in MB'), '2,000 MB');
    expect(one('30 celsius in fahrenheit'), startsWith('86'));
    expect(one('100 Mbps in MB/s'), '12.5 MB/s');
    expect(one('180 lbs in kg'), startsWith('81.6466'));
  });

  test('percent', () {
    expect(one('5% of 200'), '10');
    expect(one('25% off 159.99 + 10% tax'), startsWith('131.99'));
    expect(one('20 is what % of 80'), '25%');
  });

  test('variables and aggregates', () {
    final r = engine.evaluate([
      'rent = 2500',
      'food = 400',
      'rent + food',
      'sum',
    ]);
    expect(r[2].display, '2,900');
    expect(r[3].display, '5,800');
  });

  test('money', () {
    final fx = SheetEngine(
      now: DateTime(2026, 10, 30, 9),
      rates: const {'USD': 1, 'HKD': 7.8, 'EUR': 0.92, 'JPY': 150},
    );
    expect(fx.evaluate([r'$20 in euro']).first.display, startsWith('€'));
    expect(fx.evaluate([r'100 USD in HKD']).first.display, startsWith(r'HK$'));
  });

  test('rule of three', () {
    expect(one('9 is to 16 as 27 is to what'), '48');
  });

  test('conditional', () {
    expect(one('if 5 > 3 then 10 else 20'), '10');
  });

  test('dates', () {
    expect(one('today + 2 weeks'), '13 November 2026');
    expect(one('March 12 + 3 weeks 2 days'), '4 April 2027');
  });

  test('grand total sums every answer above, across sections', () {
    final r = engine.evaluate([
      '2000 + 3000',
      '100/2',
      '4300*2',
      '6+3x30+30',
      '合共',
    ]);
    expect(r[4].display, '13,776');

    final s2 = engine.evaluate(['# A', '100', '# B', '200', 'grand total']);
    expect(s2[4].display, '300');

    final s3 = engine.evaluate([r'$10', r'$20', '總共']);
    expect(s3[2].display, r'$30.00');
  });

  test('balance sheet: section subtotals then a grand total', () {
    final r = engine.evaluate([
      '# 資產',
      '現金 500000',
      '股票 300000',
      'sum',
      '# 負債',
      '貸款 -500000',
      '卡數 -20000',
      'sum',
      '合共',
    ]);
    expect(r[3].display, '800,000');
    expect(r[7].display, '-520,000');
    // leaves only: the two subtotals are not counted a second time
    expect(r[8].display, '280,000');
  });

  test('grand total groups by unit instead of faking one number', () {
    final r = engine.evaluate(['5 kg', '3 lb', '2 m', '總計']);
    expect(r[3].display, '6.36077711 kg, 2 m');
  });

  test('tagged subtotal', () {
    final r = engine.evaluate([
      '午餐 120 #food',
      '晚餐 280 #food',
      '車費 50 #transport',
      'total of #food',
    ]);
    expect(r[3].display, '400');
  });

  test('x as multiplication and trailing words', () {
    expect(one('4300 x 30%'), '1,290');
    expect(one(r'$500 x 3'), r'$1,500.00');
  });

  test('chinese operators', () {
    expect(one('30乘3'), '90');
    expect(one('30 乘 3'), '90');
    expect(one('10除以2'), '5');
    expect(one('5加3'), '8');
    expect(one('10減4'), '6');
    expect(one('含運費 30乘3'), '90');
  });

  test('operator precedence, including the x sign with no spaces', () {
    expect(one('4+4x3+3'), '19');
    expect(one('6+3x30'), '96');
    expect(one('6+3x30*2'), '186');
    expect(one('2+3x4'), '14');
    expect(one('10-2x3'), '4');
    expect(one('6+3乘30'), '96');
    expect(one('(6+3)x30'), '270');
    expect(one('6+3*30'), '96');
  });

  test('functions in every form people type', () {
    expect(one('sin 30 deg'), '0.5');
    expect(one('sin30deg'), '0.5');
    expect(one('sin(pi/2)'), '1');
    expect(one('cos pi'), '-1');
    expect(one('sqrt16'), '4');
    expect(one('max(1, 9, 4)'), '9');
    expect(one('round(3.14159, 2)'), '3.14');
    expect(one('round 3.14159 2'), '3.14');
  });

  test('uppercase X is not a times sign', () {
    expect(one('4300 x 30%'), '1,290');
    expect(one('4300 X 30%'), isNull);
  });

  test('reads past leading prose', () {
    expect(one('買嘢 4300 * 30%'), '1,290');
    expect(one('hello 3+4'), '7');
  });

  test('functions, money and timezone', () {
    expect(one('round 3.14159 2'), '3.14');
    expect(one('fact 5'), '120');
    expect(one('sin 30 deg'), '0.5');
    expect(one('days between 2026-01-01 and 2026-10-30'), '302 days');
    expect(one('3pm HKT in New York'), endsWith('3:00 AM'));
    expect(one('compound interest 5000 at 7.5% for 3 years'),
        startsWith('6,211.48'));
    expect(one('30 celsius in fahrenheit'), '86 °F');
  });

  test('step breakdown', () {
    final steps = engine.explain('(2.5+7.5)*1.11/10-15^2');
    expect(steps.first, '2.5 + 7.5 = 10');
    expect(steps.last, '1.11 - 225 = -223.89');
    expect(steps.length, 5);
    expect(engine.explain('2 apples'), isEmpty);
    expect(engine.explain('hello world'), isEmpty);
    // one operation is not "complex" — no + button
    expect(engine.explain('120 + 80'), isEmpty);
    // prose prefix and tag are stripped, same read-past rule as answers
    expect(engine.explain('午餐 120 + 80 * 2 #food').first, '80 * 2 = 160');
  });

  test('pasted P&L note: labels, unicode minus, cents, cross-check', () {
    final r = engine.evaluate([
      r'Take Profit Trader: +$9,623.00',
      r'Topstep: −$10,408.52',
      r'Tradeify: −$5,038.50',
      r'Vest: −$3,383.80',
      r'My Funded Futures: −$1,054.02',
      r'Lucid: −$935.90',
      r'Sim2Funded: −$232.00',
      r'Apex: −$214.40',
      r'TradeSyncer software: −$590.96',
      r'Total expenses: $65,397.03',
      r'Total payouts and credited profits: $53,161.93',
      r'Overall net: −$12,235.10',
      '(Live trading excluded)',
      '合共',
    ]);
    expect(r[0].display, r'$9,623.00');
    expect(r[1].display, r'-$10,408.52'); // unicode minus kept its sign
    expect(r[6].display, r'-$232.00'); // label with a digit still parses
    expect(r[12].display, isNull); // prose in brackets stays quiet
    // the grand total reproduces the note's own net: -12,235.10
    expect(r[13].display, r'-$12,235.10');
  });

  test('text lines stay quiet', () {
    expect(one('hello world'), isNull);
  });

  test('unit object counting', () {
    expect(one('2 apples + 3 apples'), '5 apples');
  });
}
