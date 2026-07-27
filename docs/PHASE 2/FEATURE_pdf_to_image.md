# Feature: PDF to Image

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_to_image/pdf_to_image_screen.dart`,
> `lib/tools/pdf_to_image/pdf_to_image_controller.dart`, plus registry + route entries.

## Refactor note before starting

Reuse the shared `pdf_thumbnail_service.dart` (extracted per `FEATURE_pdf_split.md`) for page
preview rendering here too, rather than writing a third copy of page-rasterization logic. The
actual export step needs full-resolution rendering (not thumbnail-resolution), so the service may
need a `renderPage(pageIndex, targetDpi)` method that both thumbnail preview and final export call
with different DPI arguments — check if this refactor is already done before duplicating anything.

## User story

"I need specific pages of a PDF as actual image files — for pasting into a slide deck, a chat, a
doc, wherever a PDF isn't accepted but an image is."

## User flow

1. User taps "PDF to Image" tool card, picks a single PDF file
2. Screen renders the page thumbnail grid (shared component), each thumbnail with a checkbox —
   **all pages selected by default**
3. User can deselect specific pages, or use "Select All" / "Select None" quick actions
4. Export settings panel:
   - **Format**: PNG (default, lossless) or JPEG (smaller files, lossy)
   - **Resolution**: Low (72 DPI, screen use) / Medium (150 DPI, default) / High (300 DPI, print
     quality) — show the approximate output pixel dimensions next to each option (e.g. "150 DPI —
     approx. 1275×1650px") so the choice is concrete, not abstract
5. Live summary: "Export 8 pages as PNG at 150 DPI"
6. "Export" primary button triggers processing
7. **If exporting 1 page**: output is a single image file, Save As lets user pick exact filename
   /location
8. **If exporting 2+ pages**: output is multiple image files into a new folder named after the
   source PDF (e.g. `report_images/`), named `report_page1.png`, `report_page2.png`, etc. —
   consistent with the multi-file pattern used in PDF Split
9. Success state (stamp): "8 images exported to `report_images/`" with Open Folder action

## Functional requirements

- Original file is never modified
- Output image dimensions must be proportional to the source page's actual dimensions at the
  chosen DPI — respect each page's real aspect ratio, don't force a fixed square/standard size
  (same class of care as the page-size bug already fixed in Merge — this feature is at real risk
  of repeating it since it's a new rendering path)
- Page order in filenames must match source document order regardless of selection order

## Edge cases

| Case | Required behavior |
|---|---|
| User deselects all pages | Export button disabled: "Select at least one page to export" |
| Password-protected source | Same rejection pattern as other PDF tools |
| One specific page fails to render (corrupted page data) | Skip that page, continue exporting the rest, and report it clearly in the success state: "7 of 8 pages exported. Page 4 couldn't be rendered and was skipped." — don't fail the whole batch for one bad page (same principle as the Page Manager thumbnail-failure case) |
| High DPI export on a large page count (e.g. 300 DPI × 100 pages) | This can be slow and memory-heavy — show real progress ("Exporting page 42 of 100…") rather than an indeterminate spinner, so the user knows it's working, not frozen |
| Output folder name collision (e.g. `report_images/` already exists from a previous export) | Append a number: `report_images_2/` — never silently overwrite a previous export's contents |
| JPEG format selected on a page with transparency or fine text | Expected quality tradeoff of JPEG — not a bug, but the format selector's helper text should mention "JPEG doesn't support transparency and may soften fine text" so the user chooses knowingly |

## Controller responsibilities (`pdf_to_image_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfToImageState>>` with:

- `loadDocument(PlatformFile)`
- `togglePageSelected(int pageIndex)` / `selectAll()` / `selectNone()`
- `setFormat(ImageFormat format)` — enum: `png`, `jpeg`
- `setResolution(ExportResolution res)` — enum: `low`, `medium`, `high` (mapped to concrete DPI
  constants — define these explicitly, e.g. 72/150/300, as named constants, not magic numbers
  scattered in code)
- `export()` — renders each selected page at the chosen DPI/format, writes files (single-file or
  folder pattern per flow above), tracks and reports any per-page failures, handles folder name
  collision

Write unit tests covering: single-page export path, multi-page export path, all-pages-deselected
guard, one-page-fails-mid-batch (assert the rest still complete and the failure is reported), and
folder name collision handling.

## Out of scope for this feature

- TIFF, BMP, WebP, or other export formats — PNG/JPEG only for v1
- Combining exported images back into a single "contact sheet" image
- OCR on the resulting images
