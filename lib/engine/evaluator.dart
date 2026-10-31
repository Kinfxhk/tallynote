import 'dart:math' as math;

import 'parser.dart';
import 'units.dart';
import 'values.dart';

class EvalContext {
  final UnitRegistry units;
  final Map<String, Value> vars;
  final Map<String, double> rates; // 1 USD = rates[ccy]
  final DateTime now;
  final Value? prev;
  final List<Value> above;

  /// Line labels: the first word of an earlier line -> its answer.
  final Map<String, Value> labels;

  EvalContext({
    required this.units,
    required this.now,
    Map<String, Value>? vars,
    Map<String, double>? rates,
    this.prev,
    List<Value>? above,
    Map<String, Value>? labels,
  }) : vars = vars ?? {},
       labels = labels ?? const {},
       rates = rates ?? const {'USD': 1},
       above = above ?? const [];
}

class Evaluator {
  final EvalContext ctx;

  Evaluator(this.ctx);

  Value eval(Node node) {
    switch (node) {
      case NumberNode(:final value, :final unit):
        if (unit != null &&
            unit.dims.length == 1 &&
            unit.dims.containsKey('currency')) {
          return MoneyValue(value, unit.id);
        }
        return NumValue(value, unit);
      case MoneyNode(:final value, :final currency):
        return MoneyValue(value, currency);
      case VarNode(:final name):
        return _var(name);
      case PercentNode(:final operand):
        final inner = eval(operand);
        if (inner is NumValue) return PercentValue(inner.value / 100);
        return const ErrorValue('bad percent');
      case UnaryNode(:final op, :final operand):
        // A leading sign belongs to the number, not to the converted result:
        // -40 °F is -40 °C, while negating after converting would give -4.4 °C.
        if (op == '-' && operand is ConvertNode) {
          return _convert(eval(UnaryNode('-', operand.value)), operand.unit);
        }
        final v = eval(operand);
        if (v is NumValue) {
          return NumValue(op == '-' ? -v.value : v.value, v.unit);
        }
        if (v is MoneyValue && op == '-') {
          return MoneyValue(-v.value, v.currency);
        }
        if (v is PercentValue && op == '-') {
          return PercentValue(-v.ratio);
        }
        return const ErrorValue('bad unary');
      case BinNode(:final op, :final left, :final right):
        return _binary(op, eval(left), eval(right));
      case CallNode(:final name, :final args):
        return _call(name, args.map(eval).toList());
      case ConvertNode(:final value, :final unit):
        return _convert(eval(value), unit);
      case PercentOfNode(:final percent, :final of):
        return _percentOf(eval(percent), eval(of));
    }
  }

  Value _var(String name) {
    final key = name.toLowerCase();
    final v = ctx.vars[key];
    if (v != null) return v;
    // a word that names an earlier line ("Tradeify", "午餐") is a reference
    final named = ctx.labels[key];
    if (named != null) return named;
    if (key == 'pi' || key == 'π') return NumValue(math.pi);
    if (key == 'e') return NumValue(math.e);
    if (key == 'tau' || key == 'τ') return NumValue(2 * math.pi);
    // unknown word that looks like a unit-less number is a text token
    throw UnresolvedWord(name);
  }

