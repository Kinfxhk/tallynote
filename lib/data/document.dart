import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Folder {
  final String id;
  String name;

  Folder({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Folder.fromJson(Map<String, dynamic> j) =>
      Folder(id: j['id'] as String, name: j['name'] as String? ?? 'Folder');
}

class Sheet {
  final String id;
  String title;
  String content;
  String? folderId;
  DateTime updated;
  bool pinned;

  /// Once the user renames a sheet, the first line must stop overwriting it.
  bool customTitle;

  Sheet({
    required this.id,
    required this.title,
    required this.content,
    this.folderId,
    this.pinned = false,
    this.customTitle = false,
    DateTime? updated,
  }) : updated = updated ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'folderId': folderId,
    'pinned': pinned,
    'customTitle': customTitle,
    'updated': updated.toIso8601String(),
  };

  factory Sheet.fromJson(Map<String, dynamic> j) => Sheet(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Untitled',
    content: j['content'] as String? ?? '',
    folderId: j['folderId'] as String?,
    pinned: j['pinned'] as bool? ?? false,
    customTitle: j['customTitle'] as bool? ?? false,
    updated: DateTime.tryParse(j['updated'] as String? ?? ''),
  );
}

/// Sheets and folders live in one JSON blob in shared preferences: small,
/// portable and enough for a notepad. Swap for file IO when sheets grow past
/// a few MB.
class DocumentStore extends ChangeNotifier {
  static const _key = 'tallynote.sheets.v1';
  static const _activeKey = 'tallynote.active.v1';

  static const backupKey = 'tallynote.sheets.v1.bak';

  final List<Sheet> sheets = [];
  final List<Folder> folders = [];
  String? activeId;
  bool loaded = false;

  /// The on-disk library could not be parsed. A copy is kept under [backupKey]
  /// when that write succeeds; until then new saves are refused so a blank
  /// library cannot replace the unreadable one.
  bool libraryUnreadable = false;
  bool _protectCorrupt = false;

  /// Test hook. `SharedPreferences.setString` reports failure as `false`
  /// rather than a throw; production passes that result through.
  @visibleForTesting
  static Future<bool> Function(SharedPreferences prefs, String raw)?
  debugKeepBackup;

  Sheet? get active =>
      sheets.where((s) => s.id == activeId).firstOrNull ??
      (sheets.isEmpty ? null : sheets.first);

  /// Newest first, optionally filtered to one folder (null = unfiled).
  List<Sheet> inFolder(String? folderId) {
    final list = sheets.where((s) => s.folderId == folderId).toList()
      ..sort(_order);
    return list;
  }

  /// Pinned first, then most recently edited.
  static int _order(Sheet a, Sheet b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updated.compareTo(a.updated);
  }

  /// Case-insensitive title/content search across every folder.
  List<Sheet> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return sheets
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.content.toLowerCase().contains(q),
        )
        .toList()
      ..sort(_order);
  }

  Folder? folderOf(Sheet s) => s.folderId == null
      ? null
      : folders.where((f) => f.id == s.folderId).firstOrNull;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          // v1: a bare list of sheets, no folders
          sheets
            ..clear()
            ..addAll(
              decoded.map((e) => Sheet.fromJson(e as Map<String, dynamic>)),
            );
        } else if (decoded is Map) {
          final m = decoded as Map<String, dynamic>;
          folders
            ..clear()
            ..addAll(
              (m['folders'] as List? ?? []).map(
                (e) => Folder.fromJson(e as Map<String, dynamic>),
              ),
            );
          sheets
            ..clear()
            ..addAll(
              (m['sheets'] as List? ?? []).map(
                (e) => Sheet.fromJson(e as Map<String, dynamic>),
              ),
            );
        }
      } catch (e, st) {
        debugPrint('Tallynote: sheet library could not be read ($e)\n$st');
        libraryUnreadable = true;
        final kept = await _keepBackup(prefs, raw);
        // Only a successful backup may be followed by a fresh library.
        // Otherwise the next save would erase the only copy.
        _protectCorrupt = !kept;
      }
    }
    if (sheets.isEmpty) {
      sheets.add(Sheet(id: _newId(), title: 'Untitled', content: ''));
    }
    // drop sheets pointing at folders that no longer exist
    final ids = folders.map((f) => f.id).toSet();
    for (final s in sheets) {
      if (s.folderId != null && !ids.contains(s.folderId)) s.folderId = null;
    }
    activeId = prefs.getString(_activeKey) ?? sheets.first.id;
    if (!sheets.any((s) => s.id == activeId)) activeId = sheets.first.id;
    loaded = true;
    notifyListeners();
  }

  Future<bool> _keepBackup(SharedPreferences prefs, String raw) async {
    try {
      final hook = debugKeepBackup;
      if (hook != null) return await hook(prefs, raw);
      return await prefs.setString(backupKey, raw);
    } catch (e, st) {
      debugPrint('Tallynote: could not keep a backup of the library ($e)\n$st');
      return false;
    }
  }

  Future<void> _persist() async {
    if (_protectCorrupt) {
      debugPrint(
        'Tallynote: not saving; the on-disk library could not be read '
        'and a backup was not written.',
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'v': 2,
        'folders': folders.map((f) => f.toJson()).toList(),
        'sheets': sheets.map((s) => s.toJson()).toList(),
      }),
    );
    if (activeId != null) await prefs.setString(_activeKey, activeId!);
  }

  void select(String id) {
    activeId = id;
    notifyListeners();
    _persist();
  }

  Sheet create({String? folderId}) {
    final s = Sheet(
      id: _newId(),
      title: 'Untitled',
      content: '',
      folderId: folderId,
    );
    sheets.insert(0, s);
    activeId = s.id;
    notifyListeners();
    _persist();
    return s;
  }

  /// Save a copy: same content, new id, "(copy)" suffix.
  Sheet duplicate(String id) {
    final src = sheets.where((e) => e.id == id).firstOrNull;
    final copy = Sheet(
      id: _newId(),
      title: src == null ? 'Untitled copy' : '${src.title} (copy)',
      content: src?.content ?? '',
      folderId: src?.folderId,
      customTitle: true,
    );
    sheets.insert(0, copy);
    activeId = copy.id;
    notifyListeners();
    _persist();
    return copy;
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

  /// A user-chosen name, which stops the first line from renaming the sheet.
  void rename(String id, String title) {
    final s = sheets.where((e) => e.id == id).firstOrNull;
    final t = title.trim();
    if (s == null || t.isEmpty) return;
    s.title = t;
    s.customTitle = true;
    s.updated = DateTime.now();
    notifyListeners();
    _persist();
  }

  void togglePin(String id) {
    final s = sheets.where((e) => e.id == id).firstOrNull;
    if (s == null) return;
    s.pinned = !s.pinned;
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

  // ---- folders -------------------------------------------------------------

  Folder createFolder(String name) {
    final f = Folder(
      id: _newId(),
      name: name.trim().isEmpty ? 'Folder' : name.trim(),
    );
    folders.add(f);
    notifyListeners();
    _persist();
    return f;
  }

  void renameFolder(String id, String name) {
    final f = folders.where((e) => e.id == id).firstOrNull;
    if (f == null || name.trim().isEmpty) return;
    f.name = name.trim();
    notifyListeners();
    _persist();
  }

  /// Deleting a folder keeps its sheets: they fall back to unfiled.
  void deleteFolder(String id) {
    folders.removeWhere((f) => f.id == id);
    for (final s in sheets) {
      if (s.folderId == id) s.folderId = null;
    }
    notifyListeners();
    _persist();
  }

  void moveSheet(String sheetId, String? folderId) {
    final s = sheets.where((e) => e.id == sheetId).firstOrNull;
    if (s == null) return;
    s.folderId = folderId;
    s.updated = DateTime.now();
    notifyListeners();
    _persist();
  }

  // a counter keeps ids unique when several objects are made in one tick
  static int _seq = 0;
  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';
}
