# AGENTS.md — Anvil

> Read this file FIRST, before any spec file, at the start of every session.
> Update the "Progress Log" and "Decisions Log" sections at the END of every session, before
> stopping work — this file is the only thing that carries context forward to your next session
> or to a different agent picking up the work.

## 1. What this repo is

Anvil — a free, offline, open-source utility app (PDF tools, image tools) for Windows + Android,
built in Flutter. Full product vision: `PROJECT_OVERVIEW.md`. Visual identity: `DESIGN_SYSTEM.md`.
Build/CI: `BUILD_SETUP.md`. Each shippable feature has its own `FEATURE_*.md`.

> v2 image tools are sequenced via `PRD_image_tools_v2.md` — one sprint per tool, gated through
> Scope → Implement → Test → Debug → Audit. Read it before starting any `FEATURE_image_*.md`.

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
8. **Standardized File Picker and Completion View Pattern.** All tool screens MUST use `FileService` (`lib/core/services/file_service.dart`) for picking and saving files, and MUST implement the standardized completion view layout (`_buildSuccessView` / completion state):
   - `StampAnimation(label: '<STAMP_TEXT>')` with a descriptive uppercase stamp (e.g. `MERGED`, `ARRANGED`, `SPLIT`, `COMPRESSED`, `EXPORTED`, `PROTECTED`, `UNPROTECTED`, `PAGE INSERTED`, `PAGES INSERTED`, `CREATED`, `CONVERTED`).
   - Standardized completion title in `AppTypography.displayMedium(brightness)`.
   - File details / size / page comparison card styled with `AppColors.cardBackground(brightness)` and `AppColors.pegGrey` border.
   - `'Saved to:'` header in `AppTypography.labelSmall(brightness)` followed by a full-width `SelectableText` containing the output file or directory path in a rounded `AppColors.pegGrey.withValues(alpha: 0.15)` container.
   - Standardized action buttons wrapped in `Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center)`:
     1. `AppButton(label: 'Open Folder', icon: Icons.folder_open_rounded, variant: AppButtonVariant.primary)`
     2. `AppButton(label: 'Save As…', icon: Icons.save_alt_rounded, variant: AppButtonVariant.secondary)`
     3. `AppButton(label: 'Share', icon: Icons.share_rounded, variant: AppButtonVariant.secondary)`
     4. `AppButton(label: '<Tool Reset Label>', icon: Icons.refresh, variant: AppButtonVariant.secondary)`
   - SnackBar feedback on `Save As…` completion (`File saved to $savedPath` using `AppColors.anvilTeal` or `AppColors.rustRed` on error).

## 3. Progress log

> Add a new dated entry each session. Keep entries short — what changed, what's left, what broke.
> Don't delete old entries; this is a history, not just a current-state snapshot.

## 2026-08-02 — Session 26
- Implemented Storage Cleanup — Temp/Cache File Lifecycle (Android) (`TASK_storage_cleanup.md`):
  - Created `TempFileManager` service (`lib/core/services/temp_file_manager.dart`) and Riverpod singleton provider (`tempFileManagerProvider`) featuring session path tracking, path guard validation (`getTemporaryDirectory()`), fault-tolerant `cleanupSession()`, non-blocking orphan sweep `sweepOrphanedFiles()`, and `cacheDirectorySize()` calculation hook.
  - Centralized file registration inside `FileService` (`lib/core/services/file_service.dart`) `pickPdfFiles` and `pickImageFiles` methods — zero controller boilerplate required for tracking picked copies.
  - Configured startup orphan sweep in `lib/main.dart` via `ref.read(tempFileManagerProvider)` post-frame callback.
  - Adopted `TempFileManager` across all 14 tool controllers (8 PDF, 1 PDF-adjacent, 5 Image) at operation success, operation error/failure, and tool reset/clear endpoints.
  - Created unit test suite `test/core/services/temp_file_manager_test.dart` (7 tests) and updated `test/file_service_test.dart`. All 196 workspace unit/widget tests passing cleanly.
  - Created technical specification document `docs/Audit App/TECHNICAL_DOC_temp_file_lifecycle.md`.

