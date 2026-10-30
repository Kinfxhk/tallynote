import 'package:flutter/material.dart';

/// Lightweight inline formatting.
///
/// Markers live in the plain text, so a sheet stays a text file and the
/// engine can still read the line after [stripMarkers]. No selection model,
/// no rich-text document: just markers rendered by the text controller.
///
///   **bold**   _italic_   ~~strike~~   __underline__   {red}coloured{/}
class Fmt {
  static const colours = <String, Color>{
    'red': Color(0xFFA8442B),
    'orange': Color(0xFFC2703A),
    'green': Color(0xFF4F7A45),
    'blue': Color(0xFF3C6E9E),
    'grey': Color(0xFF8A8578),
  };

  static const Map<String, String> _openToClose = {
    '**': '**',
    '__': '__',
    '~~': '~~',
    '_': '_',
  };

  /// Removes every marker so the engine sees plain arithmetic.
  static String stripMarkers(String s) {
    var out = s;
    for (final m in ['**', '__', '~~']) {
      out = out.replaceAll(m, '');
    }
    out = out.replaceAll('{/}', '');
    out = out.replaceAllMapped(
      RegExp(r'\{(' + colours.keys.join('|') + r')\}'),
      (_) => '',
    );
    // single underscores only when they wrap something, so identifiers like
    // my_var survive
    out = out.replaceAllMapped(
      RegExp(r'(^|\s)_([^_]+)_(?=\s|$)'),
      (m) => '${m[1]}${m[2]}',
    );
    return out;
  }

  /// Turns one line into styled spans. Unmatched markers are shown as text.
  static List<TextSpan> spans(
    String text,
    TextStyle base, {
    bool cursor = false,
  }) {
    final spans = <TextSpan>[];
    var style = base;
    final buf = StringBuffer();
    var i = 0;

    void flush() {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString(), style: style));
        buf.clear();
      }
    }

    while (i < text.length) {
      // colour open: {red}
      final colour = RegExp(r'^\{(' + colours.keys.join('|') + r')\}')
          .firstMatch(text.substring(i));
      if (colour != null) {
        flush();
        style = style.copyWith(color: colours[colour[1]]);
        i += colour[0]!.length;
        continue;
      }
      if (text.startsWith('{/}', i)) {
        flush();
        style = base;
        i += 3;
        continue;
      }
      var matched = false;
      for (final entry in _openToClose.entries) {
        final open = entry.key;
        if (text.startsWith(open, i)) {
          final close = text.indexOf(entry.value, i + open.length);
          if (close > i) {
            flush();
            final inner = text.substring(i + open.length, close);
            spans.add(TextSpan(text: inner, style: _apply(style, open)));
            i = close + entry.value.length;
            matched = true;
            break;
          }
        }
      }
      if (matched) continue;
      buf.write(text[i]);
      i++;
    }
    flush();
    if (spans.isEmpty) spans.add(TextSpan(text: text, style: base));
    return spans;
  }

  static TextStyle _apply(TextStyle base, String marker) {
    switch (marker) {
      case '**':
        return base.copyWith(fontWeight: FontWeight.w700);
      case '__':
        return base.copyWith(decoration: TextDecoration.underline);
      case '~~':
        return base.copyWith(decoration: TextDecoration.lineThrough);
      case '_':
        return base.copyWith(fontStyle: FontStyle.italic);
      default:
        return base;
    }
  }

  /// Wraps [selection] in the given marker pair; returns the new text and
  /// where the caret should land.
  static (String, TextSelection) wrap(
    String text,
    TextSelection sel,
    String open,
    String close,
  ) {
    if (!sel.isValid || sel.isCollapsed) return (text, sel);
    final before = text.substring(0, sel.start);
    final middle = text.substring(sel.start, sel.end);
    final after = text.substring(sel.end);
    final newText = '$before$open$middle$close$after';
    return (
      newText,
      TextSelection(
        baseOffset: sel.start + open.length,
        extentOffset: sel.start + open.length + middle.length,
      ),
    );
  }

  /// Paints `line 3` and line names ("lucid", "午餐") as chips: a tinted
  /// background plus the answer colour, so a reference never reads as prose.
  static List<InlineSpan> withReferences(
    List<TextSpan> spans,
    TextStyle base, {
    required Set<String> labels,
    required bool dark,
  }) {
    if (labels.isEmpty) return spans;
    final pattern = RegExp(
      r'line\s+\d+|[A-Za-z_][A-Za-z0-9_]*|[\u4e00-\u9fff]+',
    );
    final out = <InlineSpan>[];

    for (final span in spans) {
      final text = span.text;
      if (text == null || text.isEmpty) {
        out.add(span);
        continue;
      }
      var last = 0;
      for (final m in pattern.allMatches(text)) {
        final word = m.group(0)!;
        final isRef =
            word.startsWith('line ') || labels.contains(word.toLowerCase());
        if (!isRef) continue;
        if (m.start > last) {
          out.add(
            TextSpan(text: text.substring(last, m.start), style: span.style),
          );
        }
        final tint = dark ? const Color(0xFFE8B75A) : const Color(0xFFA8442B);
        out.add(
          TextSpan(
            text: word,
            style: (span.style ?? base).copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
              backgroundColor: tint.withValues(alpha: 0.14),
            ),
          ),
        );
        last = m.end;
      }
      if (last < text.length) {
        out.add(TextSpan(text: text.substring(last), style: span.style));
      }
    }
    return out;
  }

  /// Every line that starts with `//` is a draft: nothing is calculated.
  static bool isDraft(String line) => line.trimLeft().startsWith('//');
}
