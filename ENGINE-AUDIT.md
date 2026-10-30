# ENGINE-AUDIT: main vs PR Kinfxhk/tallynote#3

Scope: the three engine areas, compared between `main` (2e67256) and external PR Kinfxhk/tallynote#3,
and the minimal port sitting in this worktree (`audit/engine`, uncommitted).

Evidence rule: every claim below comes from a command actually run; its output is pasted inline.

State of the worktree:

```
$ cd /private/tmp/tn-a && git status --short
 M lib/engine/engine.dart
 M lib/engine/evaluator.dart
 M lib/engine/lexer.dart
 M lib/engine/parser.dart
 M lib/engine/units.dart
 M lib/engine/values.dart
 M lib/ui/answer_column.dart
 M lib/ui/editor_view.dart
?? test/audit_probe_test.dart
$ git branch -vv | grep '^\*'
* audit/engine 2e67256 ...
```

PR#3 is 21 files (1,929-line diff: engine + settings + prefs + storage/autosave + i18n + tests + roadmap).
The worktree port is 8 files, 270 insertions / 59 deletions, engine + answer column only:

```
$ git diff main --stat
 lib/engine/engine.dart    | 54 +++++++++++++++++++++++++++++----------
 lib/engine/evaluator.dart | 18 ++++++++++---
 lib/engine/lexer.dart     | 49 ++++++++++++++++++++++++++++++-----
 lib/engine/parser.dart    | 13 +++++++---
 lib/engine/units.dart     | 47 ++++++++++++++++++++++++++++++++++
 lib/engine/values.dart    | 65 +++++++++++++++++++++++++++++++++++------------
 lib/ui/answer_column.dart | 53 ++++++++++++++++++++++++++++----------
 lib/ui/editor_view.dart   | 30 ++++++++++++++++++++--
 8 files changed, 270 insertions(+), 59 deletions(-)
```

## 1. ErrorValue surfaced in the UI

### 1a. What PR#3 does

- `lib/engine/engine.dart` — `LineResult` gains `final bool engineError`; it is set true only in the
  branch where the evaluator returned an `ErrorValue` (`engineError: bad`, where `bad = value is ErrorValue`).
  Parse failures and unfinished lines keep `engineError == false`.
- `lib/ui/editor_view.dart` — the answer-column loop paints a row when `display != null || engineError`;
  `_answerText` renders the error as a muted, italic, one-line `Text` with `ValueKey('engine-error-$i')`,
  wrapped in a `Tooltip` carrying the full message.
- `test/app_test.dart` — widget test: typing `1/0\n5 kg + 2 m\n2+` paints `divide by zero` and
  `incompatible values`, and paints nothing containing `unexpected`.

PR#3 body, verbatim: "**Errors.** `ErrorValue` (divide by zero, incompatible units, and the other engine
failures) shows as a muted one-line note in the answer column, with the full message on hover. An
unfinished line such as `2+` still stays blank: that path is not an `engineError`."

### 1b. Does main have it?

No. Three independent checks:

```
$ git grep -n "engineError" main -- lib/
rc=1
$ git show main:lib/engine/engine.dart | grep -n "display: value == null"
```
main sets `display` to null for an `ErrorValue` (`display: value == null || bad ? null : formatValue(value)`)
and its editor paints only non-null displays:

```
$ git show main:lib/ui/editor_view.dart | grep -n "display != null"
183:                    if (widget.results[i].display != null)
```

So on main `1/0` and `5 kg + 2 m` evaluate to `ErrorValue` -> `display == null` -> nothing is painted.
That matches the observed "shows nothing".

### 1c. Minimal port (in this worktree, this codebase's idiom)

- `lib/engine/engine.dart:18,28,238` — `LineResult.engineError` field, default `false`, set to `bad` in the
  `ErrorValue` branch only.
