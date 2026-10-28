import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'media_engine.dart';

/// Where in the download pipeline a failure happened. Used for logging and to
/// shape stage-correct messages — a connection drop while pulling the audio
/// track must never be reported as an FFmpeg/processing failure.
enum DownloadStage {
  resolve, // parsing / normalizing the pasted URL
  metadata, // fetching video info (title / author / duration)
  manifest, // fetching the stream manifest
  selection, // choosing video / audio streams from the manifest
  video, // downloading the video-only track
  audio, // downloading the audio track
  cover, // fetching cover art (non-fatal)
  processing, // FFmpeg mux / MP3 encode
  saving, // copying the finished file to its destination
}

/// The actionable category of a failure. Drives the user-facing message and
/// whether an automatic retry can plausibly help.
enum FailureKind {
  invalidUrl, // the link genuinely isn't a usable YouTube video
  network, // DNS / TLS / timeout / connection reset / closed mid-download
  rateLimit, // YouTube throttled this IP (HTTP 429)
  unavailable, // private / deleted / purchase-required / geo-blocked / live
  processing, // the bytes downloaded fine, but FFmpeg failed
  io, // couldn't write / save the output file locally
  unknown, // anything we couldn't positively identify
}

/// A classified, user-safe failure. [message] is the polished line shown to the
/// user; [technical] is a scrubbed, secret-free line meant only for logcat.
class DownloadException implements Exception {
  final FailureKind kind;
  final DownloadStage stage;
  final String technical; // scrubbed; safe to log, never shown to users
  final bool retryable;
  final int? statusCode;

  DownloadException._({
    required this.kind,
    required this.stage,
    required this.technical,
    required this.retryable,
    this.statusCode,
  });

  /// The polished, user-facing line. Never contains raw ClientException text,
  /// URLs, cookies, or tokens.
  String get message => _messageFor(kind, stage);

  /// One compact, secret-free line for logcat / `debugPrint`.
  String get logLine => 'stage=${stage.name} kind=${kind.name} '
      'retryable=$retryable status=${statusCode ?? '-'} :: $technical';

  @override
  String toString() => 'DownloadException($logLine)';

  /// Maps any raw error into a classified [DownloadException]. The caller passes
  /// the [stage] it was running so a failure is attributed to the right step.
  /// Classification is by concrete type — never by matching the ugly message
  /// text — so it stays correct in release builds.
  factory DownloadException.classify(
      Object error, StackTrace stack, DownloadStage stage) {
    if (error is DownloadException) return error;

    // FFmpeg stage — the bytes are already on disk, so this is strictly
    // processing, never a download/network failure.
    if (error is MediaEngineException) {
      return DownloadException._(
          kind: FailureKind.processing,
          stage: DownloadStage.processing,
          technical: _scrub(error.message),
          retryable: false);
    }

    // youtube_explode's VideoId throws ArgumentError on an unusable id.
    if (error is ArgumentError) {
      return DownloadException._(
          kind: FailureKind.invalidUrl,
          stage: stage,
          technical: _scrub(error.toString()),
          retryable: false);
    }
    return _classifyYoutube(error, stage) ?? _classifyTransport(error, stage);
  }

  /// Builds a classified failure directly (for conditions we detect ourselves,
  /// e.g. an empty manifest with no downloadable stream).
  factory DownloadException.of({
    required FailureKind kind,
    required DownloadStage stage,
    required String technical,
    bool retryable = false,
    int? statusCode,
  }) =>
      DownloadException._(
          kind: kind,
          stage: stage,
          technical: _scrub(technical),
          retryable: retryable,
          statusCode: statusCode);

  /// A premature EOF — fewer bytes than the known total. Retryable, since a
  /// fresh attempt against a refreshed manifest usually recovers it.
  factory DownloadException.incompleteDownload(
          DownloadStage stage, int received, int expectedTotal) =>
      DownloadException._(
          kind: FailureKind.network,
          stage: stage,
          technical: 'Incomplete download: $received/$expectedTotal bytes',
          retryable: true);
}


