import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/document.dart';
import 'data/rates.dart';
import 'engine/engine.dart';
import 'ui/editor_view.dart';
import 'ui/feedback.dart';
import 'ui/folding.dart';
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
  double _answerW = 212;
  double _uiScale = 1.0;
  bool _lineNumbers = true;
  bool _showTabs = true;
  final List<String> _tabs = [];

  /// Ctrl/Cmd held: the wheel zooms instead of scrolling.
  final ValueNotifier<bool> _zoomModifier = ValueNotifier(false);
  bool _zoomHud = false;
  Timer? _zoomHudTimer;

  bool _onKey(KeyEvent e) {
    final down =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (_zoomModifier.value != down) _zoomModifier.value = down;
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_zoomModifier.value) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _zoom(dy < 0 ? 1.1 : 1 / 1.1);
    });
  }

  /// non-null while a section is folded: the full document, set aside
  List<String>? _foldSource;
  Set<int> _foldedLines = {};
  List<int> _lineMap = const [];
  bool _signColours = true;
  String _posName = ''; // empty = the built-in paper-and-ink colours
  String _negName = '';
  bool _syncing = false;
  Timer? _saveTimer;
  String? _boundSheetId;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
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
    _answerW = prefs.getDouble('tallynote.answerWidth') ?? 212;
    _uiScale = prefs.getDouble('tallynote.uiScale') ?? 1.0;
    _lineNumbers = prefs.getBool('tallynote.lineNumbers') ?? true;
    _showTabs = prefs.getBool('tallynote.showTabs') ?? true;
    _signColours = prefs.getBool('tallynote.signColours') ?? true;
    _posName = prefs.getString('tallynote.posColour') ?? '';
    _negName = prefs.getString('tallynote.negColour') ?? '';

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
    final id = _store.activeId;
    if (id != null && !_tabs.contains(id)) _tabs.add(id);
    if (_tabs.length > 8) _tabs.removeAt(0);
    if (_store.activeId != _boundSheetId) _bindSheet();
  }

  void _closeTab(String id) {
    _tabs.remove(id);
    if (_store.activeId == id && _tabs.isNotEmpty) _store.select(_tabs.last);
    setState(() {});
  }

  void _zoom(double factor) => _setScale((_uiScale * factor).clamp(0.75, 2.5));

  void _setScale(double v) {
    setState(() {
      _uiScale = v.clamp(0.75, 2.5);
      _zoomHud = true;
    });
    _zoomHudTimer?.cancel();
    _zoomHudTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _zoomHud = false);
    });
    _saveSettings();
  }

  Set<int> get _foldable {
    final src = _foldSource ?? _controller.text.split('\n');
    return {
      for (var i = 0; i < src.length; i++)
        if (isHeading(src[i])) i,
    };
  }

  /// Fold or unfold the section that starts at [original].
  /// Folding swaps the visible text for a projection, so the editor is
  /// read-only until the section is opened again — nothing can be lost.
  void _toggleFold(int original) {
    final source = _foldSource ?? _controller.text.split('\n');
    final folded = Set<int>.from(_foldedLines);
    if (!folded.remove(original)) folded.add(original);

    if (folded.isEmpty) {
      _controller.text = source.join('\n');
      _foldSource = null;
      _foldedLines = {};
      _lineMap = List<int>.generate(source.length, (i) => i);
      _recalc();
      return;
    }

    final result = foldDocument(source, folded);
    _foldSource = source;
    _foldedLines = folded;
    _lineMap = result.map;
    _controller.text = result.visibleLines.join('\n');
    _recalc();
  }

  void _bindSheet() {
    final sheet = _store.active;
    if (sheet == null) return;
    _boundSheetId = sheet.id;
    _syncing = true;
    _foldSource = null;
    _foldedLines = {};
    _lineMap = const [];
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

  /// Dropping an answer appends a live reference; the engine keeps it fresh.
  void _insertReference(int line, String token) {
    final base = _controller.text;
    final sep = base.isEmpty || base.endsWith('\n') ? '' : '\n';
    final ref = token;
    final text = '$base$sep$ref';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
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
    HardwareKeyboard.instance.removeHandler(_onKey);
    _zoomModifier.dispose();
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
    await prefs.setDouble('tallynote.answerWidth', _answerW);
    await prefs.setDouble('tallynote.uiScale', _uiScale);
    await prefs.setBool('tallynote.lineNumbers', _lineNumbers);
    await prefs.setBool('tallynote.showTabs', _showTabs);
    await prefs.setBool('tallynote.signColours', _signColours);
    await prefs.setString('tallynote.posColour', _posName);
    await prefs.setString('tallynote.negColour', _negName);
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
    // each line only sees the names defined above it
    final labelsByLine = <Set<String>>[];
    final seen = <String>{};
    for (final r in _results) {
      labelsByLine.add(Set.of(seen));
      final label = r.display == null ? null : SheetEngine.labelOf(r.text);
      if (label != null) seen.add(label);
    }
    _controller.labelsByLine = labelsByLine;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final theme = buildTheme(_dark);

    final sidebar = Sidebar(
      store: _store,
      dark: _dark,
      wheelBlocked: _zoomModifier,
      onClose: wide ? _toggleSidebar : () => Navigator.of(context).maybePop(),
    );

    return MaterialApp(
      title: 'Tallynote',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        final s = _uiScale;
        if ((s - 1).abs() < 0.01) return child;
        final mq = MediaQuery.of(context);
        final logical = mq.size / s;
        // OverflowBox pins the child to the reduced logical size; the transform
        // then paints it back to exactly one screen, so nothing spills out and
        // no gap is left behind.
        return ColoredBox(
          color: Palette.bg(_dark),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: logical.width,
              maxWidth: logical.width,
              minHeight: logical.height,
              maxHeight: logical.height,
              child: Transform.scale(
                key: const ValueKey('ui-zoom'),
                scale: s,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: logical.width,
                  height: logical.height,
                  child: MediaQuery(
                    data: mq.copyWith(
                      size: logical,
                      padding: mq.padding / s,
                      viewPadding: mq.viewPadding / s,
                      viewInsets: mq.viewInsets / s,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      navigatorKey: _navKey,
      theme: theme,
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
              _zoom(1.25),
          const SingleActivator(LogicalKeyboardKey.equal, control: true): () =>
              _zoom(1.25),
          const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
              _zoom(0.8),
          const SingleActivator(LogicalKeyboardKey.minus, control: true): () =>
              _zoom(0.8),
          const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
            setState(() => _uiScale = 1.0);
            _saveSettings();
          },
          const SingleActivator(LogicalKeyboardKey.digit0, control: true): () {
            setState(() => _uiScale = 1.0);
            _saveSettings();
          },
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
              _store.create(),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              _store.create(),
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
          child: Listener(
            onPointerSignal: _onPointerSignal,
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
                            showMenu: !(wide && _sidebarOpen),
                            onMenu: wide
                                ? _toggleSidebar
                                : () => _scaffoldKey.currentState?.openDrawer(),
                            onSettings: () => showSettingsSheet(
                              context: _navKey.currentContext!,
                              dark: _dark,
                              answersVisible: _answersVisible,
                              autoRates: _autoRates,
                              steps: _steps,
                              signColours: _signColours,
                              lineNumbers: _lineNumbers,
                              showTabs: _showTabs,
                              uiScale: _uiScale,
                              posName: _posName,
                              negName: _negName,
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
                              onSignColours: (v) {
                                setState(() => _signColours = v);
                                _saveSettings();
                              },
                              onPosColour: (name) {
                                setState(() => _posName = name);
                                _saveSettings();
                              },
                              onNegColour: (name) {
                                setState(() => _negName = name);
                                _saveSettings();
                              },
                              onLineNumbers: (v) {
                                setState(() => _lineNumbers = v);
                                _saveSettings();
                              },
                              onShowTabs: (v) {
                                setState(() => _showTabs = v);
                                _saveSettings();
                              },
                              onUiScale: (v) {
                                setState(() => _uiScale = v);
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
                          if (_showTabs && _tabs.length > 1)
                            _TabBar(
                              dark: _dark,
                              tabs: _tabs,
                              activeId: _store.activeId,
                              titleOf: (id) {
                                final s = _store.sheets
                                    .where((x) => x.id == id)
                                    .firstOrNull;
                                return s == null || s.title.isEmpty
                                    ? 'Untitled'
                                    : s.title;
                              },
                              onSelect: _store.select,
                              onClose: _closeTab,
                            ),
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: EditorView(
                                    controller: _controller,
                                    results: _results,
                                    dark: _dark,
                                    answersVisible: _answersVisible,
                                    showSteps: _steps,
                                    explain: _engine.explain,
                                    answerWidth: _answerW,
                                    scale: 1,
                                    wheelBlocked: _zoomModifier,
                                    showLineNumbers: _lineNumbers,
                                    onInsertReference: _insertReference,
                                    lineMap: _lineMap,
                                    foldable: _foldable,
                                    folded: _foldedLines,
                                    onToggleFold: _toggleFold,
                                    readOnly: _foldSource != null,
                                    signColours: _signColours,
                                    positiveColour: _posName.isEmpty
                                        ? null
                                        : Fmt.colours[_posName],
                                    negativeColour: _negName.isEmpty
                                        ? null
                                        : Fmt.colours[_negName],
                                    onAnswerWidth: (w) {
                                      setState(() => _answerW = w);
                                      _saveSettings();
                                    },
                                  ),
                                ),
                                if (_zoomHud)
                                  Positioned(
                                    right: 18,
                                    bottom: 18,
                                    child: _ZoomHud(
                                      dark: _dark,
                                      scale: _uiScale,
                                      onMinus: () => _zoom(1 / 1.1),
                                      onPlus: () => _zoom(1.1),
                                      onReset: () => _setScale(1.0),
                                    ),
                                  ),
                                if (_hasSelection)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 14,
                                    child: Center(
                                      child: _FormatBar(
                                        dark: _dark,
                                        onFormat: _format,
                                      ),
                                    ),
                                  ),
                                if (_answersVisible)
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    right: _answerW + 24 - 5,
                                    width: 10,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.resizeColumn,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragUpdate: (d) {
                                          final widest = _results
                                              .map(
                                                (r) => r.display?.length ?? 0,
                                              )
                                              .fold<int>(
                                                0,
                                                (a, b) => a > b ? a : b,
                                              );
                                          final minW = (widest * 9.2 + 60)
                                              .clamp(140.0, 520.0);
                                          setState(
                                            () => _answerW =
                                                (_answerW - d.delta.dx).clamp(
                                                  minW,
                                                  520.0,
                                                ),
                                          );
                                        },
                                        onHorizontalDragEnd: (_) =>
                                            _saveSettings(),
                                        onDoubleTap: () {
                                          final widest = _results
                                              .map(
                                                (r) => r.display?.length ?? 0,
                                              )
                                              .fold<int>(
                                                0,
                                                (a, b) => a > b ? a : b,
                                              );
                                          setState(
                                            () => _answerW = (widest * 9.2 + 44)
                                                .clamp(140.0, 520.0),
                                          );
                                          _saveSettings();
                                        },
                                        child: Center(
                                          child: Container(
                                            width: 1,
                                            color: Palette.hairline(_dark),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool dark;
  final bool sidebarOpen;

  /// The sidebar carries its own collapse control, so the header only shows a
  /// menu button when the sidebar is actually hidden.
  final bool showMenu;
  final VoidCallback onMenu;
  final VoidCallback onSettings;

  const _Header({
    required this.dark,
    required this.sidebarOpen,
    required this.showMenu,
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
            if (showMenu)
              IconButton(
                iconSize: 18,
                tooltip: 'Sheets  ⌘\\',
                onPressed: onMenu,
                icon: Icon(Icons.menu, color: Palette.faint(dark)),
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
          Flexible(
            child: Text(
              '$lines lines · $answers answers',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'rates $rateDate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: Palette.faint(dark)),
            ),
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
    // a floating card: showing it must not reflow the text above
    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Palette.bg(dark),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Palette.hairline(dark)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 9,
                  ),
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
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final bool dark;
  final List<String> tabs;
  final String? activeId;
  final String Function(String id) titleOf;
  final void Function(String id) onSelect;
  final void Function(String id) onClose;

  const _TabBar({
    required this.dark,
    required this.tabs,
    required this.activeId,
    required this.titleOf,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.hairline(dark))),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final id in tabs)
            Pressable(
              onTap: () => onSelect(id),
              padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
              child: Row(
                children: [
                  Text(
                    titleOf(id),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: id == activeId
                          ? Palette.fg(dark)
                          : Palette.faint(dark),
                    ),
                  ),
                  Pressable(
                    onTap: () => onClose(id),
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      Icons.close,
                      size: 11,
                      color: Palette.faint(dark),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomHud extends StatelessWidget {
  final bool dark;
  final double scale;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onReset;

  const _ZoomHud({
    required this.dark,
    required this.scale,
    required this.onMinus,
    required this.onPlus,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tip, VoidCallback tap) => Pressable(
      onTap: tap,
      padding: const EdgeInsets.all(7),
      child: Tooltip(
        message: tip,
        child: Icon(icon, size: 15, color: Palette.fg(dark)),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Palette.bg(dark),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Palette.hairline(dark)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.remove, 'Zoom out  ⌘−', onMinus),
            SizedBox(
              width: 46,
              child: Text(
                '${(scale * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontFeatures: const [],
                  color: Palette.fg(dark),
                ),
              ),
            ),
            button(Icons.add, 'Zoom in  ⌘=', onPlus),
            Container(width: 1, height: 16, color: Palette.hairline(dark)),
            button(Icons.restart_alt, 'Reset to 100%  ⌘0', onReset),
          ],
        ),
      ),
    );
  }
}
