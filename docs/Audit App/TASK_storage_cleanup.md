# Task: Storage Cleanup — Temp/Cache File Lifecycle (Android)

> Depends on: `PROJECT_OVERVIEW.md`, `AGENTS.md` (read both first — check the Feature Status
> Tracker in `AGENTS.md` §4 for the current full tool list before starting; it has grown since
> this task was first scoped and this doc has been updated to match).
> This is a standalone incremental task, not a rewrite of any shipped `FEATURE_*.md`. It touches
> a shared core service and existing tool controllers — do not re-spec any tool's user-facing flow.

## Why this exists

On Android, app storage is currently reporting roughly: App 95 MB / Data 1.77 GB (of which
Cache is 1.66 GB) / Total 1.87 GB. The cache figure is a subset of the data figure, so the real
story is ~1.66 GB of accumulated cache against ~110 MB of genuine persistent data.

## Confirmed root cause (from prior audit — do not re-investigate)

- `FilePicker.platform.pickFiles()` on Android copies picked files into the app's cache
  directory (`getTemporaryDirectory()`). These copies persist indefinitely. Every tool reads
  `platformFile.path`, which points at this cache copy. **This is the confirmed primary source
  of the bloat.**
- `PdfThumbnailService` was audited and is **not** a contributor — it uses `pdfx`'s native
  rendering API, which returns `Uint8List` bytes held only in memory (in controller state),
  garbage-collected on controller dispose/reset. No disk-side fix or LRU cache needed here.

## Scope — full current tool list

The original version of this task named only 6 PDF tools. The app has since grown; per
`AGENTS.md` §4 Feature Status Tracker, **every** tool below picks files via `FileService` and
must be covered by this fix:

**PDF tools:** Merge, Page Manager, Split, Compress, PDF to Image, Password, Insert Pages,
Insert Image as Page

**Also PDF-adjacent:** Images to PDF

**Image tools:** Format Convert, Resize, Compress, Blur, Crop & Rotate

That's 13 tool controllers total. Do not scope this down to a subset — a partial fix leaves the
same leak active in whichever tools are skipped, which defeats the point of the task.

## Architectural approach — centralize in `FileService`, not per-controller

Per `AGENTS.md` §2 Rule #8, **all tool screens already MUST use `FileService`
(`lib/core/services/file_service.dart`) for picking and saving files.** This is a single choke
point every tool already funnels through — use it instead of duplicating registration logic
across 13 controllers.

**Do not** add "read bytes → manually register path" boilerplate to each controller. Instead:

- Registration happens **inside `FileService`'s pick methods themselves** (e.g.
  `pickPdfFiles()`, `pickImageFiles()`, and any other pick method it exposes) — every path
  returned to a caller is already registered with `TempFileManager` before the method returns.
- This means **zero controller changes are needed for registration**, today or for any future
  tool that adopts `FileService` — leak protection is automatic just by using the existing
  standard pattern.
- Controllers only need to add `cleanupSession()` calls at their existing lifecycle points
  (success / error / reset) — see §3 below. This is a much smaller, less error-prone surface
  than touching registration logic 13 separate times.

## Proposed structure

### 1. New shared service: `lib/core/services/temp_file_manager.dart`

- `registerTempFile(File file)` / `registerTempPath(String path)` — tracks a file created or
  copied during a tool session so it can be cleaned up later
- `cleanupSession()` — deletes all currently registered files, silently skipping locked/missing
  files (never throws), then clears the tracked set
- `sweepOrphanedFiles()` — deletes everything inside `getTemporaryDirectory()` not currently
  registered; fire-and-forget, never surfaces a UI error
