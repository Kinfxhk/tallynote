enum TokType { number, word, op, lparen, rparen, comma, currency, tag }

class Token {
  final TokType type;
  final String text;
  final double? num;
  final int pos;

  const Token(this.type, this.text, this.pos, [this.num]);

  @override
  String toString() => '${type.name}($text)';
}

/// Folds fullwidth digits and operator glyphs to ASCII so a line typed with
/// a Chinese IME parses the same way as one typed on a US keyboard.
///
/// Ideographic `。` becomes a decimal point only when it sits between digits
/// (`3。14`). The minus signs people paste (`−`, `–`, `—`, `－`) fold too,
/// which is what the lexer already did one token at a time. `×` and `÷`
/// stay as themselves; the parser accepts both.
String normalizeMathSource(String src) {
  if (src.isEmpty) return src;
  final codes = src.runes.toList(growable: false);
  final out = StringBuffer();
  for (var i = 0; i < codes.length; i++) {
    final code = codes[i];
    final prevDigit = i > 0 && _isFoldDigit(codes[i - 1]);
    final nextDigit = i + 1 < codes.length && _isFoldDigit(codes[i + 1]);
    out.write(_foldRune(code, prevDigit: prevDigit, nextDigit: nextDigit));
  }
  return out.toString();
}

bool _isFoldDigit(int code) =>
    (code >= 0x30 && code <= 0x39) || (code >= 0xFF10 && code <= 0xFF19);

String _foldRune(int code, {required bool prevDigit, required bool nextDigit}) {
  if (code >= 0xFF10 && code <= 0xFF19) {
    return String.fromCharCode(0x30 + (code - 0xFF10));
  }
  // Fullwidth Latin. Keeps the case split so `ｘ` is multiply and `Ｘ` is not.
  if (code >= 0xFF21 && code <= 0xFF3A) {
    return String.fromCharCode(0x41 + (code - 0xFF21));
  }
  if (code >= 0xFF41 && code <= 0xFF5A) {
    return String.fromCharCode(0x61 + (code - 0xFF41));
  }
  const mapped = <int, String>{
    0xFF0B: '+', // ＋
    0xFF0D: '-', // －
    0x2212: '-', // −
    0x2013: '-', // –
    0x2014: '-', // —
    0xFE63: '-', // ﹣
    0xFF0A: '*', // ＊
    0xFF0F: '/', // ／
    0xFF05: '%', // ％
    0xFE6A: '%', // ﹪
    0xFF08: '(', // （
    0xFF09: ')', // ）
    0xFF0C: ',', // ，
    0xFF0E: '.', // ．
    0xFF04: r'$', // ＄
    0xFFE5: '¥', // ￥
    0xFFE1: '£', // ￡
    0xFF1D: '=', // ＝
    0xFF1A: ':', // ：
    0xFF1B: ';', // ；
  };
  final hit = mapped[code];
  if (hit != null) return hit;
  // `3。14` — the ideographic full stop used as a decimal point.
  if (code == 0x3002 && prevDigit && nextDigit) return '.';
  return String.fromCharCode(code);
}

class Lexer {
  final String src;
  int _i = 0;
  final List<Token> out = [];

  Lexer(String source) : src = normalizeMathSource(source);

  List<Token> tokenize() {
    while (_i < src.length) {
      final c = src[_i];
      if (c.trim().isEmpty) {
        _i++;
        continue;
      }
      if (_isDigit(c) ||
          (c == '.' && _i + 1 < src.length && _isDigit(src[_i + 1]))) {
        _number();
        continue;
      }
      if (_isLetter(c) || c == '°') {
        _word();
        continue;
      }
      if (c == r'$' || '€£¥₩₹฿'.contains(c)) {
        out.add(Token(TokType.currency, c, _i));
        _i++;
        if (c == r'$' && _i + 1 < src.length && _isDigit(src[_i + 1])) {
          // "$20" handled by the parser as currency + number
        }
        continue;
      }
      if (c == '#') {
        _i++;
        final start = _i;
        while (_i < src.length &&
            (_isLetter(src[_i]) || _isDigit(src[_i]) || src[_i] == '_')) {
          _i++;
        }
        if (_i > start) {
          out.add(Token(TokType.tag, src.substring(start, _i), start));
        }
        continue;
      }
      if (c == '(') {
        out.add(Token(TokType.lparen, '(', _i++));
        continue;
      }
      if (c == ')') {
        out.add(Token(TokType.rparen, ')', _i++));
        continue;
      }
      if (c == ',') {
        out.add(Token(TokType.comma, ',', _i++));
        continue;
      }
      // people paste − (U+2212), – and － from other apps
      const dashVariants = {'−', '–', '—', '－'};
      const plusVariants = {'＋'};
      if (dashVariants.contains(c)) {
        out.add(Token(TokType.op, '-', _i++));
        continue;
      }
      if (plusVariants.contains(c)) {
        out.add(Token(TokType.op, '+', _i++));
        continue;
      }
      out.add(Token(TokType.op, c, _i++));
    }
    return out;
  }