/// youtube_explode domain exceptions. These reach us only after the library's
/// own internal retry loop (and its 403-expiry manifest refresh) is exhausted.
DownloadException? _classifyYoutube(Object error, DownloadStage stage) {
  if (error is RequestLimitExceededException) {
    return DownloadException._(
        kind: FailureKind.rateLimit,
        stage: stage,
        technical: _scrub(error.message),
        retryable: true);
  }
  if (error is TransientFailureException) {
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: _scrub(error.message),
        retryable: true);
  }
  if (error is FatalFailureException) {
    final sc = error.statusCode;
    // 403 is usually an expired signed URL (a fresh manifest fixes it); 408 and
    // 5xx are transient; 429 is throttling; other 4xx mean the video is gone.
    final transient = sc == 403 || sc == 408 || sc == 429 || sc >= 500;
    return DownloadException._(
        kind: sc == 429
            ? FailureKind.rateLimit
            : transient
                ? FailureKind.network
                : FailureKind.unavailable,
        stage: stage,
        statusCode: sc,
        technical: 'HTTP $sc from YouTube',
        retryable: transient);
  }
  // Covers VideoUnavailable + VideoRequiresPurchase + plain/ live unplayable.
  if (error is VideoUnplayableException) {
    return DownloadException._(
        kind: FailureKind.unavailable,
        stage: stage,
        technical: _scrub(error.message),
        retryable: false);
  }
  if (error is HttpClientClosedException) {
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: 'YoutubeExplode http client was closed',
        retryable: false);
  }
  if (error is YoutubeExplodeException) {
    return DownloadException._(
        kind: FailureKind.unknown,
        stage: stage,
        technical: _scrub(error.message),
        retryable: false);
  }
  return null;
}

/// Transport-layer failures from dart:io, dart:async, and package:http. These
/// are the real source of the raw `ClientException` the user was seeing.
DownloadException _classifyTransport(Object error, DownloadStage stage) {
  if (error is SocketException) {
    final os = error.osError?.message ?? '';
    final dns = error.message.contains('Failed host lookup');
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: 'SocketException${dns ? ' (DNS)' : ''}: '
            '${_scrub('${error.message} $os')}',
        retryable: true);
  }
  // HandshakeException/CertificateException both extend TlsException.
  if (error is TlsException) {
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: 'TLS failure: ${_scrub(error.message)}',
        retryable: true);
  }
  if (error is TimeoutException) {
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: 'Timed out',
        retryable: true);
  }
  if (error is ClientException) {
    // package:http — connection reset / closed before full response, etc.
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: 'ClientException: ${_scrub(error.message)}',
        retryable: true);
  }
  if (error is HttpException) {
    return DownloadException._(
        kind: FailureKind.network,
        stage: stage,
        technical: 'HttpException: ${_scrub(error.message)}',
        retryable: true);
  }
  if (error is FileSystemException) {
    return DownloadException._(
        kind: FailureKind.io,
        stage: stage,
        technical: 'FileSystem: ${_scrub(error.message)}',
        retryable: false);
  }
  return DownloadException._(
      kind: FailureKind.unknown,
      stage: stage,
      technical: '${error.runtimeType}: ${_scrub(error.toString())}',
      retryable: false);
}

/// Builds the polished, user-facing line. Known categories get an actionable
/// message; an unidentified failure falls back to a stage-correct one so an
/// audio-download failure never masquerades as a processing failure.
String _messageFor(FailureKind kind, DownloadStage stage) {
  switch (kind) {
    case FailureKind.invalidUrl:
      return 'Invalid YouTube URL.';
    case FailureKind.network:
      return 'Couldn\'t connect to YouTube. Check your internet connection and '
          'try again.';
    case FailureKind.rateLimit:
      return 'YouTube temporarily rejected the request. Please try again in a '
          'moment.';
    case FailureKind.unavailable:
      return 'This video isn\'t currently available for download.';
    case FailureKind.processing:
      return 'The media was downloaded, but processing failed.';
    case FailureKind.io:
      return 'Couldn\'t save the download. Check your available storage and try '
          'again.';
    case FailureKind.unknown:
      switch (stage) {
        case DownloadStage.video:
          return 'Video download failed. Please try again.';
        case DownloadStage.audio:
          return 'Audio download failed. Please try again.';
        case DownloadStage.metadata:
        case DownloadStage.manifest:
          return 'Couldn\'t read that video\'s information. Please try again.';
        default:
          return 'Download failed. Please try again.';
      }
  }
}

/// Strips URLs (which can carry signatures/tokens) and collapses the multi-line
/// youtube_explode messages into one short, secret-free line for logging.
String _scrub(String input) {
  var out = input.replaceAll(RegExp(r'https?://\S+'), '<url>');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (out.length > 200) out = '${out.substring(0, 200)}…';
  return out;
}

/// A download is complete only when it produced bytes and — when the expected
/// size is known (>0) — reached at least that many. Streams with an unknown
/// total (chunked, reported as 0) are judged complete on any non-empty EOF, so
/// legitimate chunked transfers are never rejected.
bool streamComplete({required int received, required int expectedTotal}) {
  if (received <= 0) return false;
  if (expectedTotal <= 0) return true;
  return received >= expectedTotal;
}



