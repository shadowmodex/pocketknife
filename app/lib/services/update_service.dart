import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/update_info.dart';

/// Service coordinating the in-app update check, APK download, verification,
/// and Android package installer handoff.
class UpdateService extends ChangeNotifier {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Default stable manifest URL hosted on GitHub raw content.
  static const String defaultManifestUrl =
      'https://raw.githubusercontent.com/shadowmodex/pocketknife/main/app-update.json';

  String _manifestUrl = defaultManifestUrl;
  String get manifestUrl => _manifestUrl;
  set manifestUrl(String url) {
    _manifestUrl = url;
    notifyListeners();
  }

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  AppVersion? _currentVersion;
  AppVersion? get currentVersion => _currentVersion;

  UpdateManifest? _latestManifest;
  UpdateManifest? get latestManifest => _latestManifest;

  /// Returns true if the currently installed version is older than
  /// the manifest's minimum supported version.
  bool get isMandatoryUpdate {
    final manifest = _latestManifest;
    if (manifest == null || manifest.minimumSupportedVersion == null) {
      return false;
    }
    final minVer = AppVersion.tryParse(manifest.minimumSupportedVersion);
    if (minVer == null) return false;
    final current = _currentVersion ?? const AppVersion(major: 1, minor: 0, patch: 0, raw: '1.0.0');
    return minVer.isNewerThan(current);
  }

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  int _downloadedBytes = 0;
  int get downloadedBytes => _downloadedBytes;

  int _totalBytes = 0;
  int get totalBytes => _totalBytes;

  String? _downloadedApkPath;
  String? get downloadedApkPath => _downloadedApkPath;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  DateTime? _lastChecked;
  DateTime? get lastChecked => _lastChecked;

  bool _isDownloading = false;

  /// Custom client provider for unit test injection.
  HttpClient Function()? customClientFactory;

  /// Custom temporary directory provider for unit test injection.
  Directory Function()? customTempDirProvider;

