import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

enum PicFormat { jpeg, png, webp, bmp, gif }

extension PicFormatMeta on PicFormat {
  String get ext {
    switch (this) {
      case PicFormat.jpeg:
        return 'jpg';
      case PicFormat.png:
        return 'png';
      case PicFormat.webp:
        return 'webp';
      case PicFormat.bmp:
        return 'bmp';
      case PicFormat.gif:
        return 'gif';
    }
  }

  String get label => this == PicFormat.jpeg ? 'JPG' : ext.toUpperCase();

  /// Only JPEG and WEBP are lossy — quality / target-size apply to them.
  bool get isLossy => this == PicFormat.jpeg || this == PicFormat.webp;

  static PicFormat fromName(String s) {
    switch (s.toLowerCase()) {
      case 'png':
        return PicFormat.png;
      case 'webp':
        return PicFormat.webp;
      case 'bmp':
        return PicFormat.bmp;
      case 'gif':
        return PicFormat.gif;
      default:
        return PicFormat.jpeg;
    }
  }
}

enum ResizeMode { keep, maxDimension, exact }

class PhotoOptions {
  final PicFormat format;
  final int quality; // 1..100 (lossy only)
  final ResizeMode resize;
  final int? maxDimension; // for ResizeMode.maxDimension
  final int? width; // for ResizeMode.exact
  final int? height;
  final int? targetKb; // if set (lossy), binary-search quality to fit

  const PhotoOptions({
    this.format = PicFormat.jpeg,
    this.quality = 92,
    this.resize = ResizeMode.keep,
    this.maxDimension,
    this.width,
    this.height,
    this.targetKb,
  });
}

class ProcessedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final PicFormat format;
  const ProcessedImage(this.bytes, this.width, this.height, this.format);

  int get sizeBytes => bytes.length;
}

/// Pure-Dart + native image processing: resize/convert plus optional
/// "reduce to target size". Runs 100% offline.
class PhotoService {
  PhotoService._();
  static final PhotoService instance = PhotoService._();

  Future<ProcessedImage> process(Uint8List input, PhotoOptions o) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image.');
    }
    final resized = _applyResize(decoded, o);

    Future<Uint8List> encode(int q) => _encode(resized, o.format, q);

    Uint8List out;
    if (o.format.isLossy && o.targetKb != null && o.targetKb! > 0) {
      out = await _fitToTarget(encode, o.targetKb! * 1024, o.quality);
    } else {
      out = await encode(o.quality);
    }
    return ProcessedImage(out, resized.width, resized.height, o.format);
  }

  img.Image _applyResize(img.Image src, PhotoOptions o) {
    switch (o.resize) {
      case ResizeMode.keep:
        return src;
      case ResizeMode.maxDimension:
        final m = o.maxDimension ?? 1920;
        if (src.width <= m && src.height <= m) return src;
        if (src.width >= src.height) {
          return img.copyResize(src, width: m, interpolation: img.Interpolation.average);
        }
        return img.copyResize(src, height: m, interpolation: img.Interpolation.average);
      case ResizeMode.exact:
        if (o.width == null && o.height == null) return src;
        return img.copyResize(
          src,
          width: o.width,
          height: o.height,
          interpolation: img.Interpolation.average,
        );
    }
  }

  Future<Uint8List> _encode(img.Image im, PicFormat fmt, int q) async {
    switch (fmt) {
      case PicFormat.jpeg:
        return Uint8List.fromList(img.encodeJpg(im, quality: q));
      case PicFormat.png:
        return Uint8List.fromList(img.encodePng(im));
      case PicFormat.bmp:
        return Uint8List.fromList(img.encodeBmp(im));
      case PicFormat.gif:
        return Uint8List.fromList(img.encodeGif(im));
      case PicFormat.webp:
        // image pkg can't encode WEBP — hand the raw PNG bytes to
        // the native compressor to produce WebP at the desired quality.
        final png = img.encodePng(im);
        final result = await FlutterImageCompress.compressWithList(
          png,
          format: CompressFormat.webp,
          quality: q,
          minWidth: im.width,
          minHeight: im.height,
        );
        return Uint8List.fromList(result);
    }
  }

  /// Binary-search quality so the encoded size lands just under [targetBytes].
  Future<Uint8List> _fitToTarget(
    Future<Uint8List> Function(int q) encode,
    int targetBytes,
    int startQuality,
  ) async {
    int lo = 5, hi = startQuality.clamp(5, 100);
    Uint8List best = await encode(hi);
    if (best.length <= targetBytes) return best; // already fits at requested quality
    best = await encode(lo);
    // Search for the highest quality that still fits.
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final bytes = await encode(mid);
      if (bytes.length <= targetBytes) {
        best = bytes;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  /// Quick metadata read for preview cards.
  ({int width, int height})? probe(Uint8List input) {
    final d = img.decodeImage(input);
    if (d == null) return null;
    return (width: d.width, height: d.height);
  }
}
