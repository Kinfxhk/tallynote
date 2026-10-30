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
  static const _backupKey = 'tallynote.sheets.v1.bak';
  static const _activeKey = 'tallynote.active.v1';

  final List<Sheet> sheets = [];
  final List<Folder> folders = [];
  String? activeId;
  bool loaded = false;

  /// The stored blob could not be read and a copy of it is in [_backupKey]:
  /// nothing may write over the original until the user acts.
  bool _keepBackup = false;

  /// The last write did not land (quota exceeded, private mode). The status
  /// bar must not claim "Saved" while this is true: a silent save failure is
  /// how a notepad loses a day's work.
  bool saveFailed = false;

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
      // decode into locals first: a half-read document must not replace a
      // whole one, or the next save keeps only the first few sheets
      final nextFolders = <Folder>[];
      final nextSheets = <Sheet>[];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          // v1: a bare list of sheets, no folders
          nextSheets.addAll(
            decoded.map((e) => Sheet.fromJson(e as Map<String, dynamic>)),
          );
        } else if (decoded is Map) {
          final m = decoded as Map<String, dynamic>;
          nextFolders.addAll(
            (m['folders'] as List? ?? []).map(
              (e) => Folder.fromJson(e as Map<String, dynamic>),
            ),
          );
          nextSheets.addAll(
            (m['sheets'] as List? ?? []).map(
              (e) => Sheet.fromJson(e as Map<String, dynamic>),
            ),
          );
        } else {
          throw const FormatException('the store is not a document');
        }
        folders
          ..clear()
          ..addAll(nextFolders);
        sheets
          ..clear()
          ..addAll(nextSheets);
      } catch (e) {
        // keep the damaged blob: it may be the only copy of the user's text
        _keepBackup = await prefs.setString(_backupKey, raw);
        debugPrint('tallynote: unreadable store, kept in $_backupKey: $e');
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

  Future<void> _persist() async {
    // the backup is all that is left of the damaged store: do not bury it
    if (_keepBackup) return;
    final prefs = await SharedPreferences.getInstance();
    var ok = false;
    try {
      ok = await prefs.setString(
        _key,
        jsonEncode({
          'v': 2,
          'folders': folders.map((f) => f.toJson()).toList(),
          'sheets': sheets.map((s) => s.toJson()).toList(),
        }),
      );
    } catch (e) {
      // a full quota or a private window can throw instead of returning false
      debugPrint('tallynote: save failed: $e');
    }
    if (!ok && !saveFailed) {
      saveFailed = true;
      notifyListeners();
    } else if (ok && saveFailed) {
      saveFailed = false;
      notifyListeners();
    }
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

  /// Brings sheets in from a file. Ids are always regenerated, so importing
  /// the same file twice cannot overwrite anything.
  int importSheets(List<Sheet> incoming, List<Folder> incomingFolders) {
    final folderMap = <String, String>{};
    for (final f in incomingFolders) {
      final created = createFolder(f.name);
      folderMap[f.id] = created.id;
    }
    for (final s in incoming) {
      sheets.insert(
        0,
        Sheet(
          id: _newId(),
          title: s.title,
          content: s.content,
          folderId: s.folderId == null ? null : folderMap[s.folderId],
          pinned: s.pinned,
          customTitle: true,
        ),
      );
    }
    if (sheets.isNotEmpty) activeId = sheets.first.id;
    notifyListeners();
    _persist();
    return incoming.length;
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
