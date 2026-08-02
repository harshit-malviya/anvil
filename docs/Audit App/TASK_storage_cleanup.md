# Task: Storage Cleanup — Temp/Cache File Lifecycle (Android)

> Depends on: `PROJECT_OVERVIEW.md`, `AGENTS.md` (read both first).
> This is a standalone incremental task, not a rewrite of any shipped `FEATURE_*.md`. It touches
> shared services and existing tool controllers — do not re-spec any tool's user-facing flow.

## Why this exists

On Android, app storage is currently reporting roughly: App 95 MB / Data 1.77 GB (of which
Cache is 1.66 GB) / Total 1.87 GB. The cache figure is a subset of the data figure, so the
real story is ~1.66 GB of accumulated cache against ~110 MB of genuine persistent data. None of
the shipped feature specs explicitly required temp-file cleanup after an operation completes,
so this is a gap across the whole app, not a regression in any one tool.

## Root cause hypothesis (confirm each before fixing)

1. **`file_picker` copies picked files into app cache on Android.** Every file picked across
   every tool (Merge, Split, Compress, Password, PDF to Image, Page Manager) likely leaves a
   copy in `getTemporaryDirectory()` that is never deleted once the tool is done with it.
2. **`PdfThumbnailService`** (shared by Page Manager, Split, PDF to Image) may be persisting
   rendered page bitmaps to disk rather than holding them only in memory, with no cap or
   eviction — every PDF ever opened potentially leaves its rendered pages behind permanently.
3. **Intermediate/working files during processing** (e.g. draft compressed output before final
   write, per-page renders before folder assembly in Split / PDF to Image) may land in cache or
   app-documents directories and not be swept afterward, success or failure.
4. Confirm/deny each hypothesis by instrumenting a debug build and inspecting
   `getTemporaryDirectory()` / `getApplicationDocumentsDirectory()` contents after running each
   tool once — don't guess which one is the actual culprit before fixing it.

## Scope

This task adds a **shared temp-file lifecycle**, not per-tool patches. Fix once in a shared
service and have all six existing tools adopt it, per the "single source of truth" pattern
already used for `PdfThumbnailService` and `FileService`.

### 1. New shared service: `lib/core/services/temp_file_manager.dart`

- `registerTempFile(File file)` — tracks a file created during a tool session (e.g. a
  `file_picker`-copied source, a per-page render, a draft output) so it can be cleaned up later
- `cleanupSession()` — deletes all files registered in the current tool session; call this on:
  - successful completion of an operation (after the final output is written to its
    user-chosen, non-temp destination)
  - operation failure/cancellation (mirrors the existing PDF Split rollback pattern — temp files
    are not "the output," so they're always safe to delete, unlike output files which need the
    rollback-on-partial-failure treatment already specced in `FEATURE_pdf_split.md`)
  - app launch — sweep any orphaned temp files left behind by a previous session that crashed
    or was killed before cleanup ran (this is the most likely source of the current 1.66 GB,
    since a killed app never gets to run its own cleanup)
- `cacheDirectorySize()` — returns current size of the app's temp directory, for optional
  display in a future Settings screen (not required by this task, just don't block it)

### 2. `PdfThumbnailService` audit

- Confirm whether rendered thumbnails are written to disk or held in memory
- If written to disk: convert to an in-memory LRU cache with a hard size cap (define a concrete
  number as a named constant, e.g. `maxThumbnailCacheBytes`, rather than leaving it unbounded —
  document the chosen value as a `// ASSUMPTION:` comment since no spec pins it)
- If held in memory already: no disk-side fix needed here, but confirm the in-memory cache is
  actually bounded (evicted when a tool screen is disposed) and not silently growing across
  tool sessions within a single app run

### 3. Per-tool adoption

Every existing controller that currently reads a `PlatformFile` from `file_picker` or writes an
intermediate file must call `TempFileManager.registerTempFile()` for each such file, and the
screen/controller must call `cleanupSession()` at the appropriate lifecycle point (success,
error, and `dispose()`/navigate-away). Tools affected: PDF Merge, PDF Page Manager, PDF Split,
PDF Compress, PDF to Image, PDF Password.

- This is an additive change to each controller — do not restructure their existing public API
  or re-implement any already-shipped business logic
- Final output files the user explicitly saves (via Save As / Open Folder) are **never** treated
  as temp files and must never be touched by this cleanup, regardless of where they were
  staged during processing

### 4. Startup sweep

On app launch (`main.dart`, before the home screen renders), run
`TempFileManager.sweepOrphanedFiles()` — deletes anything left in the app's temp directory from
a previous session. This must not block the UI; run it fire-and-forget after first frame, not
as a blocking splash step.

## Edge cases

| Case | Required behavior |
|---|---|
| App is killed (not gracefully closed) mid-operation | Orphaned temp files remain until next launch's startup sweep — acceptable, this is exactly what the sweep is for |
| Cleanup runs but a file is locked/in-use by the OS | Log and skip that file rather than throwing — cleanup failures must never surface as a user-facing error, this is invisible maintenance |
| User picks the same file twice in one session (e.g. re-adds after removing from Merge list) | Don't double-register/double-copy if avoidable, but if the underlying `file_picker` behavior forces a fresh copy each time, registering the duplicate is fine — correctness over cleverness here |
| Thumbnail LRU cache cap is hit mid-session (user scrolls through a 300-page PDF) | Oldest thumbnails evicted first; re-scroll re-renders them — a brief re-render is an acceptable tradeoff for a bounded cache, don't skip the cap to avoid this |

## Testing

- Unit test `TempFileManager`: register → cleanupSession deletes registered files; sweep deletes
  files not registered in the current run; cleanup never touches a file outside the temp
  directory (guard against a bad path being registered)
- For each of the six tools, add a regression test (or extend the existing controller test file)
  asserting that after a successful operation, no files remain in the temp directory except the
  user's chosen output destination
- Manual verification: run each tool once on a real Android device/emulator, check
  Settings → Apps → Anvil → Storage before and after, confirm Cache no longer grows unbounded
  across repeated use

## Out of scope for this task

- A user-facing "Clear Cache" button or Settings screen — future fast-follow if still needed
  after this fix, not required to solve the current bloat
- Changing where final output files are saved — this task only touches temporary/intermediate
  files, never user-chosen output locations
- Any iOS/macOS/Linux/Web-specific temp directory handling — Android is the platform where this
  was observed; revisit for other platforms if the same pattern shows up later
