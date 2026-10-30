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
    expect(one('4300 X 30% consistency'), '1,290');
    expect(one(r'$500 x 3'), r'$1,500');
  });

  test('reads past leading prose', () {
    expect(one('買嘢 4300 * 30%'), '1,290');
    expect(one('hello 3+4'), '7');
  });

  test('text lines stay quiet', () {
    expect(one('hello world'), isNull);
  });

  test('unit object counting', () {
    expect(one('2 apples + 3 apples'), '5 apples');
  });
}
