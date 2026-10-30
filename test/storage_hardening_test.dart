import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/data/document.dart';
import 'package:tallynote/main.dart';
import 'package:tallynote/ui/editor_view.dart';

/// A kill, a background app or a damaged store must not cost the user text.
const _key = 'tallynote.sheets.v1';
const _bak = 'tallynote.sheets.v1.bak';

void main() {
  Finder editorField() => find.descendant(
    of: find.byType(EditorView),
    matching: find.byType(TextField),
  );

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  /// Mock pref writes settle on microtasks; a bare read can beat them.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Future<List<String>> storedContents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final doc = jsonDecode(raw);
    final sheets = (doc is Map ? doc['sheets'] : doc) as List;
    return [for (final s in sheets) (s as Map)['content'] as String? ?? ''];
  }

  /// The binding only accepts the real transition order.
  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final s in states) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  testWidgets('leaving the app flushes an edit still inside the debounce', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);

    await tester.enterText(editorField(), 'typed then backgrounded');
    await tester.pump(const Duration(milliseconds: 50)); // inside 400 ms
    expect(await storedContents(), isNot(contains('typed then backgrounded')));

    lifecycle(tester, [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await settle(tester);

    expect(await storedContents(), contains('typed then backgrounded'));

    lifecycle(tester, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('closing the window flushes an edit still inside the debounce', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await boot(tester);

    await tester.enterText(editorField(), 'typed then closed');
    await tester.pump(const Duration(milliseconds: 50));

    await tester.pumpWidget(const SizedBox()); // dispose with the timer pending
    await settle(tester);

    expect(await storedContents(), contains('typed then closed'));
  });

  testWidgets('a corrupt store is kept and never overwritten', (tester) async {
    const damaged = '{"v":2,"sheets":[{"id":"a","content":"half a doc';
    SharedPreferences.setMockInitialValues({_key: damaged});
    await boot(tester);

    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_bak), damaged, reason: 'the copy is kept');

    await tester.enterText(editorField(), '1+1');
    await tester.pump(const Duration(milliseconds: 600));

    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_key), damaged, reason: 'not overwritten');
    expect(prefs.getString(_bak), damaged);
  });

  test('a document that breaks halfway keeps its whole copy', () async {
    // the second sheet has no id: decoding dies after the first one was read
    const damaged =
        '{"v":2,"folders":[],"sheets":['
        '{"id":"a","content":"the only copy"},{"title":"no id"}]}';
    SharedPreferences.setMockInitialValues({_key: damaged});
    final store = DocumentStore();
    await store.load();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_bak), damaged);
    expect(
      store.sheets.map((s) => s.content),
      isNot(contains('the only copy')),
      reason: 'half a document is not a document',
    );

    store.update(store.sheets.first.id, content: 'new text');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.getString(_key), damaged, reason: 'refuses to overwrite it');
  });
}