  HttpClient _createClient() {
    if (customClientFactory != null) {
      return customClientFactory!();
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    return client;
  }

  /// Initialize and read the installed application version.
  Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber) ?? 1;
      _currentVersion = AppVersion.parse(info.version, versionCode: code);
    } catch (e) {
      // Fallback to static manifest version if platform query fails
      _currentVersion = const AppVersion(major: 1, minor: 0, patch: 0, versionCode: 1, raw: '1.0.0+1');
      if (kDebugMode) debugPrint('PackageInfo error: $e. Falling back to default version.');
    }
    notifyListeners();
  }

  /// Set the current version directly (useful for tests and previews).
  void setCurrentVersion(AppVersion version) {
    _currentVersion = version;
    notifyListeners();
  }

  /// Fetch the remote manifest and compare versions.
  Future<void> checkForUpdates({bool silent = false}) async {
    if (_status == UpdateStatus.checking || _isDownloading) return;

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    if (_currentVersion == null) {
      await init();
    }

    final client = _createClient();
    try {
      final uri = Uri.parse(_manifestUrl);
      if (!uri.isScheme('https')) {
        throw const FormatException('Manifest URL must use secure HTTPS.');
      }

      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Pocketknife-Updater');

      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Server returned HTTP ${response.statusCode} while fetching manifest.');
      }

      final responseBody = await response.transform(utf8.decoder).join();
      final manifest = UpdateManifest.fromJsonString(responseBody);
      _latestManifest = manifest;
      _lastChecked = DateTime.now();

      final current = _currentVersion ?? const AppVersion(major: 1, minor: 0, patch: 0, versionCode: 1, raw: '1.0.0');

      if (manifest.appVersion.isNewerThan(current)) {
        _status = UpdateStatus.updateAvailable;
      } else {
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = _friendlyError(e);
      if (kDebugMode) debugPrint('Check for updates failed: $e');
    } finally {
      client.close();
      notifyListeners();
    }
  }

  /// Download the APK with progress streaming, checksum verification, and atomic save.
  Future<void> downloadUpdate() async {
    if (_latestManifest == null) {
      _errorMessage = 'No update manifest available to download.';
      _status = UpdateStatus.error;
      notifyListeners();
      return;
    }

    if (_isDownloading) return;

    _isDownloading = true;
    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = _latestManifest!.fileSizeBytes ?? 0;
    _errorMessage = null;
    notifyListeners();

    final client = _createClient();
    File? tempFile;

    try {
      final tempDir = customTempDirProvider != null
          ? customTempDirProvider!()
          : await getTemporaryDirectory();
      final updatesDir = Directory('${tempDir.path}/pocketknife_updates');
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }

      tempFile = File('${updatesDir.path}/update_${_latestManifest!.versionCode}.apk.download');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      var currentUri = Uri.parse(_latestManifest!.apkUrl);
      HttpClientResponse? response;
      var redirectCount = 0;
      const maxRedirects = 6;

      while (redirectCount < maxRedirects) {
        // Enforce HTTPS on all redirects
        if (!currentUri.isScheme('https')) {
          throw const FormatException('Insecure HTTP redirect rejected.');
        }

        // Validate redirect host domain
        final host = currentUri.host.toLowerCase();
        final isAllowed = host == 'github.com' ||
            host.endsWith('.github.com') ||
            host == 'githubusercontent.com' ||
            host.endsWith('.githubusercontent.com');

        if (!isAllowed) {
          throw FormatException('Redirect to untrusted host "$host" was blocked.');
        }

        final request = await client.getUrl(currentUri);
        request.headers.set(HttpHeaders.userAgentHeader, 'Pocketknife-Updater');
        request.followRedirects = false; // Manual verification of redirects

        response = await request.close().timeout(const Duration(seconds: 20));

        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) {
            throw const HttpException('Redirect header missing location.');
          }
          currentUri = Uri.parse(location);
          redirectCount++;
          continue;
        }

        break;
      }

      if (response == null || response.statusCode != HttpStatus.ok) {
        throw HttpException('Download failed with status ${response?.statusCode ?? "Unknown"}.');
      }

      final contentLength = response.contentLength;
      if (contentLength > 0) {
        _totalBytes = contentLength;
      }

      final sink = tempFile.openWrite();
      String computedDigest = '';
      final sha256Input = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((digests) {
          if (digests.isNotEmpty) {
            computedDigest = digests.single.toString().toLowerCase();
          }
        }),
      );

      await for (final chunk in response) {
        sink.add(chunk);
        sha256Input.add(chunk);
        _downloadedBytes += chunk.length;

        if (_totalBytes > 0) {
          _downloadProgress = (_downloadedBytes / _totalBytes).clamp(0.0, 1.0);
        } else {
          _downloadProgress = 0.5; // indeterminate fallback
        }
        notifyListeners();
      }

      await sink.flush();
      await sink.close();
      sha256Input.close();

      // Verify file is non-empty
      final fileSize = await tempFile.length();
      if (fileSize < 1024) {
        throw const FormatException('Downloaded update file is too small or empty.');
      }

      // Verify checksum (strictly required for production release integrity)
      if (_latestManifest!.sha256 == null || _latestManifest!.sha256!.trim().isEmpty) {
        throw const FormatException('Release manifest is missing required SHA-256 checksum.');
      }

      final expectedDigest = _latestManifest!.sha256!.trim().toLowerCase();
      if (computedDigest != expectedDigest) {
        throw FormatException(
          'Checksum mismatch!\nExpected: $expectedDigest\nComputed: $computedDigest',
        );
      }

      // Rename to final APK
      final finalApk = File('${updatesDir.path}/PocketKnife_${_latestManifest!.version}.apk');
      if (await finalApk.exists()) {
        await finalApk.delete();
      }
      await tempFile.rename(finalApk.path);

      _downloadedApkPath = finalApk.path;
      _status = UpdateStatus.readyToInstall;
      _downloadProgress = 1.0;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = _friendlyError(e);
      // Clean up incomplete download
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }
      if (kDebugMode) debugPrint('Download failed: $e');
    } finally {
      _isDownloading = false;
      client.close();
      notifyListeners();
    }
  }

  /// Launch Android package installer for the downloaded APK.
  Future<void> installUpdate(BuildContext context) async {
    final apkPath = _downloadedApkPath;
    if (apkPath == null || !await File(apkPath).exists()) {
      _errorMessage = 'Downloaded update file was not found. Please download again.';
      _status = UpdateStatus.error;
      notifyListeners();
      return;
    }

    _status = UpdateStatus.installing;
    notifyListeners();

    try {
      if (Platform.isAndroid) {
        // Verify or request unknown app install permission on Android 8+
        var status = await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          status = await Permission.requestInstallPackages.request();
          if (!status.isGranted) {
            if (context.mounted) {
              await _showInstallPermissionDialog(context);
            }
            _status = UpdateStatus.readyToInstall;
            notifyListeners();
            return;
          }
        }
      }

      // Handoff to Android package installer using FileProvider via open_filex
      final res = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );

      if (res.type != ResultType.done) {
        throw Exception(res.message);
      }

      _status = UpdateStatus.readyToInstall;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = 'Could not start installer: $e';
    } finally {
      notifyListeners();
    }
  }

  /// Explain why Android requires the install unknown apps permission.
  Future<void> _showInstallPermissionDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Color(0xFF1D61F2)),
            SizedBox(width: 10),
            Text('Permission Needed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'To install updates, Android requires permission to allow Pocketknife to install apps.\n\n'
          'Please tap "Open Settings" and enable "Allow from this source" for Pocketknife.',
          style: TextStyle(fontSize: 14, height: 1.45, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1D61F2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Reset status back to idle or upToDate.
  void reset() {
    _status = _latestManifest != null && _latestManifest!.appVersion.isNewerThan(_currentVersion ?? const AppVersion(major: 1, minor: 0, patch: 0, raw: '1.0.0'))
        ? UpdateStatus.updateAvailable
        : UpdateStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  String _friendlyError(Object e) {
    if (e is TimeoutException) {
      return 'Connection timed out while checking for updates. Please check your internet connection.';
    }
    if (e is SocketException) {
      return 'Unable to reach GitHub. Please check your internet connection.';
    }
    if (e is HttpException) {
      return e.message;
    }
    if (e is FormatException) {
      return e.message;
    }
    return 'Update failed: $e';
  }
}