## 2026-08-01 — Session 25
- Implemented Fine-angle "Straighten" Rotation for Image Crop & Rotate (`TASK_image_crop_rotate_straighten.md`):
  - Updated `ImageCropRotateState` in `lib/tools/image_crop_rotate/image_crop_rotate_state.dart` with `fineRotationAngle` (−45° to +45°) and derived `inscribedCropBounds` getter using inscribed-rectangle geometry to eliminate empty canvas corners.
  - Updated `ImageCropRotateController` and `isolateImageCropRotateWorker` in `lib/tools/image_crop_rotate/image_crop_rotate_controller.dart` to support fine angle adjustments, automatic crop box shrink/recenter to fit inscribed bounds, cubic interpolation fine rotation (`img.copyRotate`), coordinate shift mapping, and reset.
  - Updated `ImageCropRotateScreen` in `lib/tools/image_crop_rotate/image_crop_rotate_screen.dart` with Straighten slider (−45° to +45°), live signed readout (e.g. `+3.5°`), Reset tap target, visual rotation canvas preview (`Transform.rotate`), rule-of-thirds grid, and microcopy helper note.
  - Expanded unit test suite `test/tools/image_crop_rotate/image_crop_rotate_controller_test.dart` (14 unit tests passing cleanly). All 185 workspace unit and widget tests passing.

## 2026-08-01 — Session 24
- Implemented Image Crop & Rotate feature (`FEATURE_image_crop_rotate.md`):
  - Created `AspectRatioPreset` (`free`, `original`, `square`, `fourThree`, `sixteenNine`, `threeTwo`) and immutable `ImageCropRotateState` in `lib/tools/image_crop_rotate/image_crop_rotate_state.dart`.
  - Created `ImageCropRotateController` and `isolateImageCropRotateWorker` in `lib/tools/image_crop_rotate/image_crop_rotate_controller.dart` supporting EXIF orientation baking, 90° clockwise step rotation, crop rectangle selection in rotated pixel space, minimum crop size validation (10x10px floor), aspect ratio locking, and background isolate processing.
  - Created `ImageCropRotateScreen` in `lib/tools/image_crop_rotate/image_crop_rotate_screen.dart` with single image drop zone, interactive crop overlay canvas with corner and edge handles, rule-of-thirds grid, output size live readout, rotation reset inline notice banner, unsaved changes guard, and completion stamp view (`EXPORTED`).
  - Registered route `/image-crop-rotate` in `lib/core/router.dart` and tool metadata in `lib/tools/registry.dart`.
  - Updated `PROJECT_OVERVIEW.md` and `AGENTS.md` Feature Status Tracker.
  - Created unit test suite `test/tools/image_crop_rotate/image_crop_rotate_controller_test.dart` (9 test cases covering loading validation, rotation cycle, dimensions swap, crop bounds clamping, 10x10 floor rejection, aspect ratio lock recalculation, and background isolate execution).

## 2026-08-01 — Session 23
- Implemented Image Blur (Selective Redaction) feature (`FEATURE_image_blur.md`):
  - Created `RedactionStyle` (`pixelate`, `blur`, `solidBlock`), `RedactionIntensity` (`small`, `medium`, `large`), `RedactionRegion` model, and `ImageBlurState` in `lib/tools/image_blur/image_blur_state.dart`.
  - Created `ImageBlurController` and `isolateImageBlurWorker` in `lib/tools/image_blur/image_blur_controller.dart` supporting region adding/updating/removal, bounds clamping, minimum size validation (10x10px floor), preset block sizes (12/24/40px) and blur radii (10/25/50px capped at 40% shorter side), solid block fill colors, and background isolate processing.
  - Created `ImageBlurScreen` in `lib/tools/image_blur/image_blur_screen.dart` with single image drop zone, interactive image canvas with tap-and-drag rectangle drawing, corner resize handles, body drag moving, region deletion, redaction style segment control, blur security warning banner, color swatch picker, bottom summary bar, unsaved changes guard, and completion stamp view (`REDACTED`).
  - Registered route `/image-blur` in `lib/core/router.dart` and tool metadata in `lib/tools/registry.dart`.
  - Updated `PROJECT_OVERVIEW.md` to reflect v2 image tool set including Image Blur.
  - Created unit test suite `test/tools/image_blur/image_blur_controller_test.dart` (11 test cases covering loading validation, region clamping, minimum size floor, style toggles, and pixel-level redaction verification).

