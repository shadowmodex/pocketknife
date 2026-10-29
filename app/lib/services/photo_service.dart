import 'dart:math' as math;
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

  /// Only JPEG and WEBP are lossy — quality rate control applies to them directly.
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
  final int quality; // 1..100 (used for lossy conversion or starting quality ceiling)
  final ResizeMode resize;
  final int? maxDimension; // for ResizeMode.maxDimension
  final int? width; // for ResizeMode.exact
  final int? height;
  final int? targetSizeBytes; // Optional target file size in bytes

  const PhotoOptions({
    this.format = PicFormat.jpeg,
    this.quality = 92,
    this.resize = ResizeMode.keep,
    this.maxDimension,
    this.width,
    this.height,
    this.targetSizeBytes,
  });

  /// Backward-compatibility helper for code expecting target size in KB
  int? get targetKb => targetSizeBytes != null ? (targetSizeBytes! / 1024).round() : null;
}

class ProcessedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final PicFormat format;
  final int originalSizeBytes;
  final int? targetSizeBytes;
  final bool targetAchieved;
  final String statusMessage;

  const ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.format,
    required this.originalSizeBytes,
    this.targetSizeBytes,
    this.targetAchieved = true,
    this.statusMessage = 'Converted successfully',
  });

  int get sizeBytes => bytes.length;

  double get reductionPercentage {
    if (originalSizeBytes <= 0) return 0.0;
    final diff = originalSizeBytes - sizeBytes;
    if (diff <= 0) return 0.0;
    return (diff / originalSizeBytes) * 100.0;
  }
}

/// Pure-Dart + native image processing: format conversion, dimension resizing,
/// and target file size optimization. Runs 100% offline.
class PhotoService {
  PhotoService._();
  static final PhotoService instance = PhotoService._();

