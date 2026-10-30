import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/document.dart';
import 'feedback.dart';
import 'theme.dart';

class Sidebar extends StatefulWidget {
  final DocumentStore store;
  final bool dark;
  final VoidCallback onClose;
  final ValueListenable<bool>? wheelBlocked;
  final FocusNode? searchFocus;

  const Sidebar({
    super.key,
    required this.store,
    required this.dark,
    required this.onClose,
    this.wheelBlocked,
    this.searchFocus,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _collapsed = <String>{}; // folders default to open
  final _search = TextEditingController();
  var _query = '';
  var _unfiledOpen = true;

  bool get _dark => widget.dark;
  DocumentStore get _store => widget.store;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final matches = searching ? _store.search(_query) : const <Sheet>[];
    final unfiled = _store.inFolder(null);

    return Container(
      width: 250,
      color: _dark ? const Color(0xFF141517) : const Color(0xFFF3F1EC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 4),
            child: Row(
              children: [
                Text(
                  'Tallynote',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                    color: Palette.faint(_dark),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Collapse sidebar  ⌘\\',
                  iconSize: 18,
                  onPressed: widget.onClose,
                  icon: Icon(
                    Icons.keyboard_double_arrow_left,
                    color: Palette.faint(_dark),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: TextField(
              controller: _search,
              focusNode: widget.searchFocus,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(fontSize: 12.5, color: Palette.fg(_dark)),
              cursorColor: Palette.answer(_dark),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search sheets',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: Palette.faint(_dark),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  size: 15,
                  color: Palette.faint(_dark),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 20,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          Divider(height: 1, color: Palette.hairline(_dark)),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.wheelBlocked ?? _neverSide,
              builder: (context, blocked, _) => ListView(
                physics: blocked ? const NeverScrollableScrollPhysics() : null,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: searching
                    ? [
                        if (matches.isEmpty) _note('No matches'),
                        for (final s in matches)
                          _sheetTile(s, showFolder: true),
                      ]
                    : [
                        for (final f in _store.folders) ...[
                          _folderRow(f),
                          if (!_collapsed.contains(f.id))
                            for (final s in _store.inFolder(f.id))
                              _sheetTile(s),
                        ],
                        if (unfiled.isNotEmpty) ...[
                          _unfiledRow(unfiled.length),
                          if (_unfiledOpen || _store.folders.isEmpty)
                            for (final s in unfiled) _sheetTile(s),
                        ],
                      ],
              ),
            ),
          ),
          Divider(height: 1, color: Palette.hairline(_dark)),
          _action(
            icon: Icons.add,
            label: 'New sheet',
            onTap: () => _store.create(),
          ),
          _action(
            icon: Icons.create_new_folder_outlined,
            label: 'New folder',
            onTap: _newFolder,
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ---- rows ----------------------------------------------------------------

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: Palette.faint(_dark)),
    ),
  );

  Widget _folderRow(Folder f) {
    final open = !_collapsed.contains(f.id);
    final count = _store.inFolder(f.id).length;
    return Pressable(
      onTap: () => setState(() {
        if (open) {
          _collapsed.add(f.id);
        } else {
          _collapsed.remove(f.id);
        }
      }),
      onLongPress: () => _folderMenu(f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
              size: 16,
              color: Palette.faint(_dark),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                f.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Palette.fg(_dark).withValues(alpha: 0.85),
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(fontSize: 11, color: Palette.faint(_dark)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unfiledRow(int count) {
    return Pressable(
      onTap: () => setState(() => _unfiledOpen = !_unfiledOpen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Icon(
              _unfiledOpen
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 16,
              color: Palette.faint(_dark),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Unfiled',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Palette.fg(_dark).withValues(alpha: 0.85),
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(fontSize: 11, color: Palette.faint(_dark)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetTile(Sheet s, {bool showFolder = false}) {
    final selected = s.id == _store.activeId;
    final folder = showFolder ? _store.folderOf(s) : null;
    return Pressable(
      onTap: () {
        _store.select(s.id);
        if (MediaQuery.sizeOf(context).width < 720) {
          Navigator.of(context).maybePop();
        }
      },
      onLongPress: () => _sheetMenu(s),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.fromLTRB(22, 7, 8, 7),
        decoration: BoxDecoration(
          color: selected
              ? (_dark ? const Color(0xFF232426) : const Color(0xFFE7E3DA))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (s.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 11,
                            color: Palette.answer(_dark),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          s.title.isEmpty ? 'Untitled' : s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: selected
                                ? Palette.fg(_dark)
                                : Palette.fg(_dark).withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (folder != null)
                    Text(
                      folder.name,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Palette.faint(_dark),
                      ),
                    ),
                ],
              ),
            ),
            Pressable(
              onTap: () => _sheetMenu(s),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(
                  Icons.more_horiz,
                  size: 15,
                  color: Palette.faint(_dark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Palette.faint(_dark)),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: Palette.faint(_dark)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- menus ---------------------------------------------------------------

  Future<void> _newFolder() async {
    final name = await _prompt('New folder', 'Name');
    if (name != null) {
      _store.createFolder(name);
      setState(() {});
    }
  }

  Future<void> _folderMenu(Folder f) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.bg(_dark),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuRow('Rename folder', () => Navigator.pop(ctx, 'rename')),
            _menuRow(
              'Delete folder (sheets stay)',
              () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'rename') {
      final name = await _prompt('Rename folder', 'Name', initial: f.name);
      if (name != null) _store.renameFolder(f.id, name);
    } else if (action == 'delete') {
      _store.deleteFolder(f.id);
      setState(() {});
    }
  }

  Future<void> _sheetMenu(Sheet s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.bg(_dark),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                s.title.isEmpty ? 'Sheet' : s.title,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                  color: Palette.faint(_dark),
                ),
              ),
            ),
            _menuRow('Rename…', () => Navigator.pop(ctx, 'rename')),
            _menuRow(
              s.pinned ? 'Unpin' : 'Pin to top',
              () => Navigator.pop(ctx, 'pin'),
            ),
            const Divider(height: 12),
            _menuRow('Unfiled', () => Navigator.pop(ctx, 'none')),
            for (final f in _store.folders)
              _menuRow(f.name, () => Navigator.pop(ctx, f.id)),
            const Divider(height: 12),
            _menuRow('Delete sheet', () => Navigator.pop(ctx, 'delete')),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'rename') {
      final name = await _prompt(
        'Rename sheet',
        'Name',
        initial: s.title.isEmpty ? 'Untitled' : s.title,
      );
      if (name != null) _store.rename(s.id, name);
    } else if (action == 'pin') {
      _store.togglePin(s.id);
    } else if (action == 'delete') {
      _store.delete(s.id);
    } else {
      _store.moveSheet(s.id, action == 'none' ? null : action);
    }
  }

  Widget _menuRow(String label, VoidCallback onTap) => Pressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        label,
        style: TextStyle(fontSize: 14, color: Palette.fg(_dark)),
      ),
    ),
  );

  Future<String?> _prompt(String title, String hint, {String? initial}) async {
    final c = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.bg(_dark),
        title: Text(
          title,
          style: TextStyle(fontSize: 15, color: Palette.fg(_dark)),
        ),
        content: TextField(
          controller: c,
          autofocus: true,
          style: TextStyle(color: Palette.fg(_dark)),
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: Palette.faint(_dark)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text('OK', style: TextStyle(color: Palette.answer(_dark))),
          ),
        ],
      ),
    );
    final text = (result ?? '').trim();
    return text.isEmpty ? null : text;
  }
}

final ValueNotifier<bool> _neverSide = ValueNotifier<bool>(false);
