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

  /// Only JPEG and WEBP are lossy formats supporting variable rate control.
  bool get isLossy => this == PicFormat.jpeg || this == PicFormat.webp;

  /// Whether format supports an alpha channel (transparency).
  bool get supportsTransparency =>
      this == PicFormat.png || this == PicFormat.webp || this == PicFormat.gif;

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

enum CompressionMode {
  highQuality,
  balanced,
  smallestSize,
}

extension CompressionModeMeta on CompressionMode {
  String get label {
    switch (this) {
      case CompressionMode.highQuality:
        return 'High Quality';
      case CompressionMode.balanced:
        return 'Balanced';
      case CompressionMode.smallestSize:
        return 'Smallest Size';
    }
  }

  String get description {
    switch (this) {
      case CompressionMode.highQuality:
        return 'Prioritizes visual fidelity. Preserves 100% original dimensions with a minimum quality floor of 85.';
      case CompressionMode.balanced:
        return 'Compromise between quality and file size. Allows moderate quality adjustment and carefully limited dimension downscaling.';
      case CompressionMode.smallestSize:
        return 'Prioritizes hitting small file sizes. May cause visible compression artifacts or dimension downscaling.';
    }
  }

  /// Minimum encoder quality on a 0–100 scale for this mode.
  int get qualityFloor {
    switch (this) {
      case CompressionMode.highQuality:
        return 85;
      case CompressionMode.balanced:
        return 65;
      case CompressionMode.smallestSize:
        return 30;
    }
  }

  /// Whether this mode permits automatic dimension downscaling when quality floor alone cannot reach target size.
  bool get allowDimensionScaling {
    switch (this) {
      case CompressionMode.highQuality:
        return false;
      case CompressionMode.balanced:
      case CompressionMode.smallestSize:
        return true;
    }
  }

  /// Permitted downscale steps for this mode. High Quality NEVER downscales.
  List<double> get dimensionScales {
    switch (this) {
      case CompressionMode.highQuality:
        return const [];
      case CompressionMode.balanced:
        return const [0.90, 0.80, 0.70];
      case CompressionMode.smallestSize:
        return const [0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20];
    }
  }
}

class PhotoOptions {
  final PicFormat format;
  final int quality; // 1..100 (starting quality ceiling)
  final ResizeMode resize;
  final int? maxDimension; // for ResizeMode.maxDimension
  final int? width; // for ResizeMode.exact
  final int? height;
  final int? targetSizeBytes; // Optional target file size in bytes
  final CompressionMode mode; // High Quality, Balanced, Smallest Size

  const PhotoOptions({
    this.format = PicFormat.jpeg,
    this.quality = 95,
    this.resize = ResizeMode.keep,
    this.maxDimension,
    this.width,
    this.height,
    this.targetSizeBytes,
    this.mode = CompressionMode.highQuality,
  });

  /// Backward-compatibility helper for code expecting target size in KB
  int? get targetKb => targetSizeBytes != null ? (targetSizeBytes! / 1024).round() : null;
}

class ProcessedImage {
  final Uint8List bytes;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final PicFormat format;
  final int originalSizeBytes;
  final int? targetSizeBytes;
  final CompressionMode mode;
  final int? achievedQuality;
  final bool targetAchieved;
  final String statusMessage;
  final String? warningMessage;

  const ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.format,
    required this.originalSizeBytes,
    this.targetSizeBytes,
    this.mode = CompressionMode.highQuality,
    this.achievedQuality,
    this.targetAchieved = true,
    this.statusMessage = 'Converted successfully',
    this.warningMessage,
  });

  int get sizeBytes => bytes.length;

  double get reductionPercentage {
    if (originalSizeBytes <= 0) return 0.0;
    final diff = originalSizeBytes - sizeBytes;
    if (diff <= 0) return 0.0;
    return (diff / originalSizeBytes) * 100.0;
  }

  bool get dimensionsChanged => width != originalWidth || height != originalHeight;
}

/// Pure-Dart + native image processing engine: format conversion, dimension resizing,
/// and quality-first target file size optimization. Runs 100% offline.
class PhotoService {
  PhotoService._();
  static final PhotoService instance = PhotoService._();

