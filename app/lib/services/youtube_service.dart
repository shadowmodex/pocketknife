import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'download_error.dart';
import 'file_saver.dart';
import 'media_engine.dart';

class VideoMeta {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbUrl;
  const VideoMeta({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbUrl,
  });

  String get durationText {
    final d = duration;
    if (d == null) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '$h:${_two(m)}:${_two(s)}';
    return '$m:${_two(s)}';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class DownloadResult {
  final String tempPath;
  final String fileName;
  final String meta; // e.g. "1080p • 24.1 MB"
  const DownloadResult(this.tempPath, this.fileName, this.meta);
}

/// Wraps youtube_explode_dart for stream discovery/download, then hands off to
/// [MediaEngine] (FFmpeg) for the work Android can't do natively:
///   * Video downloads pick a separate H.264 video-only + AAC audio-only pair
///     and merge them into a playable MP4 — this lifts the old muxed-only 720p
///     ceiling up to whatever adaptive resolution YouTube offers (commonly
///     1080p). The real merged resolution is reported, never faked.
///   * Audio downloads grab the best audio-only track and transcode it to a
///     genuine MP3 (libmp3lame) with embedded metadata + cover art.
///
/// Only YouTube / YouTube Shorts are supported. Instagram (which the original
/// extension handled with the browser's login cookies) can't work from a
/// standalone app, so those URLs get a clear, honest error instead.
class YoutubeService {
  YoutubeService._();
  static final YoutubeService instance = YoutubeService._();

  final YoutubeExplode _yt = YoutubeExplode();
  final Dio _dio = Dio();

  // Monotonic counter folded into temp-file names so two downloads of the same
  // video (even started in the same microsecond) can never share scratch paths.
  int _seq = 0;

  // Stage labels surfaced to the UI via the optional onStage callback.
  static const _kGettingInfo = 'Getting video information';
  static const _kDownloadingVideo = 'Downloading video';
  static const _kDownloadingAudio = 'Downloading audio';
  static const _kMerging = 'Merging';
  static const _kConverting = 'Converting to MP3';

  /// Returns a user-facing reason when [url] points at a source we can't
  /// handle, or null when it looks like a supported YouTube link.
  static String? unsupportedReason(String url) {
    final uri = Uri.tryParse(url.trim());
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) return null; // bare ID etc. — let the parser try
    if (host.contains('instagram.com')) {
      return 'Instagram needs a logged-in session this app can\'t provide, so those links aren\'t supported. Paste a YouTube or Shorts link instead.';
    }
    final isYt = host.contains('youtube.com') ||
        host.contains('youtu.be') ||
        host.contains('youtube-nocookie.com');
    if (!isYt) {
      return 'Only YouTube and YouTube Shorts links are supported right now.';
    }
    return null;
  }

  static final RegExp _idExp = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// Extracts the canonical 11-character YouTube video ID from any common link
  /// shape — `watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`, `/live/`, `/v/` —
  /// no matter what extra query parameters follow (`?si=`, `&t=`, `&list=`) or
  /// which host variant is used (`www.`, `m.`, `music.`, `youtube-nocookie.com`),
  /// and accepts a bare ID or a scheme-less link. Returns null when the input
  /// carries no valid ID.
  ///
  /// This exists because the upstream parser anchors its `/shorts/` pattern to
  /// end-of-string, so a shared Short like `…/shorts/<id>?si=…` fails there. We
  /// resolve the ID ourselves and hand the client a clean URL instead.
  static String? extractVideoId(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;
    if (_idExp.hasMatch(raw)) return raw; // already a bare ID

    // Prepend a scheme for scheme-less pastes so host/path/query resolve.
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    bool isId(String? s) => s != null && _idExp.hasMatch(s);

    // youtu.be/<id>
    if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
      final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      if (isId(seg)) return seg;
      return null;
    }

    final isYtHost = host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtube-nocookie.com' ||
        host.endsWith('.youtube-nocookie.com');
    if (!isYtHost) return null;

    // watch?v=<id> — v may sit anywhere among the query parameters.
    final v = uri.queryParameters['v'];
    if (isId(v)) return v;

    // /shorts/<id>, /embed/<id>, /live/<id>, /v/<id>
    final segs = uri.pathSegments;
    for (var i = 0; i < segs.length - 1; i++) {
      final kind = segs[i];
      if (kind == 'shorts' || kind == 'embed' || kind == 'live' || kind == 'v') {
        if (isId(segs[i + 1])) return segs[i + 1];
      }
    }
    // Bare /<id> share form.
    if (segs.length == 1 && isId(segs.first)) return segs.first;
    return null;
  }

