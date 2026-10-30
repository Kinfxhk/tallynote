import 'dart:convert';

import '../data/document.dart';
import '../engine/engine.dart';

/// Everything that turns the in-app library into a portable artefact, and back.
/// Pure functions only: no plugins, no dialogs, so it is all testable.
class DocumentIo {
  static const fileExtension = 'tallynote';
  static const appTag = 'tallynote';

  /// Whole library as a `.tallynote` document.
  static String libraryJson(
    List<Sheet> sheets,
    List<Folder> folders, {
    DateTime? now,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'app': appTag,
      'v': 2,
      'exported': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'folders': folders.map((f) => f.toJson()).toList(),
      'sheets': sheets.map((s) => s.toJson()).toList(),
    });
  }

  /// One sheet, still a valid document so it can be opened on its own.
  static String sheetJson(Sheet sheet, {DateTime? now}) =>
      libraryJson([sheet], const [], now: now);

  /// Tolerant import: accepts our export, the internal store blob, or the old
  /// bare list. Unknown ids are fine; the caller assigns fresh ones.
  static ImportResult parse(String raw) {
    final decoded = jsonDecode(raw);
    final folders = <Folder>[];
    final sheets = <Sheet>[];

    if (decoded is Map) {
      for (final f in (decoded['folders'] as List? ?? const [])) {
        folders.add(Folder.fromJson(f as Map<String, dynamic>));
      }
      for (final s in (decoded['sheets'] as List? ?? const [])) {
        sheets.add(Sheet.fromJson(s as Map<String, dynamic>));
      }
    } else if (decoded is List) {
      for (final s in decoded) {
        sheets.add(Sheet.fromJson(s as Map<String, dynamic>));
      }
    } else {
      throw const FormatException('not a Tallynote document');
    }
    if (sheets.isEmpty) {
      throw const FormatException('no sheets in this file');
    }
    return ImportResult(sheets, folders);
  }

  /// Markdown: one section per sheet. Lines that produced an answer become a
  /// two-column line so the result survives outside the app.
  static String markdown(List<Sheet> sheets, SheetEngine engine) {
    final out = StringBuffer();
    for (final sheet in sheets) {
      out.writeln('# ${sheet.title.isEmpty ? 'Untitled' : sheet.title}');
      out.writeln();
      final lines = sheet.content.split('\n');
      final results = engine.evaluate(lines);
      for (var i = 0; i < lines.length; i++) {
        final answer = results[i].display;
        if (answer == null) {
          out.writeln(lines[i]);
        } else {
          out.writeln('${lines[i]}  →  $answer');
        }
      }
      out.writeln();
    }
    return '${out.toString().trimRight()}\n';
  }

  /// CSV with one row per line that has an answer; quoting is RFC 4180.
  static String csv(List<Sheet> sheets, SheetEngine engine) {
    final rows = <List<String>>[
      ['sheet', 'line', 'input', 'answer', 'error'],
    ];
    for (final sheet in sheets) {
      final lines = sheet.content.split('\n');
      final results = engine.evaluate(lines);
      for (var i = 0; i < lines.length; i++) {
        final r = results[i];
        if (r.display == null && r.error == null) continue;
        rows.add([
          sheet.title.isEmpty ? 'Untitled' : sheet.title,
          '${i + 1}',
          lines[i],
          r.display ?? '',
          r.error ?? '',
        ]);
      }
    }
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    return "${rows.map((r) => r.map(q).join(',')).join('\n')}\n";
  }

  /// Plain text, for printing and for "just give me the note".
  static String plainText(List<Sheet> sheets, SheetEngine engine) {
    final out = StringBuffer();
    for (final sheet in sheets) {
      out.writeln(sheet.title.isEmpty ? 'Untitled' : sheet.title);
      out.writeln('-' * 40);
      final lines = sheet.content.split('\n');
      final results = engine.evaluate(lines);
      for (var i = 0; i < lines.length; i++) {
        final a = results[i].display;
        out.writeln(a == null ? lines[i] : '${lines[i]}    $a');
      }
      out.writeln();
    }
    return '${out.toString().trimRight()}\n';
  }

  /// A filename that sorts by date and cannot collide.
  static String fileName(String base, DateTime at, String ext) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${at.year}-${two(at.month)}-${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}';
    final safe = base
        .replaceAll(RegExp(r'[^A-Za-z0-9\u4e00-\u9fff _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return '${safe.isEmpty ? appTag : safe}-$stamp.$ext';
  }
}

class ImportResult {
  final List<Sheet> sheets;
  final List<Folder> folders;
  const ImportResult(this.sheets, this.folders);
}
