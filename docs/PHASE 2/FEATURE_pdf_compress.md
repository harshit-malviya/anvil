# Feature: Compress PDF

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_compress/pdf_compress_screen.dart`,
> `lib/tools/pdf_compress/pdf_compress_controller.dart`, plus registry + route entries.

## User story

"My PDF is way bigger than it needs to be (usually because of embedded images) and I want to
shrink it without wrecking the text quality, before I email it or upload it somewhere with a
size limit."

## Important scope clarification (read before implementing)

Compression here means **re-encoding embedded images at a lower quality/resolution** and
**stripping unnecessary metadata** — it does NOT mean re-rendering text as flattened images (that
would destroy searchability/selectability) and does NOT mean lossy manipulation of vector content.
If the PDF is mostly or entirely text with no images, expect minimal size reduction — that's
correct behavior, not a bug, and must be communicated to the user (see edge cases).

## User flow

1. User taps "Compress PDF" tool card, picks a single PDF file
2. Screen shows the file's current size prominently, plus a **compression level** selector:
   - **Low** (minimal size reduction, highest image quality preserved)
   - **Medium** (balanced — recommended default, pre-selected)
   - **High** (maximum size reduction, visible quality loss on images is expected and acceptable)
3. A short explanatory line under the selector: "Compression reduces embedded image quality. Text
   stays sharp and selectable." — sets expectations up front, don't let users be surprised
4. "Compress" primary button triggers processing
5. Processing state: "Compressing…" with progress bar
6. Success state (stamp) shows **before → after size comparison** prominently (e.g. "4.2 MB → 1.1
   MB, 74% smaller") plus Save As / Open Folder actions — this comparison is the whole point of
   the feature, don't bury it
7. If the compressed result isn't meaningfully smaller (see edge case below), success state
   instead shows a neutral message explaining why

## Functional requirements

- Original file is never modified
- Text and vector content must remain fully intact — no rasterizing text-based pages
- Page count, page order, and page dimensions must be identical between input and output (this is
  purely a size operation, not a content operation — don't let it regress into the same
  page-size bug fixed in Merge; reuse the corrected page-size-handling approach)
- The three compression levels should map to concrete, testable parameters (e.g. image DPI
  downsampling targets and JPEG quality percentages) — document the exact values chosen as a
  `// ASSUMPTION:` comment if the spec doesn't pin them, since "Medium" needs to mean something
  specific and reproducible, not a vague guess

## Edge cases

| Case | Required behavior |
|---|---|
| PDF has no embedded images (text/vector only) | After compression, if size reduction is under ~5%, show: "This PDF is already efficient — there wasn't much to compress." Still offer the (barely smaller, or same-size) output rather than blocking the action entirely |
| Compressed output is *larger* than the original (can happen with certain edge-case PDFs) | Detect this and don't hand the user a worse file — show: "Compression didn't reduce the size for this file. Your original hasn't been changed." and don't produce a misleading "smaller" output |
| Password-protected source | Same rejection pattern as other PDF tools |
| Already-heavily-compressed images inside the PDF (e.g. already low-quality JPEGs) | High setting may produce visible artifacts — this is expected/acceptable per the scope clarification above, not a bug to fix |
| Very large source file (100+ MB) | Show progress feedback proportional to actual work if the underlying library supports progress callbacks; if not, at minimum don't let the UI appear frozen — show an indeterminate progress indicator with the "Compressing…" label |

## Controller responsibilities (`pdf_compress_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfCompressState>>` with:

- `loadDocument(PlatformFile)` — captures original file size
- `setCompressionLevel(CompressionLevel level)` — enum: `low`, `medium`, `high`
- `compress()` — runs compression, compares output size to original, and emits one of: normal
  success (with before/after sizes), "minimal reduction" success variant, or the
  "output was larger, kept original" variant described above

Write unit tests covering: normal compression on an image-heavy fixture PDF at each of the 3
levels (assert output size < input size), a text-only fixture (assert the "already efficient"
path triggers), and a simulated "output larger than input" case (assert original is preserved and
the correct message state is emitted).

## Out of scope for this feature

- Custom/manual DPI or quality sliders — only the 3 preset levels for v1
- Compressing non-PDF files
- OCR or re-flowing scanned-image-only PDFs into searchable text (that's a much bigger, separate
  feature if ever built)