## 2026-08-01 — Session 22

- Implemented Reactive Dimension-Reduction Fallback for Image Compress Target Size Range (`TASK_image_compress_dimension_fallback.md`):
  - Created `ImageResizeService` in `lib/core/services/image_resize_service.dart` for shared proportional image scaling and dimension stepping calculations (90% decrements, 50% min dimension floor). Refactored `ImageResizeController` to use `ImageResizeService`.
  - Updated `ImageCompressState` with `isDimensionFallbackEnabled`, `compressedWidth`, `compressedHeight`, `bothFloorsHit`, snapshot tracking for pre-resize state reversion, and getters (`isDimensionReduced`, `formattedOriginalDimensions`, `formattedCompressedDimensions`).
  - Updated `ImageCompressController` and `isolateImageCompressWorker` to perform iterative 90% resolution stepping down to 50% dimension floor when initial quality-only compression fails to land in range and fallback is enabled.
  - Added `setDimensionFallbackEnabled` toggle and `retryWithDimensionReduction` explicit action. Toggling fallback OFF restores pre-resize closest-effort state.
  - Updated `ImageCompressScreen` UI with "Also reduce image dimensions to reach your target size" checkbox, helper text showing original vs 50% floor dimensions, "Retry" button, and dual-delta messaging for file size + dimensions.
  - Created `test/core/services/image_resize_service_test.dart` and expanded `test/tools/image_compress/image_compress_controller_test.dart` with 4 new fallback test cases. All 161 workspace unit/widget tests passing.
- Implemented Sprint 3 Image Compress (`FEATURE_image_compress.md`, `PRD_image_tools_v2.md`):
  - Created `CompressionMode` (`qualityLevel`, `targetSizeRange`), `CompressionLevel` (`low`, `medium`, `high`), `SizeUnit` (`kb`, `mb`), `CompressionResultType` (`normalSuccess`, `minimalReduction`, `outputLarger`, `inRangeSuccess`, `closestEffort`, `alreadyInRange`, `smallerThanMin`), and `ImageCompressState` in `lib/tools/image_compress/image_compress_state.dart`.
  - Created `ImageCompressController` in `lib/tools/image_compress/image_compress_controller.dart` featuring background isolate worker (`isolateImageCompressWorker`), JPEG quality binary search (1-100 quality, 8 max iterations), PNG palette quantization (`img.quantize` 256..16 colors) + zlib levels, hard floor validation (>= 5 KB), original already in range skip, original smaller than minimum rejection, EXIF orientation baking (`img.bakeOrientation`), and file save/folder actions.
  - Created `ImageCompressScreen` in `lib/tools/image_compress/image_compress_screen.dart` with single image drop zone, thumbnail preview card with mono specs, mode selector (`Quality Level` vs `Target Size Range`), min/max size fields with KB/MB unit toggles, inline 5 KB floor warning, range validation error, progress dialog overlay (`Finding the right size…`), stamp animation (`COMPRESSED`), size comparison card with range confirmation badge, and completion actions (`Open Folder`, `Save As…`, `Share`, `Compress Another Image`).
  - Registered route `/image-compress` in `lib/core/router.dart` and tool metadata in `lib/tools/registry.dart`.
  - Created unit test suite `test/tools/image_compress/image_compress_controller_test.dart` (12 unit tests passing cleanly). All 152 workspace tests passing with 0 lint errors.

