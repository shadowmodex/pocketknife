# POCKETKNIFE — BUILD, TEST & OPERATIONS MANUAL

> **Document:** `docs/architecture/BUILD_TEST_AND_OPERATIONS.md`  
> **Status:** Current & Verified | **Target Android SDK:** 36

---

## 1. Prerequisites & Environment Setup

- **Flutter SDK:** Flutter 3.29.x / Dart 3.7.x or higher
- **Java Development Kit (JDK):** JDK 17 (required for Android Gradle Plugin 8.x)
- **Android SDK:** Platforms installed up to API 36 (`android-36`), Android Build-Tools 34.0.0 or 35.0.0
- **Operating System:** Windows, macOS, or Linux

---

## 2. Windows Multi-Drive Boundary Constraint

### Critical Configuration
In Windows environments where the repository is on a secondary drive (e.g., `D:\Pocketknife`) and the Android SDK / Gradle caches reside on the system drive (e.g., `C:\Users\...`):

`android/gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
kotlin.incremental=false
```

> [!CAUTION]
> **DO NOT ENABLE `kotlin.incremental=true`**  
> On Windows, Gradle's incremental Kotlin compilation daemon frequently fails when cross-referencing build artifacts across different drive letters (`C:` vs `D:`). Keeping `kotlin.incremental=false` ensures clean, reproducible builds.

---

## 3. Build & Packaging Commands

### Development Execution:
```powershell
cd D:\Pocketknife\app
flutter run
```

### Static Analysis:
```powershell
cd D:\Pocketknife\app
flutter analyze
```
*Expected output:* `No issues found!`

### Test Suite:
```powershell
cd D:\Pocketknife\app
flutter test
```
*Expected output:* `All tests passed! (29 tests)`

### Production Release Build:
To build a universal release APK (recommended for single-file GitHub Releases distribution):
```powershell
cd D:\Pocketknife\app
flutter build apk --release
```
Output: `app/build/app/outputs/flutter-apk/app-release.apk`

To build optimized split APKs per ABI:
```powershell
cd D:\Pocketknife\app
flutter build apk --split-per-abi --release
```
Output:
- `app-arm64-v8a-release.apk`
- `app-armeabi-v7a-release.apk`
- `app-x86_64-release.apk`

---

## 4. Test Suite Map

```
app/test/
├── widget_test.dart (7 tests)
│   ├── safeName: Sanitizes filenames, strips illegal characters (\/:*?"<>|), trims whitespace.
│   ├── humanSize: Verifies B, KB, MB byte formatting.
│   └── parseRanges: Verifies page range parsing (e.g. '1-3, 5' -> [0, 1, 2, 4]), de-duplication, and bounds checking.
│
├── models_and_services_test.dart (6 tests)
│   ├── ToolKind: Verifies exactly 6 tools exist, titles/blurbs are non-empty, and legacy IDs map cleanly.
│   ├── PicFormat: Verifies all 5 formats (JPG, PNG, WebP, GIF, BMP) and format detection.
│   └── ActivityItem: Verifies JSON serialization and deserialization roundtrip.
│
└── update_system_test.dart (16 tests)
    ├── AppVersion: Semver parsing, comparisons (major, minor, patch, versionCode), invalid token handling.
    ├── UpdateManifest: Valid JSON parsing, HTTPS scheme enforcement, domain whitelisting, SHA-256 validation.
    └── UpdateService Lifecycle:
        ├── Update available detection (newer version)
        ├── Up-to-date detection (same/older version)
        ├── HTTP 404 / 500 server error handling
        ├── Network SocketException handling
        ├── Streaming download with progress emission
        └── SHA-256 integrity check and mismatch rejection
```

---

## 5. Automated Release & In-App Update Publishing Workflow

PocketKnife uses an automated CI/CD pipeline via GitHub Actions ([`.github/workflows/release.yml`](../../.github/workflows/release.yml)) to build, sign, and distribute releases.

### Release Process

1. **Bump Version in `app/pubspec.yaml`**:
   ```yaml
   version: 1.0.1+2
   ```

2. **Commit and Push to `main`**:
   ```powershell
   git add app/pubspec.yaml
   git commit -m "chore: bump version to 1.0.1+2"
   git push origin main
   ```

3. **Tag the Release and Push Tag**:
   ```powershell
   git tag v1.0.1
   git push origin v1.0.1
   ```

4. **Automated Pipeline Execution**:
   - GitHub Actions triggers on `v*` tag push.
   - Validates repository signing secrets (`KEYSTORE_BASE64`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).
   - Decodes the keystore into temporary runner memory (and deletes it in `always()` post-step).
   - Builds the production release APK with Flutter.
   - Computes SHA-256 checksum and packages `PocketKnife.apk` and `PocketKnife.apk.sha256`.
   - Publishes GitHub Release under tag `v1.0.1`.
   - Automatically updates `app-update.json` with the exact version, version code, asset URL, and verified SHA-256 hash.
   - Commits and pushes the updated manifest to the `main` branch with `[skip ci]`.

5. **In-App Discovery**:
   - Installed apps check `https://raw.githubusercontent.com/shadowmodex/pocketknife/main/app-update.json`.
   - The app detects `v1.0.1`, validates the SHA-256 hash, and prompts the user to download and install.

---

## 6. Signing Compatibility & Android Constraints

> [!IMPORTANT]
> **SIGNING CERTIFICATE CONTINUITY**  
> Android's package manager enforces that an update APK must be signed with the exact same certificate as the installed version.
> If the current app was installed using a debug key (or keystore A) and an update is signed with keystore B, Android will abort installation with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.
> Ensure your release build keystore remains consistent across all releases.

---

## 7. Troubleshooting & FAQ

### Issue: Android Build Fails with "compileSdk 36 required"
- **Cause:** Some transitive AndroidX or plugin libraries require SDK 36.
- **Solution:** Ensured in `app/android/build.gradle.kts`:
  ```kotlin
  subprojects {
      afterEvaluate {
          project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
              compileSdkVersion(36)
          }
      }
  }
  ```

### Issue: In-App Update says "Checksum mismatch"
- **Cause:** The `sha256` field in `app-update.json` does not match the actual hash of the uploaded `PocketKnife.apk`.
- **Solution:** Recompute the hash using `Get-FileHash -Algorithm SHA256` and update `app-update.json`.

### Issue: Android displays "App not installed as package appears to be invalid"
- **Cause:** Signing key discrepancy between the installed version and the downloaded APK.
- **Solution:** Re-sign the APK using the exact keystore used for the initial installation.
