# Technical Specification: Temporary File & Cache Lifecycle Management

**Target Audience:** Engineering Team / Technical Stakeholders  
**Module Scope:** `lib/core/services/temp_file_manager.dart`, `lib/core/services/file_service.dart`, `lib/main.dart`, and 14 Tool Controllers  
**Status:** Implemented & Verified (196/196 Automated Tests Passing)

---

## 1. Problem Statement & Root Cause

On Android, application storage metrics previously indicated substantial cache bloat (~1.66 GB cache vs. ~110 MB actual app data). 

### Confirmed Root Causes
1. **OS File Picker Behavior:** `FilePicker.platform.pickFiles()` on Android copies selected user files into the app's cache directory (`getTemporaryDirectory()`). Every tool reads `platformFile.path`, which targets this cached copy. Prior to this implementation, these picked copies persisted indefinitely in system cache.
2. **Killed Session Accumulation:** When an app process is terminated by OS memory pressure or force-closed during an active session, transient picking copies remain orphaned in the temporary directory.

### Audited Components (Excluded from Issue)
- **`PdfThumbnailService`:** Audited and confirmed **in-memory only**. Uses native `pdfx` rendering returning `Uint8List` byte buffers stored strictly in Riverpod controller state. Bitmap buffers are garbage-collected upon controller reset/dispose. No disk-persisted thumbnail leak exists.

---

## 2. Architectural Solution

The solution introduces a centralized, choke-point managed lifecycle service called **`TempFileManager`**. It shifts responsibility from individual UI controllers to core infrastructure.

```
                  ┌─────────────────────────────────────────┐
                  │              User File Pick             │
                  └────────────────────┬────────────────────┘
                                       │
                                       ▼
                  ┌─────────────────────────────────────────┐
                  │               FileService               │
                  │  (pickPdfFiles() / pickImageFiles())    │
                  └────────────────────┬────────────────────┘
                                       │
                        Registers Path │ [Path Guard Check]
                                       ▼
                  ┌─────────────────────────────────────────┐
                  │             TempFileManager             │
                  │       (Tracks active session set)       │
                  └────────────────────┬────────────────────┘
                                       │
                                       ├──────────────────────────────┐
                                       ▼                              ▼
                         ┌───────────────────────────┐  ┌───────────────────────────┐
                         │   Controller Execution    │  │   App Launch / Startup    │
                         │   (Success / Error / Reset│  │   (Fire-and-forget sweep) │
                         └─────────────┬─────────────┘  └─────────────┬─────────────┘
                                       │                              │
                                       ▼                              ▼
                         ┌───────────────────────────┐  ┌───────────────────────────┐
                         │     cleanupSession()      │  │    sweepOrphanedFiles()   │
                         │  (Deletes session paths)  │  │ (Sweeps un-registered dir)│
                         └───────────────────────────┘  └───────────────────────────┘
```

---

## 3. Core System Components

### 3.1 `TempFileManager` (`lib/core/services/temp_file_manager.dart`)

`TempFileManager` is registered as a Riverpod singleton provider (`tempFileManagerProvider`). It maintains an in-memory tracked set of temporary file paths for the current tool session.

#### Key APIs & Mechanics

* **`registerTempPath(String path)` / `registerTempFile(File file)`**
  * **Path Guard:** Validates that normalized target path starts with the normalized system temp directory (`getTemporaryDirectory()`).
  * **Safety:** Silently rejects paths outside the temporary directory. This guarantees that user-selected output files saved to external storage or public directories (e.g. `/Download/Anvil`) can **never** be registered or accidentally deleted.

* **`cleanupSession()`**
  * Iterates over all paths registered during the session and deletes the corresponding files.
  * **Fault-Tolerant Execution:** Enclosed in try-catch per file. Missing files or files locked by the OS are silently skipped without throwing exceptions or blocking UI threads.
  * Clears the internal `_registeredPaths` tracking set upon completion.

* **`sweepOrphanedFiles()`**
  * Asynchronously enumerates `getTemporaryDirectory()`.
  * Compares disk files against currently registered session paths. Any file on disk not present in `_registeredPaths` is identified as an orphan from a killed/crashed prior session and deleted.
  * Triggered non-blocking post-frame on app launch.

* **`cacheDirectorySize()`**
  * Recursively calculates total byte consumption of `getTemporaryDirectory()`. Serves as an API hook for future Settings / Cache metrics UI.

---

### 3.2 `FileService` (`lib/core/services/file_service.dart`)

`FileService` acts as the single choke point through which all 14 tools pick files (`pickPdfFiles()`, `pickImageFiles()`).

