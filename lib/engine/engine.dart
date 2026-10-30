import 'dates.dart';
import 'evaluator.dart';
import 'parser.dart';
import 'units.dart';
import 'values.dart';

class LineResult {
  final String text;
  final Value? value;
  final String? display;
  final String? error;
  final bool isComment;
  final bool isHeading;
  final String? tag;

  const LineResult({
    required this.text,
    this.value,
    this.display,
    this.error,
    this.isComment = false,
    this.isHeading = false,
    this.tag,
  });

  bool get hasAnswer => display != null;
}

/// Evaluates a whole sheet top to bottom, carrying variables and line
/// references forward. Errors stay on their own line.
class SheetEngine {
  final UnitRegistry units;
  final DateParser dates;
  Map<String, double> rates;
  final String baseCurrency;

  SheetEngine({
    UnitRegistry? units,
    DateTime? now,
    Map<String, double>? rates,
    this.baseCurrency = 'HKD',
  })  : units = units ?? UnitRegistry(),
        dates = DateParser(now: now),
        rates = rates ?? const {'USD': 1, 'HKD': 7.8};

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
    var sectionStart = 0;

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trim();

      // blank / comment / heading
      if (trimmed.isEmpty) {
        results.add(LineResult(text: raw));
        values.add(null);
        sectionStart = i + 1;
        continue;
      }
      if (trimmed.startsWith('//') || _isComment(trimmed)) {
        results.add(LineResult(
          text: raw,
          isComment: true,
          isHeading: trimmed.startsWith('# '),
        ));
        values.add(null);
        if (trimmed.startsWith('# ')) sectionStart = i + 1;
        continue;
      }

