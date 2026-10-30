import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/document.dart';
import '../engine/engine.dart';
import 'document_io.dart';

/// Platform-facing file verbs. Everything that needs a dialog or a plugin lives
/// here; the text building stays in [DocumentIo] so it can be tested.
class FileActions {
  /// Returns the picked document text, or null when the user cancels.
  static Future<String?> openDocument() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['tallynote', 'json'],
    );
    if (files.isEmpty) return null;
    // xFile works on every platform, including the web blob
    return files.first.xFile.readAsString();
  }

  /// Writes [content] where the user says. Returns false when cancelled.
  static Future<bool> saveAs({
    required String fileName,
    required String content,
    required String extension,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: _mimeFor(extension),
      dialogTitle: 'Save $fileName',
    );
    return uri != null;
  }

  static String _mimeFor(String ext) => switch (ext) {
    'md' => 'text/markdown',
    'csv' => 'text/csv',
    'txt' => 'text/plain',
    'json' || 'tallynote' => 'application/json',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };

  /// A4 PDF, monospace, one sheet per page, answers right-aligned.
  static Future<void> printSheets(
    List<Sheet> sheets,
    SheetEngine engine, {
    bool print = true,
  }) async {
    final doc = await _buildPdf(sheets, engine);
    if (print) {
      await Printing.layoutPdf(onLayout: (_) async => doc, name: 'Tallynote');
    } else {
      await Printing.sharePdf(bytes: doc, filename: 'tallynote.pdf');
    }
  }

  static Future<Uint8List> _buildPdf(
    List<Sheet> sheets,
    SheetEngine engine,
  ) async {
    final pdf = pw.Document();
    final mono = pw.Font.courier();
    final bold = pw.Font.courierBold();

    for (final sheet in sheets) {
      final lines = sheet.content.split('\n');
      final results = engine.evaluate(lines);
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
          build: (context) => [
            pw.Text(
              sheet.title.isEmpty ? 'Untitled' : sheet.title,
              style: pw.TextStyle(font: bold, fontSize: 14),
            ),
            pw.SizedBox(height: 8),
            for (var i = 0; i < lines.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        lines[i],
                        style: pw.TextStyle(font: mono, fontSize: 9),
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Text(
                      results[i].display ?? '',
                      style: pw.TextStyle(font: mono, fontSize: 9),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return pdf.save();
  }
}
