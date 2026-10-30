import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/document.dart';
import 'data/rates.dart';
import 'engine/engine.dart';
import 'ui/editor_view.dart';
import 'ui/feedback.dart';
import 'ui/formatting.dart';
import 'ui/marked_controller.dart';
import 'ui/settings_sheet.dart';
import 'ui/sidebar.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TallynoteApp());
}

class TallynoteApp extends StatefulWidget {
  const TallynoteApp({super.key});

  @override
  State<TallynoteApp> createState() => _AppState();
}

class _AppState extends State<TallynoteApp> {
  final _store = DocumentStore();
  final _controller = MarkedController(dark: false);
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navKey = GlobalKey<NavigatorState>();

  late SheetEngine _engine;
  List<LineResult> _results = [];
  bool _dark = false;
  bool _sidebarOpen = true;
  bool _answersVisible = true;
  bool _autoRates = true;
  bool _steps = true;
  bool _syncing = false;
  Timer? _saveTimer;
  String? _boundSheetId;

  @override
  void initState() {
    super.initState();
    _engine = SheetEngine(rates: Rates.current);
    _controller.addListener(_onText);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final prefs = await SharedPreferences.getInstance();
    _dark = prefs.getBool('tallynote.dark') ?? false;
    _answersVisible = prefs.getBool('tallynote.answers') ?? true;
    _autoRates = prefs.getBool('tallynote.autoRates') ?? true;
    _steps = prefs.getBool('tallynote.steps') ?? true;

    await _store.load();
    _store.addListener(_onStore);
    _bindSheet();
    await Rates.load(allowNetwork: _autoRates);
    if (!mounted) return;
    setState(() {
      _engine = SheetEngine(rates: Rates.current);
      _recalc();
    });
  }

  void _onStore() {
    if (_store.activeId != _boundSheetId) _bindSheet();
  }

  void _bindSheet() {
    final sheet = _store.active;
    if (sheet == null) return;
    _boundSheetId = sheet.id;
    _syncing = true;
    _controller.text = sheet.content;
    _syncing = false;
    _recalc();
  }

