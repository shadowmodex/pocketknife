import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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

  group('PhotoService Target File Size Optimization', () {
    late Uint8List testJpegBytes;

    setUp(() {
      // Create a 200x100 test image with rich color content
      final image = img.Image(width: 200, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 200; x++) {
          image.setPixelRgb(x, y, (x * 13) % 256, (y * 19) % 256, ((x + y) * 23) % 256);
        }
      }
      testJpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    });

    test('normal conversion without target size retains dimensions', () async {
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(format: PicFormat.jpeg, quality: 90),
      );

      expect(res.width, 200);
      expect(res.height, 100);
      expect(res.targetSizeBytes, isNull);
      expect(res.targetAchieved, true);
      expect(res.format, PicFormat.jpeg);
    });

    test('achieves target file size using quality reduction while preserving dimensions', () async {
      // Pick a reasonable target that can be met by quality reduction alone
      final target = (testJpegBytes.length * 0.6).round();
      final res = await PhotoService.instance.process(
        testJpegBytes,
        PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: target,
        ),
      );

      expect(res.sizeBytes, lessThanOrEqualTo(target));
      expect(res.targetAchieved, true);
      expect(res.width, 200); // Dimensions preserved!
      expect(res.height, 100);
      expect(res.reductionPercentage, greaterThan(0));
    });

    test('falls back to gradual dimension scaling when quality reduction alone cannot fit', () async {
      // Pick an aggressive target that quality reduction alone cannot reach
      const aggressiveTarget = 750; // bytes
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: aggressiveTarget,
        ),
      );

      expect(res.sizeBytes, lessThanOrEqualTo(aggressiveTarget));
      expect(res.targetAchieved, true);
      expect(res.width, lessThan(200)); // Scaled dimensions
      expect(res.height, lessThan(100));
      // Aspect ratio preserved (200 / 100 = 2.0)
      final ratio = res.width / res.height;
      expect((ratio - 2.0).abs(), lessThan(0.2));
    });

    test('PNG downscales dimensions to meet target file size', () async {
      final pngImage = img.Image(width: 150, height: 150);
      for (var y = 0; y < 150; y++) {
        for (var x = 0; x < 150; x++) {
          pngImage.setPixelRgb(x, y, (x * 7) % 256, (y * 11) % 256, ((x + y) * 17) % 256);
        }
      }
      final pngBytes = Uint8List.fromList(img.encodePng(pngImage));
      final target = (pngBytes.length * 0.35).round();

      final res = await PhotoService.instance.process(
        pngBytes,
        PhotoOptions(
          format: PicFormat.png,
          targetSizeBytes: target,
        ),
      );

      expect(res.sizeBytes, lessThanOrEqualTo(target));
      expect(res.targetAchieved, true);
      expect(res.format, PicFormat.png);
      expect(res.width, lessThan(150));
    });

    test('reports status when target is unreachable without crashing', () async {
      // Completely impossible target of 10 bytes
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          targetSizeBytes: 10,
        ),
      );

      expect(res.targetAchieved, false);
      expect(res.statusMessage, contains('Closest'));
    });
  });
}
