// Unit tests for the pure helpers in util.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketknife/util.dart';
import 'package:pocketknife/services/pdf_service.dart';

void main() {
  group('safeName', () {
    test('strips unsafe characters', () {
      expect(safeName('my/report:final?.txt'), 'my report final .txt');
    });
    test('collapses whitespace and trims', () {
      expect(safeName('  a   b  '), 'a b');
    });
    test('falls back to document when empty', () {
      expect(safeName('   '), 'document');
      expect(safeName(r'\/:*?"<>|'), 'document');
    });
  });

  group('humanSize', () {
    test('formats bytes', () {
      expect(humanSize(0), '0 B');
      expect(humanSize(1024), '1.0 KB');
      expect(humanSize(1024 * 1024), '1.0 MB');
    });
  });

  group('parseRanges', () {
    test('parses single pages and ranges into 0-based indices', () {
      expect(parseRanges('1-3, 5', 10), [0, 1, 2, 4]);
    });
    test('de-duplicates in order', () {
      expect(parseRanges('2, 1-3, 2', 10), [1, 0, 2]);
    });
    test('bounds by count and ignores invalid tokens', () {
      expect(parseRanges('1, 99, abc, 3', 3), [0, 2]);
    });
  });
}