  /// Normalizes any supported link to a canonical watch URL the stream client
  /// always accepts; falls back to the trimmed input when no ID is found so the
  /// client can still attempt its own resolution.
  String _resolveUrl(String url) {
    final id = extractVideoId(url);
    return id != null ? 'https://www.youtube.com/watch?v=$id' : url.trim();
  }

  Future<VideoMeta> fetch(String url) async {
    final v = await _attempt(
        DownloadStage.metadata, (_) => _yt.videos.get(_resolveUrl(url)));
    return VideoMeta(
      id: v.id.value,
      title: v.title,
      author: v.author,
      duration: v.duration,
      thumbUrl: v.thumbnails.highResUrl,
    );
  }

  // ---------------------------------------------------------------------------
  // Video → merged MP4
  // ---------------------------------------------------------------------------

  Future<DownloadResult> downloadVideo(
    String url,
    String quality,
    void Function(double) onProgress, {
    void Function(String stage)? onStage,
  }) async {
    final target = int.tryParse(quality); // null => "best"
    onStage?.call(_kGettingInfo);

    final video = await _attempt(
        DownloadStage.metadata, (_) => _yt.videos.get(_resolveUrl(url)));
    var manifest = await _attempt(DownloadStage.manifest,
        (_) => _yt.videos.streamsClient.getManifest(video.id));

    final work = await FileSaver.instance.workDir();
    final id = video.id.value;
    final token = _token();

    // Prefer a separate H.264 video track + audio track (lifts the muxed-only
    // ceiling). The offered shape doesn't change across a refresh, so decide
    // once; when it isn't offered, fall back to the legacy muxed path.
    if (_pickAvc(manifest, target) == null || _pickAudio(manifest) == null) {
      return _downloadMuxed(
          video, manifest, target, token, work.path, onProgress, onStage);
    }

    final vTmp = '${work.path}/vo_${id}_$token.mp4';
    var aTmp = '${work.path}/ao_${id}_$token.m4a';
    final outTmp = '${work.path}/mux_${id}_$token.mp4';

    var height = 0;
    var audioIsAac = true;

    // Download both adaptive tracks. On a retry we refresh the manifest first
    // (so an expired signed URL is never re-requested) and reselect by the same
    // rule; _streamToFile tags the precise failing stage (video vs audio).
    await _attempt(DownloadStage.video, (attempt) async {
      if (attempt > 1) {
        try {
          manifest = await _yt.videos.streamsClient.getManifest(video.id);
        } catch (e, st) {
          throw DownloadException.classify(e, st, DownloadStage.manifest);
        }
      }
      final vChosen = _pickAvc(manifest, target)!;
      final aChosen = _pickAudio(manifest)!;
      audioIsAac = aChosen.audioCodec.toLowerCase().contains('mp4a');
      aTmp = '${work.path}/ao_${id}_$token.${audioIsAac ? 'm4a' : 'bin'}';
      height = vChosen.videoResolution.height;

      _log('video pick  ${height}p ${vChosen.videoCodec} ${vChosen.container} '
          '~${_size(vChosen.size.totalBytes)}');
      onStage?.call(_kDownloadingVideo);
      await _streamToFile(
          vChosen, vTmp, DownloadStage.video, (p) => onProgress(p * 0.45));
      _log('video saved ${_size(_fileSize(vTmp))}');

      _log('audio pick  ${aChosen.audioCodec} '
          '${aChosen.bitrate.bitsPerSecond ~/ 1000}kbps aac=$audioIsAac');
      onStage?.call(_kDownloadingAudio);
      await _streamToFile(aChosen, aTmp, DownloadStage.audio,
          (p) => onProgress(0.45 + p * 0.35));
      _log('audio saved ${_size(_fileSize(aTmp))}');
    });

    onStage?.call(_kMerging);
    await _process(() => MediaEngine.instance.muxToMp4(
          videoPath: vTmp,
          audioPath: aTmp,
          outPath: outTmp,
          audioIsAac: audioIsAac,
          total: video.duration,
          onProgress: (p) => onProgress(0.80 + p * 0.20),
        ));
    _requireFile(outTmp, 'The merged video file is missing.');
    _log('merged      ${_size(_fileSize(outTmp))} -> $outTmp');

    _quietDelete(vTmp);
    _quietDelete(aTmp);

    final name = '${_safe(video.title)}_${height}p.mp4';
    return DownloadResult(
        outTmp, name, '${height}p • ${_size(_fileSize(outTmp))}');
  }


