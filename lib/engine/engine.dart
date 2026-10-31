import 'dart:math' as math;

import 'dates.dart';
import 'evaluator.dart';
import 'lexer.dart';
import 'parser.dart';
import 'units.dart';
import 'values.dart';

class LineResult {
  final String text;
  final Value? value;
  final String? display;
  final String? error;

  /// A real [ErrorValue] from the evaluator (`1/0`). A line that has not
  /// been typed yet also has [error], but must not paint anything.
  final bool engineError;
  final bool isComment;
  final bool isHeading;
  final String? tag;

  const LineResult({
    required this.text,
    this.value,
    this.display,
    this.error,
    this.engineError = false,
    this.isComment = false,
    this.isHeading = false,
    this.tag,
  });

  bool get hasAnswer => display != null;
}

/// Evaluates a whole sheet top to bottom, carrying variables and line
/// references forward. Errors stay on their own line.
class SheetEngine {
  /// Whole-sheet totals. "total" alone stays the section total.
  static const _grandWords = {
    'grand total',
    'grandtotal',
    'grand-total',
    'total all',
    'sum all',
    '全部',
    '合共',
    '總共',
    '總計',
    '總和',
    '加埋',
    '全部加埋',
    '全計',
  };

  final UnitRegistry units;
  final DateParser dates;

  /// Strict mode turns off the two forgiveness rules (reading past leading
  /// prose, answering a lone number). Agents want a real error instead.
  final bool strict;
  Map<String, double> rates;
  final String baseCurrency;
  final NumberFormat format;

  SheetEngine({
    UnitRegistry? units,
    DateTime? now,
    Map<String, double>? rates,
    this.strict = false,
    this.baseCurrency = 'HKD',
    this.format = NumberFormat.us,
  }) : units = units ?? UnitRegistry(),
       dates = DateParser(now: now),
       rates = rates ?? const {'USD': 1, 'HKD': 7.8};

  /// Walks the parsed expression and returns one line per operation, e.g.
  /// ["2.5 + 7.5 = 10", "10 * 1.11 = 11.1", ...]. Empty when the line is a
  /// single value or a phrase the parser does not own.
  List<String> explain(String line) {
    var body = normalizeMathSource(line.trim());
    if (body.isEmpty) return const [];
    final tag = _extractTag(body);
    if (tag != null) body = body.substring(0, body.lastIndexOf('#')).trim();

    final ctx = EvalContext(units: units, now: dates.now, rates: rates);
    final ev = Evaluator(ctx);
    final steps = <String>[];

    String walk(Node n) {
      switch (n) {
        case NumberNode(:final value, :final unit):
          return unit == null
              ? formatNumber(value, format: format)
              : '${formatNumber(value, format: format)} ${unit.id}';
        case MoneyNode(:final value, :final currency):
          return '${formatNumber(value, format: format)} $currency';
        case VarNode(:final name):
          return name;
        case PercentNode(:final operand):
          return '${walk(operand)}%';
        case UnaryNode(:final op, :final operand):
          return '$op${walk(operand)}';
        case BinNode(:final op, :final left, :final right):
          final l = walk(left);
          final r = walk(right);
          final v = ev.eval(n);
          steps.add('$l $op $r = ${_compact(v)}');
          return _compact(v);
        case CallNode(:final name, :final args):
          final a = args.map(walk).join(', ');
          final v = ev.eval(n);
          steps.add('$name($a) = ${_compact(v)}');
          return _compact(v);
        case ConvertNode(:final value, :final unit):
          final v = walk(value);
          final res = ev.eval(n);
          steps.add('$v → ${unit.id} = ${_compact(res)}');
          return _compact(res);
        case PercentOfNode(:final percent, :final of):
          final p = walk(percent);
          final o = walk(of);
          final v = ev.eval(n);
          steps.add('$p% of $o = ${_compact(v)}');
          return _compact(v);
      }
    }

    // same read-past rule as evaluation, so a line that answers also explains
    Node? node;
    for (final candidate in _candidates(body).take(8)) {
      try {
        node = Parser.parseExpression(candidate, units, format: format);
        break;
      } catch (_) {}
    }
    if (node == null) return const [];
    walk(node);
    return steps.length >= 2 ? steps : const [];
  }

