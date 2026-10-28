import 'dart:typed_data';
import 'dart:ui' show Offset, Size;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

enum CompressStrength { light, medium, strong }

extension CompressStrengthMeta on CompressStrength {
  String get label {
    switch (this) {
      case CompressStrength.light:
        return 'Light';
      case CompressStrength.medium:
        return 'Balanced';
      case CompressStrength.strong:
        return 'Strong';
    }
  }

  String get hint {
    switch (this) {
      case CompressStrength.light:
        return 'Best quality';
      case CompressStrength.medium:
        return 'Good balance';
      case CompressStrength.strong:
        return 'Smallest file';
    }
  }

  // (dpi, jpegQuality) — lower = smaller, mirrors the extension's shrink steps.
  double get _dpi => this == CompressStrength.light
      ? 150
      : this == CompressStrength.medium
          ? 120
          : 96;
  int get _quality => this == CompressStrength.light
      ? 80
      : this == CompressStrength.medium
          ? 60
          : 45;
}

/// Everything the Docs Toolkit does with PDFs: build from text, merge, extract
/// pages and shrink. Creation uses the `pdf` package; operations on existing
/// PDFs use Syncfusion; shrinking rasterises via the printing engine.
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  pw.Font? _base;
  pw.Font? _bold;

  Future<void> _ensureFonts() async {
    if (_base != null) return;
    try {
      final data = await rootBundle.load('assets/fonts/Inter.ttf');
      _base = pw.Font.ttf(data);
      _bold = _base; // variable font renders its default weight
    } catch (_) {
      _base = null; // fall back to built-in Helvetica
    }
  }

  Future<Uint8List> textToPdf(String text, {String title = 'Document'}) async {
    await _ensureFonts();
    final theme = _base != null
        ? pw.ThemeData.withFont(base: _base!, bold: _bold ?? _base!)
        : pw.ThemeData.base();
    final doc = pw.Document(title: title, theme: theme);
    final paragraphs = text.split(RegExp(r'\n'));

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
          if (title.trim().isNotEmpty) ...[
            pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 14),
          ],
          for (final p in paragraphs)
            p.trim().isEmpty
                ? pw.SizedBox(height: 8)
                : pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(p, style: const pw.TextStyle(fontSize: 11.5, lineSpacing: 3)),
                  ),
        ],
      ),
    );
    return doc.save();
  }

  int pageCount(Uint8List pdf) {
    final doc = sf.PdfDocument(inputBytes: pdf);
    final n = doc.pages.count;
    doc.dispose();
    return n;
  }

  Future<Uint8List> merge(List<Uint8List> inputs) async {
    final out = sf.PdfDocument();
    out.pageSettings.margins.all = 0;
    for (final bytes in inputs) {
      final src = sf.PdfDocument(inputBytes: bytes);
      for (var i = 0; i < src.pages.count; i++) {
        _copyPage(src.pages[i], out);
      }
      src.dispose();
    }
    final result = Uint8List.fromList(out.saveSync());
    out.dispose();
    return result;
  }

  /// Extract the given 0-based page indices (in order) into a new PDF.
  Future<Uint8List> extractPages(Uint8List input, List<int> pages) async {
    final src = sf.PdfDocument(inputBytes: input);
    final out = sf.PdfDocument();
    out.pageSettings.margins.all = 0;
    for (final p in pages) {
      if (p >= 0 && p < src.pages.count) {
        _copyPage(src.pages[p], out);
      }
    }
    src.dispose();
    final result = Uint8List.fromList(out.saveSync());
    out.dispose();
    return result;
  }

  /// Copy one page losslessly into [dest] by drawing it as a template on a new
  /// page of the same size. (syncfusion_flutter_pdf has no importPageRange.)
  void _copyPage(sf.PdfPage srcPage, sf.PdfDocument dest) {
    final Size size = srcPage.size;
    final template = srcPage.createTemplate();
    dest.pageSettings.size = size;
    final page = dest.pages.add();
    page.graphics.drawPdfTemplate(template, Offset.zero, size);
  }

  Future<Uint8List> compress(Uint8List input, CompressStrength strength) async {
    final doc = pw.Document();
    await for (final page in Printing.raster(input, dpi: strength._dpi)) {
      final jpg = img.encodeJpg(
        img.Image.fromBytes(
          width: page.width,
          height: page.height,
          bytes: page.pixels.buffer,
          numChannels: 4,
        ),
        quality: strength._quality,
      );
      final image = pw.MemoryImage(Uint8List.fromList(jpg));
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(page.width.toDouble(), page.height.toDouble()),
          margin: pw.EdgeInsets.zero,
          build: (ctx) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
    }
    return doc.save();
  }
}

/// Parse a page-range string like "1-3, 5, 8-10" into 0-based indices, bounded
/// by [count]. Invalid tokens are ignored; the result is de-duplicated in order.
List<int> parseRanges(String input, int count) {
  final seen = <int>{};
  final out = <int>[];
  for (final partRaw in input.split(RegExp(r'[,\s]+'))) {
    final part = partRaw.trim();
    if (part.isEmpty) continue;
    final dash = part.split('-');
    if (dash.length == 2) {
      final a = int.tryParse(dash[0]);
      final b = int.tryParse(dash[1]);
      if (a == null || b == null) continue;
      final lo = a <= b ? a : b;
      final hi = a <= b ? b : a;
      for (var i = lo; i <= hi; i++) {
        final idx = i - 1;
        if (idx >= 0 && idx < count && seen.add(idx)) out.add(idx);
      }
    } else {
      final n = int.tryParse(part);
      if (n == null) continue;
      final idx = n - 1;
      if (idx >= 0 && idx < count && seen.add(idx)) out.add(idx);
    }
  }
  return out;
}
