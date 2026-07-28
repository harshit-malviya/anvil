# Feature: PDF Insert Image as Page

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `FEATURE_pdf_insert_pages.md` (read all
> three first — this feature reuses Insert Pages' splicing logic rather than duplicating it).
> Files to create: `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_screen.dart`,
> `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_controller.dart`, plus registry +
> route entries.

## Relationship to Insert Pages (read this first)

This is **not** a general image-to-PDF converter — that's separate, out-of-scope v2 work per
`PROJECT_OVERVIEW.md` §7 ("Image tools... v2, separate spec doc will follow"). This feature solves
one narrow case: "I have one image (e.g. a screenshot of a page I'm missing) and I want it added
into an existing PDF as a page."

Internally, this reuses `PdfInsertPagesController`'s splicing logic rather than duplicating it:
the image gets converted to a single-page PDF in memory, then spliced into the target using the
exact same insertion mechanism (Syncfusion sections, zero margins, explicit page size) already
built and tested for Insert Pages. Don't write a second, parallel splicing implementation — extend
or call into the existing one. If the existing controller isn't structured to make this a clean
call-through, do the minimum refactor needed (e.g. extract a shared
`insertPageIntoDocument(targetBytes, pageBytes, insertionPoint)` method) rather than copy-pasting.

## User story

"I have a PDF that's missing a page, and I have a screenshot or photo of that page — I want to
drop it into the document at the right spot as a proper page, not just attach it separately."

## User flow

1. User taps "Insert Image as Page" tool card
2. **Step 1 — pick the target file**: single PDF file picker/drop zone, labeled "PDF to insert
   into" (same target-loading pattern as Insert Pages)
3. Screen renders the target's page thumbnail grid (shared `PdfThumbnailService`), in document
   order
4. **Step 2 — pick the image**: a single-image picker/drop zone, labeled "Image to insert" —
   accepts one image file (JPEG or PNG only for v1)
5. Once loaded, the image renders as a single preview thumbnail (not a strip/grid, since it's
   always exactly one page) with a **page fit control**:
   - **Match neighboring page** (default) — the new page adopts the page size/orientation of
     whichever target page it's being inserted next to, and the image is scaled to fit within
     that page (centered, preserving the image's own aspect ratio — never stretched/distorted)
   - **Fit to image** — the new page's dimensions are derived directly from the image's own
     aspect ratio instead, useful when the image doesn't match the surrounding pages' proportions
6. User chooses the **insertion point** in the target grid — same tap-to-select gap interaction as
   Insert Pages, or "at the start" / "at the end" quick-select
7. Live preview updates the target grid to show a single distinct-colored placeholder at the
   chosen insertion point (same visual pattern as Insert Pages, just always exactly one page)
8. "Insert Page" primary button triggers processing
9. On success: stamp state, output filename (default `[target]_inserted.pdf`), Save As / Open
   Folder actions
10. On failure: Error state per `DESIGN_SYSTEM.md` §5 pattern

## Functional requirements

- Original target file and original image file are never modified — output is always a new file
- The inserted page must not distort the image (no forced stretch to fill the page — scale to fit
  within bounds, preserving aspect ratio, centered on the page with any resulting margin left as
  blank page background)
- "Match neighboring page" must correctly resolve which neighbor to match: if inserting at the
  start, match the (current) first page; if inserting at the end, match the (current) last page;
  if inserting in the middle, match the page immediately *before* the insertion point
- If the target document has zero pages (shouldn't normally happen, but see edge cases), "Match
  neighboring page" has no neighbor to match — fall back to "Fit to image" automatically in that
  case
- Output document's total page count = target page count + 1

## Edge cases

| Case | Required behavior |
|---|---|
| Target file is password-protected | Same rejection pattern as other PDF tools — reject at file-select time with a specific message |
| Target file is corrupted/unreadable | Same pattern — reject at file-select time |
| Image file is corrupted/unreadable | Reject at file-select time: "This image couldn't be read. Try a different file." |
| Unsupported image format (e.g. GIF, WebP, BMP) | Reject at file-select time: "Only JPEG and PNG images are supported." |
| User doesn't choose an insertion point | Button disabled until a point is chosen — same behavior as Insert Pages, no silent default |
| Image has transparency (PNG) and "Match neighboring page" is selected | Transparent areas render as white/blank page background, not black or undefined — flatten explicitly rather than leaving it to renderer-default behavior |
| Very large image file (e.g. 50+ MB photo) | Downscale internally to a sane maximum resolution before embedding (e.g. cap at the target DPI equivalent of the page size) so the output PDF isn't absurdly bloated by an oversized source image — document the chosen cap as an `// ASSUMPTION:` comment |
| Target PDF has only 1 page and user inserts "at the start" | Neighboring-page match uses that single existing page as the reference — no special-case needed beyond the zero-page fallback above |

## Controller responsibilities (`pdf_insert_image_as_page_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfInsertImageAsPageState>>` with:

- `loadTargetDocument(PlatformFile)` — validates + generates target thumbnail data (mirrors
  `PdfInsertPagesController.loadTargetDocument`)
- `loadImage(PlatformFile)` — validates format/readability, generates a preview thumbnail
- `setPageFitMode(PageFitMode mode)` — enum: `matchNeighboringPage`, `fitToImage`
- `setInsertionPoint(int afterTargetPageIndex)` — same semantics as Insert Pages (`-1` = at start)
- `insertImagePage()` — converts the image to a single-page PDF at the resolved page size (per
  the fit mode and neighbor-resolution rule above), then calls the shared insertion logic from
  Insert Pages to splice it into the target at the chosen point; writes output, emits
  success/error

Write unit tests covering: insert-at-start with match-neighboring-page, insert-at-end with
fit-to-image, insert-in-middle (asserting the correct *preceding* page is used as the neighbor
reference), unsupported-format rejection, corrupted-image rejection, and the zero-existing-pages
fallback-to-fit-to-image path.

## Out of scope for this feature

- Inserting multiple images as multiple pages in one operation — one image, one page, per
  operation for v1; run the tool again for additional pages
- General-purpose image-to-PDF conversion (batch images → standalone PDF with no target document)
  — that belongs to the future v2 image-tools spec, not here
- Image editing/cropping/rotation before insertion — if the image needs adjustment, the user
  handles that before bringing it into Anvil; this tool only places it as-is (aside from the
  fit-to-page scaling described above)