## 2026-07-31 — Session 20
- Implemented Sprint 2 Image Resize (`FEATURE_image_resize.md`, `PRD_image_tools_v2.md`):
  - Created `ResizeMode` (`exactDimensions`, `percentage`, `preset`), `ImagePreset` (HD, Full HD, 4K, Square, Story, Web banner), and immutable `ImageResizeState` in `lib/tools/image_resize/image_resize_state.dart`.
  - Created `ImageResizeController` in `lib/tools/image_resize/image_resize_controller.dart` featuring background isolate worker (`isolateImageResizeWorker`), EXIF orientation baking (`img.bakeOrientation`), mode switching intent preservation, aspect-ratio locking calculations, preset selection, percentage scaling, floor validation (< 10px), upscaling detection getter, and error handling.
  - Created `ImageResizeScreen` in `lib/tools/image_resize/image_resize_screen.dart` with single image drop zone, thumbnail preview card with mono specs, mode selector, exact dimensions inputs with lock toggle, percentage slider and chips, preset chips, inline stretch/squash warning when unlocked, upscaling warning, live numeric preview line (`New size: W × H px`), stamp animation (`RESIZED`), and completion save/folder actions.
  - Registered route `/image-resize` in `lib/core/router.dart` and tool metadata in `lib/tools/registry.dart`.
  - Created comprehensive unit test suite `test/tools/image_resize/image_resize_controller_test.dart` (14 unit tests passing cleanly). All 140 workspace tests passing with 0 lint errors.

## 2026-07-31 — Session 19
- Unified Tool Family Colors & Global Dark/Light Theme Mode:
  - Added global `themeModeProvider` (`System`, `Light`, `Dark`) and `ThemeToggleButton` widget integrated across `HomeScreen` and all 10 tool AppBars.
  - Standardized tool family accent colors across all screens (`ToolCategory.pdf` -> Copper `#FFB5502D` / `#FFC75D37`, `ToolCategory.image` -> Blue `#FF357ABD` / `#FF498ED1`).
  - Purged legacy `anvilTeal` and `anvilTealDark` colors and all cross-contaminated UI element colors.
  - Verified static analysis (`0 errors`) and test suite (`126/126` unit & widget tests passing).

## 2026-07-31 — Session 18
- Implemented Visual Differentiation (`TASK_visual_differentiation.md`):
  - Added `ToolCategory` enum (`pdf` vs `image`) and `category` field to `ToolMetadata` in `lib/tools/registry.dart`.
  - Added `AppColors.familyAccent(ToolCategory, [Brightness])` color token resolver in `lib/core/theme/app_colors.dart` (`emberCopper` for PDF tools, `anvilBlue` light blue for Image tools).
  - Updated `ToolCard` so icon colors follow tool family accent colors while icon container background stays neutral (`pegGrey` tint / `steelCard`). Wired card hover/focus borders to use family accent color.
  - Updated `HomeScreen` to group tool grid into two ordered sections: "PDF TOOLS" followed by "IMAGE TOOLS" (24px top / 12px bottom header spacing).
  - Updated `AppButton`, `StampAnimation`, `ImageConvertScreen`, `ImagesToPdfScreen`, `PdfInsertPagesScreen`, and `PdfInsertImageAsPageScreen` to use family accent color tokens.
  - Updated `DESIGN_SYSTEM.md` (§2 & §5) and test suite `test/home/tool_search_controller_test.dart`.
- Implemented Sprint 1 Image Format Convert (`FEATURE_image_convert.md`, `PRD_image_tools_v2.md`):
  - Created `ImageOutputFormat` enum and `ImageConvertState` in `lib/tools/image_convert/image_convert_state.dart`.
  - Created `ImageConvertController` in `lib/tools/image_convert/image_convert_controller.dart` featuring magic-byte format detection (PNG, JPEG, BMP, GIF, TIFF, WebP), `compute()` background isolate image encoding, JPEG transparency flattening onto white background, animated GIF/WebP first-frame extraction, JPEG quality adjustment, and error handling.
  - Created `ImageConvertScreen` in `lib/tools/image_convert/image_convert_screen.dart` with drag-drop zone, thumbnail preview card with mono specs, format pill selector (disabling same-format selection), JPEG quality slider, inline transparency and animation notices, stamp animation (`CONVERTED`), and output save/folder actions.
  - Registered route `/image-convert` in `lib/core/router.dart` and metadata in `lib/tools/registry.dart`.
  - Updated `PROJECT_OVERVIEW.md` and `AGENTS.md` per `PATCH_notes_for_v2_kickoff.md`.
  - Created unit test suite `test/tools/image_convert/image_convert_controller_test.dart` (9 unit tests passing cleanly). All 124 workspace tests passing with 0 lint errors.
