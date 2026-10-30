import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/document.dart';
import 'data/rates.dart';
import 'engine/engine.dart';
import 'ui/editor_view.dart';
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
  final _controller = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late SheetEngine _engine;
  List<LineResult> _results = [];
  bool _dark = false;
  bool _sidebarOpen = true;
  bool _answersVisible = true;
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
    await _store.load();
    _store.addListener(_onStore);
    _bindSheet();
    await Rates.load();
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
      _store.update(
        id,
        content: _controller.text,
        title: firstLine.length > 34 ? firstLine.substring(0, 34) : firstLine,
      );
    });
  }

  void _recalc() {
    final lines = _controller.text.split('\n');
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

  @override
  Widget build(BuildContext context) {
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
      theme: theme,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.backslash, meta: true):
              _toggleSidebar,
          const SingleActivator(LogicalKeyboardKey.backslash, control: true):
              _toggleSidebar,
          const SingleActivator(LogicalKeyboardKey.keyA,
              meta: true, shift: true): () {
            setState(() => _answersVisible = !_answersVisible);
          },
          const SingleActivator(LogicalKeyboardKey.keyA,
              control: true, shift: true): () {
            setState(() => _answersVisible = !_answersVisible);
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
                          answersVisible: _answersVisible,
                          onMenu: wide
                              ? _toggleSidebar
                              : () => _scaffoldKey.currentState?.openDrawer(),
                          onToggleAnswers: () =>
                              setState(() => _answersVisible = !_answersVisible),
                          onToggleTheme: () => setState(() => _dark = !_dark),
                          onRefreshRates: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await Rates.refresh();
                            if (!mounted) return;
                            setState(() {
                              _engine = SheetEngine(rates: Rates.current);
                              _recalc();
                            });
                            if (!ok) {
                              messenger.showSnackBar(
                                const SnackBar(
                                    content:
                                        Text('Offline — kept the last rates')),
                              );
                            }
                          },
                        ),
                        Divider(height: 1, color: Palette.hairline(_dark)),
                        Expanded(
                          child: EditorView(
                            controller: _controller,
                            results: _results,
                            dark: _dark,
                            answersVisible: _answersVisible,
                          ),
                        ),
                        _StatusBar(
                          dark: _dark,
                          lines: _controller.text.split('\n').length,
                          answers:
                              _results.where((r) => r.display != null).length,
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
  final bool answersVisible;
  final VoidCallback onMenu;
  final VoidCallback onToggleAnswers;
  final VoidCallback onToggleTheme;
  final VoidCallback onRefreshRates;

  const _Header({
    required this.dark,
    required this.sidebarOpen,
    required this.answersVisible,
    required this.onMenu,
    required this.onToggleAnswers,
    required this.onToggleTheme,
    required this.onRefreshRates,
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
              icon: answersVisible
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              tooltip: 'Answers  ⌘⇧A',
              dark: dark,
              onTap: onToggleAnswers,
            ),
            _IconAction(
              icon: Icons.currency_exchange,
              tooltip: 'Refresh rates',
              dark: dark,
              onTap: onRefreshRates,
            ),
            _IconAction(
              icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              tooltip: 'Theme',
              dark: dark,
              onTap: onToggleTheme,
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
          Text('$lines lines · $answers answers',
              style: TextStyle(fontSize: 11, color: Palette.faint(dark))),
          const Spacer(),
          Text('rates $rateDate',
              style: TextStyle(fontSize: 11, color: Palette.faint(dark))),
        ],
      ),
    );
  }
}
