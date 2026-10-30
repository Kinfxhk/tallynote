import 'package:flutter/material.dart';

import '../engine/engine.dart';
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

  const EditorView({
    super.key,
    required this.controller,
    required this.results,
    required this.dark,
    this.answersVisible = true,
    this.explain,
    this.showSteps = true,
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
    final answerW = widget.answersVisible ? 150.0 : 0.0;

    return LayoutBuilder(builder: (context, constraints) {
      final text = widget.controller.text;
      final textWidth = constraints.maxWidth - answerW - 48;
      final tops = _lineTops(text, style, textWidth < 80 ? 80 : textWidth);

      return SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: answerW),
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
                        Flexible(
                          child: IgnorePointer(
                            child: Text(
                              widget.results[i].display!,
                              textAlign: TextAlign.right,
                              style: answerStyle(widget.dark).copyWith(
                                color: widget.results[i].error != null
                                    ? Palette.answer(widget.dark)
                                        .withValues(alpha: 0.6)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        if (widget.showSteps &&
                            widget.explain != null &&
                            _hasOperators(widget.results[i].text))
                          _StepButton(
                            dark: widget.dark,
                            onTap: () => _openSteps(widget.results[i].text),
                          ),
                      ],
                    ),
                  ),
          ],
        ),
      );
    });
  }

  /// Mirrors SheetEngine.explain: two or more operations is "complex".
  static bool _hasOperators(String line) =>
      RegExp(r'[+\-*/^%×÷]|乘|除|加|減|减').allMatches(line).length >= 2;

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
                SelectableText(
                  steps.join('\n'),
                  style: editStyle(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text('Close',
                        style: TextStyle(
                            fontSize: 13, color: Palette.answer(widget.dark))),
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
          TextPosition(offset: offset), Rect.zero);
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
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(Icons.add, size: 13, color: Palette.faint(dark)),
      ),
    );
  }
}
