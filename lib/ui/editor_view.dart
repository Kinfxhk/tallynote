import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/engine.dart';
import '../engine/values.dart';
import 'feedback.dart';
import 'theme.dart';

/// A single text field with answers aligned to each logical line.
///
/// Answers are positioned with a TextPainter over the same text/style/width,
/// so soft-wrapped lines still line up without a per-line widget tree.
class EditorView extends StatefulWidget {
  final TextEditingController controller;
  final List<LineResult> results;
  final bool dark;
  final bool answersVisible;
  final List<String> Function(String line)? explain;
  final bool showSteps;
  final double answerWidth;
  final ValueChanged<double>? onAnswerWidth;
  final bool signColours;
  final void Function(int line)? onInsertReference;
  final Color? positiveColour;
  final Color? negativeColour;

  const EditorView({
    super.key,
    required this.controller,
    required this.results,
    required this.dark,
    this.answersVisible = true,
    this.explain,
    this.showSteps = true,
    this.answerWidth = 212,
    this.onAnswerWidth,
    this.signColours = true,
    this.onInsertReference,
    this.positiveColour,
    this.negativeColour,
  });

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant EditorView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = editorStyle(widget.dark);
    const stepGutter = 30.0; // finger-sized, but the icon stays small
    const gutterW = 38.0; // faint line numbers, Notepad++ style
    final answerW = widget.answersVisible ? widget.answerWidth : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final text = widget.controller.text;
        final textWidth = constraints.maxWidth - answerW - gutterW - 48;
        final tops = _lineTops(text, style, textWidth < 80 ? 80 : textWidth);
        final metrics = _columnMetrics(
          widget.results,
          available: answerW - stepGutter - 10,
        );

