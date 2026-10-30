import 'package:flutter/material.dart';

import 'formatting.dart';
import 'theme.dart';

/// Renders the inline markers (**bold**, _italic_, ~~strike~~, __underline__,
/// {red}colour{/}) without turning the sheet into a rich-text document.
class MarkedController extends TextEditingController {
  bool dark;

  /// For each line, the names of the lines *above* it. Only those are live
  /// references; a line's own name is just a name.
  List<Set<String>> labelsByLine = const [];
  MarkedController({super.text, required this.dark});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final children = <InlineSpan>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (Fmt.isDraft(line)) {
        children.add(
          TextSpan(
            text: line,
            style: base.copyWith(
              color: Palette.faint(dark),
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      } else {
        children.addAll(
          Fmt.withReferences(
            Fmt.spans(line, base),
            base,
            labels: i < labelsByLine.length ? labelsByLine[i] : const {},
            dark: dark,
          ),
        );
      }
      if (i < lines.length - 1) children.add(TextSpan(text: '\n', style: base));
    }

    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      // keep the IME's composing range visible while typing Chinese
      final start = value.composing.start.clamp(0, text.length);
      final end = value.composing.end.clamp(0, text.length);
      return TextSpan(
        style: base,
        children: [
          ...children.take(0),
          TextSpan(text: text.substring(0, start), style: base),
          TextSpan(
            text: text.substring(start, end),
            style: base.copyWith(decoration: TextDecoration.underline),
          ),
          TextSpan(text: text.substring(end), style: base),
        ],
      );
    }

    return TextSpan(style: base, children: children);
  }
}
