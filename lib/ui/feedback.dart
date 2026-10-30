import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The app had no press feedback at all (NoSplash everywhere), which reads as
/// "dead" on both desktop and phone. Everything tappable goes through here:
/// a short haptic on mobile, a tint + hover on desktop, and a splash that is
/// a whisper rather than a ripple.
Future<void> tapFeedback() async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await HapticFeedback.selectionClick();
  }
}

/// A tap target with consistent paper-and-ink feedback.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final EdgeInsets? padding;
  final BoxDecoration? decoration;
  final MouseCursor cursor;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
    this.padding,
    this.decoration,
    this.cursor = SystemMouseCursors.click,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = Palette.answer(dark);
    final active = _down || (_hover && widget.onTap != null);

    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: (widget.decoration ?? const BoxDecoration()).copyWith(
        color: active
            ? tint.withValues(alpha: _down ? 0.14 : 0.06)
            : (widget.decoration?.color ?? Colors.transparent),
        borderRadius:
            widget.decoration?.borderRadius ?? BorderRadius.circular(3),
      ),
      child: widget.child,
    );

    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : widget.cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap == null
            ? null
            : () async {
                if (widget.haptic) await tapFeedback();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () async {
                if (widget.haptic) await tapFeedback();
                widget.onLongPress!();
              },
        child: box,
      ),
    );
  }
}
