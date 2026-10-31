import 'package:flutter/material.dart';

import '../data/rates.dart';
import '../i18n/strings.dart';
import 'cheat_sheet.dart';
import 'feedback.dart';
import 'formatting.dart';
import 'theme.dart';

/// All settings, grouped into tabs. The main screen keeps two buttons, so
/// everything that is a preference rather than an action ends up here.
Future<void> showSettingsSheet({
  required BuildContext context,
  required bool dark,
  required bool answersVisible,
  required bool autoRates,
  required bool steps,
  required bool signColours,
  required String posName,
  required String negName,
  required bool lineNumbers,
  required bool showTabs,
  required double uiScale,
  required String locale,
  required String numberPreset,
  required ValueChanged<String> onLocale,
  required ValueChanged<String> onNumberPreset,
  required ValueChanged<bool> onAnswers,
  required ValueChanged<bool> onTheme,
  required ValueChanged<bool> onAutoRates,
  required ValueChanged<bool> onSteps,
  required ValueChanged<bool> onSignColours,
  required ValueChanged<String> onPosColour,
  required ValueChanged<String> onNegColour,
  required ValueChanged<bool> onLineNumbers,
  required ValueChanged<bool> onShowTabs,
  required ValueChanged<double> onUiScale,
  required Future<bool> Function() onRefreshRates,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SettingsDialog(
      dark: dark,
      answersVisible: answersVisible,
      autoRates: autoRates,
      steps: steps,
      signColours: signColours,
      posName: posName,
      negName: negName,
      lineNumbers: lineNumbers,
      showTabs: showTabs,
      uiScale: uiScale,
      locale: locale,
      numberPreset: numberPreset,
      onNumberPreset: onNumberPreset,
      onLocale: onLocale,
      onAnswers: onAnswers,
      onTheme: onTheme,
      onAutoRates: onAutoRates,
      onSteps: onSteps,
      onSignColours: onSignColours,
      onPosColour: onPosColour,
      onNegColour: onNegColour,
      onLineNumbers: onLineNumbers,
      onShowTabs: onShowTabs,
      onUiScale: onUiScale,
      onRefreshRates: onRefreshRates,
    ),
  );
}

class _SettingsDialog extends StatefulWidget {
  final bool dark;
  final bool answersVisible;
  final bool autoRates;
  final bool steps;
  final bool signColours;
  final String posName;
  final String negName;
  final bool lineNumbers;
  final bool showTabs;
  final double uiScale;
  final String locale;
  final String numberPreset;
  final ValueChanged<String> onLocale;
  final ValueChanged<String> onNumberPreset;
  final ValueChanged<bool> onAnswers;
  final ValueChanged<bool> onTheme;
  final ValueChanged<bool> onAutoRates;
  final ValueChanged<bool> onSteps;
  final ValueChanged<bool> onSignColours;
  final ValueChanged<String> onPosColour;
  final ValueChanged<String> onNegColour;
  final ValueChanged<bool> onLineNumbers;
  final ValueChanged<bool> onShowTabs;
  final ValueChanged<double> onUiScale;
  final Future<bool> Function() onRefreshRates;

