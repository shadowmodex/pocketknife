# POCKETKNIFE — PROJECT CONTEXT & MASTER OVERVIEW

> **Primary Entry Point for AI Coding Sessions & Developers**  
> *Last Verified:* October 2026 | *Status:* Production Ready | *Distribution:* GitHub Releases + In-App Updater

---

## 1. What Pocketknife Does

**Pocketknife** is a fast, privacy-first utility toolkit for Android built with Flutter. It provides everyday document and media tools that execute entirely in-memory and on-device without uploading user files to any cloud or remote server.

### Core Active Tool Suite (6 Tools):
1. **Merge PDF** — Combines multiple PDF documents into a single document with drag-and-drop reordering, page count analysis, and custom output naming.
2. **Image Converter / Resizer** — Converts single or batch images across JPG, PNG, WebP, JPEG, and GIF formats with compression quality tuning and aspect-ratio-locked resizing.
3. **Word to PDF** — Converts Microsoft Word (`.docx`) files into clean, paginated PDF documents using an in-house XML parsing and PDF rendering pipeline.
4. **Text to PDF** — Types or pastes notes into a formatted A4 PDF with automatic pagination and margins.
5. **Split / Extract PDF** — Extracts custom page ranges (e.g., `1-3, 5`) from an existing PDF into a new standalone document.
6. **Compress PDF** — Shrinks large PDFs via multi-tier rasterization (Light, Balanced, Strong) optimized for scans and image-heavy documents.

### In-App Update System:
- Seamless, user-controlled updates delivered directly from **GitHub Releases**.
- Automatic version comparison (`AppVersion`) against a public JSON manifest (`app-update.json`).
- Download engine with progress tracking, atomic disk writes, and SHA-256 integrity verification.
- Safe handoff to Android's native `PackageInstaller` via `FileProvider`.

> [!NOTE]
> **Excised Features:** Video Downloader and Audio Downloader (YouTube Explode, FFmpegKit, Dio) were completely removed from Pocketknife. Media downloading is handled by the separate application **Omni**. Network connectivity in Pocketknife is strictly scoped to checking update manifests and downloading official update APKs from GitHub.

---

## 2. Verified Technology Stack

| Layer | Technology | Details / Package |
|---|---|---|
| **Framework** | Flutter 3.x / Dart 3.x | Target Android (API 24 to 36), Null-safe Dart |
| **State Management** | `provider` (v6.1.2) | `AppStore` & `UpdateService` (`ChangeNotifier`) |
| **UI Design System** | Material 3 + Custom Tokens | `#1D61F2` Royal Blue, `#F6F9FC` Ice Canvas, Inter font |
| **PDF Generation** | `pdf` (v3.11.1) | Vector text-to-PDF & Word-to-PDF pagination |
| **PDF Manipulation** | `syncfusion_flutter_pdf` (v27.2.5) | Document merging, page extraction & page counting |
| **PDF Rasterizer** | `printing` (v5.14.3) | Converts PDF pages to high-DPI raster images for compression |
| **DOCX Processing** | `archive` (v3.6.1) + `xml` (v6.6.1) | Pure Dart OOXML extraction and element mapping |
| **Image Engine** | `image` (v4.3.0) + `flutter_image_compress` (v2.3.0) | Pure Dart decoding/encoding + native WebP acceleration |
| **File Picker** | `file_picker` (v8.3.7) | Native document and image picking |
| **Storage & Gallery** | `path_provider` (v2.1.5) + `saver_gallery` (v4.1.2) | Local app storage (`Pocketknife/`) & MediaStore integration |
| **System Integration** | `open_filex` (v4.7.0) + `share_plus` (v10.1.4) | System file viewer launching, share sheets, & package install |
| **App Versioning** | `package_info_plus` (v9.0.1) | Queries installed version and build code at runtime |
| **Integrity & Hash** | `crypto` (v3.0.8) | SHA-256 chunked conversion for APK verification |
| **Preferences** | `shared_preferences` (v2.5.5) | Persistent settings and JSON activity history log |

---

## 3. High-Level Architecture

```mermaid
graph TD
    UI[Flutter UI Layer\nScreens, Tabs & Custom Controls]
    Store[AppStore\nProvider / ChangeNotifier]
    Update[UpdateService\nIn-App Updater]
    FileSaver[FileSaver Service\nLocal App Dir & MediaStore]

    subgraph "Pure Offline Engines"
        PDF[PdfService\npdf + syncfusion_flutter_pdf + printing]
        DOCX[DocxService\narchive + xml -> pdf]
        PHOTO[PhotoService\nimage + flutter_image_compress]
    end

    subgraph "Update Engine"
        GH[(GitHub Releases\nRaw Manifest & APK Assets)]
        PI[Android PackageInstaller\nvia FileProvider & OpenFilex]
    end

    subgraph "Durable Storage"
        SP[(SharedPreferences\nSettings & History)]
        FS[(Local Storage\nApplicationDocuments/Pocketknife)]
    end

    UI --> Store
    UI --> Update
    UI --> PDF
    UI --> DOCX
    UI --> PHOTO
    PDF --> FileSaver
    DOCX --> FileSaver
    PHOTO --> FileSaver
    FileSaver --> FS
    Store --> SP
    Store --> FS
    Update --> GH
    Update --> PI
```

---

## 4. Source Code Navigation Map