  void _number() {
    final start = _i;
    var sawDot = false;
    while (_i < src.length) {
      final c = src[_i];
      if (_isDigit(c)) {
        _i++;
      } else if (c == ',' && _i + 3 <= src.length && _digitsAhead(3)) {
        _i++; // thousands separator
      } else if (c == '.' &&
          !sawDot &&
          _i + 1 < src.length &&
          _isDigit(src[_i + 1])) {
        sawDot = true;
        _i++;
      } else {
        break;
      }
    }
    var value = double.parse(src.substring(start, _i).replaceAll(',', ''));
    // 5k / 1.5k shorthand; "5m" stays metres, "5b" stays bits
    if (_i < src.length && (src[_i] == 'k' || src[_i] == 'K')) {
      final next = _i + 1 < src.length ? src[_i + 1] : ' ';
      if (!_isLetter(next)) {
        value *= 1000;
        _i++;
      }
    }
    out.add(Token(TokType.number, src.substring(start, _i), start, value));
  }

  bool _digitsAhead(int n) {
    if (_i + n >= src.length) return false;
    for (var k = 1; k <= n; k++) {
      if (!_isDigit(src[_i + k])) return false;
    }
    return true;
  }

  static const _funcNames = {
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'arcsin',
    'arccos',
    'arctan',
    'sqrt',
    'cbrt',
    'abs',
    'log',
    'ln',
    'exp',
    'round',
    'ceil',
    'floor',
    'fact',
    'min',
    'max',
    'pow',
    'root',
    'random',
  };

  void _word() {
    final start = _i;
    // "sin30" / "sqrt16": function name glued to its argument
    var j = _i;
    while (j < src.length && _isLetter(src[j]) && !_isCjk(src[j])) {
      j++;
    }
    if (j > _i &&
        j < src.length &&
        _isDigit(src[j]) &&
        _funcNames.contains(src.substring(_i, j).toLowerCase())) {
      final name = src.substring(_i, j);
      _i = j;
      out.add(Token(TokType.word, name, start));
      return;
    }
    // "3x30": the times sign is its own token, the digits after it a number
    if (src[_i] == 'x' && _i + 1 < src.length && _isDigit(src[_i + 1])) {
      _i++;
      out.add(Token(TokType.word, 'x', start));
      return;
    }
    final cjkStart = _isCjk(src[_i]);
    while (_i < src.length) {
      final c = src[_i];
      // "30乘3": 乘 is a word, the 3 after it is a number
      if (cjkStart && _isDigit(c)) break;
      if (_isLetter(c) ||
          _isDigit(c) ||
          c == '_' ||
          c == '°' ||
          c == '/' ||
          c == '%') {
        // stop '/' inside a word only when it starts a unit ratio like MB/s
        if (c == '/' && !(_i + 1 < src.length && _isLetter(src[_i + 1]))) break;
        _i++;
      } else if (c == '\u4e00' || _isCjk(c)) {
        _i++;
      } else {
        break;
      }
    }
    final word = src.substring(start, _i);
    // HK$ / US$ / NT$ / S$ prefixes
    if (_i < src.length &&
        src[_i] == r'$' &&
        word.length <= 3 &&
        word.toUpperCase() == word) {
      _i++;
      out.add(Token(TokType.currency, '$word\$', start));
      return;
    }
    out.add(Token(TokType.word, word, start));
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static bool _isLetter(String c) {
    final code = c.codeUnitAt(0);
    if (code < 128) {
      return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }
    return _isCjk(c) || c == '°';
  }

  static bool _isCjk(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3040 && code <= 0x30FF);
  }
}
