import 'dart:convert';

/// Represents a parsed application semantic version and optional version code.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final int versionCode;
  final String raw;

  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.versionCode = 0,
    required this.raw,
  });

  /// Parse a version string (e.g. "1.0.0", "1.2.3+4", "v2.1.0").
  factory AppVersion.parse(String versionString, {int? versionCode}) {
    final clean = versionString.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (clean.isEmpty) {
      throw const FormatException('Version string cannot be empty.');
    }

    // Split on '+' to separate version from build number if present
    final parts = clean.split('+');
    final semverPart = parts[0];
    int parsedCode = versionCode ?? 0;

    if (parts.length > 1 && versionCode == null) {
      parsedCode = int.tryParse(parts[1]) ?? 0;
    }

    final segments = semverPart.split('.');
    if (segments.isEmpty || segments.any((s) => s.isEmpty)) {
      throw FormatException('Invalid semver format: $versionString');
    }

    final major = int.tryParse(segments[0]);
    if (major == null || major < 0) {
      throw FormatException('Invalid major version in "$versionString"');
    }

    final minor = segments.length > 1 ? int.tryParse(segments[1]) : 0;
    if (minor == null || minor < 0) {
      throw FormatException('Invalid minor version in "$versionString"');
    }

    final patch = segments.length > 2 ? int.tryParse(segments[2]) : 0;
    if (patch == null || patch < 0) {
      throw FormatException('Invalid patch version in "$versionString"');
    }

    return AppVersion(
      major: major,
      minor: minor,
      patch: patch,
      versionCode: parsedCode,
      raw: versionString.trim(),
    );
  }

  /// Safe parse that returns null on malformed strings.
  static AppVersion? tryParse(String? versionString, {int? versionCode}) {
    if (versionString == null) return null;
    try {
      return AppVersion.parse(versionString, versionCode: versionCode);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if this version is strictly newer than [other].
  bool isNewerThan(AppVersion other) {
    return compareTo(other) > 0;
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // If semver parts are identical, compare version code if either is non-zero
    if (versionCode != 0 || other.versionCode != 0) {
      return versionCode.compareTo(other.versionCode);
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch &&
          versionCode == other.versionCode;

  @override
  int get hashCode => Object.hash(major, minor, patch, versionCode);

  @override
  String toString() => versionCode > 0 ? '$major.$minor.$patch+$versionCode' : '$major.$minor.$patch';
}

/// Represents the update manifest published on GitHub Releases.
class UpdateManifest {
  final String version;
  final int versionCode;
  final String releaseNotes;
  final String apkUrl;
  final String? minimumSupportedVersion;
  final String? sha256;
  final int? fileSizeBytes;

  const UpdateManifest({
    required this.version,
    required this.versionCode,
    required this.releaseNotes,
    required this.apkUrl,
    this.minimumSupportedVersion,
    this.sha256,
    this.fileSizeBytes,
  });

  /// Parse and validate JSON manifest.
  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['version'];
    if (rawVersion == null || rawVersion is! String || rawVersion.trim().isEmpty) {
      throw const FormatException('Manifest "version" field is missing or invalid.');
    }

    // Verify version is parseable
    AppVersion.parse(rawVersion);

    final rawCode = json['versionCode'];
    final versionCode = rawCode is int ? rawCode : int.tryParse('$rawCode') ?? 1;
    if (versionCode <= 0) {
      throw const FormatException('Manifest "versionCode" must be a positive integer.');
    }

    final rawUrl = json['apkUrl'];
    if (rawUrl == null || rawUrl is! String || rawUrl.trim().isEmpty) {
      throw const FormatException('Manifest "apkUrl" field is missing or invalid.');
    }

    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || uri.scheme.toLowerCase() != 'https') {
      throw const FormatException('Manifest "apkUrl" must be a valid HTTPS URL.');
    }

    // Validate trusted domain (GitHub Releases, AWS S3 redirects from GitHub)
    final host = uri.host.toLowerCase();
    final isAllowed = host == 'github.com' ||
        host.endsWith('.github.com') ||
        host == 'githubusercontent.com' ||
        host.endsWith('.githubusercontent.com');

    if (!isAllowed) {
      throw FormatException('Manifest "apkUrl" host "$host" is not a trusted GitHub domain.');
    }

    // Validate optional SHA-256
    final rawSha = json['sha256'];
    String? cleanSha;
    if (rawSha != null && rawSha is String && rawSha.trim().isNotEmpty) {
      cleanSha = rawSha.trim().toLowerCase();
      final hexRegex = RegExp(r'^[a-f0-9]{64}$');
      if (!hexRegex.hasMatch(cleanSha)) {
        throw const FormatException('Manifest "sha256" must be a 64-character hex string.');
      }
    }

    final rawSize = json['fileSizeBytes'];
    final fileSizeBytes = rawSize is int ? rawSize : int.tryParse('$rawSize');

    return UpdateManifest(
      version: rawVersion.trim(),
      versionCode: versionCode,
      releaseNotes: (json['releaseNotes'] as String?)?.trim() ?? 'Bug fixes and performance improvements.',
      apkUrl: rawUrl.trim(),
      minimumSupportedVersion: json['minimumSupportedVersion'] as String?,
      sha256: cleanSha,
      fileSizeBytes: fileSizeBytes,
    );
  }

  /// Parse from raw JSON string.
  factory UpdateManifest.fromJsonString(String jsonString) {
    final decoded = json.decode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manifest root must be a JSON object.');
    }
    return UpdateManifest.fromJson(decoded);
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'versionCode': versionCode,
        'releaseNotes': releaseNotes,
        'apkUrl': apkUrl,
        if (minimumSupportedVersion != null) 'minimumSupportedVersion': minimumSupportedVersion,
        if (sha256 != null) 'sha256': sha256,
        if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
      };

  AppVersion get appVersion => AppVersion.parse(version, versionCode: versionCode);
}

/// Status of the in-app update check and download lifecycle.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  readyToInstall,
  installing,
  error,
}