  Value _binary(String op, Value l, Value r) {
    // percent sugar: "100 + 10%" / "100 - 10%"
    if (r is PercentValue && (op == '+' || op == '-')) {
      if (l is NumValue) {
        final f = op == '+' ? 1 + r.ratio : 1 - r.ratio;
        return NumValue(l.value * f, l.unit);
      }
      if (l is MoneyValue) {
        final f = op == '+' ? 1 + r.ratio : 1 - r.ratio;
        return MoneyValue(l.value * f, l.currency);
      }
    }

    if (op == '+' || op == '-') {
      final sum = _addSub(l, r, op == '-' ? -1 : 1);
      if (sum != null) return sum;
      if (l is String || r is String) {
        return const ErrorValue('cannot add text');
      }
      return const ErrorValue('incompatible values');
    }

    if (op == '^') {
      if (l is NumValue && r is NumValue) {
        return NumValue(math.pow(l.value, r.value).toDouble());
      }
      return const ErrorValue('bad power');
    }

    if (op == '*') {
      if (l is NumValue && r is NumValue) {
        return _scaled(l.value * r.value, _mulUnit(l.unit, r.unit), [
          if (l.unit != null) l.unit!,
          if (r.unit != null) r.unit!,
        ]);
      }
      if (l is MoneyValue && r is NumValue) {
        return MoneyValue(l.value * r.value, l.currency);
      }
      if (l is NumValue && r is MoneyValue) {
        return MoneyValue(l.value * r.value, r.currency);
      }
      if (l is PercentValue && r is NumValue) {
        return NumValue(l.ratio * r.value, r.unit);
      }
      if (l is NumValue && r is PercentValue) {
        return NumValue(l.value * r.ratio, l.unit);
      }
      if (l is MoneyValue && r is PercentValue) {
        return MoneyValue(l.value * r.ratio, l.currency);
      }
      return const ErrorValue('cannot multiply');
    }

    if (op == '/') {
      if (r is PercentValue) {
        if (r.ratio == 0) return const ErrorValue('divide by zero');
        if (l is NumValue) return NumValue(l.value / r.ratio, l.unit);
        if (l is MoneyValue) return MoneyValue(l.value / r.ratio, l.currency);
        if (l is PercentValue) return NumValue(l.ratio / r.ratio);
      }
      if (l is PercentValue && r is NumValue) {
        if (r.value == 0) return const ErrorValue('divide by zero');
        return NumValue(l.ratio / r.value);
      }
      if (l is NumValue && r is NumValue) {
        if (r.value == 0) return const ErrorValue('divide by zero');
        return _scaled(l.value / r.value, _divUnit(l.unit, r.unit), [
          if (l.unit != null) l.unit!,
          if (r.unit != null) r.unit!,
        ]);
      }
      if (l is MoneyValue && r is NumValue) {
        if (r.value == 0) return const ErrorValue('divide by zero');
        return MoneyValue(l.value / r.value, l.currency);
      }
      if (l is MoneyValue && r is MoneyValue) {
        final rr = _toCurrency(r, l.currency);
        if (rr == null || rr.value == 0) {
          return const ErrorValue('bad division');
        }
        return NumValue(l.value / rr.value);
      }
      return const ErrorValue('cannot divide');
    }

    return const ErrorValue('unknown operator');
  }

  Value? _addSub(Value l, Value r, int sign) {
    if (l is NumValue && r is NumValue) {
      if (l.unit == null && r.unit == null) {
        return NumValue(l.value + sign * r.value);
      }
      if (l.unit != null && r.unit != null) {
        if (!l.unit!.sameDimension(r.unit!)) return null;
        if (l.unit!.isTemperature || r.unit!.isTemperature) {
          if (l.unit!.id != r.unit!.id) return null; // no mixing °C and °F
          return NumValue(l.value + sign * r.value, l.unit);
        }
        final converted = ctx.units.convert(r.value, r.unit!, l.unit!);
        if (converted == null) return null;
        return NumValue(l.value + sign * converted, l.unit);
      }
      // unit-less + quantity: adopt the unit
      if (l.unit == null && r.unit != null && sign > 0) {
        return NumValue(l.value + r.value, r.unit);
      }
      return null;
    }

    if (l is MoneyValue && r is MoneyValue) {
      final rr = _toCurrency(r, l.currency);
      if (rr == null) return null;
      return MoneyValue(l.value + sign * rr.value, l.currency);
    }

    // dates
    if (l is DateValue) {
      final d = _asDuration(r);
      if (d != null) {
        return DateValue(
          l.date.add(Duration(seconds: (sign * d).round())),
          hasTime: l.hasTime || _hasTimePart(d),
        );
      }
      if (r is DateValue && sign < 0) {
        final diff = l.date.difference(r.date).inSeconds;
        return DurationValue(diff.toDouble());
      }
    }

    if (l is DurationValue && r is DurationValue) {
      return DurationValue(l.seconds + sign * r.seconds);
    }
    if (l is DurationValue && r is NumValue) {
      return DurationValue(l.seconds + sign * r.value);
    }

    return null;
  }

