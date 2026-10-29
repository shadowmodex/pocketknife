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
  final bool isOriginalPreserved;
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
    this.isOriginalPreserved = false,
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

    // A. Original is already at or below requested target
    if (input.length <= targetBytes) {
      // If user did not explicitly request resizing and format is identical:
      // Preserve original file directly without needlessly re-encoding into a larger file.
      final isSameFormat = _isSameFormat(input, o.format);
      if (!userExplicitResize && isSameFormat) {
        return ProcessedImage(
          bytes: input,
          width: origW,
          height: origH,
          originalWidth: origW,
          originalHeight: origH,
          format: o.format,
          originalSizeBytes: input.length,
          targetSizeBytes: targetBytes,
          mode: o.mode,
          achievedQuality: null,
          targetAchieved: true,
          isOriginalPreserved: true,
          statusMessage: 'Original is already below target size. Preserved original file.',
        );
      }

      // If format changed or dimensions were explicitly set, test encoding
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

    // B. Target size optimization when targetBytes < input.length (or re-encoded exceeds target)
    if (o.format.isLossy) {
      return _optimizeLossy(input, base, origW, origH, userExplicitResize, o, targetBytes);
    } else {
      return _optimizeLosslessOrPalette(input, base, origW, origH, userExplicitResize, o, targetBytes);
    }
  }

  /// Quality-first bounded optimization for lossy formats (JPEG, WebP).
  ///
  /// Safe optimization pipeline:
  /// 1. Measures actual output bytes.
  /// 2. Never accepts an output larger than the original when reducing file size.
  /// 3. In High Quality mode, strictly enforces quality floor (85) and 100% original dimensions.
  /// 4. In Balanced / Smallest Size, carefully tests bounded dimension downscaling.
  /// 5. If target cannot be reached, returns best acceptable smaller result (< input.length).
  ///    If no smaller acceptable result exists, preserves original image.
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

    // 1. Measure output bytes at quality ceiling on full dimensions
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

    // 2. Measure output bytes at mode's quality floor on full dimensions
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

    // 3. Size at floor quality on full dimensions still exceeds targetBytes.
    // Track best candidate that is strictly smaller than the original input (< input.length).
    ({Uint8List bytes, int width, int height, int quality})? bestSmallerCandidate;

    if (atFloor.length < input.length) {
      bestSmallerCandidate = (
        bytes: atFloor,
        width: base.width,
        height: base.height,
        quality: floorQ,
      );
    }

    // 4. Test permitted dimension downscaling if mode permits and user didn't request explicit resize
    if (o.mode.allowDimensionScaling && !userExplicitResize) {
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
          // Fits within target! Find highest quality >= floorQ that still fits
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

        // Check if this candidate is strictly smaller than original input
        if (scaledAtFloor.length < input.length) {
          if (bestSmallerCandidate == null || scaledAtFloor.length < bestSmallerCandidate.bytes.length) {
            bestSmallerCandidate = (
              bytes: scaledAtFloor,
              width: newW,
              height: newH,
              quality: floorQ,
            );
          }
        }
      }
    }

    // 5. Target was NOT met within mode constraints.
    // Safe fallback:
    // If a smaller result was found (< input.length), return it with an honest warning.
    // If NO candidate was smaller than input.length, PRESERVE THE ORIGINAL! Never output a larger file!
    if (bestSmallerCandidate != null) {
      final achievedSize = bestSmallerCandidate.bytes.length;
      final reduction = ((input.length - achievedSize) / input.length * 100).toStringAsFixed(1);

      return ProcessedImage(
        bytes: bestSmallerCandidate.bytes,
        width: bestSmallerCandidate.width,
        height: bestSmallerCandidate.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: bestSmallerCandidate.quality,
        targetAchieved: false,
        statusMessage: 'Closest achieved: ${_formatBytes(achievedSize)} (-$reduction%)',
        warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached within ${o.mode.label} constraints (min $floorQ%). Produced best available reduction (${_formatBytes(achievedSize)}).',
      );
    }

    // Preserve original image
    return ProcessedImage(
      bytes: input,
      width: origW,
      height: origH,
      originalWidth: origW,
      originalHeight: origH,
      format: o.format,
      originalSizeBytes: input.length,
      targetSizeBytes: targetBytes,
      mode: o.mode,
      achievedQuality: null,
      targetAchieved: false,
      isOriginalPreserved: true,
      statusMessage: 'Original preserved: no smaller acceptable result found',
      warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached within ${o.mode.label} quality constraints (min $floorQ%) without exceeding original file size (${_formatBytes(input.length)}). Preserved original image.',
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

    ({Uint8List bytes, int width, int height})? bestSmallerCandidate;
    if (initial.length < input.length) {
      bestSmallerCandidate = (bytes: initial, width: base.width, height: base.height);
    }

    if (o.mode.allowDimensionScaling && !userExplicitResize) {
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

        if (candidate.length < input.length) {
          if (bestSmallerCandidate == null || candidate.length < bestSmallerCandidate.bytes.length) {
            bestSmallerCandidate = (bytes: candidate, width: newW, height: newH);
          }
        }
      }
    }

    if (bestSmallerCandidate != null) {
      final achievedSize = bestSmallerCandidate.bytes.length;
      final reduction = ((input.length - achievedSize) / input.length * 100).toStringAsFixed(1);
      return ProcessedImage(
        bytes: bestSmallerCandidate.bytes,
        width: bestSmallerCandidate.width,
        height: bestSmallerCandidate.height,
        originalWidth: origW,
        originalHeight: origH,
        format: o.format,
        originalSizeBytes: input.length,
        targetSizeBytes: targetBytes,
        mode: o.mode,
        achievedQuality: o.quality,
        targetAchieved: false,
        statusMessage: 'Closest achieved: ${_formatBytes(achievedSize)} (-$reduction%)',
        warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached within ${o.mode.label} limits. Produced best available reduction (${_formatBytes(achievedSize)}).',
      );
    }

    // Preserve original if no smaller acceptable output can be produced
    final formatExplanation = o.format == PicFormat.png
        ? 'PNG is a lossless format and cannot reduce bytes below original without further downscaling.'
        : '${o.format.label} cannot meet target without exceeding original file size.';

    return ProcessedImage(
      bytes: input,
      width: origW,
      height: origH,
      originalWidth: origW,
      originalHeight: origH,
      format: o.format,
      originalSizeBytes: input.length,
      targetSizeBytes: targetBytes,
      mode: o.mode,
      achievedQuality: null,
      targetAchieved: false,
      isOriginalPreserved: true,
      statusMessage: 'Original preserved: no smaller acceptable result found',
      warningMessage: 'Target of ${_formatBytes(targetBytes)} could not be reached. $formatExplanation Original image preserved.',
    );
  }

  /// Binary search quality in [minQ..maxQ] to find highest quality setting that fits <= [targetBytes].
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

  bool _isSameFormat(Uint8List data, PicFormat format) {
    final decoder = img.findDecoderForData(data);
    if (decoder == null) return false;
    switch (format) {
      case PicFormat.jpeg:
        return decoder is img.JpegDecoder;
      case PicFormat.png:
        return decoder is img.PngDecoder;
      case PicFormat.webp:
        return decoder is img.WebPDecoder;
      case PicFormat.gif:
        return decoder is img.GifDecoder;
      case PicFormat.bmp:
        return decoder is img.BmpDecoder;
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
