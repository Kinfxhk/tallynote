import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Daily ECB rates via frankfurter.app (no key, CORS-friendly).
/// Falls back to the last cached copy, then to a small built-in table, so the
/// calculator always works offline.
class Rates {
  static const _key = 'tallynote.rates.v1';
  static const _dateKey = 'tallynote.rates.date.v1';

  static const fallback = <String, double>{
    'USD': 1, 'HKD': 7.80, 'EUR': 0.92, 'GBP': 0.77, 'JPY': 152,
    'CNY': 7.10, 'TWD': 32.2, 'KRW': 1380, 'SGD': 1.34, 'AUD': 1.52,
    'CAD': 1.38, 'CHF': 0.88, 'INR': 84, 'THB': 34.5, 'MYR': 4.4,
    'PHP': 58, 'VND': 25400, 'NZD': 1.66, 'SEK': 10.5, 'NOK': 10.9,
    'DKK': 6.9, 'RUB': 92, 'BRL': 5.5, 'MXN': 18, 'ZAR': 18.2,
    'AED': 3.67, 'IDR': 15800, 'TRY': 34, 'PLN': 4.0, 'ILS': 3.7,
  };

  static Map<String, double> current = fallback;
  static String? updatedDate;
  static bool fromNetwork = false;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_key);
    if (cached != null) {
      try {
        current = {
          for (final e in (jsonDecode(cached) as Map).entries)
            e.key as String: (e.value as num).toDouble(),
        };
        updatedDate = prefs.getString(_dateKey);
      } catch (_) {}
    }
    await refresh();
  }

  static Future<bool> refresh() async {
    try {
      final res = await http
          .get(Uri.parse('https://api.frankfurter.app/latest?from=USD'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rates = (body['rates'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble()));
      rates['USD'] = 1;
      current = rates;
      updatedDate = body['date'] as String?;
      fromNetwork = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(rates));
      if (updatedDate != null) await prefs.setString(_dateKey, updatedDate!);
      return true;
    } catch (_) {
      return false;
    }
  }
}
