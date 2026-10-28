import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/log.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_audio/session_state.dart';
import 'package:ffmpeg_kit_flutter_new_audio/statistics.dart';

/// Raised when an FFmpeg operation fails. Carries a short, user-facing message.
class MediaEngineException implements Exception {
  final String message;
  MediaEngineException(this.message);
  @override
  String toString() => message;
}

/// Thin wrapper over FFmpeg (via ffmpeg_kit_flutter_new_audio). Performs the two
/// jobs the app needs that Android has no built-in codec for:
///   * muxing a separate video-only + audio-only pair into a playable MP4, and
///   * transcoding an audio track into a genuine MP3 (libmp3lame) with embedded
///     ID3 metadata and cover art.
///
/// Arguments are passed as a list (never a joined string) so titles and paths
/// with spaces or quotes can't corrupt the command line.
class MediaEngine {
  MediaEngine._();
  static final MediaEngine instance = MediaEngine._();

  /// Combine [videoPath] (H.264) and [audioPath] into an MP4 at [outPath].
  /// The video track is always stream-copied (lossless, fast); the audio track
  /// is copied when it is already AAC, otherwise re-encoded to AAC so the file
  /// plays everywhere. [total] is the clip duration, used only for progress.
  Future<void> muxToMp4({
    required String videoPath,
    required String audioPath,
    required String outPath,
    required bool audioIsAac,
    Duration? total,
    required void Function(double) onProgress,
  }) async {
    final args = <String>[
      '-y',
      '-i', videoPath,
      '-i', audioPath,
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-c:v', 'copy',
      if (audioIsAac) ...['-c:a', 'copy'] else ...['-c:a', 'aac', '-b:a', '192k'],
      '-movflags', '+faststart',
      outPath,
    ];
    await _run(args, total, onProgress,
        'Couldn\'t combine the video and audio tracks.');
  }

  /// Transcode [inputPath] into a real MP3 at [bitrateKbps] kbps at [outPath].
  /// When [coverJpgPath] is given it is embedded as front cover art, and
  /// [title]/[artist] are written as ID3v2 tags.
  Future<void> toMp3({
    required String inputPath,
    required String outPath,
    required int bitrateKbps,
    String? coverJpgPath,
    String? title,
    String? artist,
    Duration? total,
    required void Function(double) onProgress,
  }) async {
    final hasCover = coverJpgPath != null;
    final args = <String>[
      '-y',
      '-i', inputPath,
      if (hasCover) ...['-i', coverJpgPath],
      '-map', '0:a:0',
      if (hasCover) ...['-map', '1:0'],
      '-c:a', 'libmp3lame',
      '-b:a', '${bitrateKbps}k',
      '-id3v2_version', '3',
      if (hasCover) ...[
        '-c:v', 'copy',
        '-metadata:s:v', 'title=Album cover',
        '-metadata:s:v', 'comment=Cover (front)',
        '-disposition:v', 'attached_pic',
      ],
      if (title != null && title.isNotEmpty) ...['-metadata', 'title=$title'],
      if (artist != null && artist.isNotEmpty) ...['-metadata', 'artist=$artist'],
      outPath,
    ];
    await _run(args, total, onProgress, 'Couldn\'t encode the MP3 file.');
  }

  // ---------------------------------------------------------------------------
  // Execution core
  // ---------------------------------------------------------------------------

  /// Runs an FFmpeg session and resolves only once its real outcome is known.
  ///
  /// The previous implementation waited solely on the async completion
  /// callback. That callback is delivered over the plugin's EventChannel and,
  /// in a release build, can silently never arrive — which left the UI pinned
  /// on "Merging"/"Processing" forever with no error. This version:
  ///
  ///   * completes its own future the instant the callback fires (fast path),
  ///     but *also* polls [FFmpegSession.getState] over the robust MethodChannel
  ///     so completion is detected even when the callback is lost;
  ///   * reads the authoritative state + return code, and verifies the output
  ///     file actually exists and is non-empty before reporting success;
  ///   * on a genuine stall, cancels the session and throws a real error with
  ///     the state, return code and the tail of the FFmpeg log — it never fakes
  ///     success or fabricates progress;
  ///   * emits concise, greppable diagnostics (command, session id, state,
  ///     return code, input/output paths, output size, log tail) to logcat so
  ///     the exact step can be observed on a real device via `adb logcat`.
  Future<void> _run(
    List<String> args,
    Duration? total,
    void Function(double) onProgress,
    String failMessage,
  ) async {
    final outPath = args.isNotEmpty ? args.last : '';
    final totalMs = total?.inMilliseconds ?? 0;
    final logTail = <String>[]; // bounded ring of recent FFmpeg log lines
    final done = Completer<void>();

    _log('run    out=$outPath');
    _log('args   ${args.join(' ')}');

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      // Completion callback — kept trivial and synchronous so it can never
      // throw back into the plugin's fire-and-forget dispatcher (which only
      // catches Exception, not Error) and strand this future.
      (FFmpegSession s) {
        if (!done.isCompleted) done.complete();
      },
      // Log callback — accumulate a bounded tail we can print on failure even
      // if getAllLogsAsString would block on a wedged session.
      (Log log) {
        final m = log.getMessage();
        if (m.isEmpty) return;
        logTail.add(m);
        if (logTail.length > 80) logTail.removeAt(0);
      },
      // Statistics callback — drives the progress bar. Guarded so a UI
      // listener throwing can't break the event pipeline.
      (Statistics s) {
        if (totalMs <= 0) return;
        try {
          onProgress((s.getTime() / totalMs).clamp(0.0, 0.99).toDouble());
        } catch (_) {}
      },
    );

