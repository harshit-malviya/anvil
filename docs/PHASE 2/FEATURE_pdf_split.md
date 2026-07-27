# Feature: PDF Split

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_split/pdf_split_screen.dart`,
> `lib/tools/pdf_split/pdf_split_controller.dart`, plus registry + route entries.

## Refactor note before starting

Page Manager already generates per-page thumbnails from a PDF (`pdf_page_manager_controller.dart`
/ its thumbnail rendering logic). Extract that into a shared service —
`lib/core/services/pdf_thumbnail_service.dart` — that both Page Manager and this feature call,
instead of duplicating thumbnail generation here. If Page Manager isn't structured to make this
a clean extraction, do the minimum refactor needed rather than copy-pasting the logic.

## User story

"I have one large PDF and I want to break it into smaller PDFs — either one file per page, or
specific page ranges as separate documents."

## User flow

1. User taps "Split PDF" tool card, picks a single PDF file
2. Screen renders the page thumbnail grid (shared component/service per refactor note above)
3. User picks a **split mode** via a segmented control at the top:
   - **Every page → separate file** (no further input needed)
   - **Custom ranges** — user taps between thumbnails to insert a split marker (visual divider
     line), producing N groups of consecutive pages; or types ranges directly (e.g. "1-3, 4-10, 11-15")
   - **Split into N equal parts** — user enters a number, app calculates page ranges automatically
4. A live summary updates as the user configures: "Will produce 4 files: pages 1-3, 4-10, 11-15,
   16-20"
5. "Split" primary button triggers processing
6. Output: multiple PDF files, all written into a single new folder named after the source file
   (e.g. `report_split/`), named `report_part1.pdf`, `report_part2.pdf`, etc., in-order
7. Success state (stamp) shows: "12 files created in `report_split/`" with an "Open Folder" action
   — no per-file confirmation needed, this is a batch result

## Functional requirements

- Original file is never modified
- Each output file preserves exact page size/orientation per page (same requirement as Merge —
  don't regress the bug that was already fixed there; reuse the same page-size-matching logic
  where possible)
- Output files must be in strict page order matching the source
- If disk space or write permissions fail partway through producing multiple files, do not leave
  a partial/corrupt set silently — see edge cases

## Edge cases

| Case | Required behavior |
|---|---|
| Source PDF has only 1 page | "Every page → separate file" and "Custom ranges" are effectively no-ops; show a message: "This PDF only has one page — nothing to split." Don't let the user proceed into a meaningless operation |
| User enters a range that doesn't cover all pages (e.g. "1-3, 4-8" on a 10-page doc, missing 9-10) | Warn before processing: "Pages 9-10 aren't included in any range — they'll be left out. Continue?" Require explicit confirmation, don't silently drop pages |
| User enters overlapping ranges (e.g. "1-5, 4-8") | Reject with inline validation error before allowing split: "Ranges can't overlap (pages 4-5 appear twice)." |
| "Split into N equal parts" where N > page count | Reject: "This PDF only has X pages — can't split into more than X parts." |
| Password-protected source | Same rejection pattern as other PDF tools — reject at file-select time with a specific message |
| Write fails partway through (e.g. disk fills up on file 6 of 10) | Delete any partially-written output files from this run and show: "Split failed partway through and was rolled back — no partial files were kept. [specific error]" Never leave the user with an incomplete, confusing set of output files |
| Very high split count (e.g. splitting a 500-page PDF into 500 files) | Show a confirmation with the file count before proceeding: "This will create 500 separate files. Continue?" — protects against accidental huge batch operations |

## Controller responsibilities (`pdf_split_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfSplitState>>` with:

- `loadDocument(PlatformFile)`
- `setSplitMode(SplitMode mode)` — enum: `everyPage`, `customRanges`, `equalParts`
- `addRangeMarker(int afterPageIndex)` / `removeRangeMarker(int afterPageIndex)` — for the visual
  divider interaction
- `setRangesFromText(String input)` — parses typed range input, returns validation errors inline
- `setEqualPartsCount(int n)`
- `split()` — validates full coverage/no-overlap, then writes all output files; on any failure,
  rolls back (deletes) files written so far in that run before surfacing the error

Write unit tests covering: every-page mode on a small fixture, custom ranges with full coverage,
custom ranges with a gap (confirmation-required path), overlapping range rejection, N > page
count rejection, and the rollback-on-partial-failure path (can simulate by injecting a write
failure on file N in a test double).

## Out of scope for this feature

- Merging split output back together (that's the existing Merge tool — don't build a "quick
  re-merge" shortcut here)
- Zipping the output folder automatically — leave files in a plain folder for v1; zip export can
  be a fast-follow if requested later
- Splitting by file size (e.g. "each part under 5MB") — only page-count-based splitting for v1
