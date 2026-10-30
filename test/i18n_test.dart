import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tallynote/i18n/strings.dart';
import 'package:tallynote/main.dart';

void main() {
  test('every language has every key', () {
    final en = <String>{};
    final zhHant = <String>{};
    final zhHans = <String>{};
    for (final key in const ['newSheet', 'unfiled', 'editor', 'privacy']) {
      en.add(key);
      zhHant.add(key);
      zhHans.add(key);
    }
    for (final key in en) {
      expect(T.of('en', key), isNot(key), reason: 'en missing $key');
      expect(T.of('zh_Hant', key), isNot(key), reason: 'zh_Hant missing $key');
      expect(T.of('zh_Hans', key), isNot(key), reason: 'zh_Hans missing $key');
    }
  });

  test('lookups and placeholders', () {
    expect(T.of('en', 'newSheet'), 'New sheet');
    expect(T.of('zh_Hant', 'newSheet'), '新記事');
    expect(T.of('zh_Hans', 'newSheet'), '新笔记');
    expect(T.format('zh_Hant', 'linesAnswers', {'lines': '3', 'answers': '2'}),
        '3 行 · 2 個答案');
    // unknown keys fall back to the key itself rather than crashing
    expect(T.of('en', 'nope'), 'nope');
  });

  testWidgets('switching language changes the sidebar', (tester) async {
    SharedPreferences.setMockInitialValues({'tallynote.locale': 'en'});
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const TallynoteApp());
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('New sheet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('繁'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last); // Done
    await tester.pumpAndSettle();

    expect(find.text('新記事'), findsOneWidget);
    expect(find.text('New sheet'), findsNothing);
  });
}