  /// Legacy path: download a single progressive (muxed) stream. Used only when
  /// no adaptive H.264 video track or no audio track is available. Wrapped in
  /// the same retry / manifest-refresh / verify guarantees as the adaptive path.
  Future<DownloadResult> _downloadMuxed(
    Video video,
    StreamManifest manifest,
    int? target,
    String token,
    String workPath,
    void Function(double) onProgress,
    void Function(String stage)? onStage,
  ) async {
    final id = video.id.value;
    final outTmp = '$workPath/mux_${id}_$token.mp4';
    var height = 0;
    await _attempt(DownloadStage.video, (attempt) async {
      var m = manifest;
      if (attempt > 1) {
        try {
          m = await _yt.videos.streamsClient.getManifest(video.id);
        } catch (e, st) {
          throw DownloadException.classify(e, st, DownloadStage.manifest);
        }
      }
      final chosen = _pickMuxed(m, target);
      if (chosen == null) {
        throw DownloadException.of(
            kind: FailureKind.unavailable,
            stage: DownloadStage.selection,
            technical: 'No downloadable stream in manifest');
      }
      height = chosen.videoResolution.height;
      _log('muxed pick  ${height}p ${chosen.videoCodec} ${chosen.container} '
          '~${_size(chosen.size.totalBytes)}');
      onStage?.call(_kDownloadingVideo);
      await _streamToFile(chosen, outTmp, DownloadStage.video, onProgress);
    });
    _requireFile(outTmp, 'The video didn\'t download. Try again.');
    final name = '${_safe(video.title)}_${height}p.mp4';
    return DownloadResult(
        outTmp, name, '${height}p • ${_size(_fileSize(outTmp))}');
  }

  // ---------------------------------------------------------------------------
  // Audio → genuine MP3 (libmp3lame)
  // ---------------------------------------------------------------------------

