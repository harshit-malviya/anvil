# Anvil — Project Overview

> Read this file first, and keep it as standing context for every task in this repo.
> Feature-specific instructions live in separate `FEATURE_*.md` files — implement one at a time.

## 1. What this is

Anvil is a free, open-source, offline-first desktop/mobile utility app. It bundles small
everyday file-manipulation tools (PDF merging, page management, image compression, resizing,
format conversion) into a single app, so users never have to upload personal files to a random
web tool. Everything runs **locally on the user's machine** — no server, no accounts, no
telemetry, no ads.

**Target platforms (v1):** Windows desktop, Android
**Future platforms:** macOS, Linux, iOS, Web (Flutter makes these low-cost additions later — don't
build platform-specific code that would block this)

## 2. Tech stack

- **Framework:** Flutter (stable channel) + Dart
- **State management:** Riverpod (`flutter_riverpod`) — use providers for all cross-widget state,
  avoid raw `setState` beyond purely local widget UI state (e.g. a hover flag)
- **Navigation:** `go_router`
- **PDF manipulation:** `syncfusion_flutter_pdf` (free community license — confirm revenue
  threshold still applies before shipping commercially; flag to the human if unsure)
- **Image manipulation:** `image` package (pure Dart, no native build dependency headaches)
- **File I/O:** `file_picker`, `path_provider`, `share_plus` (for Android "share result" flow)
- **Local persistence (settings only):** `shared_preferences` — no user file content is ever
  persisted outside the file system locations the user explicitly chooses

## 3. Non-negotiable product principles

Bake these into every feature, not just as an afterthought:

1. **Fully offline.** No network calls, ever, for core functionality. No "sign in," no cloud sync.
2. **No data leaves the device.** Files are read/written to disk directly; never transmitted.
3. **No dark patterns.** No fake progress bars, no forced ratings prompts, no upsells (this app has
   no paid tier — don't build monetization scaffolding).
4. **Fail loudly and clearly.** If a PDF is corrupted or a file can't be written (e.g. permission
   denied), show a specific, actionable error — never a silent failure or generic "Something went
   wrong."
5. **Non-destructive by default.** Never overwrite the user's original file unless they explicitly
   confirm. Default output behavior: save as a new file (e.g. `merged_output.pdf`), let the user
   pick the destination.

## 4. Repository / folder structure

```
Anvil/
  lib/
    core/
      theme/              # design tokens as Dart constants — see DESIGN_SYSTEM.md
      widgets/             # shared reusable widgets (buttons, file-drop-zone, tool card, etc.)
      services/
        file_service.dart # shared file pick/save logic used by all tools
      router.dart
    tools/
      registry.dart        # single source of truth: list of all tools, their metadata, routes
      pdf_merge/
        pdf_merge_screen.dart
        pdf_merge_controller.dart   # Riverpod StateNotifier — business logic, no UI
      pdf_page_manager/
        pdf_page_manager_screen.dart
        pdf_page_manager_controller.dart
      image_convert/
        image_convert_screen.dart
        image_convert_controller.dart
    home/
      home_screen.dart      # grid of tool cards, reads from tools/registry.dart
    main.dart
  test/
    tools/                  # one test file per tool controller (unit tests on logic, not widgets, for v1)
  pubspec.yaml
```

**Why this structure:** every tool is self-contained (screen + controller pair). Adding a new
tool later means adding one new folder + one registry entry — it should never require touching
existing tool code. Business logic lives in controllers, not in widgets, so it's testable without
spinning up the UI.

## 5. Coding conventions

- Follow standard `flutter_lints` rules (include the package, don't disable rules casually)
- Every controller class gets at least one unit test covering: happy path, empty input, and one
  realistic failure case (corrupt/locked file)
- No business logic inside `build()` methods — widgets read state from providers and call
  controller methods, that's it
- Use `AsyncValue` (Riverpod) to represent loading/error/data states for any file operation —
  never a bare boolean `isLoading` flag scattered across widgets
- Comment *why*, not *what* — assume the reader knows Dart

## 6. v1 scope (build in this order)

1. App shell: theme, router, home screen with tool grid (even if only 1-2 tools exist yet)
2. **PDF Merge** — see `FEATURE_pdf_merge.md`
3. **PDF Page Manager** (delete / reorder / rotate pages) — see `FEATURE_pdf_page_manager.md`
4. Polish pass: error states, empty states, loading states, responsive layout check on both
   Windows window-resize and Android small-screen

## 7. Explicitly out of scope for v1 (don't build yet)

- Image tools (Format Convert, Resize, Compress, Blur / Redact, Crop & Rotate) — v2, see `PRD_image_tools_v2.md` and per-tool `FEATURE_image_*.md` files
- PDF split, PDF compress, PDF-to-image, image-to-PDF — fast-follow after v1 ships, not v1
- Any account system, cloud storage, or sync
- In-app purchases / licensing tiers
- Batch processing (running one tool against many files at once) — v1 is single-file/single-job

## 8. When something is ambiguous

If a feature doc doesn't specify exact behavior for an edge case, make the most user-safe
choice (non-destructive, explicit confirmation, clear error) and leave a `// ASSUMPTION:` comment
explaining what you chose and why, so it can be reviewed later — don't block on it.
