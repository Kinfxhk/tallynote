import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Offline natural-language date/time parsing.
///
/// Deliberately small: an ordered list of patterns plus a word list, not an
/// NLP stack. Anything not matched returns null and the line is treated as
/// plain text.
class DateParser {
  final DateTime now;
  static bool _tzReady = false;

  DateParser({DateTime? now}) : now = now ?? DateTime.now() {
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
  }

  static const Map<String, String> zones = {
    'hkt': 'Asia/Hong_Kong',
    'hk': 'Asia/Hong_Kong',
    'hongkong': 'Asia/Hong_Kong',
    '香港': 'Asia/Hong_Kong',
    'utc': 'UTC',
    'gmt': 'UTC',
    'tokyo': 'Asia/Tokyo',
    'jst': 'Asia/Tokyo',
    '東京': 'Asia/Tokyo',
    'singapore': 'Asia/Singapore',
    'sgt': 'Asia/Singapore',
    'seoul': 'Asia/Seoul',
    'kst': 'Asia/Seoul',
    '首爾': 'Asia/Seoul',
    'shanghai': 'Asia/Shanghai',
    'beijing': 'Asia/Shanghai',
    'cst': 'Asia/Shanghai',
    '上海': 'Asia/Shanghai',
    '北京': 'Asia/Shanghai',
    'taipei': 'Asia/Taipei',
    '台北': 'Asia/Taipei',
    'bangkok': 'Asia/Bangkok',
    '曼谷': 'Asia/Bangkok',
    'kualalumpur': 'Asia/Kuala_Lumpur',
    'kl': 'Asia/Kuala_Lumpur',
    'jakarta': 'Asia/Jakarta',
    'manila': 'Asia/Manila',
    'mumbai': 'Asia/Kolkata',
    'delhi': 'Asia/Kolkata',
    'ist': 'Asia/Kolkata',
    'dubai': 'Asia/Dubai',
    'london': 'Europe/London',
    '倫敦': 'Europe/London',
    'paris': 'Europe/Paris',
    '巴黎': 'Europe/Paris',
    'berlin': 'Europe/Berlin',
    'zurich': 'Europe/Zurich',
    'moscow': 'Europe/Moscow',
    'newyork': 'America/New_York',
    'nyc': 'America/New_York',
    'losangeles': 'America/Los_Angeles',
    'la': 'America/Los_Angeles',
    'sanfrancisco': 'America/Los_Angeles',
    'sf': 'America/Los_Angeles',
    'chicago': 'America/Chicago',
    'toronto': 'America/Toronto',
    'vancouver': 'America/Vancouver',
    'sydney': 'Australia/Sydney',
    'melbourne': 'Australia/Melbourne',
    'auckland': 'Pacific/Auckland',
  };

  static const _months = {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  };

  static const _weekdays = {
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tue': 2,
    'wednesday': 3,
    'wed': 3,
    'thursday': 4,
    'thu': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  };