  Future<ProcessedImage> process(Uint8List input, PhotoOptions o) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image.');
    }

    final origW = decoded.width;
    final origH = decoded.height;
    final userExplicitResize = o.resize != ResizeMode.keep;
    final base = _applyResize(decoded, o);
    final targetBytes = o.targetSizeBytes;

    // Normal conversion when Target File Size is disabled
    if (targetBytes == null || targetBytes <= 0) {
      final out = await _encode(base, o.format, o.quality);
      return ProcessedImage(
        bytes: out,
        width: base.width,
        height: base.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        mode: o.mode,
        achievedQuality: o.quality,
        statusMessage: 'Converted successfully',
      );
    }

    // Never inflate an image that is already smaller than the requested target
    if (input.length <= targetBytes) {
      final out = await _encode(base, o.format, o.quality);
      if (out.length <= targetBytes) {
        return ProcessedImage(
          bytes: out,
          width: base.width,
          height: base.height,
          originalWidth: origW,
          originalHeight: origH,
          format: o.format,
          originalSizeBytes: input.length,
          targetSizeBytes: targetBytes,
          mode: o.mode,
          achievedQuality: o.quality,
          targetAchieved: true,
          statusMessage: 'Image is within target size limit',
        );
      }
    }

    // Optimization when Target File Size is active
    if (o.format.isLossy) {
      return _optimizeLossy(input, base, origW, origH, userExplicitResize, o, targetBytes);
    } else {
      return _optimizeLosslessOrPalette(input, base, origW, origH, userExplicitResize, o, targetBytes);
    }
  }

  /// Quality-first bounded optimization for lossy formats (JPEG, WebP).
  ///
  /// In High Quality mode:
  /// - Enforces a strict minimum quality floor of 85.
  /// - NEVER downscales dimensions automatically.
  /// - If target cannot be met within quality floor, returns the cleanest result at quality 85
  ///   with a clear warning.
  Future<ProcessedImage> _optimizeLossy(
    Uint8List input,
    img.Image base,
    int origW,
    int origH,
    bool userExplicitResize,
    PhotoOptions o,
    int targetBytes,
  ) async {
    final floorQ = o.mode.qualityFloor;
    final ceilingQ = math.max(floorQ, o.quality.clamp(1, 100));

    // 1. Measure output bytes at quality ceiling
    final atCeiling = await _encode(base, o.format, ceilingQ);
    if (atCeiling.length <= targetBytes) {
      return ProcessedImage(
        bytes: atCeiling,
        width: base.width,
        height: base.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: ceilingQ,
        targetAchieved: true,
        statusMessage: 'Target achieved at quality $ceilingQ%',
      );
    }

    // 2. Measure output bytes at mode's quality floor
    final atFloor = await _encode(base, o.format, floorQ);
    if (atFloor.length <= targetBytes) {
      // Target is achievable within [floorQ..ceilingQ] without altering dimensions!
      final result = await _binarySearchQuality(base, o.format, targetBytes, floorQ, ceilingQ);
      return ProcessedImage(
        bytes: result.bytes,
        width: base.width,
        height: base.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: result.quality,
        targetAchieved: true,
        statusMessage: 'Target achieved at quality ${result.quality}% (${o.mode.label})',
      );
    }

    // 3. At this point, output at floor quality still exceeds targetBytes.
    // In High Quality mode OR when user explicitly specified custom dimensions:
    // DO NOT automatically downscale dimensions.
    if (!o.mode.allowDimensionScaling || userExplicitResize) {
      final modeName = o.mode.label;
      return ProcessedImage(
        bytes: atFloor,
        width: base.width,
        height: base.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: floorQ,
        targetAchieved: false,
        statusMessage: 'Quality floor reached ($floorQ%). Target could not be achieved without quality degradation.',
        warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached within the $modeName floor (min $floorQ%). Original dimensions and visual fidelity were preserved.',
      );
    }

    // 4. In Balanced or Smallest Size modes: test permitted dimension scales
    Uint8List bestBytes = atFloor;
    int bestW = base.width;
    int bestH = base.height;
    int bestQ = floorQ;

    for (final scale in o.mode.dimensionScales) {
      final newW = math.max(1, (base.width * scale).round());
      final newH = math.max(1, (base.height * scale).round());
      final scaled = img.copyResize(
        base,
        width: newW,
        height: newH,
        interpolation: img.Interpolation.average,
      );

      final scaledAtFloor = await _encode(scaled, o.format, floorQ);
      if (scaledAtFloor.length <= targetBytes) {
        // Fits at this scale! Search for highest quality >= floorQ that fits
        final result = await _binarySearchQuality(scaled, o.format, targetBytes, floorQ, ceilingQ);
        return ProcessedImage(
          bytes: result.bytes,
          width: newW,
          height: newH,
          originalWidth: origW,
          originalHeight: origH,
          format: o.format,
          originalSizeBytes: input.length,
          targetSizeBytes: targetBytes,
          mode: o.mode,
          achievedQuality: result.quality,
          targetAchieved: true,
          statusMessage: 'Target achieved with limited downscaling to $newW×$newH at quality ${result.quality}%',
        );
      }

      if (scaledAtFloor.length < bestBytes.length) {
        bestBytes = scaledAtFloor;
        bestW = newW;
        bestH = newH;
        bestQ = floorQ;
      }
    }

    // Target could not be met even with mode's permitted downscaling
    return ProcessedImage(
      bytes: bestBytes,
      width: bestW,
      height: bestH,
      originalWidth: origW,
      originalHeight: origH,
      format: o.format,
      originalSizeBytes: input.length,
      targetSizeBytes: targetBytes,
      mode: o.mode,
      achievedQuality: bestQ,
      targetAchieved: false,
      statusMessage: 'Closest reached: ${_formatBytes(bestBytes.length)} (Target: ${_formatBytes(targetBytes)})',
      warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be met within ${o.mode.label} limits without unacceptable quality loss.',
    );
  }

  /// Dimension optimization for lossless (PNG) and palette-limited (GIF, BMP) formats.
  Future<ProcessedImage> _optimizeLosslessOrPalette(
    Uint8List input,
    img.Image base,
    int origW,
    int origH,
    bool userExplicitResize,
    PhotoOptions o,
    int targetBytes,
  ) async {
    final initial = await _encode(base, o.format, o.quality);
    if (initial.length <= targetBytes) {
      return ProcessedImage(
        bytes: initial,
        width: base.width,
        height: base.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: o.quality,
        targetAchieved: true,
        statusMessage: 'Target achieved (${_formatBytes(initial.length)})',
      );
    }

    // In High Quality mode OR with explicit user dimensions: never automatically downscale dimensions
    if (!o.mode.allowDimensionScaling || userExplicitResize) {
      final formatName = o.format.label;
      final formatExplanation = o.format == PicFormat.png
          ? 'PNG uses lossless compression and cannot reduce file size without reducing dimensions.'
          : '$formatName cannot meet the target size without reducing dimensions.';

      return ProcessedImage(
        bytes: initial,
        width: base.width,
        height: base.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: o.quality,
        targetAchieved: false,
        statusMessage: '$formatExplanation Original dimensions preserved in High Quality mode.',
        warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached. $formatExplanation',
      );
    }

    // In Balanced or Smallest Size modes: test permitted scales
    Uint8List bestBytes = initial;
    int bestW = base.width;
    int bestH = base.height;

    for (final scale in o.mode.dimensionScales) {
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
        final formatNote = o.format == PicFormat.png ? ' (lossless PNG)' : '';
        return ProcessedImage(
          bytes: candidate,
          width: newW,
          height: newH,
          originalWidth: origW,
          originalHeight: origH,
          format: o.format,
          originalSizeBytes: input.length,
          targetSizeBytes: targetBytes,
          mode: o.mode,
          achievedQuality: o.quality,
          targetAchieved: true,
          statusMessage: 'Target achieved via dimension scaling to $newW×$newH$formatNote',
        );
      }

      if (candidate.length < bestBytes.length) {
        bestBytes = candidate;
        bestW = newW;
        bestH = newH;
      }
    }

    return ProcessedImage(
      bytes: bestBytes,
      width: bestW,
      height: bestH,
      originalWidth: origW,
      originalHeight: origH,
      format: o.format,
      originalSizeBytes: input.length,
      targetSizeBytes: targetBytes,
      mode: o.mode,
      achievedQuality: o.quality,
      targetAchieved: false,
      statusMessage: 'Closest reached: ${_formatBytes(bestBytes.length)} (Target: ${_formatBytes(targetBytes)})',
      warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached within ${o.mode.label} dimension limits.',
    );
  }

  /// Binary search quality in [minQ..maxQ] to find the highest quality setting that fits <= [targetBytes].
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
        // img.encodeGif encodes all frames when im has animation, preserving multi-frame GIFs.
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
          return Uint8List.fromList(img.encodeJpg(im, quality: q));
        }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var b = bytes.toDouble();
    var i = 0;
    while (b >= 1024 && i < units.length - 1) {
      b /= 1024;
      i++;
    }
    return '${b.toStringAsFixed(b >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  /// Quick metadata read for preview cards.
  ({int width, int height})? probe(Uint8List input) {
    final d = img.decodeImage(input);
    if (d == null) return null;
    return (width: d.width, height: d.height);
  }
}