  Future<DownloadResult> downloadMp3(
    String url,
    String bitrate,
    bool embedThumbnail,
    void Function(double) onProgress, {
    void Function(String stage)? onStage,
  }) async {
    final kbps = int.tryParse(bitrate) ?? 192;
    onStage?.call(_kGettingInfo);

    final video = await _attempt(
        DownloadStage.metadata, (_) => _yt.videos.get(_resolveUrl(url)));
    var manifest = await _attempt(DownloadStage.manifest,
        (_) => _yt.videos.streamsClient.getManifest(video.id));

    final work = await FileSaver.instance.workDir();
    final id = video.id.value;
    final token = _token();
    final srcTmp = '${work.path}/src_${id}_$token.bin';
    final outTmp = '${work.path}/out_${id}_$token.mp3';

    // Download the best audio track. A failure here is an *audio download*
    // failure — never reported as an encoding failure. Refresh + reselect on
    // retry so an expired stream URL isn't re-requested.
    await _attempt(DownloadStage.audio, (attempt) async {
      if (attempt > 1) {
        try {
          manifest = await _yt.videos.streamsClient.getManifest(video.id);
        } catch (e, st) {
          throw DownloadException.classify(e, st, DownloadStage.manifest);
        }
      }
      final src = _pickBestAudio(manifest);
      if (src == null) {
        throw DownloadException.of(
            kind: FailureKind.unavailable,
            stage: DownloadStage.selection,
            technical: 'No audio track in manifest');
      }
      _log('audio pick  ${src.audioCodec} '
          '${src.bitrate.bitsPerSecond ~/ 1000}kbps -> mp3 ${kbps}k');
      onStage?.call(_kDownloadingAudio);
      await _streamToFile(
          src, srcTmp, DownloadStage.audio, (p) => onProgress(p * 0.55));
    });
    // Fetch the cover as JPG so FFmpeg can embed it as attached_pic. A failure
    // here must not sink the download — we just skip the artwork.
    String? coverTmp;
    if (embedThumbnail) {
      coverTmp = '${work.path}/cover_${id}_$token.jpg';
      try {
        await _dio.download(video.thumbnails.highResUrl, coverTmp);
        onProgress(0.62);
      } catch (_) {
        _quietDelete(coverTmp);
        coverTmp = null;
      }
    }

    onStage?.call(_kConverting);
    await _process(() => MediaEngine.instance.toMp3(
          inputPath: srcTmp,
          outPath: outTmp,
          bitrateKbps: kbps,
          coverJpgPath: coverTmp,
          title: video.title,
          artist: video.author,
          total: video.duration,
          onProgress: (p) => onProgress(0.62 + p * 0.38),
        ));
    _requireFile(outTmp, 'The MP3 file is missing.');
    _log('encoded     ${_size(_fileSize(outTmp))} -> $outTmp');

    // Clean scratch inputs only after a verified non-empty MP3.
    _quietDelete(srcTmp);
    if (coverTmp != null) _quietDelete(coverTmp);

    final name = '${_safe(video.title)}.mp3';
    return DownloadResult(
        outTmp, name, '$kbps kbps • ${_size(_fileSize(outTmp))}');
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Streams [info] to [path] with hardening: a failure mid-download closes the
  /// sink, deletes the partial file, and rethrows a stage-correct classified
  /// error; a short read (fewer bytes than a known total) is treated as a
  /// retryable incomplete download, never as success; an unknown total (chunked
  /// transfer, reported as 0) is accepted on any non-empty EOF. The sink is
  /// always closed, even on error, so no handle or partial file leaks.
  Future<void> _streamToFile(
    StreamInfo info,
    String path,
    DownloadStage stage,
    void Function(double) onProgress,
  ) async {
    final total = info.size.totalBytes;
    final file = File(path);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in _yt.videos.streamsClient.get(info)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await _closeQuietly(sink);
    } catch (e, st) {
      await _closeQuietly(sink);
      _quietDelete(path); // never leave a half-written file behind
      throw DownloadException.classify(e, st, stage);
    }
    // A premature EOF (fewer bytes than the known total) is a failed partial,
    // not a success — surface it as a retryable incomplete download.
    if (!streamComplete(received: received, expectedTotal: total)) {
      _quietDelete(path);
      throw DownloadException.incompleteDownload(stage, received, total);
    }
  }