- Completed PDF Tools Audit (`TASK_audit_isolate_error_handling.md`, `TASK_audit_edge_case_fidelity.md`, `TASK_audit_error_message_consistency.md`):
  - Created shared static utility `PdfValidationService` in `lib/core/services/pdf_validation_service.dart` and dedicated test suite `test/core/services/pdf_validation_service_test.dart` (6 tests).
  - Consolidated password/corrupted PDF validation across 8 PDF tool controllers.
  - Hardened isolate error handling (`OutOfMemoryError`, `FileSystemException`) across all PDF tool controllers.
  - Separated `PdfSplitController` isolate processing errors from disk write errors with automatic output rollback.
  - Swept all 10 controllers to eliminate raw `Exception.toString()` output in user-facing error messages, replacing them with actionable plain-language text adhering to DESIGN_SYSTEM.md §5.
  - Re-verified all edge case spec rows across all 10 tools — 100% pass rate. All 115 tests passing cleanly.

## 2026-07-30 — Session 16
- Implemented Images to PDF feature (`FEATURE_images_to_pdf.md`):
  - Extracted shared `ImageToPdfPageService` in `lib/core/services/image_to_pdf_page_service.dart` for image format validation (.png/.jpg/.jpeg), 3000px max dimension downscaling cap, and 400px preview thumbnail generation. Refactored `PdfInsertImageAsPageController` to use shared service.
  - Added `ImagesToPdfParams` and `isolateImagesToPdf` in `lib/core/services/pdf_isolate_worker.dart` for background isolate PDF page generation with white background rectangle fill (flattening PNG transparency).
  - Created `lib/tools/images_to_pdf/images_to_pdf_state.dart` with `ImageFileItem` model and state getters.
  - Created `lib/tools/images_to_pdf/images_to_pdf_controller.dart` supporting image addition, format/readability validation, reordering, removal, clearing, and background isolate PDF creation with timestamped output file paths.
  - Created `lib/tools/images_to_pdf/images_to_pdf_screen.dart` with file drop zone, virtualized reorderable list view (`ReorderableListView.builder`), progress overlay, stamp animation (`PDF CREATED`), and completion actions.
  - Registered route `/images-to-pdf` in `lib/core/router.dart` and metadata with keywords in `lib/tools/registry.dart`.
  - Created comprehensive unit test suite `test/tools/images_to_pdf/images_to_pdf_controller_test.dart` testing single/multi-image conversion, order preservation, unsupported format rejection, corrupted image rejection, 3000px downscale, mixed orientation sizing, reordering, item removal, and state resets.


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

## 2026-07-29 — Session 15
- Upgraded PDF Insert Image as Page feature to v1.1 / v2 (`docs/PHASE 3/FEATURE_pdf_insert_image_as_page_v2.md`):
  - Updated `ImageItemState` and `PdfInsertImageAsPageState` to store a list of images (`images`) with unique IDs, files, bytes, thumbnails, and pixel dimensions.
  - Updated `PdfInsertImageAsPageController` with `addImages` (handling multi-file pick and per-file error messages), `removeImage`, `reorderImages`, `clearImages`, and `insertImagePages`.
  - Updated `isolateInsertImagePages` in `lib/core/services/pdf_isolate_worker.dart` to construct multi-page image PDFs and splice them into the target document at a single shared insertion point.
  - Refactored `PdfInsertImageAsPageScreen` UI with multi-file picker support, reorderable image list view with drag handles, thumbnail previews, file size indicators, item removal controls, and dynamic primary button labels ("Insert Page" / "Insert N Pages").
  - Updated unit test suite `test/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_controller_test.dart` covering 1-image regression, N-images insertion at start/middle/end, `matchNeighboringPage` shared neighbor sizing, `fitToImage` per-image aspect ratio sizing, image reordering before insert, bad image isolation, item removal, and zero-page fallback. All 14 unit test cases passing.

