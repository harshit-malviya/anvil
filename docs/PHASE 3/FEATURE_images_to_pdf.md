# Feature: Images to PDF

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/images_to_pdf/images_to_pdf_screen.dart`,
> `lib/tools/images_to_pdf/images_to_pdf_controller.dart`, plus registry + route entries.

## Refactor note before starting

`PDF Insert Image as Page` (`docs/PHASE 3/FEATURE_pdf_insert_image_as_page_v2.md`) already contains
the core "turn one image into one PDF page" logic: filling a white background rectangle before
compositing (so PNG transparency doesn't render black), and capping/downscaling oversized source
images to a max 3000px dimension before use. This feature needs that exact same per-image
conversion step, just applied to *multiple* images building a brand-new document instead of
inserting into an existing one.

Before writing new conversion code, check whether that logic in
`pdf_insert_image_as_page_controller.dart` is already extracted into a shared, reusable function.
If not, do the minimum extraction needed (e.g. into
`lib/core/services/image_to_pdf_page_service.dart`) so both features call the same code — don't
copy-paste the white-background-fill / downscale logic a second time.

## Why this is a separate tool from Insert Image as Page

Insert Image as Page takes photos *into an existing PDF* at a chosen insertion point. This tool
takes photos *and produces a brand-new PDF* with no source PDF involved at all — e.g. turning a
batch of receipt or whiteboard photos into one shareable document. Different starting point,
different user intent; keeping them separate avoids overloading either screen's UI with a mode
switch, consistent with the single-purpose-tool principle already used across the app.

## User story

"I have a handful of photos — receipts, scanned pages, whatever — and I want them combined into a
single PDF, in an order I choose, without opening any other app."

## User flow

1. User taps the "Images to PDF" tool card on the home screen
2. Screen shows an empty **File Drop Zone**, picker filtered to `.png` / `.jpg` / `.jpeg` only
   (same supported formats as Insert Image as Page — don't introduce a third format list)
3. Added images appear as a **reorderable list** (drag handles), each row showing: thumbnail,
   filename, pixel dimensions, file size (in `mono` style), and a remove (×) button
4. User can keep adding more images at any point before converting
5. "Create PDF" primary button is enabled once **1 or more** images are present — unlike Merge,
   a single image is a legitimate use case here (e.g. "just make this one photo a PDF"), so don't
   require 2+
6. On tap: Processing state ("Creating PDF from 5 images…") with indeterminate progress bar per
   Rule #7 (isolate-based work, no incremental progress possible)
7. On success: stamp success state with output filename, "Save As" / "Open Folder" actions,
   consistent with Merge/Split's completion pattern
8. On failure: Error state with the specific problem (see edge cases below)

## Functional requirements

- Each image becomes exactly one PDF page, **sized to match that image's own dimensions** (after
  any downscale cap is applied) — do not force every page to a uniform standard size like A4.
  This mirrors the per-page-size-integrity principle already established for Merge/Split/Compress
  and avoids reintroducing that class of bug.
- Page order matches the list order the user arranged, top to bottom
- PNG transparency is flattened onto a white background before placing on the page (reuse the
  Insert Image as Page decision — don't render transparent PNGs onto a black or undefined page
  background)
- Source images are never modified or deleted
- Output file default name: `images_to_pdf_[timestamp].pdf`, written to the same directory as the
  first added image, renameable via "Save As"
- All PDF construction runs in a background isolate via `compute()` per standing Rule #7 — this
  is genuinely CPU-heavy work (image decode + page composition per image), never let it run on
  the main thread

## Edge cases — handle explicitly, don't let them silently fail

| Case | Required behavior |
|---|---|
| User adds an unsupported file type (e.g. `.heic`, `.tiff`, `.gif`) | Reject at add-time with a specific message: "Unsupported format — PNG and JPEG images only." Don't add it to the list |
| User adds a corrupted/unreadable image file | Same pattern — reject at add-time with a specific message, not a generic parse error |
| Very large source image (e.g. a 20+ MB photo) | Apply the same 3000px max-dimension downscale used in Insert Image as Page before use — don't bloat the output PDF or risk memory pressure |
| User removes all images after adding some | Return to empty Drop Zone state |
| Single image added | Allowed — "Create PDF" is enabled, produces a valid one-page PDF |
| Mixed portrait/landscape images in one batch | Each page independently matches its own image's orientation — don't force uniform orientation across the document |
| High image count (e.g. 50+ photos) | Use lazy/virtualized rendering for the reorderable list thumbnails (same approach as Page Manager's `GridView.builder`) — don't eagerly render all thumbnails at full res |
| Disk full / write permission denied at save time | Error state: "Couldn't save the file — [specific OS error]. Try a different location." |
| User backs out mid-conversion (navigates away while processing) | Cancel cleanly; no orphaned partial output file left on disk |

## Controller responsibilities (`images_to_pdf_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImagesToPdfState>>` with:

- `addImages(List<PlatformFile>)` — validates format + readability, downscales oversized images
  per the shared cap, appends valid ones to state; invalid files surface a per-file error
- `reorderImages(int oldIndex, int newIndex)`
- `removeImage(String imageId)`
- `createPdf()` — calls `compute()` with a new top-level isolate function (add
  `isolateImagesToPdf` alongside the existing functions in `pdf_isolate_worker.dart`), builds one
  section/page per image at that image's own dimensions, writes output, emits success with output
  path or a typed error

`ImagesToPdfState` should track images as a list of value objects
(`{id, filePath, fileName, fileSizeBytes, pixelWidth, pixelHeight}`) in user-arranged order, so
reordering and removal stay simple list operations.

Write unit tests covering: single-image conversion (happy path), multi-image order preservation,
unsupported-format rejection, corrupted-image rejection, oversized-image downscale, mixed-
orientation page sizing, and empty-list-after-removal returning to the initial state.

## Registry / Tool Search entry

Add to `lib/tools/registry.dart` with keywords at entry time (per standing convention — not
optional polish): `photo to pdf`, `picture to pdf`, `jpg to pdf`, `png to pdf`, `image to pdf`,
`scan`, `convert images`, `combine photos`. These should surface the tool for casual phrasing like
"scan" or "jpg" the same way existing tools map "shrink" → Compress.

## Out of scope for this feature

- Inserting images into an existing PDF — that's Insert Image as Page, don't duplicate it
- Cropping, rotating, or otherwise editing images before conversion — bring them in as-is (aside
  from the transparency flatten and size-cap downscale, which are technical necessities, not
  editing features)
- Forcing a standard page size (A4 / Letter) with margins — a future `// ASSUMPTION`-flagged
  option could add this later if requested, but v1 of this tool is fit-to-image only
- OCR on the resulting PDF
- Any format beyond PNG/JPEG (WebP, HEIC, TIFF, BMP) — matches the existing image-in-PDF format
  scope, revisit only if the Image Format Convert tool ends up supporting broader formats
