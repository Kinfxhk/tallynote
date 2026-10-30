import 'lexer.dart';
import 'units.dart';

sealed class Node {
  const Node();
}

class NumberNode extends Node {
  final double value;
  final Unit? unit;
  const NumberNode(this.value, [this.unit]);
}

class MoneyNode extends Node {
  final double value;
  final String currency;
  const MoneyNode(this.value, this.currency);
}

class VarNode extends Node {
  final String name;
  const VarNode(this.name);
}

class PercentNode extends Node {
  final Node operand;
  const PercentNode(this.operand);
}

class BinNode extends Node {
  final String op;
  final Node left;
  final Node right;
  const BinNode(this.op, this.left, this.right);
}

class UnaryNode extends Node {
  final String op;
  final Node operand;
  const UnaryNode(this.op, this.operand);
}

class CallNode extends Node {
  final String name;
  final List<Node> args;
  const CallNode(this.name, this.args);
}

class ConvertNode extends Node {
  final Node value;
  final Unit unit;
  const ConvertNode(this.value, this.unit);
}

class PercentOfNode extends Node {
  final Node percent;
  final Node of;
  const PercentOfNode(this.percent, this.of);
}

class ParseError implements Exception {
  final String message;
  ParseError(this.message);
  @override
  String toString() => message;
}

const _funcNames = {
  'sqrt', 'cbrt', 'abs', 'log', 'ln', 'exp', 'sin', 'cos', 'tan',
  'asin', 'acos', 'atan', 'arcsin', 'arccos', 'arctan', 'round', 'ceil',
  'floor', 'fact', 'min', 'max', 'pow', 'random', 'root',
};

class Parser {
  final List<Token> tokens;
  final UnitRegistry units;
  int _p = 0;

  Parser(String source, this.units) : tokens = Lexer(source).tokenize();

  bool get atEnd => _p >= tokens.length;

  Token? get cur => atEnd ? null : tokens[_p];

  Node parse({bool lenient = true}) {
    if (atEnd) throw ParseError('empty');
    final node = _additive();
    if (!atEnd) {
      // trailing words ("10% tax", "3 apples each") are not an error: the
      // answer we have is still the one the user meant.
      final rest = tokens.skip(_p);
      final ignorable = rest.every((t) =>
          t.type == TokType.word ||
          t.type == TokType.tag ||
          t.type == TokType.comma);
      if (!lenient || !ignorable) {
        throw ParseError('unexpected "${cur!.text}"');
      }
    }
    return node;
  }

  // ---- helpers -------------------------------------------------------------

  bool _isOp(String s) {
    final c = cur;
    return c != null && c.type == TokType.op && c.text == s;
  }

  bool _matchOp(String s) {
    if (_isOp(s)) {
      _p++;
      return true;
    }
    return false;
  }

  bool _isWordToken(String s) {
    final c = cur;
    return c != null && c.type == TokType.word && c.text.toLowerCase() == s;
  }

  bool _matchRparen() {
    if (cur?.type == TokType.rparen) {
      _p++;
      return true;
    }
    return false;
  }

  /// Matches a sequence of consecutive words, e.g. "multiplied by".
  bool _matchWords(List<String> words) {
    final save = _p;
    for (final w in words) {
      final c = cur;
      if (c == null || c.type != TokType.word || c.text.toLowerCase() != w) {
        _p = save;
        return false;
      }
      _p++;
    }
    return true;
  }

  // ---- grammar -------------------------------------------------------------

  Node _additive() {
    var left = _multiplicative();
    while (true) {
      if (_matchOp('+') || _matchWords(['plus']) || _matchWords(['and'])) {
        left = BinNode('+', left, _multiplicative());
      } else if (_matchOp('-') || _matchWords(['minus'])) {
        left = BinNode('-', left, _multiplicative());
      } else {
        break;
      }
    }
    return left;
  }

  Node _multiplicative() {
    var left = _unary();
    while (true) {
      if (_matchOp('*') || _matchOp('×') || _matchWords(['times'])) {
        left = BinNode('*', left, _unary());
      } else if (_isWordToken('x')) {
        // "x" is how people type × on a keyboard
        _p++;
        left = BinNode('*', left, _unary());
      } else if (_matchWords(['multiplied', 'by'])) {
        left = BinNode('*', left, _unary());
      } else if (_matchOp('/') || _matchOp('÷') ||
          _matchWords(['divided', 'by']) || _matchWords(['over']) ||
          _matchWords(['into']) || _matchWords(['per'])) {
        left = BinNode('/', left, _unary());
      } else if (cur?.type == TokType.lparen) {
        left = BinNode('*', left, _unary()); // implicit: 2(3+4)
      } else {
        break;
      }
    }
    return left;
  }

  Node _unary() {
    if (_matchOp('-')) return UnaryNode('-', _unary());
    if (_matchOp('+')) return _unary();
    return _power();
  }

  Node _power() {
    final base = _postfix();
    if (_matchOp('^')) return BinNode('^', base, _unary());
    return base;
  }

  Node _postfix() {
    var node = _primary();
    while (true) {
      final c = cur;
      if (c == null) break;
      if (c.type == TokType.word) {
        final w = c.text.toLowerCase();
        // conversion: "in" / "to" / "as" followed by a unit
        if (w == 'in' || w == 'to' || w == 'as' || w == 'into') {
          final save = _p;
          _p++;
          final target = _readUnit();
          if (target != null) {
            node = ConvertNode(node, target);
            continue;
          }
          _p = save;
          break;
        }
        if (w == 'of' && node is PercentNode) {
          _p++;
          node = PercentOfNode(node.operand, _unary());
          continue;
        }
      }
      break;
    }
    return node;
  }