  bool _hasTimePart(double seconds) => seconds % 86400 != 0;

  double? _asDuration(Value v) {
    if (v is DurationValue) return v.seconds;
    if (v is NumValue &&
        v.unit != null &&
        v.unit!.dims.length == 1 &&
        v.unit!.dims.containsKey('time')) {
      return v.value * v.unit!.factor;
    }
    return null;
  }

  NumValue _scaled(double value, Unit? unit, List<Unit> hints) {
    if (unit == null) return NumValue(value);
    final (v, u) = ctx.units.ideal(value, unit, hints);
    return NumValue(v, u);
  }

  Unit? _mulUnit(Unit? a, Unit? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a * b;
  }

  Unit? _divUnit(Unit? a, Unit? b) {
    if (b == null) return a;
    if (a == null) {
      return Unit('1/${b.id}', {
        for (final e in b.dims.entries) e.key: -e.value,
      }, 1 / b.factor);
    }
    return a / b;
  }

  MoneyValue? _toCurrency(MoneyValue v, String target) {
    if (v.currency == target) return v;
    final from = ctx.rates[v.currency];
    final to = ctx.rates[target];
    if (from == null || to == null) return null;
    return MoneyValue(v.value / from * to, target);
  }

  Value _convert(Value v, Unit unit) {
    if (v is NumValue) {
      if (v.unit == null) {
        return NumValue(v.value, unit); // attach a unit: "20 C"
      }
      final out = ctx.units.convert(v.value, v.unit!, unit);
      if (out == null) {
        return ErrorValue('cannot convert ${v.unit!.id} to ${unit.id}');
      }
      return NumValue(_round(out), unit);
    }
    if (v is MoneyValue) {
      final code = _currencyFromUnit(unit.id);
      if (code != null) {
        final from = ctx.rates[v.currency];
        final to = ctx.rates[code];
        if (from == null || to == null) {
          return ErrorValue('no rate for ${v.currency}->$code');
        }
        return MoneyValue(_round(v.value / from * to), code);
      }
    }
    if (v is DurationValue) {
      final out = ctx.units.convert(v.seconds, ctx.units.lookup('s')!, unit);
      if (out != null) return NumValue(_round(out), unit);
    }
    return ErrorValue('cannot convert to ${unit.id}');
  }

  String? _currencyFromUnit(String id) {
    final upper = id.toUpperCase();
    return currencyCodes.contains(upper) ? upper : null;
  }

  /// Floating point noise: sin(pi) should read 0, not 1.2e-16.
  double _snap(double v) => v.abs() < 1e-12 ? 0.0 : v;

  double _round(double v) {
    if (v.abs() >= 1e12) return v;
    return double.parse(v.toStringAsPrecision(12));
  }

