# Anvil 🛠️

**Anvil** is a free, open-source, privacy-first, offline utility application built with Flutter. It consolidates everyday file manipulation tools — such as PDF merging, page reordering, splitting, compression, image conversion, resizing, and image compression — into a single, intuitive interface.

With Anvil, your files never leave your device. Everything runs 100% locally with zero cloud dependencies, zero telemetry, and zero tracking.

---

## 🌟 Key Features

Anvil offers a comprehensive suite of utilities organized into PDF and Image toolsets:

### 📄 PDF Utilities
- **Merge PDFs**: Combine multiple PDF files into a single, unified document in custom order.
- **Page Manager**: Visually reorder, rotate (90°, 180°, 270°), or remove individual pages from a PDF.
- **Split PDF**: Divide a PDF into smaller files by specific page ranges, single pages, or equal parts.
- **Compress PDF**: Reduce PDF file size while preserving text clarity and document structure.
- **PDF to Image**: Export PDF pages as high-resolution PNG or JPEG images with customizable DPI resolution.
- **Password Protect PDF**: Add password encryption to secure documents or remove existing password protection.
- **Insert Pages**: Insert pages from one PDF into specific position inside another PDF.
- **Insert Image as Page**: Insert JPEG or PNG images directly as new pages into an existing PDF.
- **Images to PDF**: Convert scanned documents, receipts, and photos into a structured PDF document.

### 🖼️ Image Utilities
- **Image Format Convert**: Convert images seamlessly between PNG, JPEG, WebP, BMP, GIF, and TIFF formats.
- **Resize Image**: Adjust image pixel dimensions by exact measurements, percentage scaling, or predefined ratio presets.
- **Compress Image**: Reduce image file size targeting quality or file size limits with intelligent dimension fallback, quality floor enforcement, and palette dithering.

---

## 🔒 Core Principles

1. **100% Offline & Private**: Zero network requests. No user accounts, cloud sync, or telemetry. Your files stay on your machine.
2. **Non-Destructive Workflows**: Original files are never overwritten automatically. Output files are saved as new files in destination directories of your choice.
3. **Fail Loudly & Actionably**: Precise error messages for corrupted files, permission errors, or unsupported formats — never silent failures or vague warnings.
4. **Clean & High-Performance**: Built using Dart and native Flutter bindings for desktop and mobile responsiveness.
5. **Completely Free & Open Source**: No paywalls, subscriptions, advertisements, or dark patterns.

---

## 🛠️ Tech Stack & Architecture

- **Framework**: [Flutter](https://flutter.dev) (Stable Channel)
- **Language**: [Dart](https://dart.dev) (SDK `^3.12.2`)
- **State Management**: [Riverpod](https://riverpod.dev) (`flutter_riverpod` `^2.5.0`) — Controller business logic decoupled from UI widgets (`StateNotifier` / `AsyncValue`)
- **Routing**: [go_router](https://pub.dev/packages/go_router) (`^14.0.0`)
- **PDF Processing**: `syncfusion_flutter_pdf` (`^26.0.0`), `pdfx` (`^2.6.0`)
- **Image Engine**: Pure Dart `image` package (`^4.2.0`)
- **File Management**: `file_picker`, `path_provider`, `share_plus`, `shared_preferences`

---

## 📁 Repository Structure

```text
anvil/
├── lib/
│   ├── core/                  # Design tokens, theme constants, global widgets & file services
│   ├── home/                  # Dashboard grid & tool search UI
│   ├── tools/                 # Self-contained tool modules (Screen + Controller pairs)
│   │   ├── registry.dart      # Single source of truth for tool metadata & routing
│   │   ├── pdf_merge/         # PDF Merge feature module
│   │   ├── pdf_page_manager/  # Page Manager feature module
│   │   ├── image_convert/     # Image Format Convert feature module
│   │   ├── image_compress/    # Image Compression feature module
│   │   └── ...                # Other PDF & Image tool modules
│   └── main.dart              # Application entry point & router setup
├── test/                      # Unit tests for all controllers & services
├── docs/                      # Architectural specs, feature requirements & build guides
├── windows/                   # Windows desktop platform code & Inno Setup configuration
└── android/                   # Android platform configuration & release settings
```

---

## 🚀 Getting Started & Building from Source

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.24.0`)
- Dart SDK (`^3.12.2`)
- [Inno Setup Compiler](https://jrsoftware.org/isinfo.php) *(Optional: Required only for building the Windows setup installer)*

### 1. Clone the Repository
```bash
git clone https://github.com/harshit-malviya/anvil.git
cd anvil
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Run Unit Tests
```bash
flutter test
```

### 4. Run Locally

- **Windows Desktop:**
  ```bash
  flutter run -d windows
  ```

- **Android:**
  ```bash
  flutter run -d android
  ```

---

## 📦 Building Releases

### Windows Desktop Release
```bash
flutter build windows --release
```
The compiled executable and dependencies will be located at:
`build/windows/x64/runner/Release/`

#### Windows Setup Installer (`.exe`)
To generate the standalone setup installer (`AnvilSetup-1.0.0.exe`):
```powershell
iscc windows/installer/anvil.iss
```
The installer output will be created at `build/windows/installer/AnvilSetup-1.0.0.exe`.

### Android Release APK
```bash
flutter build apk --release
```
The generated APK file will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