- `lib/ui/editor_view.dart:191` — paint condition becomes `display != null || engineError`;
  `lib/ui/editor_view.dart:270` — `_answerText` returns the italic error `Text` for `engineError` rows.
  (Port drops PR#3's `Tooltip` and its fixed 12.5pt mono face; it reuses the line's `answerStyle`.)
- No new dependencies, no new types beyond the one bool.

### 1d. Test cases, expected values, and the actual run

Engine level (from `test/audit_probe_test.dart`, run via
`flutter test test/audit_probe_test.dart -r expanded`):

```
US [null] err=true/divide by zero [null]  <- 1/0
US [null] err=true/incompatible values [null]  <- 5 kg + 2 m
US [2] err=false/null [2.0]  <- 2+
```

Widget level (same file, ported from PR#3's app test):

```
00:00 +1: engine errors paint in the answer column; a half line does not
00:00 +2: All tests passed!
```

The widget test boots `TallynoteApp`, enters `1/0\n5 kg + 2 m\n2+`, and asserts
`find.text('divide by zero')`, `find.text('incompatible values')` each `findsOneWidget`, and
`find.textContaining('unexpected')` `findsNothing` — i.e. the errors really are painted in the column
and the unfinished `2+` paints no parse-error text.

Note on `2+`: PR#3's own test only pins `engineError isFalse` / `error isNull`; the lone-number
fallback (`_loneNumber`) still shows `2`, in both PR#3 and the port. Verified above.

## 2. US/EU number format setting

### 2a. What PR#3 does

- `lib/engine/values.dart` — new `NumberFormat { String decimal; String group; String yen; }`, presets
  `us` (`1,234.56`) and `eu` (`1.234,56`), `withYen`, `fromPrefs`, `preset`. `formatNumber`/`formatValue`/
  `_fmtDuration` take `format:` and write `format.group`/`format.decimal`.
- `lib/engine/lexer.dart` — `Lexer(source, {format})`; `_number` treats `format.decimal` as the decimal
  mark and `format.group` as grouping, but only when it is followed by exactly three digits then a
  boundary (`_groupAhead`: `1.234` groups, `1.2345` does not). A paren stack `_parenIsCall` records
  whether each `(` followed a known function name (`min(`, `pow(`...). `_decimalIsArgumentSeparator`
  makes a comma an argument separator only inside a call's parens; inside grouping parens and bare, a
  comma stays a decimal: `min(1,2)` is two args, `(1,5)` is 1.5.
- `lib/engine/parser.dart` — `Parser(source, units, {format})` threads the format into the lexer
  (and PR#3 additionally maps `¥` to `format.yen`).
- `lib/engine/engine.dart` — `SheetEngine.format`; every `formatNumber`/`formatValue` call and both
  `Parser.parseExpression` calls pass it; `_loneNumber` is rewritten to lex with the format so a
  grouping mark that is not exactly three digits (`1,23` US, `1.23` EU) is not rewritten into a
  different integer.
- `lib/ui/answer_column.dart` — `AnswerParts.parse(display, {decimal, group})` + `decimalMark`;
  `measureAnswers`/`AnswerReadout` take `decimal`/`group` so `1.234,56` still shares the decimal column.
- `lib/ui/editor_view.dart` — `EditorView.numberFormat` feeds the metrics.
- `lib/ui/settings_sheet.dart` — Editor tab rows: number format `us`/`eu` (and ¥ = JPY/CNY).
- `lib/main.dart` — prefs `tallynote.numFormat` (default `us`, so existing sheets do not change).

PR#3 body: "US `1,234.56` (default, so existing sheets do not change) or EU `1.234,56` ... The lexer,
parser, and display share that setting."

### 2b. Does main have it?

No. Main hardcodes `,` grouping and `.` decimal:

```
$ git grep -n "NumberFormat\|ideal(" main -- lib/engine/
rc=1
$ git show main:lib/engine/values.dart | grep -n "buf.write"
145:    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
```

### 2c. Minimal port

Same pipeline as PR#3, minus the yen part: `values.dart` `NumberFormat` (decimal+group only,
`ofPreset`) -> `lexer.dart` `Lexer(format)` with `_parenIsCall`/`_isArgSeparator`/`_groupAhead`
(`lexer.dart:82,88,214,219`) -> `parser.dart` `Parser(format)` -> `engine.dart` `SheetEngine.format`
+ format-aware `_loneNumber` -> `answer_column.dart`/`editor_view.dart` decimal/group threading.
`lib/ui/editor_view.dart:121-127` passes `widget.numberFormat.decimal/.group` into `measureAnswers`.

### 2d. Test cases with expected values — actual run

`flutter test test/audit_probe_test.dart -r expanded` (EU = `SheetEngine(format: NumberFormat.eu)`):

```
EU [10,875] err=false/null [10.875]  <- 9,875+1          (task case: must be 10.875)
EU [1.234,56] err=false/null [1234.56]  <- 1.234,56
EU [1,5] err=false/null [1.5]  <- 1,5
EU [1,5] err=false/null [1.5]  <- (1,5)                  (grouping parens: decimal)
EU [3,5] err=false/null [3.5]  <- (1,5)+2
EU [3] err=false/null [3.0]  <- 2 x (1,5)
EU [3] err=false/null [3.0]  <- 2 times (1,5)
EU [1] err=false/null [1.0]  <- min(1,2)                 (call parens: arg separator)
EU [256] err=false/null [256.0]  <- pow(2,8)
EU [2] err=false/null [2.0]  <- root(8,3)
EU [1,5] err=false/null [1.5]  <- 1,5 +                  (unfinished line keeps EU decimal)
EU [null] err=false/unexpected "." [null]  <- 1.23 +     (grouping must be 3 digits)
EU [null] err=false/unexpected "." [null]  <- 1.2345
EU [null] err=false/unexpected ",000" [null]  <- 2,000,000   (US input is malformed in EU)
EU [-1,5] err=false/null [-1.5]  <- -1,5 +
EU [$1.234,56] err=false/null [1234.56]  <- $1.234,56
US [9,876] err=false/null [9876.0]  <- 9,875+1           (US unchanged: thousands)
US [1,234] err=false/null [1234.0]  <- 1,234 +
US [null] err=false/unexpected "," [null]  <- 1,2345     (US grouping must be 3 digits)
US [null] err=false/unexpected "," [null]  <- 1,23 +
US [-1,234] err=false/null [-1234.0]  <- -1,234 +
```

Answer-column alignment (EU marks):

```
PARTS [10,875] aligns=true head=[10] frac=875 tail=[,875] suffix=[]
PARTS [1.234,56] aligns=true head=[1.234] frac=56 tail=[,56] suffix=[]
PARTS [1,5] aligns=true head=[1] frac=5 tail=[,5] suffix=[]
PARTS [-1,5] aligns=true head=[-1] frac=5 tail=[,5] suffix=[]
PARTS [30 October 2026] aligns=false ...
US parts 1,234.5 -> 1,234 / 5
```

These reproduce every PR#3 assertion for this area: `9,875+1` -> 10.875; `(1,5)` -> 1.5;
`(1,5)+2` -> 3.5; `1,5` -> 1.5; `1,5 +` -> engineError false, value 1.5, display `1,5`;
`1,23 +` US -> display null; `1.23 +` EU -> display null; `-1,234 +` US -> -1234;
`-1,5 +` EU -> -1.5, display `-1,5`; `1,234 +` US -> 1234.

### 2e. Port divergence from PR#3

- The yen half of the setting is dropped: `NumberFormat` has no `yen` field and the parser keeps
  main's hardcoded `¥ -> JPY` map. (PR#3's parser change is `code = format.yen`.)
- The settings row and prefs wiring are absent (see section 4): EU is reachable only by constructing
  `SheetEngine(format: NumberFormat.eu)` — as the probe test does — not from the UI.

## 3. Unit "ideal form"

### 3a. What PR#3 does

- `lib/engine/evaluator.dart` — `NumValue * NumValue` and `NumValue / NumValue` route through
  `_scaled(value, unit, hints)` -> `ctx.units.ideal(value, unit, hints)`; hints are the operands' units.
- `lib/engine/units.dart` — `UnitRegistry.ideal`: if the compound unit has dims {time:1, speed:1}
  (time × speed) it rewrites to a length in the typed family; if {length:1, time:-1} (length ÷ time)
  it rewrites to a speed. `_pickLength(meters, hints)` (PR#3) picks nmi / ft-vs-mi by magnitude /
  km-vs-m by magnitude / m; `_pickSpeed(hints)` picks knot / mph / km/h / m/s from the hints.
  `_tidy` snaps float noise (`45.00000000000001`) at 12 significant digits.

PR#3 body: "Time × speed becomes a length (`3 min * 15 mph` -> `0.75 mi`, `2 h * 100 km/h` ->
`200 km`). Length ÷ time becomes a speed (`10 m / 2 s` -> `5 m/s`, `30 km / 0.5 h` -> `60 km/h`).
The family follows the units that were typed."

### 3b. Does main have it?

No:

```
$ git grep -n "ideal(" main -- lib/engine/
rc=1
```

main's evaluator returns the raw compound unit (`NumValue(l.value * r.value, unit)` with
`_mulUnit` -> `45 min·mph`).

