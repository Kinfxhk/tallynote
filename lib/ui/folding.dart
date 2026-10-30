import '../engine/engine.dart';

/// Section folding, in the spirit of a code editor's fold gutter.
///
/// A `# heading` opens a fold that runs to the next heading. Folding removes
/// the lines from the *visible* document and replaces them with one summary
/// line, so the shape of a long note stays readable. The full text is kept
/// aside by the caller: while anything is folded the editor is read-only,
/// which is what makes this safe with a single TextField.
class FoldResult {
  final List<String> visibleLines;

  /// visible index -> original line index (-1 for a generated summary line)
  final List<int> map;

  /// original line index -> can it be folded
  final Set<int> foldable;

  const FoldResult(this.visibleLines, this.map, this.foldable);
}

bool isHeading(String line) => line.trimLeft().startsWith('# ');

/// [lines] is the full document; [folded] holds the indices of folded headings.
FoldResult foldDocument(List<String> lines, Set<int> folded) {
  final visible = <String>[];
  final map = <int>[];
  final foldable = <int>{};
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];
    if (!isHeading(line)) {
      visible.add(line);
      map.add(i);
      i++;
      continue;
    }

    foldable.add(i);
    visible.add(line);
    map.add(i);

    // extent of this section
    var end = i + 1;
    while (end < lines.length && !isHeading(lines[end])) {
      end++;
    }

    if (folded.contains(i) && end > i + 1) {
      final body = lines.sublist(i + 1, end);
      visible.add(_summary(body, i + 2, end));
      map.add(-1);
    } else {
      for (var k = i + 1; k < end; k++) {
        visible.add(lines[k]);
        map.add(k);
      }
    }
    i = end;
  }
  return FoldResult(visible, map, foldable);
}

String _summary(List<String> body, int firstLine, int lastLine) {
  final engine = SheetEngine();
  final results = engine.evaluate(body);
  final values = results
      .map((r) => r.display)
      .whereType<String>()
      .where((d) => RegExp(r'^[-+\$€£¥\d]').hasMatch(d))
      .toList();
  final total = values.isEmpty ? '' : ' · ${_total(body, engine)}';
  final rows = '${body.length} ${body.length == 1 ? 'line' : 'lines'}';
  return '  ⋯  $rows ($firstLine–$lastLine)$total';
}

String _total(List<String> body, SheetEngine engine) {
  final r = engine.evaluate([...body, 'grand total']);
  return r.last.display ?? '';
}
