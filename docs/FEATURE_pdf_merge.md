# Feature: PDF Merge

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_merge/pdf_merge_screen.dart`,
> `lib/tools/pdf_merge/pdf_merge_controller.dart`, plus a registry entry in
> `lib/tools/registry.dart` and a route in `lib/core/router.dart`.

## User story

"I have 3 separate PDF files and I want to combine them into one, in an order I choose, without
uploading them anywhere."

## User flow

1. User taps the "Merge PDFs" tool card on the home screen
2. Screen shows an empty **File Drop Zone** (see DESIGN_SYSTEM.md §5)
3. User adds 2+ PDF files via drag-drop (Windows) or file picker (both platforms) — picker must
   filter to `.pdf` only
4. Added files appear as a **reorderable list** (drag handles), each row showing: filename, page
   count, file size (in `mono` type style), and a remove (×) button
5. User can keep adding more files to the list at any point before merging
6. "Merge" primary button is disabled until at least 2 files are present
7. On tap: show Processing state ("Merging 3 files…") with progress bar
8. On success: show the stamp success state with output filename, "Save As" and "Open Folder"
   actions
9. On failure: show Error state with the specific problem (see edge cases below)

## Functional requirements

- Merge preserves the **exact page order** implied by the list order the user arranged
- Merge preserves each source PDF's original page size/orientation per page (don't force-resize
  or force-rotate pages to match)
- Output file default name: `merged_[timestamp].pdf` in the same directory as the first source
  file, but the user can rename via "Save As" before final write
- Original source files are never modified or deleted
- No file size limit imposed by the app itself — if the OS/device runs out of memory, that surfaces
  as the "processing failed" error case below, not a pre-emptive artificial cap

## Edge cases — handle explicitly, don't let them silently fail

| Case | Required behavior |
|---|---|
| User selects only 1 file | Merge button stays disabled; helper text: "Add at least 2 PDFs to merge" |
| One of the selected files is password-protected | Error on that specific file at add-time: "This file is password-protected and can't be merged. Remove the password first." — don't add it to the list |
| One of the selected files is corrupted/unreadable | Same pattern — reject at add-time with a specific message, not a generic parse error |
| User removes all files after adding some | Return to empty Drop Zone state |
| Disk is full / write permission denied at save time | Error state: "Couldn't save the file — [specific OS error]. Try a different location." |
| Very large files (memory pressure) | If the underlying merge throws an out-of-memory-class exception, catch it and show: "This merge is too large to process on this device. Try merging fewer files at once." — don't crash the app |
| User backs out mid-merge (navigates away while processing) | Cancel the operation cleanly; no orphaned partial output file left on disk |

## Controller responsibilities (`pdf_merge_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfMergeState>>` (or equivalent) with methods:

- `addFiles(List<PlatformFile>)` — validates each file (readable, not password-protected) before
  adding to state; invalid files surface a per-file error, valid ones get appended to the list
- `reorderFiles(int oldIndex, int newIndex)`
- `removeFile(String fileId)`
- `merge()` — runs the actual Syncfusion merge operation, emits progress if the package supports
  progress callbacks (if not, at minimum emit "started" → "done"/"error" states), writes output,
  emits success with output path or emits a typed error

Write one unit test per row in the edge case table above, using a small set of fixture PDFs
(create a `test/fixtures/` folder with a valid small PDF, a password-protected one, and a
corrupted one — a few KB each is enough).

## Out of scope for this feature (don't build)

- Merging non-PDF files (e.g. auto-converting a Word doc before merge) — PDF-only input
- Splitting or extracting pages as part of this screen — that's the Page Manager feature
- Batch merge presets or saved merge "projects"
