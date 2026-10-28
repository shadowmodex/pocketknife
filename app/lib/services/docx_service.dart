import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

class _Para {
  final String text;
  final bool heading;
  const _Para(this.text, this.heading);
}

/// Best-effort DOCX → PDF. A .docx is a zip whose word/document.xml holds the
/// text; we pull paragraph text (and heading styles) and lay it out as a PDF.
/// Complex layout, images and tables degrade to plain text.
class DocxService {
  DocxService._();
  static final DocxService instance = DocxService._();

  pw.Font? _base;

  Future<void> _ensureFont() async {
    if (_base != null) return;
    try {
      final data = await rootBundle.load('assets/fonts/Inter.ttf');
      _base = pw.Font.ttf(data);
    } catch (_) {
      _base = null;
    }
  }

  Future<Uint8List> docxToPdf(Uint8List docx, {String title = 'Document'}) async {
    final paras = _extract(docx);
    await _ensureFont();
    final theme = _base != null
        ? pw.ThemeData.withFont(base: _base!, bold: _base!)
        : pw.ThemeData.base();
    final doc = pw.Document(title: title, theme: theme);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 54, 48, 54),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          for (final p in paras)
            p.text.trim().isEmpty
                ? pw.SizedBox(height: 8)
                : pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: p.heading ? 8 : 6, top: p.heading ? 6 : 0),
                    child: pw.Text(
                      p.text,
                      style: p.heading
                          ? pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)
                          : const pw.TextStyle(fontSize: 11.5, lineSpacing: 3),
                    ),
                  ),
        ],
      ),
    );
    return doc.save();
  }

  List<_Para> _extract(Uint8List docx) {
    final archive = ZipDecoder().decodeBytes(docx);
    ArchiveFile? docFile;
    for (final f in archive.files) {
      if (f.name == 'word/document.xml') {
        docFile = f;
        break;
      }
    }
    if (docFile == null) {
      throw const FormatException('Not a valid Word (.docx) file.');
    }
    final xmlStr = String.fromCharCodes(docFile.content as List<int>);
    final document = XmlDocument.parse(xmlStr);
    final out = <_Para>[];

    for (final p in document.findAllElements('w:p')) {
      final buf = StringBuffer();
      for (final t in p.findAllElements('w:t')) {
        buf.write(t.innerText);
      }
      // Tabs and line breaks inside a paragraph.
      for (final _ in p.findAllElements('w:tab')) {
        // keep as spacing hint only
      }
      final text = buf.toString();
      final styleEl = p.findAllElements('w:pStyle');
      var heading = false;
      if (styleEl.isNotEmpty) {
        final val = styleEl.first.getAttribute('w:val') ?? '';
        heading = val.toLowerCase().contains('heading') || val.toLowerCase().contains('title');
      }
      out.add(_Para(text, heading));
    }
    if (out.isEmpty) out.add(const _Para('(No readable text found in document.)', false));
    return out;
  }
}
