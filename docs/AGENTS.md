# AGENTS.md — Anvil

> Read this file FIRST, before any spec file, at the start of every session.
> Update the "Progress Log" and "Decisions Log" sections at the END of every session, before
> stopping work — this file is the only thing that carries context forward to your next session
> or to a different agent picking up the work.

## 1. What this repo is

Anvil — a free, offline, open-source utility app (PDF tools, image tools) for Windows + Android,
built in Flutter. Full product vision: `PROJECT_OVERVIEW.md`. Visual identity: `DESIGN_SYSTEM.md`.
Build/CI: `BUILD_SETUP.md`. Each shippable feature has its own `FEATURE_*.md`.

## 2. Standing rules (never violate these, even under a specific feature request)

1. No network calls for core functionality — the app is offline-first, always
2. Never modify or delete a user's original file without explicit confirmation
3. Every controller (business logic class) gets unit tests before being considered "done" — see
   `PROJECT_OVERVIEW.md` §5 for what "done" means per feature
4. All colors/type/spacing come from `lib/core/theme/` tokens — no hardcoded values in widgets
5. If a feature spec is ambiguous, make the safest choice and leave an `// ASSUMPTION:` comment —
   don't block, but don't guess silently either
6. Don't start a new `FEATURE_*.md` file's work until the previous one is fully checked off in
   the Progress Log below, including its tests