  Value _call(String name, List<Value> args) {
    double? n(int i) => args.length > i && args[i] is NumValue
        ? (args[i] as NumValue).value
        : null;

    // angle handling: sin 45 deg -> 45° in radians
    double? angle(int i) {
      final a = args.length > i ? args[i] : null;
      if (a is NumValue) {
        if (a.unit != null && a.unit!.dims.containsKey('angle')) {
          return a.value * a.unit!.factor;
        }
        return a.value;
      }
      return null;
    }

    switch (name) {
      case 'sqrt':
        final v = n(0);
        return v == null
            ? const ErrorValue('sqrt needs a number')
            : NumValue(math.sqrt(v));
      case 'cbrt':
        final v = n(0);
        if (v == null) return const ErrorValue('cbrt needs a number');
        return NumValue(_signedRoot(v, 3));
      case 'root':
        final v = n(0);
        final degree = n(1) ?? 2;
        if (v == null || degree == 0) {
          return const ErrorValue('root needs a number');
        }
        if (v < 0 &&
            degree.roundToDouble() == degree &&
            degree.round().isEven) {
          return const ErrorValue('root needs a number');
        }
        final out = _signedRoot(v, degree);
        if (out.isNaN) return const ErrorValue('root needs a number');
        return NumValue(out);
      case 'abs':
        final v = n(0);
        return v == null
            ? const ErrorValue('abs needs a number')
            : NumValue(v.abs());
      case 'log':
        final v = n(0);
        if (v == null) return const ErrorValue('log needs a number');
        return NumValue(
          args.length > 1
              ? math.log(v) / math.log(n(1)!)
              : math.log(v) / math.ln10,
        );
      case 'ln':
        final v = n(0);
        return v == null
            ? const ErrorValue('ln needs a number')
            : NumValue(math.log(v));
      case 'exp':
        final v = n(0);
        return v == null
            ? const ErrorValue('exp needs a number')
            : NumValue(math.exp(v));
      case 'sin':
        return NumValue(_snap(math.sin(angle(0) ?? 0)));
      case 'cos':
        return NumValue(_snap(math.cos(angle(0) ?? 0)));
      case 'tan':
        return NumValue(_snap(math.tan(angle(0) ?? 0)));
      case 'asin' || 'arcsin':
        return NumValue(math.asin(n(0) ?? 0));
      case 'acos' || 'arccos':
        return NumValue(math.acos(n(0) ?? 0));
      case 'atan' || 'arctan':
        return NumValue(math.atan(n(0) ?? 0));
      case 'round':
        final v = n(0);
        if (v == null) return const ErrorValue('round needs a number');
        final dp = args.length > 1 ? (n(1) ?? 0).round() : 0;
        final f = math.pow(10, dp).toDouble();
        return NumValue((v * f).roundToDouble() / f);
      case 'ceil':
        return NumValue((n(0) ?? 0).ceilToDouble());
      case 'floor':
        return NumValue((n(0) ?? 0).floorToDouble());
      case 'fact':
        final v = (n(0) ?? 0).round();
        if (v < 0 || v > 170) return const ErrorValue('factorial out of range');
        var r = 1.0;
        for (var i = 2; i <= v; i++) {
          r *= i;
        }
        return NumValue(r);
      case 'min':
        final nums = args.whereType<NumValue>().map((e) => e.value).toList();
        return nums.isEmpty
            ? const ErrorValue('min needs numbers')
            : NumValue(nums.reduce(math.min));
      case 'max':
        final nums = args.whereType<NumValue>().map((e) => e.value).toList();
        return nums.isEmpty
            ? const ErrorValue('max needs numbers')
            : NumValue(nums.reduce(math.max));
      case 'pow':
        return NumValue(math.pow(n(0) ?? 0, n(1) ?? 0).toDouble());
      case 'random':
        final hi = n(0) ?? 1;
        return NumValue(math.Random().nextDouble() * hi);
      default:
        return ErrorValue('unknown function $name');
    }
  }

  /// `5% of $200`, `10% of 50%`, and `5% of 3 kg`.
  Value _percentOf(Value part, Value whole) {
    final ratio = switch (part) {
      NumValue(:final value) => value / 100,
      PercentValue(:final ratio) => ratio,
      MoneyValue() ||
      DateValue() ||
      DurationValue() ||
      BoolValue() ||
      ListValue() ||
      ErrorValue() => null,
    };
    if (ratio == null) return const ErrorValue('bad percent of');
    return switch (whole) {
      NumValue(:final value, :final unit) => NumValue(ratio * value, unit),
      MoneyValue(:final value, :final currency) => MoneyValue(
        ratio * value,
        currency,
      ),
      PercentValue(ratio: final base) => PercentValue(ratio * base),
      DateValue() ||
      DurationValue() ||
      BoolValue() ||
      ListValue() ||
      ErrorValue() => const ErrorValue('bad percent of'),
    };
  }

  /// Odd roots of a negative stay negative. `pow` itself returns NaN for that.
  double _signedRoot(double value, double degree) {
    final mag = math.pow(value.abs(), 1 / degree).toDouble();
    final neg =
        value < 0 && degree.roundToDouble() == degree && degree.round().isOdd;
    return _round(neg ? -mag : mag);
  }
}

/// Thrown when a bare word is not a known variable; the engine turns it into
/// "this line is text" instead of an error.
class UnresolvedWord implements Exception {
  final String name;
  UnresolvedWord(this.name);
  @override
  String toString() => name;
}