    final sessionId = session.getSessionId();
    _log('session #$sessionId  cmd: ${session.getCommand()}');

    // Wait for a terminal state via callback OR polling, bounded by a generous
    // watchdog that scales with clip length. The watchdog only ever leads to a
    // thrown error, never to a success.
    final watchdog = _watchdogFor(total);
    final how = await _awaitTerminal(session, done, watchdog);

    // Authoritative outcome, read over the MethodChannel (survives a dead
    // EventChannel). Any platform error here is treated as a failure, not a
    // hang.
    SessionState state;
    ReturnCode? rc;
    try {
      state = await session.getState();
    } catch (e) {
      _log('getState threw: $e');
      state = SessionState.failed;
    }
    try {
      rc = await session.getReturnCode();
    } catch (e) {
      _log('getReturnCode threw: $e');
      rc = null;
    }

    final outFile = outPath.isEmpty ? null : File(outPath);
    final outExists = outFile != null && outFile.existsSync();
    final outSize = outExists ? outFile.lengthSync() : 0;

    _log('done   via=$how  state=${state.name}  rc=${rc?.getValue()}  '
        'out.exists=$outExists  out.size=$outSize');

    final ok = state == SessionState.completed &&
        ReturnCode.isSuccess(rc) &&
        outExists &&
        outSize > 0;
    if (ok) {
      onProgress(1.0);
      return;
    }

    // Not a success. If the session is somehow still alive, cancel it so it
    // can't keep running in the background.
    if (state == SessionState.created || state == SessionState.running) {
      _log('still ${state.name} after ${watchdog.inSeconds}s — cancelling #$sessionId');
      try {
        await FFmpegKit.cancel(sessionId);
      } catch (_) {}
    }

    // Surface the real FFmpeg error (return code + log tail) to logcat.
    final tail = logTail.isEmpty ? '(no FFmpeg log received)' : logTail.join();
    String? failTrace;
    try {
      failTrace = await session.getFailStackTrace();
    } catch (_) {}
    _log('FAILED $failMessage\n'
        '  state=${state.name} rc=${rc?.getValue()} how=$how\n'
        '${failTrace != null && failTrace.isNotEmpty ? '  failStackTrace: $failTrace\n' : ''}'
        '--- ffmpeg log tail ---\n$tail\n--- end ---');

    // Ran to completion but produced nothing usable — call that out precisely.
    if (state == SessionState.completed &&
        ReturnCode.isSuccess(rc) &&
        !(outExists && outSize > 0)) {
      throw MediaEngineException('$failMessage The converted file was empty.');
    }
    throw MediaEngineException(failMessage);
  }

  /// Resolves when the session reaches a terminal state. Races the completion
  /// callback ([done]) against a MethodChannel state poll so completion is
  /// detected even if the callback is never delivered. Returns how it resolved:
  /// `callback`, `poll`, or `timeout`.
  Future<String> _awaitTerminal(
    FFmpegSession session,
    Completer<void> done,
    Duration watchdog,
  ) async {
    final byCallback = done.future.then((_) => 'callback');

    Future<String> byPolling() async {
      final deadline = DateTime.now().add(watchdog);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (done.isCompleted) return 'callback';
        SessionState st;
        try {
          st = await session.getState();
        } catch (_) {
          continue; // transient platform hiccup — keep polling
        }
        if (st == SessionState.completed || st == SessionState.failed) {
          return 'poll';
        }
      }
      return 'timeout';
    }

    return Future.any<String>([byCallback, byPolling()]);
  }

  /// A deliberately generous safety net. Normal completion is detected the
  /// instant it happens (callback or ~0.7s poll), so this only bounds a truly
  /// wedged session. Scales with clip length; floor of three minutes.
  Duration _watchdogFor(Duration? total) {
    const floor = Duration(minutes: 3);
    if (total == null) return floor;
    final scaled = total * 4; // encode/mux is normally far faster than realtime
    return scaled > floor ? scaled : floor;
  }

  void _log(String msg) => debugPrint('[MediaEngine] $msg');
}
