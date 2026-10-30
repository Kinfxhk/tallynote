import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/data/document.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

void main() {
  const key = 'tallynote.sheets.v1';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('folders hold sheets and survive a reload', () async {
    final store = DocumentStore();
    await store.load();

    final work = store.createFolder('Work');
    final sheet = store.create(folderId: work.id);
    store.update(sheet.id, title: 'Q4 budget', content: '2000+3000');

    expect(store.inFolder(work.id).single.id, sheet.id);
    expect(store.inFolder(null).every((s) => s.folderId == null), isTrue);

    final again = DocumentStore();
    await again.load();
    expect(again.folders.single.name, 'Work');
    expect(again.inFolder(work.id).single.title, 'Q4 budget');
  });

  test('deleting a folder keeps its sheets, unfiled', () async {
    final store = DocumentStore();
    await store.load();
    final f = store.createFolder('Temp');
    final s = store.create(folderId: f.id);

    store.deleteFolder(f.id);
    expect(store.folders, isEmpty);
    expect(store.sheets.firstWhere((x) => x.id == s.id).folderId, isNull);
    expect(store.inFolder(null).map((x) => x.id), contains(s.id));
  });

  test('moving a sheet between folders', () async {
    final store = DocumentStore();
    await store.load();
    final a = store.createFolder('A');
    final b = store.createFolder('B');
    final s = store.create();

    store.moveSheet(s.id, a.id);
    expect(store.inFolder(a.id).length, 1);
    store.moveSheet(s.id, b.id);
    expect(store.inFolder(a.id), isEmpty);
    expect(store.inFolder(b.id).length, 1);
    store.moveSheet(s.id, null);
    expect(store.inFolder(null).map((x) => x.id), contains(s.id));
  });

  test('pinned sheets sort first, rename sticks', () async {
    final store = DocumentStore();
    await store.load();
    final a = store.create();
    store.update(a.id, title: 'Older', content: '1');
    final b = store.create();
    store.update(b.id, title: 'Newer', content: '2');

    expect(store.inFolder(null).first.id, b.id);
    store.togglePin(a.id);
    expect(store.inFolder(null).first.id, a.id);

    store.rename(a.id, 'Budget 2027');
    final again = DocumentStore();
    await again.load();
    final reloaded = again.sheets.firstWhere((x) => x.id == a.id);
    expect(reloaded.title, 'Budget 2027');
    expect(reloaded.customTitle, isTrue);
    expect(reloaded.pinned, isTrue);
  });

  test('search matches title and body', () async {
    final store = DocumentStore();
    await store.load();
    final x = store.create();
    store.update(x.id, title: 'Tokyo trip', content: 'flights 4280');
    final y = store.create();
    store.update(y.id, title: 'Rent', content: 'rent = 2500');

    expect(store.search('tokyo').single.id, x.id);
    expect(store.search('4280').single.id, x.id);
    expect(store.search('RENT').length, 1);
    expect(store.search('nothing here'), isEmpty);
  });

  testWidgets('sidebar shows folders with their sheets', (tester) async {
    final seed = jsonEncode({
      'v': 2,
      'folders': [
        {'id': 'f1', 'name': 'Work'},
      ],
      'sheets': [
        {
          'id': 's1',
          'title': 'Q4 budget',
          'content': '1+1',
          'folderId': 'f1',
          'updated': '2026-10-30T00:00:00.000Z',
        },
        {
          'id': 's2',
          'title': 'Loose note',
          'content': '2+2',
          'folderId': null,
          'updated': '2026-10-30T00:00:00.000Z',
        },
      ],
    });
    SharedPreferences.setMockInitialValues({key: seed});

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Q4 budget'), findsOneWidget);
    expect(find.text('Loose note'), findsOneWidget);
    expect(find.text('Unfiled'), findsOneWidget);

    // tapping a sheet through Pressable still selects and loads it
    await tester.tap(find.text('Q4 budget'));
    await tester.pump(const Duration(milliseconds: 60));
    final editor = tester.widget<TextField>(
      find.descendant(
        of: find.byType(EditorView),
        matching: find.byType(TextField),
      ),
    );
    expect(editor.controller?.text, '1+1');
  });

  test('a v1 sheet list still loads', () async {
    final legacy = jsonEncode([
      {'id': 'a1', 'title': 'Old', 'content': '1+1', 'updated': '2026-01-01'},
    ]);
    SharedPreferences.setMockInitialValues({key: legacy});

    final store = DocumentStore();
    await store.load();
    expect(store.sheets.single.title, 'Old');
    expect(store.folders, isEmpty);
    expect(store.sheets.single.folderId, isNull);
  });
}
