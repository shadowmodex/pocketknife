import 'package:flutter_test/flutter_test.dart';
import 'package:pocketknife/services/youtube_service.dart';

/// Pure, offline coverage for YouTube link handling — the two functions that
/// decide whether a pasted URL is accepted and which 11-char video ID it maps
/// to. No network is touched, so these run deterministically in CI.
void main() {
  const id = 'dQw4w9WgXcQ'; // valid 11-char ID shape

  group('extractVideoId — supported shapes resolve to the ID', () {
    final cases = <String, String>{
      // youtube.com/watch
      'https://www.youtube.com/watch?v=$id': id,
      'https://youtube.com/watch?v=$id': id,
      'https://m.youtube.com/watch?v=$id': id,
      'https://music.youtube.com/watch?v=$id': id,
      // youtu.be
      'https://youtu.be/$id': id,
      // shorts (www + no-www)
      'https://www.youtube.com/shorts/$id': id,
      'https://youtube.com/shorts/$id': id,
      // with the ?si= share parameter
      'https://www.youtube.com/watch?v=$id&si=AbCdEf123': id,
      'https://youtu.be/$id?si=AbCdEf123': id,
      'https://www.youtube.com/shorts/$id?si=AbCdEf123': id,
      // multiple / reordered query params
      'https://www.youtube.com/watch?feature=share&v=$id': id,
      'https://www.youtube.com/watch?v=$id&list=PLxyz&index=2&t=30s': id,
      'https://youtu.be/$id?t=30&si=AbCdEf123': id,
      // embed / live / nocookie
      'https://www.youtube.com/embed/$id': id,
      'https://www.youtube.com/live/$id': id,
      'https://www.youtube-nocookie.com/embed/$id': id,
      // scheme-less paste + surrounding whitespace + bare ID
      'youtube.com/watch?v=$id': id,
      '  https://youtu.be/$id?si=AbCdEf123  ': id,
      id: id,
    };
    cases.forEach((url, expected) {
      test('resolves ${url.trim()}', () {
        expect(YoutubeService.extractVideoId(url), expected);
      });
    });
  });

  group('extractVideoId — malformed / unsupported yield null', () {
    for (final bad in <String>[
      '',
      '   ',
      'not a url',
      'https://vimeo.com/12345',
      'https://www.instagram.com/reel/CxYz/',
      'https://www.youtube.com/watch?v=tooShort',
      'https://www.youtube.com/watch?v=waytoolongforanid11',
      'https://www.youtube.com/', // no ID anywhere
    ]) {
      test('null for "${bad.trim()}"', () {
        expect(YoutubeService.extractVideoId(bad), isNull);
      });
    }
  });

  group('unsupportedReason — source gate', () {
    test('accepts every supported YouTube shape (never flagged)', () {
      for (final url in <String>[
        'https://www.youtube.com/watch?v=$id',
        'https://youtube.com/watch?v=$id',
        'https://youtu.be/$id',
        'https://www.youtube.com/shorts/$id',
        'https://youtube.com/shorts/$id',
        'https://www.youtube.com/watch?v=$id&si=AbCdEf123',
        'https://youtu.be/$id?si=AbCdEf123',
        'https://www.youtube.com/shorts/$id?si=AbCdEf123',
        'https://www.youtube-nocookie.com/embed/$id',
      ]) {
        expect(YoutubeService.unsupportedReason(url), isNull,
            reason: 'should accept $url');
      }
    });

    test('a valid YouTube URL is NEVER classified as Instagram', () {
      for (final url in <String>[
        'https://www.youtube.com/watch?v=$id&si=AbCdEf123',
        'https://youtu.be/$id?si=AbCdEf123',
        'https://www.youtube.com/shorts/$id?si=AbCdEf123',
      ]) {
        final reason = YoutubeService.unsupportedReason(url);
        expect(reason, isNull);
        expect(reason?.contains('Instagram') ?? false, isFalse);
      }
    });

    test('Instagram links get the Instagram-specific message', () {
      final reason =
          YoutubeService.unsupportedReason('https://www.instagram.com/reel/CxYz/');
      expect(reason, isNotNull);
      expect(reason, contains('Instagram'));
    });

    test('other hosts get the generic unsupported message', () {
      final reason = YoutubeService.unsupportedReason('https://vimeo.com/12345');
      expect(reason, isNotNull);
      expect(reason, contains('Only YouTube'));
    });

    test('bare ID / empty host is left for the parser (null)', () {
      expect(YoutubeService.unsupportedReason(id), isNull);
    });
  });
}
