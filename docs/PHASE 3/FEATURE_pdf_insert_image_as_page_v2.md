# Feature: PDF Insert Image(s) as Page(s)

> **Revision note (v1.1):** This feature was originally built as single-image-only. This revision
> upgrades it to accept **N images inserted at one shared insertion point**, per product decision.
> The core nature of the feature is unchanged: it is still a narrow "get image(s) into a document
> as page(s)" tool, not a general image-to-PDF converter, and it does **not** attempt scattered /
> multi-point placement — see "What did NOT change" below.
>
> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `FEATURE_pdf_insert_pages.md` (read all
> three first — this feature reuses Insert Pages' splicing logic rather than duplicating it).
> Files to update: `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_screen.dart`,
> `lib/tools/pdf_insert_image_as_page/pdf_insert_image_as_page_controller.dart` (existing feature
> — this is a modification, not a new tool/registry/route entry).

## Relationship to Insert Pages (unchanged from v1)

This is **not** a general image-to-PDF converter — that's separate, out-of-scope v2 work per
`PROJECT_OVERVIEW.md` §7. This feature solves one narrow case: "I have image(s) — e.g. screenshots
of pages I'm missing — and I want them added into an existing PDF as pages."

Internally, this still reuses `PdfInsertPagesController`'s splicing logic rather than duplicating
it: each image gets converted to a single-page PDF in memory, the resulting pages are concatenated
into one ordered source, and that source is spliced into the target using the exact same insertion
mechanism (Syncfusion sections, zero margins, explicit page size) already built and tested for
Insert Pages. Don't write a second, parallel splicing implementation.

## What changed in this revision

- **v1 (original):** exactly one image → exactly one inserted page.
- **v1.1 (this revision):** **N images → N inserted pages, all landing consecutively at one
  shared insertion point**, in an order the user controls before committing.

## What did NOT change (read this before extending anything further)

- **Still one insertion point per operation.** Images do not get individually placed at different
  spots in the target document. If a user wants images at non-adjacent locations, they insert the
  first batch, then either run this tool again or use **Page Manager** afterward to reorder pages
  within the resulting document. This tool does not attempt to replicate Page Manager's
  reorder/drag capability — that would duplicate an already-built, already-tested feature.
- **Still one shared page-fit resolution per operation**, not resolved per image. "Match
  neighboring page" resolves once, against the single target page immediately before the
  insertion point (or the fallback rule below) — the same neighbor reference is then applied
  when sizing every image's page in the batch. This avoids a cascading-resize ambiguity (image 2
  matching image 1's just-created page, and so on) that per-image resolution would introduce.
- **Still JPEG/PNG only.** Still no cropping/editing before insertion. Still not a batch
  standalone image→PDF converter (no target document = still out of scope, still belongs to the
  future v2 image-tools spec).

## User story

"I have a PDF that's missing a page or two, and I have screenshots or photos of those pages — I
want to drop them into the document at the right spot as proper pages, in the right order, without
running this tool multiple times or hand-assembling the result."

## User flow

1. User taps "Insert Image as Page" tool card
2. **Step 1 — pick the target file**: single PDF file picker/drop zone, labeled "PDF to insert
   into" (unchanged from v1)
3. Screen renders the target's page thumbnail grid (shared `PdfThumbnailService`), in document
   order
4. **Step 2 — pick the image(s)**: picker/drop zone, labeled "Images to insert" — now accepts
   **one or more** image files in a single selection (JPEG or PNG only, same as v1)
5. Once loaded, images render as a **reorderable list** (drag handles — same pattern as Merge's
   file list), each row showing: filename, thumbnail preview, file size (`mono` style), and a
   remove (×) button. List order = insertion order. User can keep adding more images to the list
   before committing.
6. A single **page fit control** applies to the whole batch (unchanged in kind from v1, just
   scoped to the batch rather than one image):
   - **Match neighboring page** (default) — every inserted page adopts the size/orientation of
     the single target page resolved as the neighbor (see resolution rule below); each image is
     scaled to fit within that page (centered, aspect ratio preserved, never stretched)
   - **Fit to image** — each inserted page's dimensions are derived from that image's own aspect
     ratio individually (this one remains genuinely per-image, since there's no shared page size
     to conform to)
7. User chooses the **insertion point** in the target grid — same tap-to-select gap interaction
   as Insert Pages / v1, or "at the start" / "at the end" quick-select. All images in the list
   land consecutively starting at this one point, in list order.
8. Live preview updates the target grid to show a distinct-colored placeholder block — now sized
   to N pages instead of always exactly 1 — at the chosen insertion point
9. "Insert Pages" primary button (label pluralizes automatically: "Insert Page" for 1 image,
   "Insert N Pages" for N > 1) triggers processing
10. On success: stamp state, output filename (default `[target]_inserted.pdf`), Save As / Open
    Folder actions
11. On failure: Error state per `DESIGN_SYSTEM.md` §5 pattern

## Functional requirements

- Original target file and original image files are never modified — output is always a new file
- No inserted page may distort its image (no forced stretch — scale to fit within bounds,
  aspect ratio preserved, centered, blank page background for any margin)
- **Neighbor resolution (batch-level, resolved once):** if inserting at the start, match the
  (current) first target page; if inserting at the end, match the (current) last target page; if
  inserting in the middle, match the target page immediately *before* the insertion point. This
  single resolved page size/orientation is then applied to every image in the batch when
  "Match neighboring page" is selected.
- If the target document has zero pages, "Match neighboring page" has no neighbor to match — fall
  back to "Fit to image" automatically (unchanged from v1, now applies batch-wide)
- Output document's total page count = target page count + number of images in the list
- One bad image in the list must not block the others — see edge cases

## Edge cases

| Case | Required behavior |
|---|---|
| Target file is password-protected | Same rejection pattern as other PDF tools — reject at file-select time |
| Target file is corrupted/unreadable | Same pattern — reject at file-select time |
| One image in the list is corrupted/unreadable | Reject **that image only** at add-time: "This image couldn't be read and wasn't added: [filename]." Valid images in the list are unaffected |
| One image in the list is an unsupported format (e.g. GIF, WebP, BMP) | Same per-image rejection pattern: "Only JPEG and PNG images are supported: [filename] wasn't added." |
| User removes all images from the list after adding some | Return to empty image-picker state; "Insert Pages" button disabled |
| User doesn't choose an insertion point | Button disabled until a point is chosen — no silent default |
| An image has transparency (PNG) and "Match neighboring page" is selected | Transparent areas render as white/blank page background, not black or undefined — flatten explicitly |
| Very large image file (e.g. 50+ MB photo) in the list | Downscale internally to a sane maximum resolution before embedding, same cap logic as v1, applied per image — document the chosen cap as an `// ASSUMPTION:` comment if not already present from v1 |
| Target PDF has only 1 page | Neighboring-page match uses that single existing page as the reference for the whole batch — no special case beyond the zero-page fallback |
| User wants images placed at multiple non-adjacent points in the document | Explicitly out of scope for this operation — insert this batch, then either run the tool again for the next batch, or use **Page Manager** to reorder pages within the result. Don't build multi-point placement into this tool. |

## Controller responsibilities (`pdf_insert_image_as_page_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfInsertImageAsPageState>>` with:

- `loadTargetDocument(PlatformFile)` — validates + generates target thumbnail data (unchanged)
- `addImages(List<PlatformFile>)` — **replaces v1's `loadImage`**; validates each image
  independently (format + readability); valid images are appended to an ordered list, invalid
  ones surface a per-file error without blocking the rest (mirrors `PdfMergeController.addFiles`)
- `removeImage(String imageId)` — new
- `reorderImages(int oldIndex, int newIndex)` — new
- `setPageFitMode(PageFitMode mode)` — enum: `matchNeighboringPage`, `fitToImage` (unchanged in
  kind; now resolved once against the batch rather than a single image)
- `setInsertionPoint(int afterTargetPageIndex)` — same semantics as v1 / Insert Pages (`-1` = at
  start)
- `insertImagePages()` — **renamed from v1's `insertImagePage()`**; converts each image in list
  order to a single-page PDF at the resolved page size (per fit mode and the batch-level neighbor
  resolution rule), concatenates them into one ordered source, then calls the shared insertion
  logic from Insert Pages **once** to splice the whole ordered source into the target at the
  chosen point; writes output, emits success/error

`PdfInsertImageAsPageState` should track images as an ordered list of value objects (mirroring
`PdfMergeState`'s file list shape), plus the single shared fit mode and single shared insertion
point — there is intentionally no per-image insertion point or per-image fit mode in this state
shape, since that would represent scope this tool doesn't support (see "What did NOT change").

Write unit tests covering (in addition to the original v1 test list, updated for batches):
insert-one-image-at-start (regression check that v1's core path still works), insert-N-images-at-
start with match-neighboring-page (assert all N pages share the resolved neighbor's size),
insert-N-images-at-end with fit-to-image (assert each page uses its own image's aspect ratio),
insert-in-middle with N images (assert the correct *preceding* page is used as the shared neighbor
reference), reorder-before-insert (assert output page order follows list order, not add order),
one-bad-image-among-several (assert the good ones still insert, the bad one is reported and
excluded), unsupported-format rejection, corrupted-image rejection, and the zero-existing-pages
fallback-to-fit-to-image path.

## Out of scope for this feature (unchanged, restated)

- Inserting images at multiple different points in the target document in one operation — one
  shared insertion point per operation; use Page Manager afterward, or run the tool again, for
  non-adjacent placement
- General-purpose image-to-PDF conversion (batch images → standalone PDF with no target document)
  — belongs to the future v2 image-tools spec, not here
- Image editing/cropping/rotation before insertion — this tool only places images as-is, aside
  from the fit-to-page scaling already described
- Per-image fit mode selection — fit mode is a single batch-level setting, not configurable per
  image
