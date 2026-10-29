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

    test('identifies formats supporting transparency', () {
      expect(PicFormat.png.supportsTransparency, true);
      expect(PicFormat.webp.supportsTransparency, true);
      expect(PicFormat.gif.supportsTransparency, true);
      expect(PicFormat.jpeg.supportsTransparency, false);
      expect(PicFormat.bmp.supportsTransparency, false);
    });
  });

  group('CompressionMode', () {
    test('defines all three compression modes with valid quality floors', () {
      expect(CompressionMode.values.length, 3);
      expect(CompressionMode.highQuality.qualityFloor, 85);
      expect(CompressionMode.balanced.qualityFloor, 65);
      expect(CompressionMode.smallestSize.qualityFloor, 30);
    });

    test('High Quality strictly forbids automatic dimension downscaling', () {
      expect(CompressionMode.highQuality.allowDimensionScaling, false);
      expect(CompressionMode.highQuality.dimensionScales, isEmpty);
    });

    test('Balanced and Smallest Size permit dimension downscaling', () {
      expect(CompressionMode.balanced.allowDimensionScaling, true);
      expect(CompressionMode.balanced.dimensionScales, isNotEmpty);
      expect(CompressionMode.smallestSize.allowDimensionScaling, true);
      expect(CompressionMode.smallestSize.dimensionScales.length,
          greaterThan(CompressionMode.balanced.dimensionScales.length));
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

  group('PhotoService Quality-First Compression Engine', () {
    late Uint8List testJpegBytes;

    setUp(() {
      // Create a 200x100 test image with rich high-frequency colors
      final image = img.Image(width: 200, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 200; x++) {
          image.setPixelRgb(x, y, (x * 13) % 256, (y * 19) % 256, ((x + y) * 23) % 256);
        }
      }
      testJpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 95));
    });

    test('An 86 KB original with a 60 KB target never produces an accepted 102 KB result', () async {
      // Create an image that encodes to ~86 KB (under or around 88,000 bytes)
      final largeImg = img.Image(width: 600, height: 500);
      for (var y = 0; y < 500; y++) {
        for (var x = 0; x < 600; x++) {
          largeImg.setPixelRgb(x, y, (x * 17) % 256, (y * 23) % 256, ((x + y) * 29) % 256);
        }
      }
      var lo = 10, hi = 95;
      Uint8List origBytes = Uint8List.fromList(img.encodeJpg(largeImg, quality: 75));
      while (lo <= hi) {
        final mid = (lo + hi) ~/ 2;
        final candidate = Uint8List.fromList(img.encodeJpg(largeImg, quality: mid));
        if (candidate.length <= 86 * 1024) {
          origBytes = candidate;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }

      const target60Kb = 60 * 1024; // 60 KB
      final res = await PhotoService.instance.process(
        origBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 90,
          targetSizeBytes: target60Kb,
          mode: CompressionMode.balanced,
        ),
      );

      // Output must NEVER exceed original size when goal is file size reduction
      expect(res.sizeBytes, lessThanOrEqualTo(origBytes.length));
      // Must never produce an inflated 102 KB result
      expect(res.sizeBytes, lessThan(102 * 1024));
      expect(res.sizeBytes, isNot(102 * 1024));

      if (res.targetAchieved) {
        expect(res.sizeBytes, lessThanOrEqualTo(target60Kb));
      } else {
        expect(res.sizeBytes <= origBytes.length, true);
      }
    });

    test('An image already below requested target is not inflated by re-encoding', () async {
      // Input is testJpegBytes (~5 KB), requested target is 60 KB
      const target60Kb = 60 * 1024;
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: target60Kb,
          mode: CompressionMode.highQuality,
        ),
      );

      expect(res.sizeBytes, lessThanOrEqualTo(testJpegBytes.length));
      expect(res.targetAchieved, true);
      expect(res.isOriginalPreserved, true);
      expect(res.statusMessage, contains('below target size'));
    });

    test('A target is marked achieved only when measured output bytes are within the limit', () async {
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: 4000,
          mode: CompressionMode.highQuality,
        ),
      );

      if (res.targetAchieved) {
        expect(res.sizeBytes, lessThanOrEqualTo(4000));
      } else {
        expect(res.sizeBytes, greaterThan(4000));
      }
    });

    test('An unreachable target produces an honest warning and targetAchieved is false', () async {
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          targetSizeBytes: 10, // impossible limit of 10 bytes
          mode: CompressionMode.highQuality,
        ),
      );

      expect(res.targetAchieved, false);
      expect(res.warningMessage, isNotNull);
      expect(res.warningMessage!.isNotEmpty, true);
      // Original preserved without inflation
      expect(res.sizeBytes, lessThanOrEqualTo(testJpegBytes.length));
    });

    test('High Quality never triggers automatic dimension downscaling', () async {
      // Target is tiny (300 bytes), impossible to achieve at min quality 85 for 200x100
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: 300,
          mode: CompressionMode.highQuality,
        ),
      );

      // High Quality must NEVER automatically reduce dimensions
      expect(res.width, 200);
      expect(res.height, 100);
      expect(res.dimensionsChanged, false);
      expect(res.targetAchieved, false);
      expect(res.warningMessage, contains('High Quality'));
    });

    test('Manual dimensions and aspect ratio are respected', () async {
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 90,
          resize: ResizeMode.exact,
          width: 120,
          height: 60,
          targetSizeBytes: 2000,
          mode: CompressionMode.highQuality,
        ),
      );

      expect(res.width, 120);
      expect(res.height, 60);
      expect(res.originalWidth, 200);
      expect(res.originalHeight, 100);
      expect(res.dimensionsChanged, true);
    });

    test('Quality floors remain enforced across modes', () async {
      // High Quality floor: 85
      final hqRes = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: 400,
          mode: CompressionMode.highQuality,
        ),
      );
      if (hqRes.achievedQuality != null) {
        expect(hqRes.achievedQuality, greaterThanOrEqualTo(85));
      }

      // Balanced floor: 65
      final balRes = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: 400,
          mode: CompressionMode.balanced,
        ),
      );
      if (balRes.achievedQuality != null) {
        expect(balRes.achievedQuality, greaterThanOrEqualTo(65));
      }

      // Smallest Size floor: 30
      final smallRes = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 95,
          targetSizeBytes: 400,
          mode: CompressionMode.smallestSize,
        ),
      );
      if (smallRes.achievedQuality != null) {
        expect(smallRes.achievedQuality, greaterThanOrEqualTo(30));
      }
    });

    test('PNG transparency is preserved where supported', () async {
      // Create a 40x40 image with transparent background and an opaque red circle
      final transparentImg = img.Image(width: 40, height: 40, numChannels: 4);
      transparentImg.clear(img.ColorRgba8(0, 0, 0, 0)); // fully transparent
      transparentImg.setPixelRgba(20, 20, 255, 0, 0, 255); // opaque center

      final pngBytes = Uint8List.fromList(img.encodePng(transparentImg));
      final res = await PhotoService.instance.process(
        pngBytes,
        const PhotoOptions(format: PicFormat.png),
      );

      final decoded = img.decodePng(res.bytes)!;
      // Check that corner pixel is transparent
      expect(decoded.getPixel(0, 0).a, 0);
      // Check that center pixel is opaque
      expect(decoded.getPixel(20, 20).a, 255);
    });

    test('Animated GIF behavior is preserved where supported', () async {
      // Create a 2-frame animated GIF
      final frame1 = img.Image(width: 30, height: 30);
      frame1.clear(img.ColorRgb8(255, 0, 0)); // Frame 1 red
      final frame2 = img.Image(width: 30, height: 30);
      frame2.clear(img.ColorRgb8(0, 0, 255)); // Frame 2 blue
      frame1.addFrame(frame2);

      final animatedGifBytes = Uint8List.fromList(img.encodeGif(frame1));
      final res = await PhotoService.instance.process(
        animatedGifBytes,
        const PhotoOptions(format: PicFormat.gif),
      );

      final decodedGif = img.decodeGif(res.bytes)!;
      expect(decodedGif.numFrames, 2); // Both animation frames preserved!
    });

    test('Reported file sizes match actual output bytes', () async {
      final res = await PhotoService.instance.process(
        testJpegBytes,
        const PhotoOptions(
          format: PicFormat.jpeg,
          quality: 88,
          targetSizeBytes: 4000,
          mode: CompressionMode.highQuality,
        ),
      );

      expect(res.sizeBytes, res.bytes.length);
    });
  });
}
