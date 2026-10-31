import 'dart:convert';
import 'dart:io';

import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/engine/values.dart';

const _version = '0.3.9';

const _usage = '''
Tallynote — the notepad that adds up, from the command line.

Usage:
  tallynote <expression>              evaluate one line
  tallynote -f <file>                 evaluate a note, one line at a time
  echo "2+2" | tallynote              read from stdin

Options:
  -e, --eval <text>    expression to evaluate
  -f, --file <path>    note file (- for stdin)
  -j, --json           structured output, one JSON object per line
  -s, --steps          include the step breakdown
      --total          print the grand total of all lines
      --dp <n>         decimal places for plain numbers
      --strict         exit 1 if any line fails
  -h, --help           this text
      --version        version

Examples:
  tallynote "5 kg + 3 lb"
  tallynote "'\$20 in euro'"
  tallynote -f budget.txt --json --total
''';

void main(List<String> argv) {
  final args = List<String>.from(argv);
  String? file;
  String? eval;
  var json = false;
  var steps = false;
  var total = false;
  var strict = false;
  int? dp;

  List<String> positional = [];

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h' || '--help':
        stdout.writeln(_usage);
        return;
      case '--version':
        stdout.writeln('tallynote $_version');
        return;
      case '-j' || '--json':
        json = true;
      case '-s' || '--steps':
        steps = true;
      case '--total':
        total = true;
      case '--strict':
        strict = true;
      case '-e' || '--eval':
        if (i + 1 >= args.length) _die('missing value for $a');
        eval = args[++i];
      case '-f' || '--file':
        if (i + 1 >= args.length) _die('missing value for $a');
        file = args[++i];
      case '--dp':
        if (i + 1 >= args.length) _die('missing value for --dp');
        dp = int.tryParse(args[++i]);
        if (dp == null) _die('--dp needs a number');
      default:
        if (a.startsWith('-') && a != '-') _die('unknown option $a');
        positional.add(a);
    }
  }

  final engine = SheetEngine(strict: strict);

  List<String> lines;
  if (file != null) {
    if (file == '-') {
      final text = _readAll();
      lines = text.isEmpty ? <String>[] : text.trimRight().split('\n');
    } else {
      lines = File(file).readAsLinesSync();
    }
  } else if (eval != null) {
    lines = [eval];
  } else if (positional.isNotEmpty) {
    lines = [positional.join(' ')];
  } else if (!stdin.hasTerminal) {
    final text = _readAll();
    lines = text.isEmpty ? <String>[] : text.trimRight().split('\n');
  } else {
    stdout.writeln(_usage);
    exit(64);
  }

  if (total) lines.add('grand total');

  final results = engine.evaluate(lines);
  var failed = 0;
  final out = StringBuffer();

  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    if (r.error != null) failed++;

    if (json) {
      out.writeln(
        jsonEncode({
          'line': i + 1,
          'input': r.text,
          'display': r.display,
          'error': r.error,
          'value': _valueJson(r.value),
          if (steps && r.display != null && r.error == null)
            'steps': engine.explain(r.text),
        }),
      );
    } else {
      final answer = r.display ?? '';
      out.writeln(answer.isEmpty ? r.text : '${r.text}\t$answer');
      if (steps && r.display != null && r.error == null) {
        for (final s in engine.explain(r.text)) {
          out.writeln('    $s');
        }
      }
    }
  }

  stdout.write(out.toString());
  if (strict && failed > 0) exit(1);
}

String _readAll() {
  final buf = StringBuffer();
  while (true) {
    final line = stdin.readLineSync(encoding: utf8);
    if (line == null) break;
    buf.writeln(line);
  }
  return buf.toString();
}

Map<String, Object?>? _valueJson(Value? v) {
  switch (v) {
    case NumValue(:final value, :final unit):
      return {'type': 'number', 'value': value, 'unit': unit?.id};
    case MoneyValue(:final value, :final currency):
      return {'type': 'money', 'value': value, 'currency': currency};
    case PercentValue(:final ratio):
      return {'type': 'percent', 'value': ratio};
    case DateValue(:final date):
      return {'type': 'date', 'value': date.toIso8601String()};
    case BoolValue(:final value):
      return {'type': 'bool', 'value': value};
    case ListValue(:final items):
      return {'type': 'list', 'value': items.map(_valueJson).toList()};
    case _:
      return null;
  }
}

Never _die(String message) {
  stderr.writeln('tallynote: $message');
  stderr.writeln('try --help');
  exit(64);
}