7. **Never run CPU-heavy processing on the main UI thread.** All Syncfusion PDF operations
   (parsing, template creation, rendering, saving) and similar CPU-bound work MUST run in a
   background isolate via `compute()`. Use the established pattern:
   - Create a **top-level async function** in `lib/core/services/pdf_isolate_worker.dart` that
     takes a serializable params object and returns serializable output
   - Call `compute(isolateFunction, params)` from the controller
   - Keep file I/O on the main isolate (it's async and non-blocking)
   - Use an **indeterminate progress bar** with a static message (compute() can't send
     incremental updates back)
   - Never use `Future.delayed()` as a workaround for UI jank — it doesn't work; use isolates

## 3. Progress log

> Add a new dated entry each session. Keep entries short — what changed, what's left, what broke.
> Don't delete old entries; this is a history, not just a current-state snapshot.

## 2026-07-27 — Session 1
- Scaffolded Flutter project per BUILD_SETUP.md targeting Windows and Android (`com.anvil`)
- Configured pubspec dependencies: `flutter_riverpod`, `go_router`, `syncfusion_flutter_pdf`, `image`, `file_picker`, `google_fonts`, `mocktail`, `flutter_lints`
- Built workshop theme tokens (`AppColors`, `AppTypography`, `AppTheme`) in `lib/core/theme/` adhering to DESIGN_SYSTEM.md
- Created shared UI components (`ToolCard`, `FileDropZone`, `AppButton`, `StampAnimation`) in `lib/core/widgets/`
- Implemented tool registry (`lib/tools/registry.dart`) and application router (`lib/core/router.dart`)
- Implemented `HomeScreen` tool grid and verified widget test harness passes
## 2026-07-27 — Session 3
- Finalized app icon selection: `anvil_icon_07.png` (Stamp Ring Impact concept) saved to `assets/icons/source/anvil_icon_master.png`
- Built generation tool (`tool/generate_icons.dart`) to produce full multi-platform asset set:
  - Android adaptive icon (`mipmap-anydpi-v26/ic_launcher.xml` with solid `workshopGrey` `#ECEAE4` background color and keyed transparent foreground assets across mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
  - Android legacy launcher PNG fallbacks (48px - 192px)
  - Play Store 512x512px icon asset
  - Windows multi-resolution `.ico` saved to `windows/runner/resources/app_icon.ico` (verified in `Runner.rc` and tested in clean Windows release build)
  - In-app 128x128px transparent mark saved to `assets/icons/anvil_mark.png` registered in `pubspec.yaml`
- Next: start `FEATURE_pdf_page_manager.md`

## 2026-07-27 — Session 5
- Implemented PDF Page Manager feature (`FEATURE_pdf_page_manager.md`):
  - Created `lib/tools/pdf_page_manager/pdf_page_manager_state.dart` with `PageItem` model and state getters
  - Created `lib/tools/pdf_page_manager/pdf_page_manager_controller.dart` supporting loading, async thumbnail rendering via `pdfx`, deletion/undo, rotation (90° steps), reordering, and Syncfusion PDF export with rotation settings
  - Created `lib/tools/pdf_page_manager/pdf_page_manager_screen.dart` with single PDF drop zone, responsive virtualized page thumbnail grid, interactive delete/undo/rotate/reorder controls, bottom summary bar, and success view
  - Registered route `/pdf-page-manager` in `lib/core/router.dart`
  - Created comprehensive unit test suite `test/tools/pdf_page_manager/pdf_page_manager_controller_test.dart` testing load, delete/undo, rotate cycle, reorder, zero-page guard, and PDF export with applied page transformations

## 2026-07-27 — Session 6
- Implemented PDF Split feature (`FEATURE_pdf_split.md`):
  - Extracted shared `PdfThumbnailService` in `lib/core/services/pdf_thumbnail_service.dart` and refactored `PdfPageManagerController` to use it
  - Created `lib/tools/pdf_split/pdf_split_state.dart` with 3 split modes (`everyPage`, `customRanges`, `equalParts`), split markers, typed custom range string parser, overlap validation, gap detection, and live summary
  - Created `lib/tools/pdf_split/pdf_split_controller.dart` supporting split modes, equal parts calculations, batch PDF creation, and rollback cleanup on write failure
  - Created `lib/tools/pdf_split/pdf_split_screen.dart` with drop zone, mode selector, thumbnail grid with interactive split markers, confirmation prompts for gaps/high file counts, and success stamp view
  - Added `openFolder` in `FileService` using native system processes
  - Registered route `/pdf-split` in `lib/core/router.dart` and metadata in `lib/tools/registry.dart`
  - Created unit test suite `test/tools/pdf_split/pdf_split_controller_test.dart` testing multi-page loading, single-page flag, protected PDF rejection, mode switching, visual range markers, text range parsing, overlap detection, gap warning & override, equal parts logic, batch PDF creation, and page orientation preservation

## 2026-07-27 — Session 7
- Implemented PDF Compress feature (`FEATURE_pdf_compress.md`):
  - Created `lib/tools/pdf_compress/pdf_compress_state.dart` with compression level presets (`Low`, `Medium`, `High`), result types (`normalSuccess`, `minimalReduction`, `outputLarger`), byte formatters, and percentage reduction getters
  - Created `lib/tools/pdf_compress/pdf_compress_controller.dart` supporting loading, password rejection, compression preset stream deflation, minimal reduction handling (< 5%), and safety guard when compressed file exceeds original size
  - Created `lib/tools/pdf_compress/pdf_compress_screen.dart` with constrained drop zone, original size indicator, level selector, before → after size comparison badge, stamp animation (`COMPRESSED`), and output actions (`Open Folder`, `Save As...`, `Share`)
  - Registered route `/pdf-compress` in `lib/core/router.dart` and metadata in `lib/tools/registry.dart`
  - Created unit test suite `test/tools/pdf_compress/pdf_compress_controller_test.dart` testing document loading, password rejection, level configuration, minimal reduction handling, and larger file protection

## 2026-07-27 — Session 8
- Implemented PDF to Image feature (`FEATURE_pdf_to_image.md`):
  - Refactored `PdfThumbnailService` in `lib/core/services/pdf_thumbnail_service.dart` adding `renderPage` and `renderPages` methods for high-resolution page rendering at target DPI/format.
  - Created `lib/tools/pdf_to_image/pdf_to_image_state.dart` with `ImageFormat` (PNG/JPEG) and `ExportResolution` (72/150/300 DPI) enums, state getters, and live pixel dimension estimates.
  - Created `lib/tools/pdf_to_image/pdf_to_image_controller.dart` supporting document loading, default all-pages selected, selection toggles (`selectAll`, `selectNone`, `togglePageSelected`), single-page vs multi-page export paths, folder collision avoidance (`report_images_2`), and per-page failure recovery with skipped page tracking.
  - Created `lib/tools/pdf_to_image/pdf_to_image_screen.dart` with drop zone constrained box (600x400), controls panel (format pills with JPEG transparency warning, resolution cards with pixel estimates), page thumbnail grid with checkboxes, live summary bar, stamp animation (`EXPORTED`), and standard completion action set (`Open Folder`, `Save As…`, `Share`, `Convert Another PDF`).
  - Registered route `/pdf-to-image` in `lib/core/router.dart` and metadata in `lib/tools/registry.dart`.
  - Created comprehensive unit test suite `test/tools/pdf_to_image/pdf_to_image_controller_test.dart` testing document parsing, password rejection, selection quick actions, format/resolution updates, single-page export, multi-page document order export, directory collision handling, and per-page failure recovery.

## 2026-07-27 — Session 9
- Implemented PDF Password Protection feature (`FEATURE_pdf_password.md`):
  - Created `lib/tools/pdf_password/pdf_password_state.dart` with `PdfPasswordMode` (Add/Remove) enum, validation getters (`isPasswordTooShort`, `passwordsMatch`, `canSubmitAdd`, `canSubmitRemove`), and file size formatters.
  - Created `lib/tools/pdf_password/pdf_password_controller.dart` supporting document loading with auto-detection of password protection status, Add Password path with minimum length and confirmation checks, and Remove Password path requiring exact valid current password (with clear error handling on wrong password).
  - Created `lib/tools/pdf_password/pdf_password_screen.dart` with single PDF drop zone, file header card with security badge, mode-specific form inputs with visibility toggles, stamp animation (`PROTECTED` / `UNPROTECTED`), and standard completion action set (`Open Folder`, `Save As…`, `Share`, `Process Another PDF`).
  - Registered route `/pdf-password` in `lib/core/router.dart` and metadata in `lib/tools/registry.dart`.
  - Created comprehensive unit test suite `test/tools/pdf_password/pdf_password_controller_test.dart` testing auto-detection on load, corrupted/empty file rejection, password length & confirmation validations, Add Password encryption execution, Remove Password incorrect password rejection, and Remove Password decryption happy path.

## 2026-07-28 — Session 11
- Implemented PDF Insert Image as Page feature (`FEATURE_pdf_insert_image_as_page.md`):
  - Refactored `PdfInsertPagesController` to expose `splicePages` static helper method for document splicing.
  - Added `pickImageFiles` to `FileService` supporting JPEG and PNG selection.
  - Created `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_state.dart` with `PageFitMode` enum (`matchNeighboringPage`, `fitToImage`) and state getters.
  - Created `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_controller.dart` supporting target document loading & validation, password/corruption rejection, image format validation (JPEG/PNG), image decoding, oversized image downscaling (>3000px cap), fit mode configuration, insertion point controls, and image-to-PDF page conversion with explicit white background transparency flattening.
  - Created `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_screen.dart` with target PDF drop zone, thumbnail grid with insertion point controls, image drop zone, image preview header, page fit mode selector, live preview grid block, stamp animation (`PAGE INSERTED`), and completion action buttons (`Open Folder`, `Save As...`, `Insert Another Image`).
  - Registered route `/pdf-insert-image-as-page` in `lib/core/router.dart` and metadata in `lib/tools/registry.dart`.
  - Created comprehensive unit test suite `test/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_controller_test.dart` testing insert-at-start with `matchNeighboringPage`, insert-at-end with `fitToImage`, insert-in-middle with preceding neighbor matching, unsupported image format rejection, corrupted image rejection, zero-existing-pages fallback, protected target rejection, and corrupted target rejection.

## 2026-07-29 — Session 14
- Implemented optional divider pages feature for PDF Merge (`docs/PHASE 3/TASK_pdf_merge_divider.md`):
  - Updated `isolateMergePdfs` in `lib/core/services/pdf_isolate_worker.dart` to accept `MergeParams` and build 1-inch (72pt) white divider pages before source files 2..N with centered/truncated filename in monospace type style (`PdfStandardFont(PdfFontFamily.courier, 12)`).
  - Updated `PdfMergeState` and `PdfMergeController` with `insertDividers` property and `setInsertDividers` toggle.
  - Added "Insert a divider page between files" checkbox in `lib/tools/pdf_merge/pdf_merge_screen.dart`.
  - Added unit test cases in `test/tools/pdf_merge/pdf_merge_controller_test.dart` for divider insertion, height/width matching, and state toggles.

## 2026-07-29 — Session 13
- Fixed critical UI freezing during PDF processing by moving all Syncfusion PDF work to background isolates:
  - Created `lib/core/services/pdf_isolate_worker.dart` with 8 top-level async functions (`isolateMergePdfs`, `isolateCompressPdf`, `isolateSplitPdf`, `isolateArrangePages`, `isolateAddPassword`, `isolateRemovePassword`, `isolateInsertPages`, `isolateInsertImageAsPage`)
  - Refactored all 7 PDF tool controllers to call `compute(isolateFunction, params)` instead of running Syncfusion work on the UI thread
  - Removed ineffective `Future.delayed(15ms)` yield workarounds from all controllers
  - Cleaned up PDF-to-Image controller (pdfx uses async platform channels, not Syncfusion — removed unnecessary delays)
  - Added standing rule #7 to enforce this pattern for all future work

## 2026-07-28 — Session 12
- Implemented Tool Search feature (`docs/PHASE 3/FEATURE_tool_search.md`):
  - Added `keywords` field to `ToolMetadata` in `lib/tools/registry.dart` and populated keyword synonyms for all 8 registered tools.
  - Created `lib/home/tool_search_controller.dart` with pure function `filterTools` (all-words, case-insensitive, title/description/keywords matching) and Riverpod providers (`searchQueryProvider`, `filteredToolsProvider`).
  - Refactored `HomeScreen` in `lib/home/home_screen.dart` with search input (6px corner radius, `pegGrey` resting border, `emberCopper` focus border, 70% opacity placeholder, clear button) and zero-match empty state presentation.
  - Created unit test suite `test/home/tool_search_controller_test.dart` testing empty query, whitespace-only query, title matching, keyword matching, description matching, multi-word matching, zero matches, and safe handling of empty keyword lists.

## 4. Feature status tracker

| Feature | Spec file | Status | Notes |
|---|---|---|---|
| App shell / theme | `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` | Done | App shell, router, design system, and home screen grid complete |
| App Icon / Branding | `DESIGN_SYSTEM.md` | Done | Master source icon, Android adaptive icons, Windows `.ico`, and in-app assets generated |
| PDF Merge | `FEATURE_pdf_merge.md` | Done | PDF Merge controller, UI, and test suite passing |
| PDF Merge Dividers | `docs/PHASE 3/TASK_pdf_merge_divider.md` | Done | Divider pages, width/height matching, isolate rendering, and test suite passing |
| PDF Page Manager | `FEATURE_pdf_page_manager.md` | Done | PDF Page Manager controller, UI, and test suite passing |
| PDF Split | `FEATURE_pdf_split.md` | Done | PDF Split controller, UI, thumbnail service extraction, and test suite passing |
| PDF Compress | `FEATURE_pdf_compress.md` | Done | PDF Compress controller, UI, before/after size badge, and test suite passing |
| PDF to Image | `FEATURE_pdf_to_image.md` | Done | PDF to Image controller, UI, DPI estimates, and test suite passing |
| PDF Password | `FEATURE_pdf_password.md` | Done | PDF Password controller, UI, Add/Remove protection, and test suite passing |
| PDF Insert Pages | `docs/PHASE 3/FEATURE_pdf_insert_pages.md` | Done | PDF Insert Pages controller, UI, live preview block, and test suite passing |
| PDF Insert Image as Page | `docs/PHASE 3/FEATURE_pdf_insert_image_as_page.md` | Done | PDF Insert Image as Page controller, UI, page fit modes, and test suite passing |
| Tool Search | `docs/PHASE 3/FEATURE_tool_search.md` | Done | Tool search controller, home screen filtering, and unit test suite passing |
| Image tools (v2) | *(spec pending)* | Not started | |

## 5. Decisions log

## 2026-07-29
- Decision: All Syncfusion PDF processing (`PdfDocument`, `createTemplate`, `drawPdfTemplate`, `.save()`) must run in background isolates via `compute()`, never on the main UI thread. `Future.delayed()` between loop iterations is not a viable alternative — Syncfusion calls are synchronous CPU-bound operations that block the event loop regardless of micro-delays.
- Decision: Used simple `compute()` (single message in, single result out) rather than full `Isolate` + `SendPort`/`ReceivePort` pipelines. Tradeoff: no per-page progress updates, but simpler code and smooth indeterminate progress bar animation. The smooth UI is a better user experience than frozen per-page text.
- Decision: Isolate worker functions live in a single shared file (`lib/core/services/pdf_isolate_worker.dart`) with parameter container classes, keeping isolate concerns separated from controller business logic.

## 2026-07-28
- Decision: Refactored `PdfInsertPagesController` to expose a static `splicePages` helper function, reusing page splicing logic directly for `PdfInsertImageAsPageController`.
- Decision: Explicitly filled background rectangle with white color when converting image to single-page PDF to ensure PNG transparency flattens cleanly without black backgrounds.
- Decision: Capped max image dimensions at 3000px and downscaled oversized source images during loading to avoid bloated output PDF file sizes.

## 2026-07-27
- Decision: Used `google_fonts` to resolve `Space Grotesk`, `Inter`, and `IBM Plex Mono` dynamically for desktop and mobile targets.
- Decision: Built reusable custom painter `_DashedBorderPainter` inside `file_drop_zone.dart` for cross-platform drag-and-drop feedback.
- Decision: Used `sourcePage.createTemplate()` and `destinationPage.graphics.drawPdfTemplate` during PDF merge to preserve exact original page content.
- Decision: Root cause of PDF Merge cropping bug identified — `destinationDoc.pages.add()` inherits default section settings with 40pt margins and default A4 size, causing clipping of non-A4 or landscape pages. Fixed by adding a dedicated `destinationDoc.sections.add()` per page with `section.pageSettings.size = sourcePage.size`, `section.pageSettings.margins.all = 0`, and explicit orientation matching.
- Decision: Catches password protection via `PdfDocument(inputBytes: bytes)` exception string analysis ("encrypted" / "password") to reject encrypted files at add-time with user-actionable instructions.
- Decision: Finalized `anvil_icon_07.png` (Stamp Ring Impact mark) as master logo asset. Configured Android adaptive background to design system token `workshopGrey` (`#ECEAE4`). Keyed background out for transparent adaptive foreground assets.

## 6. Known issues / tech debt

- **[FIXED] PDF Merge page content cropping:** Non-A4 pages and landscape pages were previously cropped due to default canvas margins and page sizes. Resolved by configuring section-level page dimensions (`pageSettings.size`) and zero margins per page. Verified via mixed-format regression tests (`test/tools/pdf_merge/pdf_merge_controller_test.dart` and `test/tools/pdf_merge/size_preservation_test.dart`).
- **[FIXED] UI freezing during PDF processing:** All PDF tool screens froze during processing because Syncfusion operations ran on the main UI thread. Fixed by moving all heavy work to background isolates via `compute()`. See `lib/core/services/pdf_isolate_worker.dart`.

## 7. Archiving old entries (keep this file lean)

This file is read in full at the start of every session — a bloated file burns tokens on history
that no longer matters. Once a feature is marked `Done` in the Feature Status Tracker AND hasn't
needed changes for a while, archive its detail:

1. Move its Progress Log entries and Decisions Log entries into `AGENTS_ARCHIVE.md` (create this
   file the first time you archive anything — same repo root, same log-entry format as here)
2. Leave a single summary line behind in this file's Progress Log, e.g.:
   `2026-XX-XX — PDF Merge shipped and stable. Full history archived in AGENTS_ARCHIVE.md.`
3. Keep the Feature Status Tracker row as-is (still shows `Done`) — don't remove it, that table
   should always show the full feature list at a glance
4. Never archive anything still `In progress` or anything with unresolved Known Issues attached

Rule of thumb: if the Progress Log section is getting longer than ~40-50 lines, it's time to
archive the oldest completed-feature entries. `AGENTS_ARCHIVE.md` is reference-only — don't read
it by default each session, only open it if you need historical context on something specific
(e.g. "why did we choose X for the merge feature back in session 2").

## 8. Before you stop working, checklist

- [ ] Progress Log has a new entry for this session
- [ ] Feature Status Tracker is up to date
- [ ] Any deviation from spec is recorded in Decisions Log
- [ ] Any shortcuts/known gaps are recorded in Known Issues
- [ ] Tests pass for anything marked "Done"