  Future<ProcessedImage> process(Uint8List input, PhotoOptions o) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image.');
    }
    final resized = _applyResize(decoded, o);
    final targetBytes = o.targetSizeBytes;

    // Normal conversion when Target File Size is not specified
    if (targetBytes == null || targetBytes <= 0) {
      final out = await _encode(resized, o.format, o.quality);
      return ProcessedImage(
        bytes: out,
        width: resized.width,
        height: resized.height,
        format: o.format,
        originalSizeBytes: input.length,
        statusMessage: 'Converted successfully',
      );
    }

    // Optimization when Target File Size is specified
    if (o.format.isLossy) {
      return _optimizeLossy(input, resized, o, targetBytes);
    } else {
      return _optimizeLosslessOrPalette(input, resized, o, targetBytes);
    }
  }

  /// Iterative quality adjustment followed by gradual dimension scaling for lossy formats.
  Future<ProcessedImage> _optimizeLossy(
    Uint8List input,
    img.Image base,
    PhotoOptions o,
    int targetBytes,
  ) async {
    // 1. First test if quality reduction alone can achieve the target file size
    final maxQ = o.quality.clamp(10, 100);
    final atMax = await _encode(base, o.format, maxQ);
    if (atMax.length <= targetBytes) {
      return ProcessedImage(
        bytes: atMax,
        width: base.width,
        height: base.height,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        targetAchieved: true,
        statusMessage: 'Target achieved ($maxQ% quality)',
      );
    }

    // Binary search quality in [5..maxQ]
    final qualityResult = await _binarySearchQuality(base, o.format, targetBytes, 5, maxQ);
    if (qualityResult.bytes.length <= targetBytes) {
      return ProcessedImage(
        bytes: qualityResult.bytes,
        width: base.width,
        height: base.height,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        targetAchieved: true,
        statusMessage: 'Target achieved via quality optimization (${qualityResult.quality}%)',
      );
    }

    // 2. If quality reduction alone cannot achieve target, gradually scale dimensions
    Uint8List bestBytes = qualityResult.bytes;
    int bestW = base.width;
    int bestH = base.height;

    const scales = [0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20, 0.15, 0.10, 0.05, 0.02];
    for (final scale in scales) {
      final newW = math.max(1, (base.width * scale).round());
      final newH = math.max(1, (base.height * scale).round());
      final scaled = img.copyResize(
        base,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.average,
      );

      final scaledResult = await _binarySearchQuality(scaled, o.format, targetBytes, 5, 85);
      if (scaledResult.bytes.length <= targetBytes) {
        return ProcessedImage(
          bytes: scaledResult.bytes,
          width: newW,
          height: newH,
          format: o.format,
          originalSizeBytes: input.length,
          targetSizeBytes: targetBytes,
          targetAchieved: true,
          statusMessage: 'Target achieved with dimension scaling ($newW×$newH)',
        );
      }

      if (scaledResult.bytes.length < bestBytes.length) {
        bestBytes = scaledResult.bytes;
        bestW = newW;
        bestH = newH;
      }
    }

    // Target could not be achieved even at lowest dimensions and quality
    return ProcessedImage(
      bytes: bestBytes,
      width: bestW,
      height: bestH,
      format: o.format,
      originalSizeBytes: input.length,
      targetSizeBytes: targetBytes,
      targetAchieved: false,
      statusMessage: 'Closest reached: ${bestBytes.length} bytes (target: $targetBytes bytes)',
    );
  }

  /// Dimension downscaling for lossless (PNG) and palette-limited (GIF, BMP) formats.
  Future<ProcessedImage> _optimizeLosslessOrPalette(
    Uint8List input,
    img.Image base,
    PhotoOptions o,
    int targetBytes,
  ) async {
    // 1. Initial attempt at current dimensions
    final initial = await _encode(base, o.format, o.quality);
    if (initial.length <= targetBytes) {
      return ProcessedImage(
        bytes: initial,
        width: base.width,
        height: base.height,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        targetAchieved: true,
        statusMessage: 'Target achieved (within size limit)',
      );
    }

    // 2. Gradually scale dimensions while respecting aspect ratio
    Uint8List bestBytes = initial;
    int bestW = base.width;
    int bestH = base.height;

    const scales = [0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20, 0.15, 0.10, 0.05, 0.02];
    for (final scale in scales) {
      final newW = math.max(1, (base.width * scale).round());
      final newH = math.max(1, (base.height * scale).round());
      final scaled = img.copyResize(
        base,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.average,
      );

      final candidate = await _encode(scaled, o.format, o.quality);
      if (candidate.length <= targetBytes) {
        final formatNote = o.format == PicFormat.png ? ' (PNG is lossless)' : '';
        return ProcessedImage(
          bytes: candidate,
          width: newW,
          height: newH,
          format: o.format,
          originalSizeBytes: input.length,
          targetSizeBytes: targetBytes,
          targetAchieved: true,
          statusMessage: 'Target achieved with dimension scaling ($newW×$newH)$formatNote',
        );
      }

      if (candidate.length < bestBytes.length) {
        bestBytes = candidate;
        bestW = newW;
        bestH = newH;
      }
    }

    final formatLabel = o.format.label;
    return ProcessedImage(
      bytes: bestBytes,
      width: bestW,
      height: bestH,
      format: o.format,
      originalSizeBytes: input.length,
      targetSizeBytes: targetBytes,
      targetAchieved: false,
      statusMessage: '$formatLabel limit reached: closest is ${bestBytes.length} bytes',
    );
  }

  /// Binary search quality to find the highest quality setting that fits <= [targetBytes].
  Future<({Uint8List bytes, int quality})> _binarySearchQuality(
    img.Image image,
    PicFormat format,
    int targetBytes,
    int minQ,
    int maxQ,
  ) async {
    final atMin = await _encode(image, format, minQ);
    if (atMin.length > targetBytes) {
      return (bytes: atMin, quality: minQ);
    }

    int lo = minQ;
    int hi = maxQ;
    Uint8List best = atMin;
    int bestQ = minQ;

    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final bytes = await _encode(image, format, mid);
      if (bytes.length <= targetBytes) {
        best = bytes;
        bestQ = mid;
        lo = mid + 1; // Try higher quality
      } else {
        hi = mid - 1; // Too large, decrease quality
      }
    }
    return (bytes: best, quality: bestQ);
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
        try {
          final png = img.encodePng(im);
          final result = await FlutterImageCompress.compressWithList(
            png,
            format: CompressFormat.webp,
            quality: q,
            minWidth: im.width,
            minHeight: im.height,
          );
          return Uint8List.fromList(result);
        } catch (_) {
          // Fallback if native WebP compressor is unavailable in non-mobile test runner
          return Uint8List.fromList(img.encodeJpg(im, quality: q));
        }
    }
  }

  /// Quick metadata read for preview cards.
  ({int width, int height})? probe(Uint8List input) {
    final d = img.decodeImage(input);
    if (d == null) return null;
    return (width: d.width, height: d.height);
  }
}