- `cacheDirectorySize()` — returns total bytes in the temp dir (hook for a future Settings
  screen; not required by this task, just don't block it)
- Guard: `registerTempFile` validates the path is actually inside the temp directory before
  accepting — prevents ever registering a user's chosen output file for deletion
- Riverpod provider: `tempFileManagerProvider` (singleton)

### 2. `FileService` — the actual fix point

- Every pick method (`pickPdfFiles()`, `pickImageFiles()`, and any others) registers each
  returned file's path with `TempFileManager` before returning it to the caller
- `FileService` takes a `TempFileManager` dependency (constructor or Riverpod-injected) so this
  is testable in isolation
- No change to each method's existing return signature — this is purely an added side effect at
  the point files are already flowing through this service

### 3. `main.dart` — startup sweep

Add a fire-and-forget orphan sweep after the first frame, non-blocking:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  tempFileManager.sweepOrphanedFiles();
});
```
This is the safety net for the case that matters most: an app killed mid-session never runs its
own `cleanupSession()`, so orphans accumulate until the next launch sweeps them.

### 4. Per-tool controller adoption (13 controllers)

Since registration is already handled by `FileService`, each controller's change is limited to
calling `cleanupSession()` at its existing lifecycle points:

- After successful completion of its operation (after the final output is written to its
  user-chosen, non-temp destination)
- On operation failure/error (temp files are never the output — always safe to delete, same
  reasoning as the existing PDF Split rollback-on-failure pattern)
- On the standardized "reset" action (per `AGENTS.md` §2 Rule #8's completion-view pattern, every
  tool already has a reset/"process another" action button — hook cleanup there too)

Apply this identically across: PDF Merge, PDF Page Manager, PDF Split, PDF Compress, PDF to
Image, PDF Password, PDF Insert Pages, PDF Insert Image as Page, Images to PDF, Image Convert,
Image Resize, Image Compress, Image Blur, Image Crop & Rotate.

Do not restructure any controller's existing public API or re-implement already-shipped business
logic — this is strictly additive.

**Before writing controller changes:** confirm each controller's actual reset/completion method
name (they may not all be literally named `reset()` — check each file). If any controller's
lifecycle doesn't cleanly expose a single place for the success/error/reset hooks, note that as
a `// ASSUMPTION:` comment rather than forcing a uniform shape that doesn't fit.

## Edge cases

| Case | Required behavior |
|---|---|
| App is killed (not gracefully closed) mid-operation | Orphaned temp files remain until next launch's startup sweep — acceptable, that's what the sweep is for |
| Cleanup runs but a file is locked/in-use by the OS | Log and skip that file rather than throwing — cleanup failures must never surface as a user-facing error |
| User picks the same file twice in one session (e.g. re-adds after removing from Merge list) | Don't double-register/double-copy if avoidable, but if `file_picker` forces a fresh copy each time, registering the duplicate is fine — correctness over cleverness |
| A tool's "reset" flow doesn't cleanly map to one method | Note as `// ASSUMPTION:` and hook cleanup at the closest equivalent point rather than forcing a mismatched shape |

## Testing

- Unit test `TempFileManager`: register → `cleanupSession()` deletes registered files; sweep
  deletes unregistered files; cleanup never touches a path outside the temp directory (guard
  test); locked/missing file during cleanup is skipped without throwing; double-registration of
  the same file doesn't error
- Unit test `FileService`: pick methods register returned paths with a mocked `TempFileManager`
  (use `mocktail`, consistent with existing test patterns)
- For each of the 13 tool controllers, extend its existing test file with one regression test
  asserting `cleanupSession()` is called on both the success and failure paths (mock
  `TempFileManager`)
- Manual verification: run each of the 13 tools once on a real Android device/emulator, check
  Settings → Apps → Anvil → Storage before and after, confirm Cache no longer grows unbounded
  across repeated use across all tool families, not just PDF tools

## Out of scope for this task

- A user-facing "Clear Cache" button or Settings screen — future fast-follow if still needed
- Changing where final output files are saved — this task only touches temporary/intermediate
  files, never user-chosen output locations
- Any iOS/macOS/Linux/Web-specific temp directory handling — Android is where this was observed;
  revisit for other platforms if the same pattern shows up there later