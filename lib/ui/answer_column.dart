import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One answer string split so a column can share a decimal point.
///
/// Padding with non-breaking spaces and multiplying by "the width of 0"
/// only lines up when every glyph — digit, comma, minus, currency, NBSP —
/// is the same width. Generic `monospace` plus `tnum` does not guarantee
/// that: currency symbols and NBSP fall back to a proportional face, and
/// the paragraph shaper drops trailing NBSP, so integers and short
/// fractions snap to the right edge. Measuring the pieces avoids that.
class AnswerParts {
  final String raw;
  final bool aligns;
  final String head;
  final String? fraction;
  final String suffix;

  const AnswerParts({
    required this.raw,
    required this.aligns,
    this.head = '',
    this.fraction,
    this.suffix = '',
  });

  /// Dot, fraction digits, and a suffix that belongs to a fractional value
  /// (`%`, ` kg`). Glued together so the suffix sits on the last digit.
  String get fractionTail => fraction == null ? '' : '.$fraction$suffix';

  static final _number = RegExp(r'\d[\d,]*(?:\.\d+)?');

  /// A single number, optionally with a sign or currency in front and a
  /// unit or `%` after. Dates, lists, and scientific notation have more
  /// than one number, so they stay a single right-aligned run.
  factory AnswerParts.parse(String display) {
    final matches = _number.allMatches(display).toList();
    if (matches.length != 1) {
      return AnswerParts(raw: display, aligns: false);
    }
    final m = matches.first;
    final token = m.group(0)!;
    final before = display.substring(0, m.start);
    final after = display.substring(m.end);
    final dot = token.indexOf('.');
    if (dot >= 0) {
      return AnswerParts(
        raw: display,
        aligns: true,
        head: before + token.substring(0, dot),
        fraction: token.substring(dot + 1),
        suffix: after,
      );
    }
    return AnswerParts(
      raw: display,
      aligns: true,
      head: before + token,
      suffix: after,
    );
  }
}

/// Pixel widths for one answer column. [headW] is the shared decimal x
/// inside the numeric block. [numericW] is that block; [totalW] may be
/// wider when a non-numeric answer (a date, a list) needs the room.
class AnswerColumnMetrics {
  final double headW;
  final double fracW;
  final double numericW;
  final double totalW;

  const AnswerColumnMetrics({
    required this.headW,
    required this.fracW,
    required this.numericW,
    required this.totalW,
  });

  static const zero = AnswerColumnMetrics(
    headW: 0,
    fracW: 0,
    numericW: 0,
    totalW: 0,
  );
}

AnswerColumnMetrics measureAnswers(
  Iterable<String> displays,
  double Function(String text) measure,
) {
  final parts = displays.map(AnswerParts.parse).toList();
  final cache = <String, double>{};
  double width(String text) => cache.putIfAbsent(text, () => measure(text));

  var headW = 0.0;
  var fracW = 0.0;
  for (final p in parts) {
    if (!p.aligns) continue;
    headW = math.max(headW, width(p.head));
    if (p.fraction != null) {
      fracW = math.max(fracW, width('.${p.fraction}'));
    }
  }

  var numericW = 0.0;
  var opaqueW = 0.0;
  for (final p in parts) {
    if (!p.aligns) {
      opaqueW = math.max(opaqueW, width(p.raw));
      continue;
    }
    final after = p.fraction != null
        ? width(p.fractionTail)
        : fracW + width(p.suffix);
    numericW = math.max(numericW, headW + after);
  }

  return AnswerColumnMetrics(
    headW: headW,
    fracW: fracW,
    numericW: numericW,
    totalW: math.max(numericW, opaqueW),
  );
}

double measureAnswerText(String text, TextStyle style, TextScaler scaler) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  // Glyph advances and the theme's letter spacing can land a fraction of a
  // pixel over the painter width. Ceil so the row is never shorter than the
  // text it holds; the shared decimal x is still the head box's right edge.
  return painter.width.ceilToDouble();
}

/// The answer cell. Every aligning row shares [AnswerColumnMetrics.headW]
/// as the decimal point; the block is right-aligned in the column.
class AnswerReadout extends StatelessWidget {
  final String display;
  final TextStyle style;
  final AnswerColumnMetrics metrics;

  const AnswerReadout({
    super.key,
    required this.display,
    required this.style,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final parts = AnswerParts.parse(display);
    return Semantics(
      label: display,
      container: true,
      excludeSemantics: true,
      child: SizedBox(
        width: metrics.totalW,
        child: parts.aligns ? _aligned(parts) : _opaque(parts),
      ),
    );
  }

  Widget _opaque(AnswerParts parts) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        parts.raw,
        maxLines: 1,
        softWrap: false,
        style: style,
        textDirection: TextDirection.ltr,
      ),
    );
  }

  Widget _aligned(AnswerParts parts) {
    final lead = metrics.totalW - metrics.numericW;
    return Row(
      textDirection: TextDirection.ltr,
      children: [
        if (lead > 0) SizedBox(width: lead),
        SizedBox(
          width: metrics.numericW,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              SizedBox(
                width: metrics.headW,
                child: Text(
                  parts.head,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                  style: style,
                  textDirection: TextDirection.ltr,
                ),
              ),
              if (parts.fraction != null)
                Text(
                  parts.fractionTail,
                  maxLines: 1,
                  softWrap: false,
                  style: style,
                  textDirection: TextDirection.ltr,
                )
              else ...[
                if (metrics.fracW > 0) SizedBox(width: metrics.fracW),
                if (parts.suffix.isNotEmpty)
                  Text(
                    parts.suffix,
                    maxLines: 1,
                    softWrap: false,
                    style: style,
                    textDirection: TextDirection.ltr,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