  /// Splits a trailing timezone token, e.g. "3pm HKT" -> ("3pm", Asia/Hong_Kong).
  (String, String?) _splitZone(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      final key = parts.last.toLowerCase().replaceAll(' ', '');
      final loc = zones[key];
      if (loc != null) {
        return (parts.sublist(0, parts.length - 1).join(' '), loc);
      }
    }
    return (s, null);
  }

  /// Returns a wall-clock DateTime in the requested zone (or local time).
  DateTime? parse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    final (body, zone) = _splitZone(s);
    s = body.trim();
    final lower = s.toLowerCase();
    final base = zone == null ? now : _inZone(now, zone);

    if (lower == 'now') return base;
    if (lower == 'today') return _dateOnly(base);
    if (lower == 'tomorrow') {
      return _dateOnly(base.add(const Duration(days: 1)));
    }
    if (lower == 'yesterday') {
      return _dateOnly(base.subtract(const Duration(days: 1)));
    }

    // next / last <weekday>
    final rel = RegExp(r'^(next|last|this)\s+([a-z]+)$').firstMatch(lower);
    if (rel != null) {
      final wd = _weekdays[rel.group(2)!];
      if (wd != null) {
        var delta = wd - base.weekday;
        if (rel.group(1) == 'next') {
          if (delta <= 0) delta += 7;
        } else if (rel.group(1) == 'last') {
          if (delta >= 0) delta -= 7;
        }
        return _dateOnly(base.add(Duration(days: delta)));
      }
    }

    // ISO date, optional time
    final iso = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?$',
    ).firstMatch(s);
    if (iso != null) {
      return DateTime(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
        iso.group(4) == null ? 0 : int.parse(iso.group(4)!),
        iso.group(5) == null ? 0 : int.parse(iso.group(5)!),
      );
    }

    // time only: 3pm, 3:30pm, 15:30
    final t = _parseTime(lower);
    if (t != null) {
      return DateTime(base.year, base.month, base.day, t.$1, t.$2);
    }

    // "March 12" / "12 March" / "March 12 2026"
    final m1 = RegExp(r'^([a-z]+)\.?\s+(\d{1,2})(?:,?\s+(\d{4}))?$')
        .firstMatch(lower);
    if (m1 != null && _months.containsKey(m1.group(1)!)) {
      final year = m1.group(3) == null ? base.year : int.parse(m1.group(3)!);
      var d = DateTime(year, _months[m1.group(1)!]!, int.parse(m1.group(2)!));
      // a bare "March 12" in the past means next year
      if (m1.group(3) == null && d.isBefore(_dateOnly(base))) {
        d = DateTime(year + 1, d.month, d.day);
      }
      return d;
    }
    final m2 = RegExp(r'^(\d{1,2})\s+([a-z]+)\.?(?:,?\s+(\d{4}))?$')
        .firstMatch(lower);
    if (m2 != null && _months.containsKey(m2.group(2)!)) {
      final year = m2.group(3) == null ? base.year : int.parse(m2.group(3)!);
      var d = DateTime(year, _months[m2.group(2)!]!, int.parse(m2.group(1)!));
      if (m2.group(3) == null && d.isBefore(_dateOnly(base))) {
        d = DateTime(year + 1, d.month, d.day);
      }
      return d;
    }

    // "March 12 at 3pm"
    final m3 = RegExp(r'^([a-z]+)\.?\s+(\d{1,2})\s+(?:at\s+)?(.+)$')
        .firstMatch(lower);
    if (m3 != null && _months.containsKey(m3.group(1)!)) {
      final time = _parseTime(m3.group(3)!);
      if (time != null) {
        return DateTime(
          base.year,
          _months[m3.group(1)!]!,
          int.parse(m3.group(2)!),
          time.$1,
          time.$2,
        );
      }
    }

    return null;
  }

  (int, int)? _parseTime(String s) {
    final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$')
        .firstMatch(s.trim());
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = m.group(2) == null ? 0 : int.parse(m.group(2)!);
    final ap = m.group(3);
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (h > 23 || min > 59) return null;
    return (h, min);
  }

  /// "2 weeks 3 days", "90 minutes"
  Duration? parseDuration(String input) {
    final re = RegExp(
      r'(\d+(?:\.\d+)?)\s*(years?|months?|weeks?|days?|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b',
    );
    final matches = re.allMatches(input.toLowerCase());
    if (matches.isEmpty) return null;
    var total = 0.0;
    for (final m in matches) {
      final n = double.parse(m.group(1)!);
      final unit = m.group(2)!;
      total +=
          n *
          switch (unit) {
            'year' || 'years' => 365 * 86400.0,
            'month' || 'months' => 30 * 86400.0,
            'week' || 'weeks' => 7 * 86400.0,
            'day' || 'days' => 86400.0,
            'hour' || 'hours' || 'hr' || 'hrs' || 'h' => 3600.0,
            'minute' || 'minutes' || 'min' || 'mins' => 60.0,
            _ => 1.0,
          };
    }
    return Duration(milliseconds: (total * 1000).round());
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _inZone(DateTime local, String zoneName) {
    try {
      final loc = tz.getLocation(zoneName);
      final converted = tz.TZDateTime.from(local, loc);
      return DateTime(
        converted.year,
        converted.month,
        converted.day,
        converted.hour,
        converted.minute,
      );
    } catch (_) {
      return local;
    }
  }

  /// Converts a wall-clock DateTime in [fromZone] to the wall clock of [toZone].
  DateTime? convertZone(DateTime dt, String fromZone, String toZone) {
    try {
      final from = tz.getLocation(fromZone);
      final to = tz.getLocation(toZone);
      final source = tz.TZDateTime(
        from,
        dt.year,
        dt.month,
        dt.day,
        dt.hour,
        dt.minute,
      );
      final target = tz.TZDateTime.from(source.toUtc(), to);
      return DateTime(
        target.year,
        target.month,
        target.day,
        target.hour,
        target.minute,
      );
    } catch (_) {
      return null;
    }
  }

  static String? zoneFor(String token) =>
      zones[token.toLowerCase().replaceAll(RegExp(r'\s+'), '').trim()];
}