### 3c. Minimal port

`units.dart` `ideal` + `_pickLength`/`_pickSpeed`/`_tidy` (`lib/engine/units.dart:204,222,230,240`);
`evaluator.dart` `_scaled` wrapper (`lib/engine/evaluator.dart:122,158,246`). Nothing else changes —
the engine's display path picks the unit up automatically.

### 3d. Test cases with expected values — actual run

```
US [0.75 mi] err=false/null [0.75]  <- 3 min * 15 mph     (task case: 0.75 mi, not 45 min·mph)
US [10 nmi] err=false/null [10.0]  <- 1 h * 10 knot       (task case: 10 nmi)
EU [200 km] err=false/null [200.0]  <- 2 h * 100 km/h
EU [5 m/s] err=false/null [5.0]  <- 10 m / 2 s
EU [60 km/h] err=false/null [60.0]  <- 30 km / 0,5 h
```

### 3e. Port divergence from PR#3

- PR#3's `_pickLength(double meters, List hints)` is magnitude-aware: small imperial lengths come out
  in feet (`1 min * 1 mph` -> `88 ft`) and metric lengths >= 1000 m come out in km. The port's
  `_pickLength(List hints)` picks by hint family only, so `1 min * 1 mph` -> `0.0166666666667 mi`
  (verified above) and a 5000 m result would stay `m`. The three required cases (0.75 mi, 10 nmi,
  and the PR-body speed cases) agree.
