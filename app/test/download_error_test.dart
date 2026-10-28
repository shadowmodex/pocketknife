import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:pocketknife/services/download_error.dart';
import 'package:pocketknife/services/media_engine.dart';

/// Offline, deterministic coverage for the download failure-classification
/// layer — the module that turns any raw error into a stage-correct, user-safe
/// [DownloadException]. No network is touched, so these run in CI.
void main() {
  group('classify — short-circuit cases', () {
    test('an existing DownloadException is returned unchanged', () {
      final original = DownloadException.of(
          kind: FailureKind.rateLimit,
          stage: DownloadStage.manifest,
          technical: 'x',
          retryable: true);
      final out = DownloadException.classify(
          original, StackTrace.current, DownloadStage.video);
      expect(identical(out, original), isTrue);
    });

    test('MediaEngineException is always processing, never a download failure',
        () {
      // Even though we claim the audio stage, FFmpeg errors are processing —
      // the bytes are already on disk, so this can never be a network failure.
      final out = DownloadException.classify(MediaEngineException('ffmpeg died'),
          StackTrace.current, DownloadStage.audio);
      expect(out.kind, FailureKind.processing);
      expect(out.stage, DownloadStage.processing);
      expect(out.retryable, isFalse);
    });

    test('ArgumentError (bad VideoId) is an invalid URL, not a network error',
        () {
      final out = DownloadException.classify(
          ArgumentError('bad id'), StackTrace.current, DownloadStage.resolve);
      expect(out.kind, FailureKind.invalidUrl);
      expect(out.stage, DownloadStage.resolve);
      expect(out.retryable, isFalse);
    });
  });

  group('classify — youtube_explode domain exceptions', () {
    test('RequestLimitExceededException → rate limit, retryable', () {
      final out = DownloadException.classify(
          RequestLimitExceededException('429'),
          StackTrace.current,
          DownloadStage.manifest);
      expect(out.kind, FailureKind.rateLimit);
      expect(out.retryable, isTrue);
    });

    test('TransientFailureException → network, retryable', () {
      final out = DownloadException.classify(TransientFailureException('5xx'),
          StackTrace.current, DownloadStage.manifest);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
    });

    test('FatalFailureException 403 → network + retryable (expired signed URL)',
        () {
      final out = DownloadException.classify(FatalFailureException('403', 403),
          StackTrace.current, DownloadStage.video);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
      expect(out.statusCode, 403);
    });

    test('FatalFailureException 429 → rate limit, retryable', () {
      final out = DownloadException.classify(FatalFailureException('429', 429),
          StackTrace.current, DownloadStage.video);
      expect(out.kind, FailureKind.rateLimit);
      expect(out.retryable, isTrue);
    });

    test('FatalFailureException 503 → network, retryable', () {
      final out = DownloadException.classify(FatalFailureException('503', 503),
          StackTrace.current, DownloadStage.video);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
    });

    test('FatalFailureException 404 → unavailable, NOT retryable', () {
      final out = DownloadException.classify(FatalFailureException('404', 404),
          StackTrace.current, DownloadStage.metadata);
      expect(out.kind, FailureKind.unavailable);
      expect(out.retryable, isFalse);
      expect(out.statusCode, 404);
    });

    test('VideoUnplayableException → unavailable, NOT retryable', () {
      final out = DownloadException.classify(VideoUnplayableException('nope'),
          StackTrace.current, DownloadStage.metadata);
      expect(out.kind, FailureKind.unavailable);
      expect(out.retryable, isFalse);
    });

    test('VideoUnavailableException (subclass) → unavailable', () {
      final out = DownloadException.classify(
          VideoUnavailableException('deleted'),
          StackTrace.current,
          DownloadStage.metadata);
      expect(out.kind, FailureKind.unavailable);
      expect(out.retryable, isFalse);
    });

    test('HttpClientClosedException → network, NOT retryable', () {
      final out = DownloadException.classify(HttpClientClosedException(),
          StackTrace.current, DownloadStage.audio);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isFalse);
    });

    test('base YoutubeExplodeException → unknown, NOT retryable', () {
      final out = DownloadException.classify(YoutubeExplodeException('mystery'),
          StackTrace.current, DownloadStage.manifest);
      expect(out.kind, FailureKind.unknown);
      expect(out.retryable, isFalse);
    });
  });

  group('classify — transport (dart:io / http) exceptions', () {
    test('ClientException → network, retryable (the real ERROR B source)', () {
      final out = DownloadException.classify(
          ClientException('Connection closed before full header was received'),
          StackTrace.current,
          DownloadStage.audio);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
      // Must keep the stage it failed at — an audio drop is NOT processing.
      expect(out.stage, DownloadStage.audio);
    });

    test('SocketException with "Failed host lookup" is tagged DNS', () {
      final out = DownloadException.classify(
          const SocketException('Failed host lookup: www.youtube.com'),
          StackTrace.current,
          DownloadStage.metadata);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
      expect(out.technical, contains('DNS'));
    });

    test('TlsException → network, retryable', () {
      final out = DownloadException.classify(const TlsException('handshake'),
          StackTrace.current, DownloadStage.manifest);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
    });

    test('TimeoutException → network, retryable', () {
      final out = DownloadException.classify(TimeoutException('too slow'),
          StackTrace.current, DownloadStage.video);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
    });

    test('HttpException → network, retryable', () {
      final out = DownloadException.classify(const HttpException('bad'),
          StackTrace.current, DownloadStage.video);
      expect(out.kind, FailureKind.network);
      expect(out.retryable, isTrue);
    });

    test('FileSystemException → io, NOT retryable', () {
      final out = DownloadException.classify(
          const FileSystemException('No space left on device'),
          StackTrace.current,
          DownloadStage.saving);
      expect(out.kind, FailureKind.io);
      expect(out.retryable, isFalse);
    });

    test('an unrecognized error → unknown, NOT retryable', () {
      final out = DownloadException.classify(const FormatException('weird'),
          StackTrace.current, DownloadStage.manifest);
      expect(out.kind, FailureKind.unknown);
      expect(out.retryable, isFalse);
    });
  });

  group('user-facing messages — exact, stage-correct, secret-free', () {
    DownloadException make(FailureKind kind, DownloadStage stage) =>
        DownloadException.of(kind: kind, stage: stage, technical: 't');

    test('each kind maps to its exact spec string', () {
      expect(make(FailureKind.invalidUrl, DownloadStage.resolve).message,
          'Invalid YouTube URL.');
      expect(
          make(FailureKind.network, DownloadStage.video).message,
          'Couldn\'t connect to YouTube. Check your internet connection and '
          'try again.');
      expect(make(FailureKind.rateLimit, DownloadStage.manifest).message,
          'YouTube temporarily rejected the request. Please try again in a moment.');
      expect(make(FailureKind.unavailable, DownloadStage.metadata).message,
          'This video isn\'t currently available for download.');
      expect(make(FailureKind.processing, DownloadStage.processing).message,
          'The media was downloaded, but processing failed.');
      expect(
          make(FailureKind.io, DownloadStage.saving).message,
          'Couldn\'t save the download. Check your available storage and try '
          'again.');
    });

    test('unknown failures fall back to a STAGE-correct message', () {
      expect(make(FailureKind.unknown, DownloadStage.video).message,
          'Video download failed. Please try again.');
      expect(make(FailureKind.unknown, DownloadStage.audio).message,
          'Audio download failed. Please try again.');
      expect(make(FailureKind.unknown, DownloadStage.metadata).message,
          'Couldn\'t read that video\'s information. Please try again.');
      expect(make(FailureKind.unknown, DownloadStage.manifest).message,
          'Couldn\'t read that video\'s information. Please try again.');
      expect(make(FailureKind.unknown, DownloadStage.processing).message,
          'Download failed. Please try again.');
    });

    test('the user message never leaks raw ClientException text or URLs', () {
      final out = DownloadException.classify(
          ClientException(
              'ClientException at https://r3.googlevideo.com/videoplayback?sig=SECRETTOKEN'),
          StackTrace.current,
          DownloadStage.audio);
      expect(
          out.message,
          'Couldn\'t connect to YouTube. Check your internet connection and '
          'try again.');
      expect(out.message, isNot(contains('ClientException')));
      expect(out.message, isNot(contains('http')));
      // …and the loggable technical line is scrubbed of the signed URL.
      expect(out.technical, isNot(contains('SECRETTOKEN')));
      expect(out.technical, isNot(contains('googlevideo.com')));
      expect(out.technical, contains('<url>'));
    });
  });

  group('_scrub via technical — strips URLs, collapses, truncates', () {
    DownloadException tech(String t) => DownloadException.of(
        kind: FailureKind.network, stage: DownloadStage.video, technical: t);

    test('replaces any http(s) URL with <url>', () {
      final e = tech('boom http://evil.test/a?tok=abc then https://x.y/z done');
      expect(e.technical, isNot(contains('tok=abc')));
      expect(e.technical, isNot(contains('evil.test')));
      expect(e.technical, contains('<url>'));
    });

    test('collapses runs of whitespace into single spaces', () {
      expect(tech('line one\n\n   line\ttwo').technical, 'line one line two');
    });

    test('truncates very long technical text', () {
      final e = tech('x' * 300);
      expect(e.technical.length, lessThanOrEqualTo(201));
      expect(e.technical.endsWith('…'), isTrue);
    });
  });

  group('logLine — compact, greppable, carries status', () {
    test('includes stage, kind, retryable and status', () {
      final e = DownloadException.of(
          kind: FailureKind.rateLimit,
          stage: DownloadStage.manifest,
          technical: 'HTTP 429 from YouTube',
          retryable: true,
          statusCode: 429);
      expect(e.logLine, contains('stage=manifest'));
      expect(e.logLine, contains('kind=rateLimit'));
      expect(e.logLine, contains('retryable=true'));
      expect(e.logLine, contains('status=429'));
    });
  });

  group('incompleteDownload — premature EOF is a retryable network failure',
      () {
    test('classified network + retryable and reports the byte shortfall', () {
      final e =
          DownloadException.incompleteDownload(DownloadStage.video, 50, 100);
      expect(e.kind, FailureKind.network);
      expect(e.retryable, isTrue);
      expect(e.stage, DownloadStage.video);
      expect(e.technical, contains('50/100'));
    });
  });

  group('streamComplete — partial vs complete vs chunked', () {
    test('zero or negative received is never complete', () {
      expect(streamComplete(received: 0, expectedTotal: 0), isFalse);
      expect(streamComplete(received: 0, expectedTotal: 100), isFalse);
      expect(streamComplete(received: -1, expectedTotal: 100), isFalse);
    });

    test('short read against a known total is incomplete', () {
      expect(streamComplete(received: 50, expectedTotal: 100), isFalse);
    });

    test('meeting or exceeding a known total is complete', () {
      expect(streamComplete(received: 100, expectedTotal: 100), isTrue);
      expect(streamComplete(received: 120, expectedTotal: 100), isTrue);
    });

    test('unknown total (chunked, 0) is complete on any non-empty read', () {
      expect(streamComplete(received: 1, expectedTotal: 0), isTrue);
      expect(streamComplete(received: 999, expectedTotal: 0), isTrue);
    });
  });
}