#### Integration Details
- Injected with `TempFileManager`.
- Inside `pickPdfFiles()` and `pickImageFiles()`, every returned `PlatformFile` with a valid disk path automatically calls `_tempFileManager.registerTempPath(file.path!)` prior to returning the list to the caller.
- **Zero Controller Boilerplate:** Tool controllers do not contain manual file registration logic. Any new tool using standard `FileService` picking methods automatically inherits temporary file tracking.

---

### 3.3 Application Entry Point (`lib/main.dart`)

`AnvilApp` (a `ConsumerWidget`) reads `tempFileManagerProvider` and registers a post-frame callback upon build:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref.read(tempFileManagerProvider).sweepOrphanedFiles();
});
```

- **Behavior:** Fires non-blocking after the initial frame renders.
- **Idempotency:** Safe against multiple rebuilds; if the directory is clean, `sweepOrphanedFiles()` executes as a zero-op.

---

## 4. Lifecycle Triggers in Tool Controllers

Controllers invoke `_tempFileManager.cleanupSession()` across three standard lifecycle events:

1. **Operation Success:** Invoked after output file bytes are flushed to user storage (or custom path).
2. **Operation Failure / Error Exception:** Invoked inside `catch` blocks (including `OutOfMemoryError` and `FileSystemException`). Transient inputs are not output files and are immediately safe to sweep.
3. **Tool Reset / Navigation:** Invoked in tool completion reset handlers (e.g., `reset()`, `clearTarget()`, `clearImages()`, `removeAll()`).

---

## 5. Coverage Matrix across All 14 Tool Controllers

| Category | Tool | Controller File | Operation Method | Reset / Clear Endpoint |
| :--- | :--- | :--- | :--- | :--- |
| **PDF** | PDF Merge | `pdf_merge_controller.dart` | `merge()` | `removeAll()` |
| **PDF** | PDF Page Manager | `pdf_page_manager_controller.dart` | `applyChanges()` | `reset()` |
| **PDF** | PDF Split | `pdf_split_controller.dart` | `split()` | `reset()` |
| **PDF** | PDF Compress | `pdf_compress_controller.dart` | `compress()` | `reset()` |
| **PDF** | PDF to Image | `pdf_to_image_controller.dart` | `export()` | `reset()` |
| **PDF** | PDF Password | `pdf_password_controller.dart` | `_addPassword()`, `_removePassword()` | `reset()` |
| **PDF** | PDF Insert Pages | `pdf_insert_pages_controller.dart` | `insertPages()` | `clearTarget()` |
| **PDF** | PDF Insert Image as Page | `pdf_insert_image_as_page_controller.dart` | `insertImagePages()` | `clearTarget()` |
| **PDF-Adjacent** | Images to PDF | `images_to_pdf_controller.dart` | `createPdf()` | `clearImages()` |
| **Image** | Image Convert | `image_convert_controller.dart` | `convert()` | `reset()` |
| **Image** | Image Resize | `image_resize_controller.dart` | `resize()` | `reset()` |
| **Image** | Image Compress | `image_compress_controller.dart` | `compress()` | `reset()` |
| **Image** | Image Blur | `image_blur_controller.dart` | `apply()` | `reset()` |
| **Image** | Image Crop & Rotate | `image_crop_rotate_controller.dart` | `apply()` | `reset()` |

---

## 6. Edge Cases & Resilience

| Scenario | System Behavior |
| :--- | :--- |
| **App Killed Mid-Operation** | Transient files stay in cache directory. On next cold start, `main.dart` post-frame sweep detects un-tracked files and deletes them. |
| **File Locked by System/OS** | `cleanupSession()` catches deletion error, logs warning via `debugPrint`, and continues silently without surfacing UI errors. |
| **Duplicate File Selection** | `_registeredPaths` uses a `Set<String>`. Duplicate registrations of identical paths are deduplicated automatically. |
| **Attempted Output File Cleanup** | `registerTempPath` path guard verifies prefix against `getTemporaryDirectory()`. External output paths return false and are ignored. |

---

## 7. Verification & Automated Test Strategy

The implementation is verified by unit and integration tests:

1. **`test/core/services/temp_file_manager_test.dart`**
   * Verifies `registerTempFile` + `cleanupSession` file deletion.
   * Tests empty session non-throwing behavior.
   * Validates path guard rejection for external directories.
   * Asserts `sweepOrphanedFiles` deletes un-registered files while preserving active session paths.
   * Verifies missing file tolerance and duplicate path handling.
   * Tests `cacheDirectorySize()` byte calculation accuracy.
2. **`test/file_service_test.dart`**
   * Verifies `FileService` constructor injection and manager binding.
3. **Full Suite (`flutter test`)**
   * **196 / 196 tests passing** across the complete codebase.
