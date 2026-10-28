import 'package:flutter_test/flutter_test.dart';
import 'package:pocketknife/models/models.dart';
import 'package:pocketknife/services/photo_service.dart';

void main() {
  group('ToolKind', () {
    test('contains exactly 6 file tools', () {
      expect(ToolKind.values.length, 6);
      expect(ToolKind.values, contains(ToolKind.mergePdf));
      expect(ToolKind.values, contains(ToolKind.imageConverter));
      expect(ToolKind.values, contains(ToolKind.wordToPdf));
      expect(ToolKind.values, contains(ToolKind.textToPdf));
      expect(ToolKind.values, contains(ToolKind.splitPdf));
      expect(ToolKind.values, contains(ToolKind.compressPdf));
    });

    test('backward compatibility maps legacy ids safely', () {
      expect(ToolKindMeta.fromId('video'), ToolKind.mergePdf);
      expect(ToolKindMeta.fromId('mp3'), ToolKind.mergePdf);
      expect(ToolKindMeta.fromId('photo'), ToolKind.imageConverter);
      expect(ToolKindMeta.fromId('docs'), ToolKind.mergePdf);
      expect(ToolKindMeta.fromId('mergePdf'), ToolKind.mergePdf);
      expect(ToolKindMeta.fromId('imageConverter'), ToolKind.imageConverter);
      expect(ToolKindMeta.fromId('wordToPdf'), ToolKind.wordToPdf);
      expect(ToolKindMeta.fromId('textToPdf'), ToolKind.textToPdf);
      expect(ToolKindMeta.fromId('splitPdf'), ToolKind.splitPdf);
      expect(ToolKindMeta.fromId('compressPdf'), ToolKind.compressPdf);
      expect(ToolKindMeta.fromId('unknown'), ToolKind.mergePdf);
    });

    test('every ToolKind has valid title and blurb', () {
      for (final kind in ToolKind.values) {
        expect(kind.title.isNotEmpty, true);
        expect(kind.blurb.isNotEmpty, true);
        expect(kind.id.isNotEmpty, true);
      }
    });
  });

  group('PicFormat', () {
    test('supports all 5 target formats', () {
      expect(PicFormat.values.length, 5);
      expect(PicFormat.jpeg.ext, 'jpg');
      expect(PicFormat.png.ext, 'png');
      expect(PicFormat.webp.ext, 'webp');
      expect(PicFormat.bmp.ext, 'bmp');
      expect(PicFormat.gif.ext, 'gif');
    });

    test('fromName correctly detects formats', () {
      expect(PicFormatMeta.fromName('jpeg'), PicFormat.jpeg);
      expect(PicFormatMeta.fromName('jpg'), PicFormat.jpeg);
      expect(PicFormatMeta.fromName('png'), PicFormat.png);
      expect(PicFormatMeta.fromName('webp'), PicFormat.webp);
      expect(PicFormatMeta.fromName('gif'), PicFormat.gif);
      expect(PicFormatMeta.fromName('bmp'), PicFormat.bmp);
    });
  });

  group('ActivityItem', () {
    test('serializes to and from json accurately', () {
      final now = DateTime.now();
      final item = ActivityItem(
        id: 'test_123',
        kind: ToolKind.mergePdf,
        name: 'Report.pdf',
        meta: '2 pages • 1.2 MB',
        at: now,
        savedPath: '/storage/Report.pdf',
      );

      final json = item.toJson();
      expect(json['id'], 'test_123');
      expect(json['kind'], 'mergePdf');
      expect(json['name'], 'Report.pdf');
      expect(json['savedPath'], '/storage/Report.pdf');

      final reconstructed = ActivityItem.fromJson(json);
      expect(reconstructed.id, item.id);
      expect(reconstructed.kind, ToolKind.mergePdf);
      expect(reconstructed.name, item.name);
      expect(reconstructed.meta, item.meta);
      expect(reconstructed.savedPath, item.savedPath);
    });
  });
}