```
app/
├── lib/
│   ├── main.dart                       # App entry point, MultiProvider setup, update init
│   ├── util.dart                       # File size formatter, safe name sanitizer, range parser
│   ├── models/
│   │   ├── models.dart                 # ToolKind (6 tools), ActivityItem, JSON serialization
│   │   └── update_info.dart            # AppVersion, UpdateManifest, UpdateStatus
│   ├── theme/
│   │   ├── app_colors.dart             # Central color palette (#1D61F2, pastel badges, ice canvas)
│   │   └── app_theme.dart              # M3 light theme, Inter typography, card shadows, radii
│   ├── widgets/
│   │   ├── scaffold.dart               # AppScaffold with circular nav buttons, help modal, brand footer
│   │   ├── controls.dart               # PrimaryButton (52h), SoftButton, SegmentedTabs, FormatChips
│   │   ├── cards.dart                  # ToolCard, HeroBanner, SummaryBanner, PdfFileCard, PkCard
│   │   └── logo.dart                   # CustomPainter BrandLogo (navy tile, blade, blue rivet)
│   ├── screens/
│   │   ├── splash_screen.dart          # Launch branding animation with seamless transition
│   │   ├── home_shell.dart             # 3-tab navigation shell (Home, Files, History)
│   │   ├── docs_screen.dart            # "All Tools" showcase list screen
│   │   ├── settings_screen.dart        # Preferences, App Updates card & About details
│   │   ├── photo_screen.dart           # Image Converter (Single/Batch, format chips, quality, resize)
│   │   ├── tabs/
│   │   │   ├── home_tab.dart           # Home dashboard: Hero banner, 2-col tool grid, settings button
│   │   │   ├── files_tab.dart          # Local file manager: search, open, share, delete
│   │   │   └── activity_tab.dart       # History log with time-ago timestamps and clear dialog
│   │   └── docs/
│   │       ├── merge_pdf_screen.dart   # Merge PDF: reorderable colorful cards, summary banner, custom name
│   │       ├── word_to_pdf_screen.dart # DOCX to PDF converter
│   │       ├── text_to_pdf_screen.dart # Notes / Text to PDF generator
│   │       ├── split_pdf_screen.dart   # Page range extraction
│   │       └── compress_pdf_screen.dart# Raster-based PDF compression
│   └── services/
│       ├── store.dart                  # AppStore state (activity, gallery pref)
│       ├── update_service.dart         # UpdateService: manifest fetch, streaming download, SHA-256 verify, install
│       ├── file_saver.dart             # Local file writer, directory scanner, Open/Share/Delete
│       ├── pdf_service.dart            # Text-to-PDF, Syncfusion merge/extract, printing compression
│       ├── docx_service.dart           # Unzips .docx, parses document.xml, renders via pdf package
│       └── photo_service.dart          # Image resize, quality encoding (JPG, PNG, WebP, GIF, BMP)
└── test/
    ├── widget_test.dart                # Unit tests for util.dart helpers (safeName, parseRanges, humanSize)
    ├── models_and_services_test.dart   # Unit tests for ToolKind, PicFormat, ActivityItem JSON roundtrip
    └── update_system_test.dart         # Unit tests for AppVersion, UpdateManifest, mock network, SHA-256 checks
```

---

## 5. How to Run, Test, and Build

### Running the App:
```powershell
cd app
flutter run
```

### Static Analysis:
```powershell
cd app
flutter analyze
```
*Current Status: 0 issues found.*

### Automated Tests:
```powershell
cd app
flutter test
```
*Current Status: 29/29 tests passing.*

### Packaging Android APK:
```powershell
cd app
flutter build apk --split-per-abi --release
```

---

## 6. Important Architectural Constraints & Rules

1. **Scoped Network Access:** Network permissions (`INTERNET`) are used exclusively for update manifest checks and downloading official APK releases from trusted GitHub endpoints. All document and media processing remains 100% offline.
2. **Package Identity & Signing:** In-app updates install via Android's `PackageInstaller`. The downloaded update APK must be signed with the same signing key and share the exact package ID (`com.pocketknife.pocketknife`).
3. **Multi-drive Boundary (Windows):** The project workspace resides on `D:\Pocketknife` while the Android SDK resides on `C:\`. Therefore, `android/gradle.properties` must retain `kotlin.incremental=false` to avoid cross-drive cache failures.
4. **Android SDK Level:** Target SDK is forced to 36 in `android/build.gradle.kts` to satisfy modern Android build toolchain requirements.
5. **Data Isolation:** User files are processed in memory and written to `getApplicationDocumentsDirectory()/Pocketknife`. A public copy is saved to `Pictures/Pocketknife` or `Download/Pocketknife` when gallery saving is toggled.

---

## 7. Documentation Index

For deep architectural breakdowns, consult the dedicated guides in `docs/architecture/`:
- **[`ARCHITECTURE.md`](file:///d:/Pocketknife/docs/architecture/ARCHITECTURE.md)** — Architectural design, module breakdown, state management, updater service, and design system.
- **[`FEATURES.md`](file:///d:/Pocketknife/docs/architecture/FEATURES.md)** — Detailed execution flows and symbol references for all 6 active tools and the update system.
- **[`DATA_STORAGE_AND_NETWORKING.md`](file:///d:/Pocketknife/docs/architecture/DATA_STORAGE_AND_NETWORKING.md)** — File persistence lifecycle, permissions, and network security model.
- **[`BUILD_TEST_AND_OPERATIONS.md`](file:///d:/Pocketknife/docs/architecture/BUILD_TEST_AND_OPERATIONS.md)** — Build configurations, Gradle settings, release publishing workflow, and CI verification.
