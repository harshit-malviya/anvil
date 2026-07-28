# Feature: PDF Insert Pages (from another PDF)

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_insert_pages/pdf_insert_pages_screen.dart`,
> `lib/tools/pdf_insert_pages/pdf_insert_pages_controller.dart`, plus registry + route entries.

## Relationship to other tools (read this first)

This tool is distinct from both Merge and Page Manager, even though it borrows from both:

- **Not Merge**: Merge only ever appends whole files end-to-end in a list the user orders. This
  tool inserts pages from a *source* PDF at a specific point inside a *target* PDF — the target
  document's existing page order is the anchor, not a reorderable list of whole files.
- **Not Page Manager**: Page Manager only removes, rotates, and reorders pages that already exist
  in the loaded document. It never grows the page count — inserting new pages is explicitly listed
  as out of scope there. This tool is the "grows the page count" counterpart.
- **Shares infrastructure with both**: reuse `PdfThumbnailService`
  (`lib/core/services/pdf_thumbnail_service.dart`) for rendering thumbnails of both the target and
  source documents, and reuse the page-size/orientation-preservation approach already fixed in
  Merge (`destinationDoc.sections.add()` per page, explicit `pageSettings.size`, zero margins) —
  don't regress that bug a third time.

This is step one of two: a follow-up feature (`FEATURE_pdf_insert_image_as_page.md`, spec to
follow separately) will let the user insert a single image as a page, for cases like "I have a
screenshot of a missing page, not another PDF." Keep `PdfInsertPagesController`'s internal
page-splicing logic reusable so that follow-up can call into it rather than duplicating it —
the image case is really just "convert 1 image to a 1-page PDF, then run the same insertion
logic."

## User story

"I have a target PDF that's missing a page (or needs an extra page added), and I have another PDF
containing that page — I want to insert it at the right spot without rebuilding the whole
document by hand."

## User flow

1. User taps "Insert Pages" tool card
2. **Step 1 — pick the target file**: single PDF file picker/drop zone, labeled "PDF to insert
   into"
3. Screen renders the target's page thumbnail grid (shared `PdfThumbnailService`), in document
   order, each labeled with its page number in `mono` style
4. **Step 2 — pick the source file**: a second, smaller drop zone/picker below or beside the grid,
   labeled "PDF to insert pages from"
5. Once a source file is loaded, its pages render as a **separate thumbnail strip** (visually
   distinct from the target grid — different border treatment, not just placed inline) with
   checkboxes so the user can select which of the source's pages to insert (default: all selected)
6. User chooses the **insertion point** in the target grid — a tap-to-select gap between two
   target thumbnails (same interaction pattern as Split's custom-range divider markers), or "at
   the start" / "at the end" quick-select buttons
7. A live preview updates the target grid to show where the incoming pages will land — e.g. the
   selected source pages appear as a distinct-colored placeholder block inserted into the grid at
   the chosen point, so the user can confirm the result before committing
8. "Insert Pages" primary button triggers processing
9. On success: stamp state, output filename (default `[target]_inserted.pdf`), Save As / Open
   Folder actions — consistent with other tools
10. On failure: Error state per `DESIGN_SYSTEM.md` §5 pattern

## Functional requirements

- Neither the target nor the source original file is ever modified — output is always a new file
- Each inserted page preserves its own original size/orientation exactly (reuse Merge's fixed
  page-size logic) — the target document's existing pages must also remain visually unchanged
- Source page selection order is preserved on insert (if the user picks source pages 5, 2, 3 in
  that order via distinct taps, they're inserted in that order) — but default behavior when
  "select all" is used is straight document order, not selection-click order
- User can insert from the same source file at multiple different points in a single session
  before committing, OR the v1 scope can be a single insertion point per session — **decide and
  document as an `// ASSUMPTION:` comment if the UI ends up single-point-only for v1**, since the
  user flow above describes one insertion point but multiple insertions is a natural extension
- Output document's total page count = target page count + selected source page count

## Edge cases

| Case | Required behavior |
|---|---|
| Target or source file is password-protected | Same rejection pattern as other PDF tools — reject at file-select time with a specific message, applies to either file independently |
| Target or source file is corrupted/unreadable | Same pattern — reject at file-select time with a specific message |
| User selects zero pages from the source | "Insert Pages" button disabled: "Select at least one page to insert" |
| User doesn't choose an insertion point | Button disabled until a point is chosen (or defaults to "at the end" if that's the simpler v1 choice — pick one and note it as an `// ASSUMPTION:`) |
| Source and target are the same file | Allow it (e.g. duplicating a page within the same document is a legitimate use case) — don't special-case reject this |
| Very high combined page count (target + source both 100+) | Use the same lazy/virtualized rendering approach as Page Manager (`GridView.builder`) for both grids — do not render all thumbnails eagerly |
| Source PDF page fails to render as a thumbnail (corrupted page data) | Same pattern as Page Manager: show a broken-page placeholder with "Preview unavailable," but still allow it to be selected/inserted — don't fail the whole screen for one bad page |
| User removes the source file after selecting pages/an insertion point | Clear the source selection and insertion-point preview; return target grid to its unmodified state |

## Controller responsibilities (`pdf_insert_pages_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfInsertPagesState>>` with:

- `loadTargetDocument(PlatformFile)` — validates + generates target thumbnail data
- `loadSourceDocument(PlatformFile)` — validates + generates source thumbnail data, independent
  of target validation
- `togglePageSelected(int sourcePageIndex)` / `selectAllSource()` / `selectNoneSource()`
- `setInsertionPoint(int afterTargetPageIndex)` — `-1` (or equivalent) represents "at the start"
- `insertPages()` — builds the new PDF by splicing selected source pages into the target at the
  chosen point, preserving per-page size/orientation for every page (both original target pages
  and inserted pages), writes output, emits success/error

`PdfInsertPagesState` should track the target as an ordered list of page references and the
insertion as a distinct, clearly-marked segment within that list (not by physically re-indexing
target pages until commit), so the live preview step can render "what the result will look like"
without mutating any loaded document state prematurely.

Write unit tests covering: insert-at-start, insert-at-end, insert-in-middle, insert-with-partial-
source-selection (not all source pages picked), same-file-as-source-and-target, and the
zero-source-pages-selected guard.

## Out of scope for this feature

- Inserting a single image as a page — that's `FEATURE_pdf_insert_image_as_page.md` (follow-up
  spec), which will reuse this controller's splicing logic against a 1-page PDF built from the
  image rather than duplicating it
- Inserting pages from more than one source file in a single operation — one source file per
  session for v1; queue multiple insert operations sequentially if more sources are needed
- Extracting/duplicating pages within the target without an external source (that's closer to
  Page Manager territory, not this tool)