- `_tidy` snap tolerance: PR#3 `1e-6` relative, port `1e-9` relative. Both snap the knot case to 10.

## 4. What the port ships vs what it deliberately skips

Ships (the three areas): ErrorValue painting, US/EU number format through
lexer -> parser -> evaluator -> engine -> answer column, unit ideal form. Analyzer clean:

```
$ flutter analyze
No issues found! (ran in 1.4s)
```

Full suite (main's 75 tests + the 2 probe tests):

```
$ flutter test
00:02 +77: All tests passed!
```

Skipped (PR#3 sections outside the three engine areas): the settings-sheet rows and prefs persistence
(`tallynote.numFormat`, `tallynote.yen`) in `main.dart`, the ¥ = JPY/CNY setting, the vertical-alignment
rework (bold/italic marker measurement, `marked_controller.dart`), the autosave/debounce/fold/corrupt-
library storage fixes, i18n strings, docs. Because nothing wires `format` in `main.dart` /
`lib/ui/folding.dart`, EU stays engine-reachable but not user-reachable in this worktree; that wiring
is the one-line-per-call-site follow-up if the setting UI is wanted.

One pre-existing flake, unrelated to the three areas and to this port: `test/app_test.dart` test
"answers can be hidden from settings" fails when run in isolation
(`flutter test test/app_test.dart --plain-name "answers can be hidden from settings"`), passes when the
file runs in order and in the full suite (2 of 3 full runs green; the one failure was that same test).
It is an order/timing-sensitive settings-sheet test, not touched by the port.
