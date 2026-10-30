import 'package:flutter/material.dart';

import '../data/rates.dart';
import 'theme.dart';

/// Every switch that is not part of typing lives here.
/// The main screen keeps two buttons: sheets and settings.
Future<void> showSettingsSheet({
  required BuildContext context,
  required bool dark,
  required bool answersVisible,
  required bool autoRates,
  required ValueChanged<bool> onAnswers,
  required ValueChanged<bool> onTheme,
  required ValueChanged<bool> onAutoRates,
  required Future<bool> Function() onRefreshRates,
}) {
  // local copies so repeated taps in the sheet stay consistent
  var localAnswers = answersVisible;
  var localDark = dark;
  var localRates = autoRates;

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Palette.bg(dark),
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Widget row(String label, String hint, Widget trailing,
                {VoidCallback? onTap}) =>
            InkWell(
              onTap: onTap,
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                fontSize: 14, color: Palette.fg(dark))),
                        const SizedBox(height: 2),
                        Text(hint,
                            style: TextStyle(
                                fontSize: 11.5, color: Palette.faint(dark))),
                      ],
                    ),
                  ),
                  trailing,
                ],
              ),
            ),
            );

        Switch plus(bool value, ValueChanged<bool> onChanged) => Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Palette.answer(dark),
            );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text('Settings',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w600,
                        color: Palette.faint(dark),
                      )),
                ),
                row('Answers', 'Show the result column',
                    plus(localAnswers, (v) {
                  localAnswers = v;
                  onAnswers(v);
                  setSheet(() {});
                }), onTap: () {
                  localAnswers = !localAnswers;
                  onAnswers(localAnswers);
                  setSheet(() {});
                }),
                row('Dark mode', 'Paper is light, ink is dark',
                    plus(localDark, (v) {
                  localDark = v;
                  onTheme(v);
                  setSheet(() {});
                }), onTap: () {
                  localDark = !localDark;
                  onTheme(localDark);
                  setSheet(() {});
                }),
                row(
                  'Auto-refresh rates',
                  'Once a day when a network is available',
                  plus(localRates, (v) {
                    localRates = v;
                    onAutoRates(v);
                    setSheet(() {});
                  }),
                  onTap: () {
                    localRates = !localRates;
                    onAutoRates(localRates);
                    setSheet(() {});
                  },
                ),
                const Divider(height: 20),
                row(
                  'Exchange rates',
                  Rates.updatedDate == null
                      ? 'Built-in table (offline)'
                      : 'Last updated ${Rates.updatedDate}',
                  TextButton(
                    onPressed: () async {
                      final ok = await onRefreshRates();
                      if (ctx.mounted) setSheet(() {});
                      if (!ok && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                              content: Text('Offline — kept the last rates')),
                        );
                      }
                    },
                    child: Text('Refresh',
                        style: TextStyle(
                            fontSize: 13, color: Palette.answer(dark))),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(
                    'Everything is computed on this device. Rates are the only '
                    'thing that ever uses the network, and only when they are '
                    'stale.',
                    style: TextStyle(
                        fontSize: 11, height: 1.5, color: Palette.faint(dark)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
