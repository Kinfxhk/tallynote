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

  const EditorView({
    super.key,
    required this.controller,
    required this.results,
    required this.dark,
    this.answersVisible = true,
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
                    child: IgnorePointer(
                      child: Text(
                        widget.results[i].display!,
                        textAlign: TextAlign.right,
                        style: answerStyle(widget.dark).copyWith(
                          color: widget.results[i].error != null
                              ? Palette.answer(widget.dark).withValues(alpha: 0.6)
                              : null,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      );
    });
  }

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
