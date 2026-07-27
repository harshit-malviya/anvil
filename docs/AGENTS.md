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

## 4. Feature status tracker

| Feature | Spec file | Status | Notes |
|---|---|---|---|
| App shell / theme | `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` | Done | App shell, router, design system, and home screen grid complete |
| App Icon / Branding | `DESIGN_SYSTEM.md` | Done | Master source icon, Android adaptive icons, Windows `.ico`, and in-app assets generated |
| PDF Merge | `FEATURE_pdf_merge.md` | Done | PDF Merge controller, UI, and test suite passing |
| PDF Page Manager | `FEATURE_pdf_page_manager.md` | Done | PDF Page Manager controller, UI, and test suite passing |
| PDF Split | *(spec pending)* | Not started | |
| Image tools (v2) | *(spec pending)* | Not started | |

## 5. Decisions log

## 2026-07-27
- Decision: Used `google_fonts` to resolve `Space Grotesk`, `Inter`, and `IBM Plex Mono` dynamically for desktop and mobile targets.
- Decision: Built reusable custom painter `_DashedBorderPainter` inside `file_drop_zone.dart` for cross-platform drag-and-drop feedback.
- Decision: Used `sourcePage.createTemplate()` and `destinationPage.graphics.drawPdfTemplate` during PDF merge to preserve exact original page content.
- Decision: Root cause of PDF Merge cropping bug identified — `destinationDoc.pages.add()` inherits default section settings with 40pt margins and default A4 size, causing clipping of non-A4 or landscape pages. Fixed by adding a dedicated `destinationDoc.sections.add()` per page with `section.pageSettings.size = sourcePage.size`, `section.pageSettings.margins.all = 0`, and explicit orientation matching.
- Decision: Catches password protection via `PdfDocument(inputBytes: bytes)` exception string analysis ("encrypted" / "password") to reject encrypted files at add-time with user-actionable instructions.
- Decision: Finalized `anvil_icon_07.png` (Stamp Ring Impact mark) as master logo asset. Configured Android adaptive background to design system token `workshopGrey` (`#ECEAE4`). Keyed background out for transparent adaptive foreground assets.

## 6. Known issues / tech debt

- **[FIXED] PDF Merge page content cropping:** Non-A4 pages and landscape pages were previously cropped due to default canvas margins and page sizes. Resolved by configuring section-level page dimensions (`pageSettings.size`) and zero margins per page. Verified via mixed-format regression tests (`test/tools/pdf_merge/pdf_merge_controller_test.dart` and `test/tools/pdf_merge/size_preservation_test.dart`).

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