  /// Bounded retry wrapper. Runs [op] (passing the 1-based attempt number so a
  /// retry can refresh an expired manifest and reselect), classifies any
  /// failure, logs one compact, secret-free line, and retries ONLY when the
  /// failure is marked retryable and attempts remain. Invalid URLs and
  /// permanent failures (private/deleted/geo-blocked) are never retried; the
  /// loop is finite — at most [maxAttempts] tries — so it can never spin.
  Future<T> _attempt<T>(
    DownloadStage stage,
    Future<T> Function(int attempt) op, {
    int maxAttempts = 3,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await op(attempt);
      } catch (e, st) {
        final de = e is DownloadException
            ? e
            : DownloadException.classify(e, st, stage);
        _log('attempt $attempt/$maxAttempts ${de.logLine}');
        if (!de.retryable || attempt >= maxAttempts) throw de;
        await Future<void>.delayed(_backoff(attempt));
      }
    }
  }

  /// Short, growing pauses between attempts: ~0.8s then ~2.5s. Deliberately
  /// small and finite — enough to ride out a transient blip or let a refreshed
  /// signed URL settle, never a user-visible stall.
  Duration _backoff(int attempt) =>
      Duration(milliseconds: attempt <= 1 ? 800 : 2500);

  /// Runs an FFmpeg step, mapping any failure to a processing-stage error. The
  /// bytes are already on disk by this point, so a failure here is strictly
  /// processing — never reported as a download/network failure.
  Future<void> _process(Future<void> Function() op) async {
    try {
      await op();
    } catch (e, st) {
      throw DownloadException.classify(e, st, DownloadStage.processing);
    }
  }

  /// Monotonic, collision-proof scratch-file token (timestamp + sequence) so
  /// two downloads of the same video can never share a temp path.
  String _token() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  Future<void> _closeQuietly(IOSink sink) async {
    try {
      await sink.close();
    } catch (_) {
      // best-effort — the real error (if any) has already been captured
    }
  }

  // Stream selection — behavior frozen, lifted verbatim from the working
  // pipeline so the resolver/quality rules the user already relies on are
  // byte-for-byte unchanged. Only the shape (inline → named, nullable)
  // differs, so a refreshed manifest can be reselected by the identical rule.

  /// Best H.264 (avc) video-only track in an mp4 container, so the merge is a
  /// lossless stream-copy into a universally playable MP4. Returns the highest
  /// resolution at or below [target] (or the overall best when [target] is
  /// null); when nothing sits at/under the cap, the smallest available. Null
  /// when the video offers no adaptive H.264 track.
  VideoOnlyStreamInfo? _pickAvc(StreamManifest manifest, int? target) {
    final avc = manifest.videoOnly
        .where((s) =>
            s.container == StreamContainer.mp4 &&
            s.videoCodec.toLowerCase().startsWith('avc'))
        .toList()
      ..sort((a, b) =>
          b.videoResolution.height.compareTo(a.videoResolution.height));
    if (avc.isEmpty) return null;
    if (target == null) return avc.first;
    final atOrBelow =
        avc.where((s) => s.videoResolution.height <= target).toList();
    return atOrBelow.isNotEmpty ? atOrBelow.first : avc.last;
  }

  /// Best AAC (mp4a) audio-only track when present (lets the mux copy it);
  /// otherwise the highest-bitrate audio of any codec, which the mux step
  /// re-encodes to AAC. Null when the video offers no audio-only track.
  AudioOnlyStreamInfo? _pickAudio(StreamManifest manifest) {
    final audio = manifest.audioOnly.toList()
      ..sort(
          (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    if (audio.isEmpty) return null;
    final aacList = audio
        .where((s) => s.audioCodec.toLowerCase().contains('mp4a'))
        .toList();
    return aacList.isNotEmpty ? aacList.first : audio.first;
  }

  /// Highest-bitrate audio-only track of any codec — the source for MP3
  /// transcoding (libmp3lame re-encodes regardless of input codec, so codec
  /// choice is irrelevant and raw bitrate is all that matters). Null when the
  /// video offers no audio-only track.
  AudioOnlyStreamInfo? _pickBestAudio(StreamManifest manifest) {
    final audio = manifest.audioOnly.toList()
      ..sort(
          (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    return audio.isEmpty ? null : audio.first;
  }

  /// Best progressive (muxed) stream for the legacy fallback path, picked by
  /// the same at-or-below-[target] rule as the adaptive video track. Null when
  /// the manifest carries no muxed stream.
  MuxedStreamInfo? _pickMuxed(StreamManifest manifest, int? target) {
    final muxed = manifest.muxed.toList()
      ..sort((a, b) =>
          b.videoResolution.height.compareTo(a.videoResolution.height));
    if (muxed.isEmpty) return null;
    if (target == null) return muxed.first;
    final atOrBelow =
        muxed.where((s) => s.videoResolution.height <= target).toList();
    return atOrBelow.isNotEmpty ? atOrBelow.first : muxed.last;
  }

  int _fileSize(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// Throws a clear, user-facing error when [path] is missing or empty — so a
  /// failed/partial download fails fast with a real message instead of handing
  /// FFmpeg an empty input and stalling.
  void _requireFile(String path, String message) {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() <= 0) {
      _log('MISSING/EMPTY $path — $message');
      throw MediaEngineException(message);
    }
  }

  void _log(String msg) => debugPrint('[YouTube] $msg');

  void _quietDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // best-effort cleanup
    }
  }

  /// Turns a video title into a safe, compact file name stem.
  String _safe(String s) {
    var out = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (out.length > 60) out = out.substring(0, 60).trim();
    return out.isEmpty ? 'download' : out;
  }

  String _size(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    final s = i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s ${units[i]}';
  }

  void dispose() => _yt.close();
}
