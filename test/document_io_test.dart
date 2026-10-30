import 'package:flutter_test/flutter_test.dart';
import 'package:tallynote/data/document.dart';
import 'package:tallynote/engine/engine.dart';
import 'package:tallynote/io/document_io.dart';

void main() {
  Sheet sheet(String title, String content, {String? folder}) =>
      Sheet(id: 's-$title', title: title, content: content, folderId: folder);

  group('json', () {
    test('round-trips sheets and folders', () {
      final json = DocumentIo.libraryJson(
        [sheet('Budget', '2000+3000')],
        [Folder(id: 'f1', name: 'Work')],
        now: DateTime.utc(2026, 10, 30, 12),
      );
      final back = DocumentIo.parse(json);
      expect(back.sheets.single.title, 'Budget');
      expect(back.sheets.single.content, '2000+3000');
      expect(back.folders.single.name, 'Work');
      expect(json, contains('"app": "tallynote"'));
      expect(json, contains('2026-10-30T12:00:00.000Z'));
    });

    test('a single sheet is still a valid document', () {
      final back = DocumentIo.parse(DocumentIo.sheetJson(sheet('One', '1+1')));
      expect(back.sheets.single.title, 'One');
      expect(back.folders, isEmpty);
    });

    test('accepts the old bare-list shape', () {
      final back = DocumentIo.parse('[{"id":"a","title":"Old","content":"1"}]');
      expect(back.sheets.single.title, 'Old');
    });

    test('rejects junk instead of importing an empty library', () {
      expect(() => DocumentIo.parse('hello'), throwsFormatException);
      expect(() => DocumentIo.parse('{"sheets":[]}'), throwsFormatException);
    });
  });

  group('exports', () {
    final engine = SheetEngine(
      rates: const {'USD': 1, 'HKD': 7.8},
      now: DateTime(2026, 10, 30),
    );
    final sheets = [
      sheet('Budget', 'rent = 2500\nfood 400\nrent + food\n# note line'),
    ];

    test('markdown keeps prose and shows answers', () {
      final md = DocumentIo.markdown(sheets, engine);
      expect(md, startsWith('# Budget'));
      expect(md, contains('rent + food  →  2,900'));
      expect(md, contains('# note line'));
    });

    test('csv quotes and only lists answered lines', () {
      final out = DocumentIo.csv(sheets, engine);
      final lines = out.trim().split('\n');
      expect(lines.first, '"sheet","line","input","answer","error"');
      expect(out, contains('"Budget","1","rent = 2500","2,500",""'));
      expect(lines.any((l) => l.startsWith('"Budget","5"')), isFalse);
    });

    test('plain text lines up answers', () {
      final txt = DocumentIo.plainText(sheets, engine);
      expect(txt, contains('Budget'));
      expect(txt, contains('2,900'));
    });
  });

  group('file names', () {
    test('are dated, safe, and keep CJK', () {
      final n = DocumentIo.fileName(
        'Tradeify P&L / 月報',
        DateTime(2026, 10, 30, 9, 5),
        'tallynote',
      );
      expect(n, 'Tradeify-PL-月報-2026-10-30-0905.tallynote');
      expect(
        DocumentIo.fileName('', DateTime(2026, 1, 2, 3, 4), 'md'),
        'tallynote-2026-01-02-0304.md',
      );
    });
  });
}