## 2026-07-29 — Session 14
- Implemented optional divider pages feature for PDF Merge (`docs/PHASE 3/TASK_pdf_merge_divider.md`):
  - Updated `isolateMergePdfs` in `lib/core/services/pdf_isolate_worker.dart` to accept `MergeParams` and build 1-inch (72pt) white divider pages before source files 2..N with centered/truncated filename.
  - Resolved Devanagari / Hindi complex script shaping issue (e.g. `भारत की नदियां #2` rendering matras correctly): pre-renders divider strips via Flutter's native `TextPainter` + HarfBuzz engine into high-res PNG images (`renderDividerImage`), passing `dividerImages` into `isolateMergePdfs` for 100% accurate visual matra positioning. Also bundled `NotoSansDevanagari-Regular.ttf` in `assets/fonts/` for isolate fallback drawing.
  - Updated `PdfMergeState` and `PdfMergeController` with `insertDividers` property and `setInsertDividers` toggle.
  - Added "Insert a divider page between files" checkbox in `lib/tools/pdf_merge/pdf_merge_screen.dart`.
  - Added unit test cases in `test/tools/pdf_merge/pdf_merge_controller_test.dart` for divider insertion, height/width matching, Hindi filename rendering, and state toggles.

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
| PDF Insert Image as Page | `docs/PHASE 3/FEATURE_pdf_insert_image_as_page_v2.md` | Done | Upgraded to v2 (N images batch insertion at shared point, reordering, test suite passing) |
| Tool Search | `docs/PHASE 3/FEATURE_tool_search.md` | Done | Tool search controller, home screen filtering, and unit test suite passing |
| Images to PDF | `docs/PHASE 3/FEATURE_images_to_pdf.md` | Done | Controller, UI, shared image service extraction, background isolate, and test suite passing |
| Image Format Convert | `FEATURE_image_convert.md` | Done | Controller, UI, isolate worker, transparency flattening, unit tests passing |
| Image Resize | `docs/V2/02_Image_Resizer/FEATURE_image_resize.md` | Done | Controller, UI, background isolate worker, ratio lock, presets, unit tests passing |
| Image Compress | `docs/V2/03_Image_Compress/FEATURE_image_compress.md` | Done | Controller, UI, background isolate worker, format-specific quality encoding, size comparison result types, unit tests passing |
| Image Blur | `docs/V2/04_Image_Blur/FEATURE_image_blur.md` | Done | Controller, UI, interactive canvas drawing, background isolate worker, redaction styles (Pixelate, Blur, Solid Block), unit tests passing |
| Image Crop & Rotate | `docs/V2/05_Crop_&_Rotate/FEATURE_image_crop_rotate.md` | Done | Controller, UI, interactive canvas crop overlay, 90° step rotation, background isolate worker, unit tests passing |
| Storage Cleanup | `docs/Audit App/TASK_storage_cleanup.md` | Done | Shared TempFileManager service, FileService auto-registration, startup sweep, 14-controller adoption, unit tests passing |

## 5. Decisions log


## 2026-08-02
- Decision: Temporary file registration is centralized inside `FileService` (`pickPdfFiles()`, `pickImageFiles()`) so controllers never need manual file registration boilerplate.
- Decision: `registerTempPath` enforces a path guard checking if the normalized path starts with `getTemporaryDirectory()`, preventing user output files saved to external storage/downloads from ever being registered or accidentally deleted.
- Decision: `cleanupSession()` and `sweepOrphanedFiles()` execute in a non-blocking, fault-tolerant manner (try-catch per file) to ensure cleanup failures never disrupt UI workflows.
- Decision: Startup sweep runs fire-and-forget in a post-frame callback (`WidgetsBinding.instance.addPostFrameCallback`) using `ref.read(tempFileManagerProvider)`.

