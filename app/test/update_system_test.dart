import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketknife/models/update_info.dart';
import 'package:pocketknife/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersion', () {
    test('parses standard semver versions', () {
      final v1 = AppVersion.parse('1.0.0');
      expect(v1.major, 1);
      expect(v1.minor, 0);
      expect(v1.patch, 0);
      expect(v1.versionCode, 0);

      final v2 = AppVersion.parse('v2.4.15');
      expect(v2.major, 2);
      expect(v2.minor, 4);
      expect(v2.patch, 15);

      final v3 = AppVersion.parse('1.2.3+5');
      expect(v3.major, 1);
      expect(v3.minor, 2);
      expect(v3.patch, 3);
      expect(v3.versionCode, 5);
    });

    test('compares versions accurately', () {
      final v100 = AppVersion.parse('1.0.0');
      final v101 = AppVersion.parse('1.0.1');
      final v110 = AppVersion.parse('1.1.0');
      final v200 = AppVersion.parse('2.0.0');

      expect(v101.isNewerThan(v100), true);
      expect(v110.isNewerThan(v101), true);
      expect(v200.isNewerThan(v110), true);

      // Same versions
      expect(v100.isNewerThan(v100), false);
      expect(v100.compareTo(v100), 0);
      expect(v100 == v100, true);

      // Downgrade cases
      expect(v100.isNewerThan(v101), false);
      expect(v101.isNewerThan(v110), false);
    });

    test('compares version codes when semver is identical', () {
      final v1 = AppVersion.parse('1.0.0+1');
      final v2 = AppVersion.parse('1.0.0+2');
      expect(v2.isNewerThan(v1), true);
      expect(v1.isNewerThan(v2), false);

      final vExplicit1 = AppVersion.parse('1.0.0', versionCode: 3);
      final vExplicit2 = AppVersion.parse('1.0.0', versionCode: 4);
      expect(vExplicit2.isNewerThan(vExplicit1), true);
    });

    test('throws FormatException on malformed versions', () {
      expect(() => AppVersion.parse(''), throwsFormatException);
      expect(() => AppVersion.parse('abc'), throwsFormatException);
      expect(() => AppVersion.parse('1..0'), throwsFormatException);
      expect(() => AppVersion.parse('1.-2.3'), throwsFormatException);
    });

    test('tryParse safely handles null and invalid inputs', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse('invalid'), isNull);
      expect(AppVersion.tryParse('1.0.0'), isNotNull);
    });
  });

  group('UpdateManifest', () {
    test('parses valid manifest JSON', () {
      const jsonStr = '''
      {
        "version": "1.0.1",
        "versionCode": 2,
        "releaseNotes": "Fixed dark mode and improved PDF merge speed.",
        "apkUrl": "https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk",
        "minimumSupportedVersion": "1.0.0",
        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "fileSizeBytes": 15728640
      }
      ''';

      final manifest = UpdateManifest.fromJsonString(jsonStr);
      expect(manifest.version, '1.0.1');
      expect(manifest.versionCode, 2);
      expect(manifest.releaseNotes, contains('PDF merge speed'));
      expect(manifest.apkUrl, contains('PocketKnife.apk'));
      expect(manifest.sha256, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(manifest.fileSizeBytes, 15728640);
      expect(manifest.appVersion.major, 1);
      expect(manifest.appVersion.minor, 0);
      expect(manifest.appVersion.patch, 1);
    });

    test('rejects insecure non-HTTPS apkUrl', () {
      final jsonMap = {
        'version': '1.0.1',
        'versionCode': 2,
        'apkUrl': 'http://github.com/shadowmodex/pocketknife/releases/download/app.apk',
      };
      expect(() => UpdateManifest.fromJson(jsonMap), throwsFormatException);
    });

    test('rejects untrusted domains for apkUrl', () {
      final jsonMap = {
        'version': '1.0.1',
        'versionCode': 2,
        'apkUrl': 'https://malicious-site.com/download/app.apk',
      };
      expect(() => UpdateManifest.fromJson(jsonMap), throwsA(isA<FormatException>()));
    });

    test('accepts trusted GitHub domains and CDNs', () {
      final allowed = [
        'https://github.com/shadowmodex/pocketknife/releases/download/v1.0.1/PocketKnife.apk',
        'https://objects.githubusercontent.com/github-production-release-asset-2e65be/PocketKnife.apk',
        'https://raw.githubusercontent.com/shadowmodex/pocketknife/main/PocketKnife.apk',
      ];

      for (final url in allowed) {
        final manifest = UpdateManifest.fromJson({
          'version': '1.0.1',
          'versionCode': 2,
          'apkUrl': url,
        });
        expect(manifest.apkUrl, url);
      }
    });

    test('rejects invalid SHA-256 strings', () {
      final jsonMap = {
        'version': '1.0.1',
        'versionCode': 2,
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
        'sha256': 'short_hash_123',
      };
      expect(() => UpdateManifest.fromJson(jsonMap), throwsFormatException);
    });
  });

  group('UpdateService Lifecycle with Mock Networking', () {
    late UpdateService service;
    late Directory testTempDir;

    setUp(() {
      testTempDir = Directory.systemTemp.createTempSync('pk_update_test_');
      service = UpdateService.instance;
      service.setCurrentVersion(AppVersion.parse('1.0.0', versionCode: 1));
      service.customClientFactory = null;
      service.customTempDirProvider = () => testTempDir;
      service.reset();
    });

    tearDown(() {
      if (testTempDir.existsSync()) {
        try {
          testTempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('detects update when newer version is returned', () async {
      final responseJson = json.encode({
        'version': '1.0.2',
        'versionCode': 3,
        'releaseNotes': 'New features added.',
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
      });

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: utf8.encode(responseJson),
          );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.updateAvailable);
      expect(service.latestManifest?.version, '1.0.2');
      expect(service.errorMessage, isNull);
    });

    test('detects up to date when same version is returned', () async {
      final responseJson = json.encode({
        'version': '1.0.0',
        'versionCode': 1,
        'releaseNotes': 'No changes.',
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
      });

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: utf8.encode(responseJson),
          );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.upToDate);
      expect(service.errorMessage, isNull);
    });

    test('handles HTTP 404 server error gracefully', () async {
      service.customClientFactory = () => _MockHttpClient(
            statusCode: 404,
            responseBytes: utf8.encode('Not Found'),
          );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('404'));
    });

    test('handles network SocketException gracefully without crashing', () async {
      service.customClientFactory = () => _MockHttpClient(
            throwOnRequest: const SocketException('Connection refused'),
          );

      await service.checkForUpdates();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('Unable to reach GitHub'));
    });

    test('downloads APK, updates progress, and verifies checksum', () async {
      final apkBytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      final expectedSha = sha256.convert(apkBytes).toString();

      final manifestJson = json.encode({
        'version': '1.0.1',
        'versionCode': 2,
        'releaseNotes': 'Test update.',
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
        'sha256': expectedSha,
        'fileSizeBytes': apkBytes.length,
      });

      // 1. Check update
      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: utf8.encode(manifestJson),
          );
      await service.checkForUpdates();
      expect(service.status, UpdateStatus.updateAvailable);

      // 2. Download update
      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: apkBytes,
          );
      await service.downloadUpdate();

      expect(service.status, UpdateStatus.readyToInstall);
      expect(service.downloadProgress, 1.0);
      expect(service.downloadedApkPath, isNotNull);
      expect(File(service.downloadedApkPath!).existsSync(), true);

      // Cleanup
      File(service.downloadedApkPath!).deleteSync();
    });

    test('fails and deletes file when SHA-256 checksum mismatches', () async {
      final apkBytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      const wrongSha = '0000000000000000000000000000000000000000000000000000000000000000';

      final manifestJson = json.encode({
        'version': '1.0.1',
        'versionCode': 2,
        'releaseNotes': 'Test update.',
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
        'sha256': wrongSha,
        'fileSizeBytes': apkBytes.length,
      });

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: utf8.encode(manifestJson),
          );
      await service.checkForUpdates();

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: apkBytes,
          );
      await service.downloadUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('Checksum mismatch'));
    });

    test('fails and rejects download when SHA-256 checksum is missing', () async {
      final apkBytes = Uint8List.fromList(List.generate(2048, (i) => i % 256));

      final manifestJson = json.encode({
        'version': '1.0.1',
        'versionCode': 2,
        'releaseNotes': 'Test update without checksum.',
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
        'fileSizeBytes': apkBytes.length,
      });

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: utf8.encode(manifestJson),
          );
      await service.checkForUpdates();

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: apkBytes,
          );
      await service.downloadUpdate();

      expect(service.status, UpdateStatus.error);
      expect(service.errorMessage, contains('missing required SHA-256'));
    });

    test('evaluates isMandatoryUpdate correctly based on minimumSupportedVersion', () async {
      final manifestJson = json.encode({
        'version': '2.0.0',
        'versionCode': 10,
        'releaseNotes': 'Major overhaul.',
        'apkUrl': 'https://github.com/shadowmodex/pocketknife/releases/latest/download/PocketKnife.apk',
        'minimumSupportedVersion': '1.5.0',
        'sha256': '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      });

      service.customClientFactory = () => _MockHttpClient(
            statusCode: 200,
            responseBytes: utf8.encode(manifestJson),
          );

      // Current is 1.0.0, minimum is 1.5.0 -> Mandatory
      service.setCurrentVersion(const AppVersion(major: 1, minor: 0, patch: 0, versionCode: 1, raw: '1.0.0'));
      await service.checkForUpdates();
      expect(service.isMandatoryUpdate, true);

      // Current is 1.5.0, minimum is 1.5.0 -> Not mandatory
      service.setCurrentVersion(const AppVersion(major: 1, minor: 5, patch: 0, versionCode: 5, raw: '1.5.0'));
      expect(service.isMandatoryUpdate, false);

      // Current is 1.6.0, minimum is 1.5.0 -> Not mandatory
      service.setCurrentVersion(const AppVersion(major: 1, minor: 6, patch: 0, versionCode: 6, raw: '1.6.0'));
      expect(service.isMandatoryUpdate, false);
    });
  });
}

// ============================================================================
// Mock HTTP Client Infrastructure for Isolated Offline Testing
// ============================================================================

class _MockHttpClient implements HttpClient {
  final int statusCode;
  final List<int>? responseBytes;
  final Exception? throwOnRequest;

  _MockHttpClient({
    this.statusCode = 200,
    this.responseBytes,
    this.throwOnRequest,
  });

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    if (throwOnRequest != null) throw throwOnRequest!;
    return _MockHttpClientRequest(
      statusCode: statusCode,
      responseBytes: responseBytes ?? [],
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final List<int> responseBytes;

  _MockHttpClientRequest({
    required this.statusCode,
    required this.responseBytes,
  });

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  Future<HttpClientResponse> close() async {
    return _MockHttpClientResponse(
      statusCode: statusCode,
      responseBytes: responseBytes,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> responseBytes;

  _MockHttpClientResponse({
    required this.statusCode,
    required this.responseBytes,
  });

  @override
  int get contentLength => responseBytes.length;

  @override
  bool get isRedirect => false;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(responseBytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, String> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _headers[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

