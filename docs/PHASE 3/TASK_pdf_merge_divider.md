# Add Optional Divider Pages to PDF Merge

## Context

PDF Merge (`FEATURE_pdf_merge.md`) already ships. This is a follow-up enhancement, not a rebuild
— it adds one new opt-in option to the existing flow: a slim divider page inserted between source
files, labeled with the upcoming file's name, so users can tell at a glance where one source file
ends and the next begins in the merged output.

This must be built **on top of** the isolate architecture from the UI-freezing fix
(`AGENTS.md` standing rule #7) — divider generation happens inside `isolateMergePdfs`, not in the
controller, since that's the only place Syncfusion work is allowed to run.

## What's changing

- New checkbox on the existing Merge screen: "Insert a divider page between files" (default off)
- When checked, the merge output gets N-1 generated divider pages inserted (for N source files),
  each showing the next file's name
- No other existing merge behavior changes — this is additive only

## Divider page spec

- **Width**: matches the width of the page immediately following it (first page of the next
  source file) — not a fixed size, since source files can vary
- **Height**: fixed **1 inch (72pt)**, regardless of surrounding page sizes
- **Content**: next file's name (no extension), centered, in `mono` style (IBM Plex Mono) per
  `DESIGN_SYSTEM.md` §3
- **Fill/text**: white background, `ink` (`#1E2226`) text — this is baked into the actual output
  PDF (may be opened outside the app), so app theme tokens/dark mode don't apply here
- **Long filenames**: truncate with ellipsis at ~90% of divider width; don't shrink font size
- **Placement**: before each file's first page, for files 2 through N — never before file 1

// ASSUMPTION: divider height (72pt) and content (filename only, not "file N of M" or a page-count
subtitle) aren't pinned by the original request — chosen for minimal footprint. Flag for review
if a page-count subtitle is wanted too.

## Proposed changes

### Isolate worker

#### [MODIFY] [pdf_isolate_worker.dart](file:///g:/Code/anvil/lib/core/services/pdf_isolate_worker.dart)
- `isolateMergePdfs`'s params object gets two new fields:
  - `List<String> fileNames` — display name (no extension) per source file, same order as the
    byte arrays, used only for divider text
  - `bool insertDividers` — when true, build and insert a divider page before each source file's
    first page (files 2..N) while assembling the output document
- Divider construction (blank page, font load, centered/truncated text draw via Syncfusion's PDF
  text APIs) happens entirely inside this isolate function — pure PDF byte manipulation, no
  platform-channel or UI dependency, safe to run off the main isolate
- **Verify before implementing further**: whether `google_fonts`' runtime resolution for IBM Plex
  Mono works inside a background isolate. If it depends on Flutter binding state unavailable in
  isolates, load the font file directly from bundled assets instead. Flag back either way.

### Controller

#### [MODIFY] [pdf_merge_controller.dart](file:///g:/Code/anvil/lib/tools/pdf_merge/pdf_merge_controller.dart)
- Add `setInsertDividers(bool value)` to toggle the new checkbox state in `PdfMergeState`
- `merge()`: extract `fileNames` alongside existing byte extraction, pass both new fields through
  to `compute(isolateMergePdfs, params)` — no other change to the method's control flow

### Screen

#### [MODIFY] [pdf_merge_screen.dart](file:///g:/Code/anvil/lib/tools/pdf_merge/pdf_merge_screen.dart)
- Add the divider checkbox below the reorderable file list, unchecked by default
- No change to the processing/success/error states

## Edge cases to add to test coverage

| Case | Required behavior |
|---|---|
| Divider enabled, 2 files | Exactly 1 divider inserted, before file 2 |
| Divider enabled, filename has unrenderable glyphs | Falls back to default font behavior already handled by `google_fonts`; doesn't crash or skip the divider |
| Divider enabled, next file's first page is a different orientation/size than prior pages | Divider width matches the very next page exactly, even if that makes consecutive dividers inconsistent widths with each other |
| User toggles the checkbox after reordering files | No special handling needed — dividers are computed at merge time from current file order, not baked into list state early |
| Divider disabled (default) | Output identical to current shipped behavior — regression check |

Add these as new test cases in the existing
`test/tools/pdf_merge/pdf_merge_controller_test.dart` suite; no new test file needed.

## Out of scope for this task

- Per-divider customization (font, color, height) — one fixed style for all dividers
- A page-count subtitle on the divider (see ASSUMPTION above) — filename only for now
- Applying dividers retroactively to already-merged files — this only affects new merges

## Verification plan

- Merge 3+ files with divider enabled — confirm N-1 dividers appear in correct positions with
  correct filenames, correct width-matching, and correct truncation on a long filename
- Merge with divider disabled — confirm byte-for-byte same behavior as before this change
- `flutter analyze` passes with no new errors
- Existing merge test suite still passes unmodified, plus new divider test cases pass
