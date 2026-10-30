import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Sheet {
  final String id;
  String title;
  String content;
  DateTime updated;

  Sheet({
    required this.id,
    required this.title,
    required this.content,
    DateTime? updated,
  }) : updated = updated ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'updated': updated.toIso8601String(),
  };

  factory Sheet.fromJson(Map<String, dynamic> j) => Sheet(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Untitled',
    content: j['content'] as String? ?? '',
    updated: DateTime.tryParse(j['updated'] as String? ?? ''),
  );
}

/// Sheets live in one JSON blob in shared preferences: small, portable and
/// enough for a notepad. Swap for file IO when sheets grow past a few MB.
class DocumentStore extends ChangeNotifier {
  static const _key = 'tallynote.sheets.v1';
  static const _activeKey = 'tallynote.active.v1';

  final List<Sheet> sheets = [];
  String? activeId;
  bool loaded = false;

  Sheet? get active =>
      sheets.where((s) => s.id == activeId).firstOrNull ??
      (sheets.isEmpty ? null : sheets.first);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        sheets
          ..clear()
          ..addAll(list.map((e) => Sheet.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // corrupt store: start clean rather than crash
      }
    }
    if (sheets.isEmpty) {
      sheets.add(Sheet(id: _newId(), title: 'Untitled', content: ''));
    }
    activeId = prefs.getString(_activeKey) ?? sheets.first.id;
    if (!sheets.any((s) => s.id == activeId)) activeId = sheets.first.id;
    loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(sheets.map((s) => s.toJson()).toList()),
    );
    if (activeId != null) await prefs.setString(_activeKey, activeId!);
  }

  void select(String id) {
    activeId = id;
    notifyListeners();
    _persist();
  }

  Sheet create() {
    final s = Sheet(id: _newId(), title: 'Untitled', content: '');
    sheets.insert(0, s);
    activeId = s.id;
    notifyListeners();
    _persist();
    return s;
  }

  void delete(String id) {
    sheets.removeWhere((s) => s.id == id);
    if (sheets.isEmpty) {
      sheets.add(Sheet(id: _newId(), title: 'Untitled', content: ''));
    }
    if (activeId == id) activeId = sheets.first.id;
    notifyListeners();
    _persist();
  }

  void update(String id, {String? title, String? content}) {
    final s = sheets.where((e) => e.id == id).firstOrNull;
    if (s == null) return;
    if (title != null) s.title = title;
    if (content != null) s.content = content;
    s.updated = DateTime.now();
    notifyListeners();
    _persist();
  }

  static String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