  String _compact(Value v) => formatValue(v, format: format);

  /// Two passes: the first collects values per tag so `total of #tag` can be
  /// answered on lines that appear above some of the tagged lines.
  List<LineResult> evaluate(List<String> lines) {
    final tags = <String, List<Value>>{};
    _run(lines, tags, collect: true);
    return _run(lines, tags, collect: false);
  }

  List<LineResult> _run(
    List<String> lines,
    Map<String, List<Value>> tags, {
    required bool collect,
  }) {
    final results = <LineResult>[];
    final vars = <String, Value>{};
    final values = <Value?>[];
    final labels = <String, Value>{};
    // answers that are not themselves totals, aligned with `values`.
    // A total must never count a subtotal on top of the lines it covers.
    final leafAt = <Value?>[];
    var sectionStart = 0;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();

      // blank / comment / heading
      if (trimmed.isEmpty) {
        results.add(LineResult(text: raw));
        values.add(null);
        leafAt.add(null);
        sectionStart = i + 1;
        continue;
      }
      if (trimmed.startsWith('//') || _isComment(trimmed)) {
        results.add(
          LineResult(
            text: raw,
            isComment: true,
            isHeading: trimmed.startsWith('# '),
          ),
        );
        values.add(null);
        leafAt.add(null);
        if (trimmed.startsWith('# ')) sectionStart = i + 1;
        continue;
      }

      // "total of #food" is a command, not a line tagged #food
      final isTagTotal = RegExp(
        r'^(?:total|sum|subtotal)\s+of\s+#',
        caseSensitive: false,
      ).hasMatch(trimmed);
      final tag = isTagTotal ? null : _extractTag(trimmed);
      final body = tag == null
          ? trimmed
          : trimmed.substring(0, trimmed.lastIndexOf('#')).trim();

      try {
        final value = _evalLine(
          body,
          vars: vars,
          values: values,
          sectionStart: sectionStart,
          current: i,
          tag: tag,
          tags: tags,
          leafAt: leafAt,
          labels: labels,
        );
        values.add(value);
        leafAt.add(
          value is ErrorValue || _isAggregateLine(body) || _isSummaryLabel(body)
              ? null
              : value,
        );
        if (collect && tag != null && value != null) {
          tags.putIfAbsent(tag.toLowerCase(), () => []).add(value);
        }
        // the first word of a line names it for later references
        final label = labelOf(body);
        if (label != null && value != null && value is! ErrorValue) {
          labels.putIfAbsent(label, () => value);
        }
        final bad = value is ErrorValue;
        results.add(
          LineResult(
            text: raw,
            value: bad ? null : value,
            display: value == null || bad
                ? null
                : formatValue(value, format: format),
            error: bad ? value.message : null,
            engineError: bad,
            tag: tag,
          ),
        );
      } on UnresolvedWord {
        // "午餐 120" is prose with a number in it: show the number.
        final fallback = strict ? null : _loneNumber(body);
        values.add(fallback);
        leafAt.add(fallback);
        if (collect && tag != null && fallback != null) {
          tags.putIfAbsent(tag.toLowerCase(), () => []).add(fallback);
        }
        results.add(
          LineResult(
            text: raw,
            value: fallback,
            display: fallback == null
                ? null
                : formatValue(fallback, format: format),
            tag: tag,
          ),
        );
      } catch (e) {
        final fallback = strict ? null : _loneNumber(body);
        values.add(fallback);
        leafAt.add(fallback);
        if (collect && tag != null && fallback != null) {
          tags.putIfAbsent(tag.toLowerCase(), () => []).add(fallback);
        }
        results.add(
          LineResult(
            text: raw,
            value: fallback,
            display: fallback == null
                ? null
                : formatValue(fallback, format: format),
            error: fallback == null ? e.toString() : null,
            tag: tag,
          ),
        );
      }
    }
    return results;
  }

  // a line starting with '#' is a comment or heading; tags only count at the end
  /// The first word of a line, used as its name for references.
  /// "Tradeify: -$5,038.50" -> "tradeify"; "午餐 120" -> "午餐"; numbers -> null.
  static String? labelOf(String line) {
    final m = RegExp(r'^\s*([A-Za-z\u4e00-\u9fff][A-Za-z0-9_\u4e00-\u9fff]*)')
        .firstMatch(line);
    if (m == null) return null;
    final word = m.group(1)!;
    if (word.length < 2) return null;
    return word.toLowerCase();
  }

  static const _aggWords = {
    'sum',
    'total',
    'average',
    'avg',
    'count',
    'min',
    'max',
  };

  bool _isAggregateLine(String body) {
    final a = body.trim().toLowerCase();
    return _aggWords.contains(a) ||
        _grandWords.contains(a) ||
        RegExp(r'^(?:total|sum|subtotal)\s+of\s+#').hasMatch(a);
  }

  /// "Total expenses: …", "Overall net: …" are summary lines: the grand total
  /// must not add them on top of the rows they summarise.
  static bool _isSummaryLabel(String body) {
    final i = body.indexOf(':');
    if (i <= 0) return false;
    final label = body.substring(0, i).toLowerCase();
    if (!RegExp(r'[a-z\u4e00-\u9fff]').hasMatch(label)) return false;
    return RegExp(r'total|subtotal|net\b|balance|合計|小計|總計|總額|淨|結餘')
        .hasMatch(label);
  }

  bool _isComment(String s) => s.startsWith('#');

  String? _extractTag(String s) {
    final m = RegExp(r'\s#([\w\u4e00-\u9fff]+)\s*$').firstMatch(s);
    return m?.group(1);
  }

  Value? _evalLine(
    String body, {
    required Map<String, Value> vars,
    required List<Value?> values,
    required int sectionStart,
    required int current,
    required Map<String, List<Value>> tags,
    required List<Value?> leafAt,
    required Map<String, Value> labels,
    String? tag,
  }) {
    body = normalizeMathSource(body);
    final ctx = EvalContext(
      units: units,
      now: dates.now,
      vars: vars,
      rates: rates,
      labels: labels,
    );

    // "Topstep: −$10,408.52" — a label in front of the value
    final label = RegExp(r'^([^:]{1,60}):\s*(.+)$').firstMatch(body);
    if (label != null &&
        RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(label.group(1)!)) {
      final v = _parseValue(
        label.group(2)!.trim(),
        ctx,
        values: values,
        sectionStart: sectionStart,
        current: current,
      );
      if (v != null && v is! ErrorValue) return v;
    }

    // assignment: "rent = 2500", "total cost = $750"
    final assign = RegExp(r'^([^=<>!]+?)\s*=\s*([^=].*)$').firstMatch(body);
    if (assign != null && !body.contains('==')) {
      final name = assign.group(1)!.trim().toLowerCase();
      if (name.isNotEmpty && !RegExp(r'^\d').hasMatch(name)) {
        final v = _parseValue(
          assign.group(2)!.trim(),
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        );
        if (v != null) {
          vars[name] = v;
          return v;
        }
      }
    }

    // aggregation
    final agg = body.toLowerCase();
    if (const {
      'sum',
      'total',
      'average',
      'avg',
      'count',
      'min',
      'max',
    }.contains(agg)) {
      final slice = leafAt.sublist(sectionStart, current);
      return _aggregate(agg, slice.whereType<Value>().toList());
    }
    // grand total: every answer above this line, grouped by unit
    if (_grandWords.contains(agg)) {
      return _grandTotal(
        leafAt.sublist(0, current).whereType<Value>().toList(),
      );
    }

    final tagged = RegExp(
      r'^(?:total|sum|subtotal)\s+of\s+#([\w\u4e00-\u9fff]+)$',
    ).firstMatch(agg);
    if (tagged != null) {
      final items = tags[tagged.group(1)!.toLowerCase()] ?? const <Value>[];
      if (items.isEmpty) {
        return ErrorValue('no lines tagged #${tagged.group(1)}');
      }
      return _aggregate('sum', items);
    }

    // rule of three: "9 is to 16 as 27 is to what"
    final r3 = RegExp(
      r'^(.*?)\s+is\s+to\s+(.*?)\s+as\s+(.*?)\s+is\s+to\s+(what|\?|.*)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (r3 != null) {
      final a = _numOf(
        _parseValue(
          r3.group(1)!.trim(),
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        ),
      );
      final b = _numOf(
        _parseValue(
          r3.group(2)!.trim(),
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        ),
      );
      final c = _numOf(
        _parseValue(
          r3.group(3)!.trim(),
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        ),
      );
      final dText = r3.group(4)!.trim().toLowerCase();
      if (a != null && b != null && c != null && a != 0) {
        if (dText == 'what' || dText == '?') return NumValue(c * b / a);
        final d = _numOf(
          _parseValue(
            r3.group(4)!.trim(),
            ctx,
            values: values,
            sectionStart: sectionStart,
            current: current,
          ),
        );
        if (d != null) {
          // solve for the missing first value instead
          if (dText.isNotEmpty && a == 0) return NumValue(c * b / d);
        }
      }
    }

    // if <cond> then <a> else <b>
    final cond = RegExp(
      r'^if\s+(.+?)\s+then\s+(.+?)\s+else\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (cond != null) {
      final ok = _compare(cond.group(1)!, ctx);
      final branch = ok == null ? null : (ok ? cond.group(2)! : cond.group(3)!);
      if (branch != null) {
        return _parseValue(
          branch.trim(),
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        );
      }
    }

    final zhPct = _zhPercent(
      body,
      ctx,
      values: values,
      sectionStart: sectionStart,
      current: current,
    );
    if (zhPct != null) return zhPct;

    // "20 is what % of 80" / "20 is what percent of 80"
    final whatPct = RegExp(
      r'^(.*?)\s+is\s+what\s+(?:%|percent)\s+of\s+(.*)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (whatPct != null) {
      final a = _numOf(
        _parseValue(
          whatPct.group(1)!,
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        ),
      );
      final b = _numOf(
        _parseValue(
          whatPct.group(2)!,
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        ),
      );
      if (a != null && b != null && b != 0) return PercentValue(a / b);
    }

    // "5% of what is 150"
    final pctWhat = RegExp(
      r'^([\d.]+)\s*%\s+of\s+what\s+is\s+(.*)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (pctWhat != null) {
      final p = double.tryParse(pctWhat.group(1)!);
      final b = _numOf(
        _parseValue(
          pctWhat.group(2)!,
          ctx,
          values: values,
          sectionStart: sectionStart,
          current: current,
        ),
      );
      if (p != null && b != null && p != 0) return NumValue(b / (p / 100));
    }

    // "compound interest 5000 at 7.5% for 3 years"
    final ci = RegExp(
      r'^(?:compound\s+interest|compounding)\s+([\d.,]+)\s*(?:at|@)\s*([\d.]+)\s*%\s+(?:for|over)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (ci != null) {
      final principal = double.tryParse(ci.group(1)!.replaceAll(',', ''));
      final rate = double.tryParse(ci.group(2)!);
      final years = _years(ci.group(3)!);
      if (principal != null && rate != null && years != null) {
        return NumValue(principal * math.pow(1 + rate / 100, years).toDouble());
      }
    }

    // "25% off 159.99"
    final off = RegExp(
      r'^([\d.]+)\s*%\s+off\s+(.*)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (off != null) {
      final p = double.tryParse(off.group(1)!);
      final v = _parseValue(
        off.group(2)!,
        ctx,
        values: values,
        sectionStart: sectionStart,
        current: current,
      );
      if (p != null && v is NumValue) {
        return NumValue(v.value * (1 - p / 100), v.unit);
      }
      if (p != null && v is MoneyValue) {
        return MoneyValue(v.value * (1 - p / 100), v.currency);
      }
    }

    // "days between A and B"
    final between = RegExp(
      r'^(?:how\s+many\s+)?(\w+)?\s*between\s+(.+?)\s+and\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (between != null) {
      final a = dates.parse(between.group(2)!);
      final b = dates.parse(between.group(3)!);
      if (a != null && b != null) {
        final diff = b.difference(a).inSeconds.toDouble();
        final unit = (between.group(1) ?? 'day').toLowerCase();
        final u = units.lookup(unit == 'days' ? 'day' : unit);
        if (u != null) {
          return NumValue(diff / u.factor, u);
        }
        return DurationValue(diff);
      }
    }

    // "<date> - <date>" is the gap between them, not arithmetic on the digits.
    // Without this "2026-10-31 - 2026-01-01" read as 2026-10-31-2026-1-1 = -43.
    final gap = RegExp(r'\s+-\s+|\s+to\s+|\s+until\s+').firstMatch(body);
    if (gap != null) {
      final a = dates.parse(body.substring(0, gap.start));
      final b = dates.parse(body.substring(gap.end));
      if (a != null && b != null) {
        // "A - B" counts backwards from A; "A to B" counts forwards.
        final seconds = gap.group(0)!.trim() == '-'
            ? a.difference(b).inSeconds
            : b.difference(a).inSeconds;
        return DurationValue(seconds.toDouble());
      }
    }

    // "30 days from today", "3 weeks ago"
    final shift = RegExp(
      r'^(\d+(?:\.\d+)?)\s*(days?|weeks?|months?|years?)\s+(from|after|before|ago)\b\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (shift != null) {
      final n = double.tryParse(shift.group(1)!);
      final unit = shift.group(2)!.toLowerCase();
      final dir = shift.group(3)!.toLowerCase();
      final rest = shift.group(4)!.trim();
      final base = rest.isEmpty ? dates.now : dates.parse(rest);
      if (n != null && base != null) {
        final days = switch (unit) {
          'week' || 'weeks' => n * 7,
          'month' || 'months' => n * 30,
          'year' || 'years' => n * 365,
          _ => n,
        };
        final signed = dir == 'before' || dir == 'ago' ? -days : days;
        return DateValue(base.add(Duration(seconds: (signed * 86400).round())));
      }
    }

    // dates: "<date> ± <duration>"
    final dateMath = RegExp(r'^(.*?)\s*([+-])\s*(.+)$').firstMatch(body);
    if (dateMath != null) {
      final left = dates.parse(dateMath.group(1)!);
      if (left != null) {
        // "today + 3 workdays" skips Saturday and Sunday.
        final wd = RegExp(
          r'^(\d{1,5})\s*(?:work|business)\s*days?$',
          caseSensitive: false,
        ).firstMatch(dateMath.group(3)!.trim());
        if (wd != null) {
          final step = dateMath.group(2) == '-' ? -1 : 1;
          var d = left;
          var leftToGo = int.parse(wd.group(1)!);
          while (leftToGo > 0) {
            d = d.add(Duration(days: step));
            if (d.weekday != DateTime.saturday &&
                d.weekday != DateTime.sunday) {
              leftToGo--;
            }
          }
          return DateValue(d, hasTime: left.hour != 0 || left.minute != 0);
        }
        final dur = dates.parseDuration(dateMath.group(3)!);
        if (dur != null) {
          final signed = dateMath.group(2) == '-'
              ? left.subtract(dur)
              : left.add(dur);
          return DateValue(
            signed,
            hasTime:
                body.contains(':') ||
                body.toLowerCase().contains('am') ||
                body.toLowerCase().contains('pm'),
          );
        }
      }
    }

    // "3pm HKT in New York"
    final zoneIn = RegExp(
      r'^(.*?)\s+in\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (zoneIn != null) {
      final dst = DateParser.zoneFor(zoneIn.group(2)!);
      if (dst != null) {
        final srcText = zoneIn.group(1)!.trim();
        final src = _trailingZone(srcText) ?? 'Asia/Hong_Kong';
        final stripped = _trailingZone(srcText) == null
            ? srcText
            : srcText.substring(0, srcText.lastIndexOf(' ')).trim();
        final dt = dates.parse(stripped);
        if (dt != null) {
          final converted = dates.convertZone(dt, src, dst);
          if (converted != null) return DateValue(converted, hasTime: true);
        }
      }
    }

    // bare date
    final bare = dates.parse(body);
    if (bare != null) {
      return DateValue(
        bare,
        hasTime: RegExp(r'\d:\d|am|pm', caseSensitive: false).hasMatch(body),
      );
    }

    // "2h 30m", "3 hours 20 minutes", "1h 2m 3s" — a duration, not a product
    // of a number and a unit.
    final span = _durationLine(body);
    if (span != null) return span;

    return _parseValue(
      body,
      ctx,
      values: values,
      sectionStart: sectionStart,
      current: current,
    );
  }

  String? _trailingZone(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    return DateParser.zoneFor(parts.last);
  }

  Value? _parseValue(
    String src,
    EvalContext ctx, {
    required List<Value?> values,
    required int sectionStart,
    required int current,
  }) {
    // line references: "line 3", "#3", "prev"
    var expanded = src.replaceAllMapped(
      RegExp(r'\b(?:line|ln)\s+(\d+)\b', caseSensitive: false),
      (m) {
        final idx = int.parse(m.group(1)!) - 1;
        final v = idx >= 0 && idx < values.length ? values[idx] : null;
        return v == null ? m.group(0)! : _literal(v);
      },
    );
    expanded = expanded.replaceAllMapped(
      RegExp(r'\bprev\b', caseSensitive: false),
      (m) {
        final v = ctx.prev;
        return v == null ? m.group(0)! : _literal(v);
      },
    );

    // Soulver's "read past" behaviour: if the line starts with prose, retry
    // the expression starting at each later word boundary. "買嘢 4300 x 30%"
    // still answers.
    Object? lastError;
    final candidates = strict
        ? [expanded]
        : _candidates(expanded).take(8).toList();
    for (final candidate in candidates) {
      try {
        final node = Parser.parseExpression(candidate, units, format: format);
        return Evaluator(ctx).eval(node);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? ParseError('empty');
  }

  /// Skips a leading *prose* prefix only. Once the prefix contains a digit or
  /// an operator we stop, so "4300 X 30%" is not rescued as "30%" — a wrong
  /// answer is worse than no answer.
  Iterable<String> _candidates(String src) sync* {
    yield src;
    for (var i = 1; i < src.length; i++) {
      if (src[i - 1] != ' ' || src[i] == ' ') continue;
      if (!_isProse(src.substring(0, i))) return;
      // "rent * 12" is a failed expression, not prose in front of a number:
      // skipping to "* 12" would answer 12. A leading minus is kept, because
      // "貸款 -500000" is a signed value in prose.
      if ('+*/^%×÷(),=<>'.contains(src[i])) return;
      yield src.substring(i);
    }
  }

  /// A leading clock time is a label, not arithmetic: "14:00 Tradeify 1000+2000"
  /// must still answer 3,000, while "4300 X 30%" stays unanswered.
  bool _isProse(String s) {
    final clock = RegExp(r'^\s*\d{1,2}:\d{2}(?::\d{2})?\s*').firstMatch(s);
    final rest = clock == null ? s : s.substring(clock.end);
    return !RegExp(r'[0-9+\-*/^%().$,=<>×÷:]').hasMatch(rest);
  }

  String _literal(Value v) {
    if (v is NumValue) {
      return v.unit == null ? '${v.value}' : '${v.value} ${v.unit!.id}';
    }
    if (v is MoneyValue) return '${v.value} ${v.currency}';
    if (v is DateValue) return '${v.date.year}-${v.date.month}-${v.date.day}';
    if (v is PercentValue) return '${v.ratio * 100}%';
    return '';
  }

  double? _numOf(Value? v) => v is NumValue ? v.value : null;

  /// Chinese forms of the two Core percent questions.
  ///
  /// "20是80的百分之幾" / "20係80嘅百分之几" → 25%.
  /// "5%的幾多是150" / "百分之5的幾是150" → 3000.
  Value? _zhPercent(
    String body,
    EvalContext ctx, {
    required List<Value?> values,
    required int sectionStart,
    required int current,
  }) {
    double? numAt(String src) {
      final v = _parseValue(
        src.trim(),
        ctx,
        values: values,
        sectionStart: sectionStart,
        current: current,
      );
      return _numOf(v);
    }

    final what = RegExp(r'^(.*?)\s*(?:是|係)\s*(.*?)\s*(?:的|嘅)\s*百分之\s*[幾几]\s*$')
        .firstMatch(body);
    if (what != null) {
      final a = numAt(what.group(1)!);
      final b = numAt(what.group(2)!);
      if (a != null && b != null && b != 0) return PercentValue(a / b);
      return null;
    }

    final inverse = RegExp(
      r'^(?:百分之\s*([\d.]+)|([\d.]+)\s*%)\s*(?:的|嘅)\s*[幾几]多?\s*(?:是|係)\s*(.+)$',
    ).firstMatch(body);
    if (inverse != null) {
      final p = double.tryParse(inverse.group(1) ?? inverse.group(2)!);
      final b = numAt(inverse.group(3)!);
      if (p != null && b != null && p != 0) return NumValue(b / (p / 100));
    }
    return null;
  }

  double? _years(String s) {
    final m = RegExp(
      r'([\d.]+)\s*(years?|months?|weeks?|days?)',
      caseSensitive: false,
    ).firstMatch(s);
    if (m == null) return double.tryParse(s.trim());
    final n = double.tryParse(m.group(1)!);
    if (n == null) return null;
    return switch (m.group(2)!.toLowerCase()) {
      'year' || 'years' => n,
      'month' || 'months' => n / 12,
      'week' || 'weeks' => n / 52,
      _ => n / 365,
    };
  }

  bool? _compare(String expr, EvalContext ctx) {
    final m = RegExp(r'^(.*?)\s*(>=|<=|==|!=|>|<)\s*(.*)$').firstMatch(expr);
    if (m == null) return null;
    final a = _numOf(
      _parseValue(
        m.group(1)!.trim(),
        ctx,
        values: const [],
        sectionStart: 0,
        current: 0,
      ),
    );
    final b = _numOf(
      _parseValue(
        m.group(3)!.trim(),
        ctx,
        values: const [],
        sectionStart: 0,
        current: 0,
      ),
    );
    if (a == null || b == null) return null;
    return switch (m.group(2)) {
      '>' => a > b,
      '<' => a < b,
      '>=' => a >= b,
      '<=' => a <= b,
      '==' => a == b,
      _ => a != b,
    };
  }

  /// Every answer above the line, grouped by unit. Mixed dimensions come back
  /// as a list ("6.36 kg, 2 m") instead of a fake single number.
  Value _grandTotal(List<Value> items) {
    final nums = items.whereType<NumValue>().toList();
    final money = items.whereType<MoneyValue>().toList();
    final out = <Value>[];

    if (money.isNotEmpty) {
      final base = money.first.currency;
      var total = 0.0;
      var ok = true;
      for (final m in money) {
        final from = rates[m.currency];
        final to = rates[base];
        if (from == null || to == null) {
          ok = false;
          break;
        }
        total += m.value / from * to;
      }
      if (ok) out.add(MoneyValue(total, base));
    }

    final groups = <String, List<NumValue>>{};
    for (final n in nums) {
      final key = n.unit == null
          ? 'plain'
          : (n.unit!.dims.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
                .map((e) => '${e.key}:${e.value}')
                .join(',');
      groups.putIfAbsent(key, () => []).add(n);
    }
    for (final list in groups.values) {
      final unit = list.first.unit;
      var total = 0.0;
      for (final n in list) {
        if (unit == null) {
          total += n.value;
        } else {
          final c = units.convert(n.value, n.unit!, unit);
          if (c != null) total += c;
        }
      }
      out.add(NumValue(total, unit));
    }

    if (out.isEmpty) return const ErrorValue('nothing to total');
    return out.length == 1 ? out.first : ListValue(out);
  }

  Value _aggregate(String op, List<Value> items) {
    final nums = items.whereType<NumValue>().toList();
    final money = items.whereType<MoneyValue>().toList();

    if (op == 'count') return NumValue(items.length.toDouble());

    if (money.isNotEmpty && nums.isEmpty) {
      final base = money.first.currency;
      var total = 0.0;
      for (final m in money) {
        final from = rates[m.currency];
        final to = rates[base];
        if (from == null || to == null) return const ErrorValue('no rate');
        total += m.value / from * to;
      }
      return MoneyValue(total, base);
    }

    if (nums.isEmpty) return const ErrorValue('nothing to sum');
    final unit = nums.first.unit;
    final vals = <double>[];
    for (final n in nums) {
      if (unit == null) {
        if (n.unit != null) return const ErrorValue('mixed units');
        vals.add(n.value);
      } else {
        if (n.unit == null) return const ErrorValue('mixed units');
        final c = units.convert(n.value, n.unit!, unit);
        if (c == null) return const ErrorValue('mixed units');
        vals.add(c);
      }
    }
    final total = vals.fold<double>(0, (a, b) => a + b);
    switch (op) {
      case 'sum' || 'total' || 'subtotal':
        return NumValue(total, unit);
      case 'average' || 'avg':
        return NumValue(total / vals.length, unit);
      case 'min':
        return NumValue(vals.reduce((a, b) => a < b ? a : b), unit);
      case 'max':
        return NumValue(vals.reduce((a, b) => a > b ? a : b), unit);
    }
    return const ErrorValue('unknown aggregate');
  }

  /// Time written the way people say it: `2h 30m`, `3 hours 20 minutes`,
  /// `1h 2m 3s`, and sums of those (`2h 30m + 45m`).
  ///
  /// An hour component is required, so a lone `45m` keeps meaning 45 metres
  /// and `5 s` keeps meaning five seconds of a unit answer, not a duration.
  Value? _durationLine(String body) {
    final into = RegExp(
      r'^(.*?)\s+in\s+(seconds?|minutes?|hours?|days?)$',
      caseSensitive: false,
    ).firstMatch(body);
    if (into != null) {
      final left = _durationLine(into.group(1)!);
      if (left is DurationValue) {
        final unit = switch (into.group(2)!.toLowerCase()) {
          'seconds' || 'second' => 's',
          'hours' || 'hour' => 'h',
          'days' || 'day' => 'day',
          _ => 'min',
        };
        final u = units.lookup(unit);
        if (u != null) {
          return NumValue(left.seconds / u.factor, u);
        }
      }
      return null;
    }

    final token = RegExp(
      r'(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|min|mins|minutes?|s|sec|secs|seconds?)\b|([+-])',
      caseSensitive: false,
    );
    final all = token.allMatches(body).toList();
    if (all.isEmpty) return null;
    if (body.replaceAll(token, '').replaceAll(RegExp(r'\s'), '').isNotEmpty) {
      return null;
    }
    double? secondsOf(String unit) => switch (unit.toLowerCase()) {
      'h' || 'hr' || 'hrs' || 'hour' || 'hours' => 3600,
      'm' || 'min' || 'mins' || 'minute' || 'minutes' => 60,
      's' || 'sec' || 'secs' || 'second' || 'seconds' => 1,
      _ => null,
    };
    final time = all.where((m) => m.group(1) != null);
    if (!time.any((m) => secondsOf(m.group(2)!) == 3600)) return null;

    var total = 0.0;
    var sign = 1.0;
    for (final m in all) {
      final op = m.group(3);
      if (op != null && m.group(1) == null) {
        sign = op == '-' ? -1 : 1;
        continue;
      }
      final n = double.tryParse(m.group(1)!);
      final unit = secondsOf(m.group(2)!);
      if (n == null || unit == null) return null;
      total += sign * n * unit;
      sign = 1;
    }
    return DurationValue(total);
  }

  /// One number, read the way the lexer would read it. A grouping mark that
  /// is not exactly three digits (`1,23` in US, `1.23` in EU) must not be
  /// rewritten into a different integer.
  Value? _loneNumber(String s) {
    final tokens = Lexer(s, format: format).tokenize();
    // A number beside an operator is an expression we could not parse, not
    // prose to quote back: answering "rent * 12" as 12 is a wrong answer.
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type != TokType.op) continue;
      final unary = i == 0 || tokens[i - 1].type == TokType.lparen;
      if (unary && (t.text == '-' || t.text == '+')) continue;
      return null;
    }
    final at = [
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i].type == TokType.number) i,
    ];
    if (at.length != 1) return null;
    final i = at.single;
    final v = tokens[i].num;
    if (v == null) return null;
    // the sign is its own token; a minus on the first token or right after
    // an opening paren is unary
    if (i > 0 &&
        tokens[i - 1].type == TokType.op &&
        tokens[i - 1].text == '-') {
      if (i == 1 || tokens[i - 2].type == TokType.lparen) return NumValue(-v);
    }
    return NumValue(v);
  }
}
