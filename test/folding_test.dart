import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/ui/folding.dart';

void main() {
  const doc = ['# A', '100', '200', '# B', '300'];

  test('folding replaces a section body with one summary line', () {
    final r = foldDocument(doc, {0});
    expect(r.visibleLines.length, 4);
    expect(r.visibleLines[0], '# A');
    expect(r.visibleLines[1], contains('2 lines'));
    expect(r.visibleLines[2], '# B');
    expect(r.visibleLines[3], '300');
    // the summary carries the section total
    expect(r.visibleLines[1], contains('300'));
    // map: summary has no original line
    expect(r.map[1], -1);
    expect(r.map[3], 4);
  });

  test('unfolded sections keep every line', () {
    final r = foldDocument(doc, {});
    expect(r.visibleLines, doc);
    expect(r.map, [0, 1, 2, 3, 4]);
    expect(r.foldable, {0, 3});
  });

  test('an empty section has nothing to fold', () {
    final r = foldDocument(['# A', '# B', '1'], {0});
    expect(r.visibleLines, ['# A', '# B', '1']);
  });

  test('folding the last section works', () {
    final r = foldDocument(doc, {3});
    // one body line is replaced by one summary line: same length, no loss
    expect(r.visibleLines.length, doc.length);
    expect(r.visibleLines.last, contains('1 line'));
    expect(r.map.last, -1);
  });
}
