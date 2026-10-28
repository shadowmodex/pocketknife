# POCKETKNIFE — DETAILED FEATURE EXECUTION FLOWS

> **Document:** `docs/architecture/FEATURES.md`  
> **Status:** Verified from Codebase | **Tool Count:** 6 Active Offline Tools

---

## 1. Merge PDF

### 1.1 Overview & Entry Point
- **Screen:** [`MergePdfScreen`](file:///d:/Pocketknife/app/lib/screens/docs/merge_pdf_screen.dart)
- **Tool Identifier:** `ToolKind.mergePdf`
- **Purpose:** Allows selecting 2 or more PDF files, visually reordering them via drag-and-drop, inspecting page counts and sizes, and combining them into a single output PDF with custom naming.

### 1.2 Execution Order & Call Trace
1. **User Action (Pick Files):** User taps `PickTile` or `+ Add More PDFs` (`SoftButton`).
2. **File Selection:** Invokes `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true)`.
3. **Metadata Analysis:** For each picked file, `PdfService.instance.pageCount(bytes)` parses the PDF header via `sf.PdfDocument(inputBytes: bytes).pages.count` to extract page counts.
4. **Reordering:** Handled by `ReorderableListView.builder` using `onReorderItem: (oldIndex, newIndex)` to update the in-memory `_files` list.
5. **Execution (Merge):** User taps `PrimaryButton` ("Merge PDF").
6. **Core Processing:** `PdfService.instance.merge([bytes1, bytes2, ...])` creates a new `sf.PdfDocument()`, copies each page losslessly as a template, and outputs `Uint8List`.
7. **Storage:** `FileSaver.instance.saveDocument(bytes, fileName)` writes bytes to `ApplicationDocuments/Pocketknife/` and registers with MediaStore if accessible.
8. **Logging:** `AppStore.addActivity(...)` adds entry with human-readable summary.
9. **UI Feedback:** Displays `SavedResultCard` with direct "Open" and "Share" options.

### 1.3 Sequence Diagram
```mermaid
sequenceDiagram
    actor User
    participant UI as MergePdfScreen
    participant Picker as FilePicker
    participant PDF as PdfService
    participant Saver as FileSaver
    participant Store as AppStore

    User->>UI: Tap "+ Add More PDFs"
    UI->>Picker: pickFiles(['pdf'], multiple)
    Picker-->>UI: List<PlatformFile>
    UI->>PDF: pageCount(bytes)
    PDF-->>UI: pageCount integer
    UI-->>User: Render Reorderable List & Summary Banner

    User->>UI: Drag to reorder & Tap "Merge PDF"
    UI->>PDF: merge(List<Uint8List>)
    PDF->>PDF: Syncfusion copyPage() loop
    PDF-->>UI: Merged Uint8List bytes
    UI->>Saver: saveDocument(bytes, fileName)
    Saver-->>UI: SavedFile (local path)
    UI->>Store: addActivity(mergePdf, fileName, meta)
    UI-->>User: Render SavedResultCard (Open / Share)
```

---

## 2. Image Converter / Resizer

### 2.1 Overview & Entry Point
- **Screen:** [`PhotoScreen`](file:///d:/Pocketknife/app/lib/screens/photo_screen.dart)
- **Tool Identifier:** `ToolKind.imageConverter`
- **Purpose:** Converts single or batch images across JPG, PNG, WebP, JPEG, and GIF formats with adjustable quality slider and optional linked aspect-ratio resizing.

### 2.2 Execution Order & Call Trace
1. **Mode Switch:** Controlled by `SegmentedTabs` ("Single Image" vs "Batch Convert").
2. **File Selection:** Invokes `FilePicker.platform.pickFiles(type: FileType.image)`.
3. **Header Probing:** `PhotoService.instance.probe(bytes)` reads metadata returning width and height.
4. **Parameter Tuning:**
   - Format: `FormatChips` selects between `JPG`, `PNG`, `WebP`, `JPEG`, and `GIF`.
   - Quality: `Slider` controls compression level (10% to 100%).
   - Resize: Optional toggle activates Width and Height inputs. When "Keep aspect ratio" is checked, editing width automatically computes proportional height and vice versa.
5. **Core Processing:** `PhotoService.instance.process(inputBytes, options)`:
   - Resizes bitmap using `img.copyResize()` if dimensions requested.
   - For JPG: uses `img.encodeJpg(im, quality: q)`.
   - For PNG: uses `img.encodePng(im)`.
   - For BMP: uses `img.encodeBmp(im)`.
   - For GIF: uses `img.encodeGif(im)`.
   - For WebP: pipes lossless raw PNG bytes through `FlutterImageCompress.compressWithList(..., format: CompressFormat.webp)` for accelerated native WebP encoding.
6. **Storage:** `FileSaver.instance.saveImage(out.bytes, fileName)` writes to local disk and triggers gallery save if enabled in settings.

### 2.3 Sequence Diagram
```mermaid
sequenceDiagram
    actor User
    participant UI as PhotoScreen
    participant Picker as FilePicker
    participant Engine as PhotoService
    participant Saver as FileSaver
    participant Store as AppStore

    User->>UI: Select Format (WebP) & Quality (85%)
    User->>UI: Tap "Convert Image"
    UI->>Engine: process(bytes, PhotoOptions)
    alt Resizing enabled
        Engine->>Engine: img.copyResize(src, width, height)
    end
    alt Format is WebP
        Engine->>Engine: FlutterImageCompress.compressWithList()
    else Other formats
        Engine->>Engine: img.encode[Jpg/Png/Gif/Bmp]()
    end
    Engine-->>UI: ProcessedImage (bytes, width, height)
    UI->>Saver: saveImage(bytes, fileName)
    Saver-->>UI: SavedFile
    UI->>Store: addActivity(imageConverter, fileName, meta)
    UI-->>User: Display SavedResultCard
```

---

## 3. Word to PDF

### 3.1 Overview & Entry Point
- **Screen:** [`WordToPdfScreen`](file:///d:/Pocketknife/app/lib/screens/docs/word_to_pdf_screen.dart)
- **Tool Identifier:** `ToolKind.wordToPdf`
- **Purpose:** Converts Microsoft Word `.docx` documents into vector PDFs offline.

### 3.2 Execution Order & Call Trace
1. **File Selection:** User picks `.docx` file using `FilePicker`.
2. **Execution:** User taps "Convert to PDF".
3. **Core Processing:** `DocxService.instance.docxToPdf(bytes, title)`:
   - Unzips archive using `ZipDecoder().decodeBytes(bytes)`.
   - Reads `word/document.xml`.
   - Traverses `<w:p>` paragraph nodes and parses run formatting:
     - Detects heading styles (`Heading1`, `Heading2`).
     - Detects bold runs (`<w:b>`) and italic runs (`<w:i>`).
     - Detects bullet points (`<w:numPr>`).
   - Renders paragraphs into `pw.Document` using `package:pdf` with standard A4 margins and Inter typography.
4. **Storage:** Saved via `FileSaver.instance.saveDocument()`.

---

## 4. Text to PDF

### 4.1 Overview & Entry Point
- **Screen:** [`TextToPdfScreen`](file:///d:/Pocketknife/app/lib/screens/docs/text_to_pdf_screen.dart)
- **Tool Identifier:** `ToolKind.textToPdf`
- **Purpose:** Takes typed or pasted notes and formats them into an A4 PDF with automatic pagination and page numbering.

### 4.2 Execution Order & Call Trace
1. **Input:** User provides optional Title and multiline Body text.
2. **Execution:** User taps "Create PDF".
3. **Core Processing:** `PdfService.instance.textToPdf(body, title)`:
   - Loads Inter font asset (`assets/fonts/Inter.ttf`) if available.
   - Splits text by newline and maps each paragraph into `pw.MultiPage`.
   - Adds footer with `${ctx.pageNumber} / ${ctx.pagesCount}` on each page.
4. **Storage:** Saved via `FileSaver.instance.saveDocument()`.

---

## 5. Split / Extract PDF

### 5.1 Overview & Entry Point
- **Screen:** [`SplitPdfScreen`](file:///d:/Pocketknife/app/lib/screens/docs/split_pdf_screen.dart)
- **Tool Identifier:** `ToolKind.splitPdf`
- **Purpose:** Extracts specific pages or page ranges (e.g., `1-3, 5`) from a PDF into a new PDF document.

### 5.2 Execution Order & Call Trace
1. **Input:** User picks a PDF; page count is extracted.
2. **Range Specification:** User enters ranges in text field. `parseRanges(text, totalPages)` in `util.dart` validates and converts tokens into ordered, de-duplicated 0-based indices.
3. **Core Processing:** `PdfService.instance.extractPages(input, pages)`:
   - Uses Syncfusion to create destination `sf.PdfDocument`.
   - Iterates through requested page indices, drawing each page template onto the target document.
4. **Storage:** Saved via `FileSaver.instance.saveDocument()`.

---

## 6. Compress PDF

### 6.1 Overview & Entry Point
- **Screen:** [`CompressPdfScreen`](file:///d:/Pocketknife/app/lib/screens/docs/compress_pdf_screen.dart)
- **Tool Identifier:** `ToolKind.compressPdf`
- **Purpose:** Reduces the file size of heavy or scanned PDFs using calibrated raster-based downsampling.

### 6.2 Execution Order & Call Trace
1. **Input & Level Selection:** User picks PDF and selects compression strength:
   - **Light:** 150 DPI, JPEG Quality 80 (Best visual fidelity).
   - **Balanced (Recommended):** 120 DPI, JPEG Quality 60 (Optimal size/clarity balance).
   - **Strong:** 96 DPI, JPEG Quality 45 (Smallest file size).
2. **Core Processing:** `PdfService.instance.compress(input, strength)`:
   - Streams pages through `Printing.raster(input, dpi: strength._dpi)`.
   - Re-encodes rendered frames as JPEG images using `img.encodeJpg(..., quality: strength._quality)`.
   - Rebuilds PDF document embedding the compressed image pages.
3. **Storage:** Saved via `FileSaver.instance.saveDocument()`.
4. **UI Feedback:** Displays percentage reduction (e.g., "42% smaller").

---

## 7. In-App Update System

### 7.1 Overview & Entry Point
- **Screen:** [`SettingsScreen`](file:///d:/Pocketknife/app/lib/screens/settings_screen.dart) (`_UpdateCard`)
- **Service:** [`UpdateService`](file:///d:/Pocketknife/app/lib/services/update_service.dart)
- **Model:** [`UpdateManifest`](file:///d:/Pocketknife/app/lib/models/update_info.dart) & [`AppVersion`](file:///d:/Pocketknife/app/lib/models/update_info.dart)
- **Purpose:** Automatically detects, securely downloads, verifies, and installs new application releases from GitHub.

### 7.2 Execution Order & Call Trace
1. **Check for Updates:**
   - User navigates to Settings and taps "Check for Updates" (or "Check Again").
   - `UpdateService.instance.checkForUpdates()` initiates HTTPS GET to `https://raw.githubusercontent.com/shadowmodex/pocketknife/master/app-update.json`.
   - Manifest JSON is decoded and validated via `UpdateManifest.fromJsonString()`.
   - `manifest.appVersion.isNewerThan(currentVersion)` compares semantic versions (`major.minor.patch`) and build numbers (`versionCode`).
   - If a newer version exists, status transitions to `UpdateStatus.updateAvailable`.
   - If current version is equal or newer, transitions to `UpdateStatus.upToDate`.
2. **Download Update:**
   - User reviews version badge, download size, and release notes, then taps "Download Update".
   - `UpdateService.instance.downloadUpdate()` validates that `apkUrl` is HTTPS on a trusted GitHub domain (`github.com`, `objects.githubusercontent.com`).
   - Streams bytes chunk-by-chunk to `pocketknife_updates/update_<versionCode>.apk.download`.
   - Computes running SHA-256 hash using `crypto.sha256.startChunkedConversion()`.
   - Emits real-time progress (`downloadProgress`, `downloadedBytes`, `totalBytes`) updating the UI progress bar.
   - When download concludes:
     - Verifies file size is non-empty (> 1024 bytes).
     - If manifest supplies `sha256`, validates computed digest against expected digest. If mismatch occurs, deletes file and sets `UpdateStatus.error`.
     - Renames `.apk.download` atomically to `PocketKnife_<version>.apk`.
     - Transitions to `UpdateStatus.readyToInstall`.
3. **Install Update:**
   - User taps "Install Update".
   - `UpdateService.instance.installUpdate(context)` checks `Permission.requestInstallPackages.status`.
   - If not granted, requests permission. If denied, displays an explanatory dialog and directs user to system settings (`openAppSettings()`).
   - Calls `OpenFilex.open(apkPath, type: 'application/vnd.android.package-archive')`.
   - Android's native `PackageInstaller` presents the system upgrade dialog for user confirmation.

### 7.3 Sequence Diagram
```mermaid
sequenceDiagram
    actor User
    participant UI as SettingsScreen (_UpdateCard)
    participant Update as UpdateService
    participant GH as GitHub (Raw & Releases)
    participant FS as File System (Updates Cache)
    participant OS as Android PackageInstaller

    User->>UI: Tap "Check for Updates"
    UI->>Update: checkForUpdates()
    Update->>GH: GET /shadowmodex/pocketknife/master/app-update.json
    GH-->>Update: 200 OK (Manifest JSON)
    Update->>Update: AppVersion.isNewerThan(current)
    Update-->>UI: UpdateStatus.updateAvailable (notes, size)

    User->>UI: Tap "Download Update"
    UI->>Update: downloadUpdate()
    Update->>GH: GET /releases/download/v1.0.1/PocketKnife.apk
    GH-->>Update: 302 Redirect to objects.githubusercontent.com
    Update->>GH: GET /objects.githubusercontent.com/...
    loop Stream Chunks
        GH-->>Update: Chunks
        Update->>FS: Write chunk
        Update->>Update: Update SHA-256 & progress
        Update-->>UI: downloadProgress (45%)
    end
    Update->>Update: Verify SHA-256 checksum
    Update->>FS: Rename to PocketKnife_1.0.1.apk
    Update-->>UI: UpdateStatus.readyToInstall

    User->>UI: Tap "Install Update"
    UI->>Update: installUpdate(context)
    Update->>OS: Check REQUEST_INSTALL_PACKAGES
    Update->>OS: OpenFilex.open(apkPath, application/vnd.android.package-archive)
    OS-->>User: System Package Installer Dialog
```