  const _SettingsDialog({
    required this.dark,
    required this.answersVisible,
    required this.autoRates,
    required this.steps,
    required this.signColours,
    required this.posName,
    required this.negName,
    required this.lineNumbers,
    required this.showTabs,
    required this.uiScale,
    required this.locale,
    required this.numberPreset,
    required this.onLocale,
    required this.onNumberPreset,
    required this.onAnswers,
    required this.onTheme,
    required this.onAutoRates,
    required this.onSteps,
    required this.onSignColours,
    required this.onPosColour,
    required this.onNegColour,
    required this.onLineNumbers,
    required this.onShowTabs,
    required this.onUiScale,
    required this.onRefreshRates,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool dark = widget.dark;
  late bool answers = widget.answersVisible;
  late bool autoRates = widget.autoRates;
  late bool steps = widget.steps;
  late bool signColours = widget.signColours;
  late String pos = widget.posName;
  late String neg = widget.negName;
  late bool lineNumbers = widget.lineNumbers;
  late bool showTabs = widget.showTabs;
  late double scale = widget.uiScale;
  late String locale = widget.locale;
  late String preset = widget.numberPreset;
  String? rateError;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Palette.bg(dark),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: DefaultTabController(
          length: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                labelColor: Palette.answer(dark),
                unselectedLabelColor: Palette.faint(dark),
                indicatorColor: Palette.answer(dark),
                labelStyle: const TextStyle(fontSize: 12.5),
                tabs: [
                  Tab(text: T.of(locale, 'appearance')),
                  Tab(text: T.of(locale, 'editor')),
                  Tab(text: T.of(locale, 'data')),
                  Tab(text: T.of(locale, 'cheatSheet')),
                ],
              ),
              Flexible(
                child: TabBarView(
                  children: [
                    _appearance(),
                    _editor(),
                    _data(),
                    CheatSheetView(dark: dark, locale: locale),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 12, 8),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      T.of(locale, 'done'),
                      style: TextStyle(color: Palette.answer(dark)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- tabs ----------------------------------------------------------------

  Widget _appearance() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _languageRow(),
      _row(
        T.of(locale, 'dark'),
        T.of(locale, 'darkHint'),
        _switch(dark, (v) {
          setState(() => dark = v);
          widget.onTheme(v);
        }, 'dark'),
      ),
      _row(
        T.of(locale, 'answers'),
        T.of(locale, 'answersHint'),
        _switch(answers, (v) {
          setState(() => answers = v);
          widget.onAnswers(v);
        }, 'answers'),
      ),
      _row(
        T.of(locale, 'signColours'),
        T.of(locale, 'signColoursHint'),
        _switch(signColours, (v) {
          setState(() => signColours = v);
          widget.onSignColours(v);
        }, 'sign'),
      ),
      if (signColours) ...[
        _colourRow(T.of(locale, 'positive'), pos, (name) {
          setState(() => pos = name);
          widget.onPosColour(name);
        }),
        _colourRow(T.of(locale, 'negative'), neg, (name) {
          setState(() => neg = name);
          widget.onNegColour(name);
        }),
      ],
    ],
  );

  Widget _editor() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _row(
        T.of(locale, 'textSize'),
        T.of(locale, 'textSizeHint'),
        _scaleButtons(),
      ),
      _row(
        'Number format',
        'US 1,234.56 · EU 1.234,56',
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in const ['us', 'eu'])
              TextButton(
                onPressed: () {
                  setState(() => preset = p);
                  widget.onNumberPreset(p);
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(40, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  foregroundColor: preset == p
                      ? Palette.answer(dark)
                      : Palette.faint(dark),
                ),
                child: Text(
                  p.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: preset == p ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
      ),
      _row(
        T.of(locale, 'lineNumbers'),
        T.of(locale, 'lineNumbersHint'),
        _switch(lineNumbers, (v) {
          setState(() => lineNumbers = v);
          widget.onLineNumbers(v);
        }),
      ),
      _row(
        T.of(locale, 'tabBar'),
        T.of(locale, 'tabBarHint'),
        _switch(showTabs, (v) {
          setState(() => showTabs = v);
          widget.onShowTabs(v);
        }),
      ),
      _row(
        T.of(locale, 'stepChevrons'),
        T.of(locale, 'stepChevronsHint'),
        _switch(steps, (v) {
          setState(() => steps = v);
          widget.onSteps(v);
        }),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: Text(
          T.of(locale, 'shortcuts'),
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Palette.faint(dark),
          ),
        ),
      ),
    ],
  );

  Widget _data() => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: [
      _row(
        T.of(locale, 'autoRates'),
        T.of(locale, 'autoRatesHint'),
        _switch(autoRates, (v) {
          setState(() => autoRates = v);
          widget.onAutoRates(v);
        }),
      ),
      _row(
        T.of(locale, 'exchangeRates'),
        rateError ??
            (Rates.updatedDate == null
                ? T.of(locale, 'ratesTable')
                : T.format(locale, 'ratesUpdated', {
                    'date': '${Rates.updatedDate}',
                  })),
        TextButton(
          onPressed: () async {
            final ok = await widget.onRefreshRates();
            if (!mounted) return;
            setState(() => rateError = ok ? null : T.of(locale, 'offline'));
          },
          child: Text(
            T.of(locale, 'refresh'),
            style: TextStyle(fontSize: 13, color: Palette.answer(dark)),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Text(
          T.of(locale, 'privacy'),
          style: TextStyle(
            fontSize: 11,
            height: 1.5,
            color: Palette.faint(dark),
          ),
        ),
      ),
    ],
  );

  // ---- rows ----------------------------------------------------------------

  Widget _languageRow() => _row(
    T.of(locale, 'language'),
    T.of(locale, 'languageHint'),
    Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in T.supported.entries)
          TextButton(
            onPressed: () {
              setState(() => locale = entry.key);
              widget.onLocale(entry.key);
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(34, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              foregroundColor: locale == entry.key
                  ? Palette.answer(dark)
                  : Palette.faint(dark),
            ),
            child: Text(
              switch (entry.key) {
                'zh_Hant' => '繁',
                'zh_Hans' => '简',
                _ => 'EN',
              },
              style: TextStyle(
                fontSize: 11,
                fontWeight: locale == entry.key
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _row(String label, String hint, Widget trailing) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 13.5, color: Palette.fg(dark)),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
              ),
            ],
          ),
        ),
        trailing,
      ],
    ),
  );

  Widget _colourRow(String label, String current, ValueChanged<String> pick) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: Palette.fg(dark)),
              ),
            ),
            for (final entry in Fmt.colours.entries)
              Pressable(
                onTap: () => pick(entry.key),
                padding: const EdgeInsets.all(6),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: entry.key == current
                        ? Border.all(color: Palette.fg(dark), width: 2)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _switch(bool value, ValueChanged<bool> onChanged, [String? id]) =>
      Switch(
        key: id == null ? null : ValueKey('switch-$id'),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Palette.answer(dark),
      );

  Widget _scaleButtons() {
    const presets = [1.0, 1.25, 1.5, 1.75, 2.0];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in presets)
          Pressable(
            onTap: () {
              setState(() => scale = p);
              widget.onUiScale(p);
            },
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: (scale - p).abs() < 0.01
                      ? Palette.answer(dark)
                      : Palette.hairline(dark),
                ),
              ),
              child: Text(
                '${(p * 100).round()}%',
                style: TextStyle(
                  fontSize: 10.5,
                  color: (scale - p).abs() < 0.01
                      ? Palette.answer(dark)
                      : Palette.faint(dark),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