  Unit? _readUnit({bool allowDynamic = false}) {
    final c = cur;
    if (c == null || c.type != TokType.word) return null;
    final u = units.lookup(c.text);
    if (u != null) {
      _p++;
      return u;
    }
    final code = _moneyFromWord(c.text.toLowerCase());
    if (code != null) {
      _p++;
      return Unit(code, const {'currency': 1}, 1);
    }
    if (allowDynamic && !_reserved.contains(c.text.toLowerCase())) {
      _p++;
      return Unit(c.text, {c.text.toLowerCase(): 1}, 1);
    }
    return null;
  }

  static const _reserved = {
    'in', 'to', 'as', 'of', 'off', 'per', 'plus', 'minus', 'times', 'x',
    'multiplied', 'divided', 'over', 'into', 'and', 'if', 'then', 'else',
    'is', 'what', 'between', 'tax', 'total', 'sum', 'average', 'prev',
    'line', 'at', 'from', 'now', 'today', 'tomorrow', 'yesterday',
  };

  Node _primary() {
    final c = cur;
    if (c == null) throw ParseError('unexpected end of line');

    if (c.type == TokType.lparen) {
      _p++;
      final inner = _additive();
      if (!_matchRparen()) throw ParseError('missing )');
      return _percentSuffix(inner);
    }

    if (c.type == TokType.currency) {
      _p++;
      String? code;
      if (c.text == r'$') {
        code = 'USD';
      } else {
        code = const {
          '€': 'EUR', '£': 'GBP', '¥': 'JPY', '₩': 'KRW',
          '₹': 'INR', '฿': 'THB', r'HK$': 'HKD', r'US$': 'USD',
          r'NT$': 'TWD', r'S$': 'SGD', r'A$': 'AUD', r'C$': 'CAD',
        }[c.text];
      }
      // HK$ / S$ / NT$ style: the word before was consumed? handled in lexer
      final numTok = cur;
      if (numTok == null || numTok.type != TokType.number) {
        throw ParseError('expected amount after ${c.text}');
      }
      _p++;
      return MoneyNode(_currencyScale(numTok.num!, code), code ?? 'USD');
    }

    if (c.type == TokType.number) {
      _p++;
      var value = c.num!;
      // currency word before number: "USD 100"
      var unit = _readUnit(allowDynamic: true);
      if (unit == null) {
        final next = cur;
        if (next != null && next.type == TokType.word) {
          final w = next.text.toLowerCase();
          final money = _moneyFromWord(w);
          if (money != null) {
            _p++;
            value = _currencyScale(value, money);
            return MoneyNode(value, money);
          }
        }
      }
      return _percentSuffix(NumberNode(value, unit));
    }

    if (c.type == TokType.word) {
      final w = c.text;
      final lower = w.toLowerCase();

      // currency code as a prefix: "USD 100"
      if (lower.length == 3 && _isCurrencyCode(lower)) {
        final next = tokens.length > _p + 1 ? tokens[_p + 1] : null;
        if (next != null && next.type == TokType.number) {
          _p++;
          _p++;
          return MoneyNode(_currencyScale(next.num!, lower.toUpperCase()),
              lower.toUpperCase());
        }
      }

      if (_funcNames.contains(lower) || _looksLikeCall(w)) {
        return _call();
      }

      final u = units.lookup(w);
      if (u != null) {
        _p++;
        return NumberNode(1, u);
      }

      if (lower == 'of' && _p > 0) {
        // stray "of" without a preceding percent is a parse error
        throw ParseError('unexpected "of"');
      }

      _p++;
      return VarNode(w);
    }

    throw ParseError('unexpected "${c.text}"');
  }

  Node _percentSuffix(Node node) {
    if (_isOp('%')) {
      _p++;
      return PercentNode(node);
    }
    return node;
  }

  bool _looksLikeCall(String w) {
    if (_p + 1 >= tokens.length) return false;
    return tokens[_p + 1].type == TokType.lparen;
  }

  Node _call() {
    final name = tokens[_p++].text.toLowerCase();
    final args = <Node>[];
    if (_matchOp('(')) {
      if (!_matchRparen()) {
        args.add(_additive());
        while (_matchOp(',') || _matchOp(';')) {
          args.add(_additive());
        }
        if (!_matchRparen()) throw ParseError('missing ) in $name()');
      }
    } else {
      // prefix functions: "sqrt 16"
      args.add(_unary());
    }
    return CallNode(name, args);
  }

  bool _isCurrencyCode(String s) =>
      const {'usd', 'hkd', 'cny', 'jpy', 'eur', 'gbp', 'krw', 'twd', 'sgd',
        'aud', 'cad', 'chf', 'inr', 'thb', 'myr', 'php', 'vnd', 'nzd', 'sek',
        'nok', 'dkk', 'rub', 'brl', 'mxn', 'zar', 'aed', 'idr', 'try', 'pln',
        'ils'}.contains(s);

  String? _moneyFromWord(String w) {
    if (_isCurrencyCode(w)) return w.toUpperCase();
    const aliases = {
      'dollar': 'USD', 'dollars': 'USD', 'usd': 'USD', 'euro': 'EUR',
      'euros': 'EUR', 'pound': 'GBP', 'pounds': 'GBP', 'yen': 'JPY',
      'won': 'KRW', 'yuan': 'CNY', 'rmb': 'CNY', '元': 'CNY', '港元': 'HKD',
      '港幣': 'HKD', '蚊': 'HKD', '美元': 'USD', '歐元': 'EUR', '日圓': 'JPY',
    };
    return aliases[w];
  }

  double _currencyScale(double v, String? code) => v;

  // ---- entry points used by the engine -------------------------------------

  /// Parses just an expression from a substring range.
  static Node parseExpression(String src, UnitRegistry units) {
    return Parser(src, units).parse();
  }
}
