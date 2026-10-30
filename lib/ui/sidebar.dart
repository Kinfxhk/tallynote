import 'package:flutter/material.dart';

import '../data/document.dart';
import 'theme.dart';

class Sidebar extends StatelessWidget {
  final DocumentStore store;
  final bool dark;
  final VoidCallback onClose;

  const Sidebar({
    super.key,
    required this.store,
    required this.dark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 236,
      color: dark ? const Color(0xFF141517) : const Color(0xFFF3F1EC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  'Tallynote',
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                    color: Palette.faint(dark),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Collapse sidebar  ⌘\\',
                  iconSize: 18,
                  onPressed: onClose,
                  icon: Icon(
                    Icons.keyboard_double_arrow_left,
                    color: Palette.faint(dark),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final s in store.sheets)
                  _SheetTile(
                    sheet: s,
                    selected: s.id == store.activeId,
                    dark: dark,
                    onTap: () {
                      store.select(s.id);
                      if (MediaQuery.sizeOf(context).width < 720) {
                        Navigator.of(context).maybePop();
                      }
                    },
                    onDelete: store.sheets.length > 1
                        ? () => store.delete(s.id)
                        : null,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          InkWell(
            onTap: store.create,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.add, size: 16, color: Palette.faint(dark)),
                  const SizedBox(width: 8),
                  Text(
                    'New sheet',
                    style: TextStyle(fontSize: 13, color: Palette.faint(dark)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final Sheet sheet;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _SheetTile({
    required this.sheet,
    required this.selected,
    required this.dark,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? (dark ? const Color(0xFF232426) : const Color(0xFFE7E3DA))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                sheet.title.isEmpty ? 'Untitled' : sheet.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? Palette.fg(dark)
                      : Palette.fg(dark).withValues(alpha: 0.75),
                ),
              ),
            ),
            if (onDelete != null && selected)
              InkWell(
                onTap: onDelete,
                child: Icon(Icons.close, size: 14, color: Palette.faint(dark)),
              ),
          ],
        ),
      ),
    );
  }
}