  void _onText() {
    _recalc();
    if (_syncing) return;
    final id = _store.activeId;
    if (id == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      final firstLine = _controller.text
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .replaceAll(RegExp(r'^#\s*'), '')
          .trim();
      final sheet = _store.sheets.where((x) => x.id == id).firstOrNull;
      _store.update(
        id,
        content: _controller.text,
        title: sheet?.customTitle == true
            ? null
            : (firstLine.length > 34 ? firstLine.substring(0, 34) : firstLine),
      );
    });
  }

  void _recalc() {
    // markers are presentation only: the engine sees plain arithmetic
    final lines = _controller.text
        .split('\n')
        .map(Fmt.stripMarkers)
        .toList(growable: false);
    _results = _engine.evaluate(lines);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.dispose();
    _store.dispose();
    super.dispose();
  }

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tallynote.dark', _dark);
    await prefs.setBool('tallynote.answers', _answersVisible);
    await prefs.setBool('tallynote.autoRates', _autoRates);
    await prefs.setBool('tallynote.steps', _steps);
  }

  bool get _hasSelection =>
      _controller.selection.isValid && !_controller.selection.isCollapsed;

  void _format(String open, String close) {
    final sel = _controller.selection;
    if (!_hasSelection) return;
    final (text, selection) = Fmt.wrap(_controller.text, sel, open, close);
    _controller.value = TextEditingValue(text: text, selection: selection);
  }

  @override
  Widget build(BuildContext context) {
    _controller.dark = _dark;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final theme = buildTheme(_dark);

    final sidebar = Sidebar(
      store: _store,
      dark: _dark,
      onClose: wide ? _toggleSidebar : () => Navigator.of(context).maybePop(),
    );

    return MaterialApp(
      title: 'Tallynote',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      theme: theme,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.backslash, meta: true):
              _toggleSidebar,
          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
              _toggleSidebar,
          const SingleActivator(
            LogicalKeyboardKey.keyA,
            meta: true,
            shift: true,
          ): () {
            setState(() => _answersVisible = !_answersVisible);
            _saveSettings();
          },
          const SingleActivator(
            LogicalKeyboardKey.keyA,
            control: true,
            shift: true,
          ): () {
            setState(() => _answersVisible = !_answersVisible);
            _saveSettings();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: _scaffoldKey,
            drawer: wide ? null : Drawer(child: SafeArea(child: sidebar)),
            body: SafeArea(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide && _sidebarOpen) ...[
                    sidebar,
                    VerticalDivider(width: 1, color: Palette.hairline(_dark)),
                  ],
                  Expanded(
                    child: Column(
                      children: [
                        _Header(
                          dark: _dark,
                          sidebarOpen: _sidebarOpen && wide,
                          onMenu: wide
                              ? _toggleSidebar
                              : () => _scaffoldKey.currentState?.openDrawer(),
                          onSettings: () => showSettingsSheet(
                            context: _navKey.currentContext!,
                            dark: _dark,
                            answersVisible: _answersVisible,
                            autoRates: _autoRates,
                            steps: _steps,
                            onAnswers: (v) {
                              setState(() => _answersVisible = v);
                              _saveSettings();
                            },
                            onTheme: (v) {
                              setState(() => _dark = v);
                              _saveSettings();
                            },
                            onAutoRates: (v) {
                              setState(() => _autoRates = v);
                              _saveSettings();
                            },
                            onSteps: (v) {
                              setState(() => _steps = v);
                              _saveSettings();
                            },
                            onRefreshRates: () async {
                              final ok = await Rates.refresh();
                              if (!mounted) return false;
                              setState(() {
                                _engine = SheetEngine(rates: Rates.current);
                                _recalc();
                              });
                              return ok;
                            },
                          ),
                        ),
                        Divider(height: 1, color: Palette.hairline(_dark)),
                        if (_hasSelection)
                          _FormatBar(dark: _dark, onFormat: _format),
                        Expanded(
                          child: EditorView(
                            controller: _controller,
                            results: _results,
                            dark: _dark,
                            answersVisible: _answersVisible,
                            showSteps: _steps,
                            explain: _engine.explain,
                          ),
                        ),
                        _StatusBar(
                          dark: _dark,
                          lines: _controller.text.split('\n').length,
                          answers: _results
                              .where((r) => r.display != null)
                              .length,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool dark;
  final bool sidebarOpen;
  final VoidCallback onMenu;
  final VoidCallback onSettings;

  const _Header({
    required this.dark,
    required this.sidebarOpen,
    required this.onMenu,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              iconSize: 18,
              tooltip: 'Sheets  ⌘\\',
              onPressed: onMenu,
              icon: Icon(
                sidebarOpen ? Icons.keyboard_double_arrow_left : Icons.menu,
                color: Palette.faint(dark),
              ),
            ),
            const Spacer(),
            _IconAction(
              icon: Icons.tune,
              tooltip: 'Settings',
              dark: dark,
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool dark;
  final VoidCallback onTap;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 17,
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: Palette.faint(dark)),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final bool dark;
  final int lines;
  final int answers;

  const _StatusBar({
    required this.dark,
    required this.lines,
    required this.answers,
  });

  @override
  Widget build(BuildContext context) {
    final rateDate = Rates.updatedDate ?? 'built-in';
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Palette.hairline(dark))),
      ),
      child: Row(
        children: [
          Text(
            '$lines lines · $answers answers',
            style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
          ),
          const Spacer(),
          Text(
            'rates $rateDate',
            style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
          ),
        ],
      ),
    );
  }
}

class _FormatBar extends StatelessWidget {
  final bool dark;
  final void Function(String open, String close) onFormat;

  const _FormatBar({required this.dark, required this.onFormat});

  @override
  Widget build(BuildContext context) {
    Widget btn(String label, TextStyle style, String open, String close) =>
        Pressable(
          onTap: () => onFormat(open, close),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(label, style: style.copyWith(color: Palette.fg(dark))),
          ),
        );

    final base = TextStyle(fontSize: 13, fontFamily: monoFamily);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.hairline(dark))),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          btn('B', base.copyWith(fontWeight: FontWeight.w700), '**', '**'),
          btn('I', base.copyWith(fontStyle: FontStyle.italic), '_', '_'),
          btn(
            'S',
            base.copyWith(decoration: TextDecoration.lineThrough),
            '~~',
            '~~',
          ),
          btn(
            'U',
            base.copyWith(decoration: TextDecoration.underline),
            '__',
            '__',
          ),
          const SizedBox(width: 6),
          for (final entry in Fmt.colours.entries)
            Pressable(
              onTap: () => onFormat('{${entry.key}}', '{/}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          const Spacer(),
          Text(
            'selection',
            style: TextStyle(fontSize: 10, color: Palette.faint(dark)),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }
}