        return DragTarget<int>(
          onAcceptWithDetails: (d) => widget.onInsertReference?.call(d.data),
          builder: (context, candidate, rejected) => SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
            child: Stack(
              children: [
                // faint line numbers, aligned with the same text metrics
                for (var i = 0; i < widget.results.length; i++)
                  Positioned(
                    top: (tops.length > i ? tops[i] : 0) + 6,
                    left: 0,
                    width: gutterW - 10,
                    child: IgnorePointer(
                      child: Text(
                        '${i + 1}',
                        key: ValueKey('gutter-${i + 1}'),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontFamily: monoFamily,
                          fontSize: 11,
                          color: Palette.faint(widget.dark)
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(left: gutterW, right: answerW),
                  child: TextField(
                    controller: widget.controller,
                    maxLines: null,
                    style: style,
                    strutStyle: StrutStyle(
                      fontFamily: monoFamily,
                      fontSize: 15,
                      height: 28 / 15,
                      forceStrutHeight: true,
                    ),
                    cursorColor: Palette.answer(widget.dark),
                    cursorWidth: 1.6,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Type a calculation…   e.g.  rent = 2500  ·  total of #food',
                    ),
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
                if (widget.answersVisible)
                  for (var i = 0; i < widget.results.length; i++)
                    if (widget.results[i].display != null)
                      Positioned(
                        top: (tops.length > i ? tops[i] : 0),
                        right: 0,
                        width: answerW,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // the step marker lives in its own gutter so numbers
                            // never move because of it
                            SizedBox(
                              width: stepGutter,
                              height: 28,
                              child:
                                  (widget.showSteps &&
                                      widget.explain != null &&
                                      _hasOperators(widget.results[i].text))
                                  ? _StepButton(
                                      dark: widget.dark,
                                      onTap: () =>
                                          _openSteps(widget.results[i].text),
                                    )
                                  : null,
                            ),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: _cell(i, metrics),
                              ),
                            ),
                          ],
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Character counts needed to line the decimal points up. Widths are exact
  /// because the answer style is monospace with tabular figures.
  _ColumnMetrics _columnMetrics(List<LineResult> results, {double? available}) {
    var maxHead = 0;
    var maxFrac = 0;
    for (final r in results) {
      final d = r.display;
      if (d == null) continue;
      final dot = d.lastIndexOf('.');
      if (dot > 0 && RegExp(r'^\d+$').hasMatch(d.substring(dot + 1))) {
        maxHead = math.max(maxHead, dot);
        maxFrac = math.max(maxFrac, math.min(2, d.length - dot - 1));
      } else if (_isNumericHead(d)) {
        maxHead = math.max(maxHead, d.length);
      }
    }
    final charW = _charWidth();
    // when the column is tight, drop decimals before shrinking the text
    if (available != null) {
      while (maxFrac > 0 && charW * (maxHead + 1 + maxFrac) > available) {
        maxFrac--;
      }
    }
    return _ColumnMetrics(maxHead, maxFrac, charW);
  }

  double _charWidth() {
    final tp = TextPainter(
      text: TextSpan(text: '0', style: answerStyle(widget.dark)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  static bool _isNumericHead(String s) =>
      RegExp(r'[\d]').hasMatch(s) &&
      !RegExp(r'[A-Za-z\u4e00-\u9fff]').hasMatch(s);

  /// Mirrors SheetEngine.explain: two or more operations is "complex".
  static bool _hasOperators(String line) =>
      RegExp(r'[+\-*/^%×÷]|乘|除|加|減|减').allMatches(line).length >= 2;

  /// One answer cell, with drag-to-reference when the sheet supports it.
  Widget _cell(int i, _ColumnMetrics metrics) {
    final r = widget.results[i];
    final style = answerStyle(widget.dark).copyWith(color: _answerColour(r));
    final cell = _tapForSteps(
      line: r.text,
      canExplain:
          widget.showSteps && widget.explain != null && _hasOperators(r.text),
      child: _AnswerCell(display: r.display!, style: style, metrics: metrics),
    );

    if (widget.onInsertReference == null) return cell;
    // Draggable (not LongPress) keeps a plain tap free for the steps dialog
    return Draggable<int>(
      data: i + 1,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _dragChip(i + 1, r.display!),
      childWhenDragging: Opacity(opacity: 0.35, child: cell),
      child: cell,
    );
  }

  Widget _dragChip(int line, String value) => Material(
    color: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.bg(widget.dark),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Palette.answer(widget.dark)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        'line $line  ·  $value',
        style: TextStyle(
          fontFamily: monoFamily,
          fontSize: 13,
          color: Palette.fg(widget.dark),
        ),
      ),
    ),
  );

  /// Negative in red, positive in green — both overridable in Settings.
  Color? _answerColour(LineResult r) {
    if (r.error != null) {
      return Palette.answer(widget.dark).withValues(alpha: 0.6);
    }
    if (!widget.signColours) return null;
    final v = r.value;
    final n = switch (v) {
      NumValue(:final value) => value,
      MoneyValue(:final value) => value,
      PercentValue(:final ratio) => ratio,
      _ => null,
    };
    if (n == null || n == 0) return null;
    return n < 0
        ? (widget.negativeColour ?? Palette.negative(widget.dark))
        : (widget.positiveColour ?? Palette.positive(widget.dark));
  }

  /// The whole answer cell is the tap target on phones — the chevron is a
  /// hint, not a 16px button.
  Widget _tapForSteps({
    required String line,
    required bool canExplain,
    required Widget child,
  }) {
    // when dragging is available the cell must stay hit-testable
    if (!canExplain) {
      return widget.onInsertReference == null
          ? IgnorePointer(child: child)
          : child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        tapFeedback();
        _openSteps(line);
      },
      child: child,
    );
  }

  Future<void> _openSteps(String line) async {
    final steps = widget.explain!(line);
    if (!mounted) return;
    if (steps.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Palette.bg(widget.dark),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Steps',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w600,
                    color: Palette.faint(widget.dark),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(steps.join('\n'), style: editStyle()),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        fontSize: 13,
                        color: Palette.answer(widget.dark),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle editStyle() => TextStyle(
    fontFamily: monoFamily,
    fontSize: 13.5,
    height: 1.7,
    color: Palette.fg(widget.dark),
  );

  /// Vertical offset of each logical line, honouring soft wraps.
  List<double> _lineTops(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      strutStyle: StrutStyle(
        fontFamily: monoFamily,
        fontSize: 15,
        height: 28 / 15,
        forceStrutHeight: true,
      ),
    )..layout(maxWidth: width);

    final tops = <double>[];
    var offset = 0;
    for (final line in text.split('\n')) {
      final caret = painter.getOffsetForCaret(
        TextPosition(offset: offset),
        Rect.zero,
      );
      tops.add(caret.dy);
      offset += line.length + 1;
    }
    return tops;
  }
}

class _StepButton extends StatelessWidget {
  final bool dark;
  final VoidCallback onTap;

  const _StepButton({required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // the whole gutter cell is tappable; only the glyph is small
    return Semantics(
      button: true,
      label: 'Show steps',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.expand(
          child: Icon(
            Icons.chevron_right,
            size: 16,
            color: Palette.faint(dark),
          ),
        ),
      ),
    );
  }
}

class _ColumnMetrics {
  final int maxHead;
  final int maxFrac;
  final double charW;
  const _ColumnMetrics(this.maxHead, this.maxFrac, this.charW);

  double get headW => charW * maxHead;
  double get totalW => charW * (maxHead + 1 + maxFrac);
}

class _AnswerCell extends StatelessWidget {
  final String display;
  final TextStyle style;
  final _ColumnMetrics metrics;

  const _AnswerCell({
    required this.display,
    required this.style,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final dot = display.lastIndexOf('.');
    final hasFrac =
        dot > 0 &&
        display.length - dot - 1 <= metrics.maxFrac &&
        RegExp(r'^\d+$').hasMatch(display.substring(dot + 1));
    // plain integers belong in the grid too: their decimal point is implied
    final isInteger = dot == -1 && RegExp(r'^[-\d,]+$').hasMatch(display);
    if (!hasFrac && !isInteger) {
      return SizedBox(
        width: metrics.totalW,
        child: Text(
          display,
          textAlign: TextAlign.right,
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
      );
    }

    final head = hasFrac ? display.substring(0, dot) : display;
    final frac = hasFrac ? display.substring(dot + 1) : '';
    return SizedBox(
      width: metrics.totalW,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            width: metrics.headW,
            child: Text(
              head,
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              style: style,
            ),
          ),
          SizedBox(
            width: metrics.charW,
            // integers get a blank here so their digits end at the decimal
            // column instead of growing a stray dot
            child: Text(hasFrac ? '.' : '', style: style),
          ),
          SizedBox(
            width: metrics.charW * metrics.maxFrac,
            child: Text(frac, style: style),
          ),
        ],
      ),
    );
  }
}