## 2026-08-01
- Decision: Rotation in Image Crop & Rotate advances 90° clockwise per tap (0° → 90° → 180° → 270° → 0°).
- Decision: Rotation resets crop rectangle selection back to full bounds of the new orientation, displaying an inline note to the user.
- Decision: EXIF orientation is baked in (`img.bakeOrientation`) before user rotation and crop transformations are applied.
- Decision: Crop selection coordinates are maintained in the current rotated image's pixel space. Isolate worker applies rotation first (`img.copyRotate`), then crop (`img.copyCrop`).
- Decision: JPEG compression levels map to concrete quality values: Low=85 (minimal reduction, high visual quality), Medium=65 (balanced), High=40 (maximum reduction).
- Decision: PNG compression levels map to zlib compression levels: Low=level 3, Medium=level 6, High=level 9.
- Decision: WebP inputs are rejected with a clear user message because package:image 4.x has a read-only WebP decoder with no WebP encoder support.
- Decision: Output size comparison categorizes results into `normalSuccess` (reduction >= 5%), `minimalReduction` (reduction < 5%), or `outputLarger` (compressed size >= original size), guarding against presenting a worse output file as a success.
- Decision: Resizing interpolation uses high-quality `img.Interpolation.cubic` in the background isolate worker.
- Decision: EXIF orientation is automatically baked into the image (`img.bakeOrientation`) before resizing so mobile photo orientation is preserved right-side up.
- Decision: Presets apply preset width as starting width when aspect ratio lock is ON, recalculating target height from source aspect ratio. When aspect ratio lock is OFF, preset exact width & height both apply.
- Decision: Tool families are visually differentiated by family accent colors resolved via `AppColors.familyAccent(category, brightness)` (`emberCopper` for PDF tools, `anvilBlue` light blue `#357ABD` / `#498ED1` for Image tools).
- Decision: Tool card icons follow their tool family accent color, housed inside a neutral icon container background (`pegGrey` tint / `steelCard`). Card hover/focus borders use family accent color.
- Decision: Home screen tool grid groups tools by category into ordered sections ("PDF TOOLS" followed by "IMAGE TOOLS") with fixed spacing (24px top, 12px bottom).
- Decision: WebP input images are decoded successfully, but WebP is excluded as a target output format due to `package:image` 4.x asymmetric support (read-only WebP decoding, no WebP encoder).
- Decision: Transparent areas in PNG, GIF, BMP, or TIFF source images are automatically flattened onto a solid white background when converting to JPEG, displaying an inline notification to the user pre-conversion.
- Decision: Animated GIF and WebP source files extract and convert only the first frame, displaying an inline notification to the user pre-conversion.
- Decision: Format detection uses magic-byte header inspection first (`0x89 PNG`, `0xFFD8 JPEG`, `0x474946 GIF`, `0x424D BMP`, `0x4949`/`0x4D4D TIFF`, `RIFF...WEBP`), with file extension as fallback.
- Decision: Image encoding and file I/O operations are offloaded to background isolates via Flutter `compute()` (`isolateImageConvertWorker`) to keep UI main thread 100% smooth.

## 2026-07-30
- Decision: Centralized password-protected and corrupted PDF validation into a static utility class `PdfValidationService` (`lib/core/services/pdf_validation_service.dart`) with dedicated unit test coverage (`test/core/services/pdf_validation_service_test.dart`), eliminating 8 duplicate implementations across PDF controllers.
- Decision: Replaced all raw `$e` / `Exception.toString()` messages across controllers with bold, plain-language, actionable error text.
- Decision: Separated `PdfSplitController` isolate execution failures from file I/O write failures to prevent misleading "rolled back" messaging when processing fails before any files are written to disk.
- Decision: Extracted `ImageToPdfPageService` to unify image format validation, 3000px downscaling, and preview thumbnail generation across `Insert Image as Page` and `Images to PDF` tools.
- Decision: PDF pages generated from images retain each image's native aspect ratio and pixel dimensions (after downscaling cap), supporting mixed portrait and landscape pages within the same document without forcing uniform A4/Letter sizing.


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
