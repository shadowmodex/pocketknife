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
*Expected output:* `All tests passed!`

### Production Release Build:
To build optimized split APKs per ABI (drastically reduces download size):
```powershell
cd D:\Pocketknife\app
flutter build apk --split-per-abi --release
```

Generated APKs will be located in:
`app/build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk`
- `app-armeabi-v7a-release.apk`
- `app-x86_64-release.apk`

---

## 4. Test Suite Map

```
app/test/
├── widget_test.dart
│   ├── safeName: Sanitizes filenames, strips illegal characters (\/:*?"<>|), trims whitespace.
│   ├── humanSize: Verifies B, KB, MB byte formatting.
│   └── parseRanges: Verifies page range parsing (e.g. '1-3, 5' -> [0, 1, 2, 4]), de-duplication, and bounds checking.
│
└── models_and_services_test.dart
    ├── ToolKind: Verifies exactly 6 tools exist, titles/blurbs are non-empty, and legacy IDs map cleanly.
    ├── PicFormat: Verifies all 5 formats (JPG, PNG, WebP, GIF, BMP) and format detection.
    └── ActivityItem: Verifies JSON serialization and deserialization roundtrip.
```

---

## 5. Troubleshooting & FAQ

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

### Issue: Image conversion fails on WebP
- **Cause:** The pure-Dart `image` package does not have an internal WebP encoder.
- **Solution:** Pocketknife uses `flutter_image_compress`'s native WebP engine via `FlutterImageCompress.compressWithList(...)`. This requires no internet and runs directly via the platform channel.

### Issue: Word-to-PDF text spacing or font missing
- **Cause:** Missing fallback font asset.
- **Solution:** `PdfService` bundles `assets/fonts/Inter.ttf`. If the asset is missing, it falls back gracefully to standard Helvetica.