      // "total of #food" is a command, not a line tagged #food
      final isTagTotal = RegExp(r'^(?:total|sum|subtotal)\s+of\s+#',
              caseSensitive: false)
          .hasMatch(trimmed);
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
        );
        values.add(value);
        if (collect && tag != null && value != null) {
          tags.putIfAbsent(tag.toLowerCase(), () => []).add(value);
        }
        results.add(LineResult(
          text: raw,
          value: value,
          display: value == null ? null : formatValue(value),
          tag: tag,
        ));
      } on UnresolvedWord {
        // "午餐 120" is prose with a number in it: show the number.
        final fallback = _loneNumber(body);
        values.add(fallback);
        if (collect && tag != null && fallback != null) {
          tags.putIfAbsent(tag.toLowerCase(), () => []).add(fallback);
        }
        results.add(LineResult(
          text: raw,
          value: fallback,
          display: fallback == null ? null : formatValue(fallback),
          tag: tag,
        ));
      } catch (e) {
        final fallback = _loneNumber(body);
        values.add(fallback);
        if (collect && tag != null && fallback != null) {
          tags.putIfAbsent(tag.toLowerCase(), () => []).add(fallback);
        }
        results.add(LineResult(
          text: raw,
          value: fallback,
          display: fallback == null ? null : formatValue(fallback),
          error: fallback == null ? e.toString() : null,
          tag: tag,
        ));
      }
    }
    return results;
  }

  bool _isComment(String s) => s.startsWith('#') && !s.startsWith('# ');

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
    String? tag,
  }) {
    final ctx = EvalContext(
      units: units,
      now: dates.now,
      vars: vars,
      rates: rates,
    );

    // assignment: "rent = 2500", "total cost = $750"
    final assign = RegExp(r'^([^=<>!]+?)\s*=\s*([^=].*)$').firstMatch(body);
    if (assign != null && !body.contains('==')) {
      final name = assign.group(1)!.trim().toLowerCase();
      if (name.isNotEmpty && !RegExp(r'^\d').hasMatch(name)) {
        final v = _parseValue(assign.group(2)!.trim(), ctx,
            values: values, sectionStart: sectionStart, current: current);
        if (v != null) {
          vars[name] = v;
          return v;
        }
      }
    }

    // aggregation
    final agg = body.toLowerCase();
    if (const {'sum', 'total', 'average', 'avg', 'count', 'min', 'max'}
        .contains(agg)) {
      final slice = values.sublist(sectionStart, current);
      return _aggregate(agg, slice.whereType<Value>().toList());
    }
    final tagged = RegExp(r'^(?:total|sum|subtotal)\s+of\s+#([\w\u4e00-\u9fff]+)$')
        .firstMatch(agg);
    if (tagged != null) {
      final items = tags[tagged.group(1)!.toLowerCase()] ?? const <Value>[];
      if (items.isEmpty) {
        return ErrorValue('no lines tagged #${tagged.group(1)}');
      }
      return _aggregate('sum', items);
    }

    // rule of three: "9 is to 16 as 27 is to what"
    final r3 = RegExp(r'^(.*?)\s+is\s+to\s+(.*?)\s+as\s+(.*?)\s+is\s+to\s+(what|\?|.*)$',
            caseSensitive: false)
        .firstMatch(body);
    if (r3 != null) {
      final a = _numOf(_parseValue(r3.group(1)!.trim(), ctx,
          values: values, sectionStart: sectionStart, current: current));
      final b = _numOf(_parseValue(r3.group(2)!.trim(), ctx,
          values: values, sectionStart: sectionStart, current: current));
      final c = _numOf(_parseValue(r3.group(3)!.trim(), ctx,
          values: values, sectionStart: sectionStart, current: current));
      final dText = r3.group(4)!.trim().toLowerCase();
      if (a != null && b != null && c != null && a != 0) {
        if (dText == 'what' || dText == '?') return NumValue(c * b / a);
        final d = _numOf(_parseValue(r3.group(4)!.trim(), ctx,
            values: values, sectionStart: sectionStart, current: current));
        if (d != null) {
          // solve for the missing first value instead
          if (dText.isNotEmpty && a == 0) return NumValue(c * b / d);
        }
      }
    }

    // if <cond> then <a> else <b>
    final cond = RegExp(r'^if\s+(.+?)\s+then\s+(.+?)\s+else\s+(.+)$',
            caseSensitive: false)
        .firstMatch(body);
    if (cond != null) {
      final ok = _compare(cond.group(1)!, ctx);
      final branch = ok == null ? null : (ok ? cond.group(2)! : cond.group(3)!);
      if (branch != null) {
        return _parseValue(branch.trim(), ctx,
            values: values, sectionStart: sectionStart, current: current);
      }
    }

    // "20 is what % of 80" / "20 is what percent of 80"
    final whatPct = RegExp(r'^(.*?)\s+is\s+what\s+(?:%|percent)\s+of\s+(.*)$',
            caseSensitive: false)
        .firstMatch(body);
    if (whatPct != null) {
      final a = _numOf(_parseValue(whatPct.group(1)!, ctx,
          values: values, sectionStart: sectionStart, current: current));
      final b = _numOf(_parseValue(whatPct.group(2)!, ctx,
          values: values, sectionStart: sectionStart, current: current));
      if (a != null && b != null && b != 0) return PercentValue(a / b);
    }

    // "5% of what is 150"
    final pctWhat = RegExp(r'^([\d.]+)\s*%\s+of\s+what\s+is\s+(.*)$',
            caseSensitive: false)
        .firstMatch(body);
    if (pctWhat != null) {
      final p = double.tryParse(pctWhat.group(1)!);
      final b = _numOf(_parseValue(pctWhat.group(2)!, ctx,
          values: values, sectionStart: sectionStart, current: current));
      if (p != null && b != null && p != 0) return NumValue(b / (p / 100));
    }

    // "25% off 159.99"
    final off = RegExp(r'^([\d.]+)\s*%\s+off\s+(.*)$', caseSensitive: false)
        .firstMatch(body);
    if (off != null) {
      final p = double.tryParse(off.group(1)!);
      final v = _parseValue(off.group(2)!, ctx,
          values: values, sectionStart: sectionStart, current: current);
      if (p != null && v is NumValue) {
        return NumValue(v.value * (1 - p / 100), v.unit);
      }
      if (p != null && v is MoneyValue) {
        return MoneyValue(v.value * (1 - p / 100), v.currency);
      }
    }

    // "days between A and B"
    final between = RegExp(r'^(?:how\s+many\s+)?(\w+)?\s*between\s+(.+?)\s+and\s+(.+)$',
            caseSensitive: false)
        .firstMatch(body);
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

    // dates: "<date phrase> ± <duration>"
    final dateMath = RegExp(r'^(.*?)\s*([+-])\s*(.+)$').firstMatch(body);
    if (dateMath != null) {
      final left = dates.parse(dateMath.group(1)!);
      if (left != null) {
        final dur = dates.parseDuration(dateMath.group(3)!);
        if (dur != null) {
          final signed = dateMath.group(2) == '-'
              ? left.subtract(dur)
              : left.add(dur);
          return DateValue(signed, hasTime: body.contains(':') || body.toLowerCase().contains('am') || body.toLowerCase().contains('pm'));
        }
      }
    }

    // "3pm HKT in New York"
    final zoneIn = RegExp(r'^(.*?)\s+in\s+(.+)$', caseSensitive: false)
        .firstMatch(body);
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
      return DateValue(bare,
          hasTime: RegExp(r'\d:\d|am|pm', caseSensitive: false).hasMatch(body));
    }

    return _parseValue(body, ctx,
        values: values, sectionStart: sectionStart, current: current);
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
    expanded = expanded.replaceAllMapped(RegExp(r'\bprev\b', caseSensitive: false),
        (m) {
      final v = ctx.prev;
      return v == null ? m.group(0)! : _literal(v);
    });

    try {
      final node = Parser.parseExpression(expanded, units);
      return Evaluator(ctx).eval(node);
    } on UnresolvedWord {
      rethrow;
    } catch (_) {
      rethrow;
    }
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

  bool? _compare(String expr, EvalContext ctx) {
    final m = RegExp(r'^(.*?)\s*(>=|<=|==|!=|>|<)\s*(.*)$').firstMatch(expr);
    if (m == null) return null;
    final a = _numOf(_parseValue(m.group(1)!.trim(), ctx,
        values: const [], sectionStart: 0, current: 0));
    final b = _numOf(_parseValue(m.group(3)!.trim(), ctx,
        values: const [], sectionStart: 0, current: 0));
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

  Value? _loneNumber(String s) {
    final m = RegExp(r'-?\d[\d,]*(?:\.\d+)?').allMatches(s).toList();
    if (m.length == 1) {
      final v = double.tryParse(m.first.group(0)!.replaceAll(',', ''));
      if (v != null) return NumValue(v);
    }
    return null;
  }
}
