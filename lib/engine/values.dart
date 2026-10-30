import 'units.dart';

/// A value a line can evaluate to.
sealed class Value {
  const Value();
}

class NumValue extends Value {
  final double value;
  final Unit? unit;
  const NumValue(this.value, [this.unit]);
}

class MoneyValue extends Value {
  final double value;
  final String currency; // ISO 4217
  const MoneyValue(this.value, this.currency);
}

class PercentValue extends Value {
  final double ratio; // 25% -> 0.25
  const PercentValue(this.ratio);
}

class DateValue extends Value {
  final DateTime date;
  final bool hasTime;
  const DateValue(this.date, {this.hasTime = false});
}

class DurationValue extends Value {
  final double seconds;
  const DurationValue(this.seconds);
}

class BoolValue extends Value {
  final bool value;
  const BoolValue(this.value);
}

class ListValue extends Value {
  final List<Value> items;
  const ListValue(this.items);
}

class ErrorValue extends Value {
  final String message;
  const ErrorValue(this.message);
}

const Map<String, String> currencySymbols = {
  'USD': r'$',
  'HKD': r'HK$',
  'CNY': r'¥',
  'JPY': r'¥',
  'EUR': '€',
  'GBP': '£',
  'KRW': '₩',
  'TWD': r'NT$',
  'SGD': r'S$',
  'AUD': r'A$',
  'CAD': r'C$',
  'CHF': 'CHF ',
  'INR': '₹',
  'THB': '฿',
  'MYR': 'RM ',
  'PHP': '₱',
  'VND': '₫',
};

const Set<String> currencyCodes = {
  'USD',
  'HKD',
  'CNY',
  'JPY',
  'EUR',
  'GBP',
  'KRW',
  'TWD',
  'SGD',
  'AUD',
  'CAD',
  'CHF',
  'INR',
  'THB',
  'MYR',
  'PHP',
  'VND',
  'NZD',
  'SEK',
  'NOK',
  'DKK',
  'RUB',
  'BRL',
  'MXN',
  'ZAR',
  'AED',
  'IDR',
  'TRY',
  'PLN',
  'ILS',
};

/// How numbers are written and how the ambiguous ¥ sign is read.
///
/// [us] is the historical default (`1,234.56`, ¥ = JPY) so existing sheets
/// keep their answers. [eu] reads `9,875` as 9.875, not nine thousand.
class NumberFormat {
  final String decimal;
  final String group;

  /// ISO code the ¥ glyph parses as. JPY amounts drop cents; CNY keeps them.
  final String yen;

  const NumberFormat({this.decimal = '.', this.group = ',', this.yen = 'JPY'});

  static const us = NumberFormat();
  static const eu = NumberFormat(decimal: ',', group: '.');

  NumberFormat withYen(String code) =>
      NumberFormat(decimal: decimal, group: group, yen: code);

  static NumberFormat fromPrefs(String preset, String yen) {
    final base = preset == 'eu' ? eu : us;
    return yen == base.yen ? base : base.withYen(yen);
  }

  String get preset => decimal == ',' && group == '.' ? 'eu' : 'us';
}

const Map<String, String> currencyAliases = {
  r'$': 'USD',
  'US\$': 'USD',
  'HK\$': 'HKD',
  '€': 'EUR',
  '£': 'GBP',
  '¥': 'JPY',
  '₩': 'KRW',
  '₹': 'INR',
  '฿': 'THB',
};

/// 12 significant digits, grouping separators, no trailing zeros.
String formatNumber(
  double v, {
  int? decimals,
  NumberFormat format = NumberFormat.us,
}) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  if (v == 0 && decimals == null) return '0';

  // `decimals` is decimal places, not significant digits: money keeps cents
  var s = decimals != null
      ? v.toStringAsFixed(decimals)
      : v.abs() >= 1e15 || v.abs() < 1e-9
      ? v.toStringAsExponential(6)
      : _toPrecision(v, 12);

  if (s.contains('e')) {
    s = s.replaceAll(RegExp(r'0+e'), 'e').replaceAll(RegExp(r'\.e'), 'e');
    return v < 0 ? '-$s' : s;
  }

  var parts = s.split('.');
  var intPart = parts[0];
  var frac = parts.length > 1 ? parts[1] : '';
  // strip trailing zeros only when no explicit decimal count was requested
  if (decimals == null) {
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
  }
  final neg = intPart.startsWith('-');
  if (neg) intPart = intPart.substring(1);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (format.group.isNotEmpty && i > 0 && (intPart.length - i) % 3 == 0) {
      buf.write(format.group);
    }
    buf.write(intPart[i]);
  }
  final out = frac.isEmpty
      ? buf.toString()
      : '${buf.toString()}${format.decimal}$frac';
  return neg ? '-$out' : out;
}

String _toPrecision(double v, int sig) {
  if (v == v.roundToDouble() && v.abs() < 1e15) {
    return v.toStringAsFixed(0);
  }
  final s = v.toStringAsPrecision(sig);
  if (s.contains('e')) {
    // fall back to fixed for moderate magnitudes
    final mag = v.abs();
    if (mag < 1e15 && mag > 1e-6) {
      var d =
          sig - 1 - (v.abs().toStringAsExponential().split('e')[0].length - 2);
      if (d < 0) d = 0;
      if (d > 12) d = 12;
      return v.toStringAsFixed(d);
    }
  }
  return s;
}

const _unitSymbols = {'C': '°C', 'F': '°F'};
const _plurals = {
  'day': 'days',
  'week': 'weeks',
  'month': 'months',
  'year': 'years',
};

String _unitLabel(String id, double value) {
  final symbol = _unitSymbols[id];
  if (symbol != null) return symbol;
  final plural = _plurals[id];
  if (plural != null && value != 1) return plural;
  return id;
}

String formatValue(
  Value v, {
  int? decimals,
  NumberFormat format = NumberFormat.us,
}) {
  switch (v) {
    case NumValue(:final value, :final unit):
      final n = formatNumber(value, decimals: decimals, format: format);
      if (unit == null) return n;
      return '$n ${_unitLabel(unit.id, value)}';
    case MoneyValue(:final value, :final currency):
      final n = formatNumber(
        value.abs(),
        decimals: decimals ?? 2,
        format: format,
      );
      final sym = currencySymbols[currency] ?? '$currency ';
      final sign = value < 0 ? '-' : '';
      return currency == 'JPY' || currency == 'KRW'
          ? '$sign$sym${formatNumber(value.abs().roundToDouble(), format: format)}'
          : '$sign$sym$n';
    case PercentValue(:final ratio):
      return '${formatNumber(ratio * 100, decimals: decimals, format: format)}%';
    case DateValue(:final date, :final hasTime):
      return hasTime ? _fmtDateTime(date) : _fmtDate(date);
    case DurationValue(:final seconds):
      return _fmtDuration(seconds, format);
    case BoolValue(:final value):
      return value ? 'true' : 'false';
    case ListValue(:final items):
      return items
          .map((e) => formatValue(e, decimals: decimals, format: format))
          .join(', ');
    case ErrorValue(:final message):
      return message;
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _fmtDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${_fmtDate(d)} at $h:$m $ap';
}

String _fmtDuration(double seconds, NumberFormat format) {
  final s = seconds.abs();
  if (s < 60) return '${formatNumber(seconds, format: format)} s';
  if (s < 3600) return '${formatNumber(seconds / 60, format: format)} min';
  if (s < 86400) return '${formatNumber(seconds / 3600, format: format)} h';
  return '${formatNumber(seconds / 86400, format: format)} days';
}
