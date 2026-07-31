# Feature: Image Compress

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `AGENTS.md` (read all first).
> Files to create: `lib/tools/image_compress/image_compress_screen.dart`,
> `lib/tools/image_compress/image_compress_controller.dart`, plus registry + route entries.
> This is the third and final v2 image tool (after Image Format Convert and Image Resize).

## Scope boundary — read this first

This feature changes an image's **file size only**, via quality re-encoding, not its pixel
dimensions and not its format. Same separation-of-concerns logic already applied between Resize
and Format Convert:

- Pixel dimensions → Image Resize's job, not this one
- Format (e.g. PNG → JPEG) → Image Format Convert's job, not this one
- This tool → re-encode the image at a lower quality/more efficient encoding, same dimensions,
  same format, same file extension in, file extension out

This mirrors `FEATURE_pdf_compress.md`'s scope clarification almost exactly, just one level down
(compressing the image itself rather than images embedded inside a PDF).

## User story

"My photo or screenshot is way bigger than it needs to be and I want to shrink the file size
before I email it, upload it somewhere with a size limit, or just save disk space — without
changing what it looks like at a glance."

## User flow

1. User taps "Compress Image" tool card, picks a single image file (same supported-format list as
   Resize / Format Convert)
2. Screen shows the file's current size prominently, plus a **compression level** selector:
   - **Low** (minimal size reduction, highest visual quality preserved)
   - **Medium** (balanced — recommended default, pre-selected)
   - **High** (maximum size reduction, visible quality loss is expected and acceptable)
3. A short explanatory line under the selector: "Compression reduces image quality to save space.
   Dimensions and format stay the same." — sets expectations up front, same pattern as PDF
   Compress
4. "Compress" primary button triggers processing
5. Processing state: "Compressing…" with progress bar (or indeterminate spinner if the operation
   is fast enough that a determinate bar would just flash)
6. Success state (stamp) shows **before → after size comparison** prominently (e.g. "8.4 MB → 2.1
   MB, 75% smaller") plus Save As / Open Folder / Share actions — this comparison is the whole
   point of the feature, same as PDF Compress, don't bury it
7. If the compressed result isn't meaningfully smaller (see edge cases), success state instead
   shows a neutral message explaining why, rather than a misleading "smaller" claim

## Functional requirements

- Original file is never modified; output is always a new file, `[name]_compressed.[ext]` in the
  same directory as the source, same extension as the source (this tool never changes format)
- Pixel dimensions must be identical between input and output — this is purely a quality/encoding
  operation, not a resize (don't regress into re-implementing Resize's job here)
- Compression strategy differs by source format, since "compress" doesn't mean the same thing for
  a lossy vs. lossless format — handle each explicitly rather than applying one generic operation:
  - **JPEG**: re-encode at a lower JPEG quality percentage
  - **PNG**: PNG is lossless, so there's no quality knob in the JPEG sense — apply the `image`
    package's strongest available lossless PNG compression level (zlib level / filter strategy)
    and strip non-essential metadata (EXIF, color profiles beyond what's needed for correct
    display). Expect small gains here, not dramatic ones — that's correct behavior, not a bug,
    and must be communicated (see edge cases, matches PDF Compress's "already efficient" pattern
    for text-only PDFs)
  - **WebP** (if supported per Format Convert's WebP assumption — check that resolution before
    building this path): WebP supports a quality parameter similarly to JPEG; re-encode at lower
    quality if the underlying `image` package's WebP encoder support allows it. If Format Convert
    concluded the `image` package can't encode WebP and dropped it from its target list, drop
    WebP from this tool's input scope too for consistency — `// ASSUMPTION:` whichever way that
    resolved, since it directly gates this tool's format list
- The three compression levels should map to concrete, testable parameters per format (e.g. JPEG
  quality: Low=85, Medium=65, High=40 — pin exact numbers as a `// ASSUMPTION:` comment if not
  otherwise decided, since "Medium" needs to mean something specific and reproducible, same
  requirement PDF Compress already established)
- Metadata stripped (EXIF GPS/camera data, etc.) should be mentioned in the pre-compress
  explanatory line if it happens by default, since some users care about preserving EXIF (e.g.
  photographers) — simplest safe default: strip at Medium/High, preserve at Low,
  `// ASSUMPTION:` this specific mapping since the spec doesn't pin it and it's a legitimate user
  concern worth a deliberate (not silent) choice

## Edge cases

| Case | Required behavior |
|---|---|
| PNG source with little redundancy (already well-optimized) | If size reduction is under ~5%, show: "This image is already efficient — there wasn't much to compress." Still offer the (barely smaller, or same-size) output rather than blocking the action entirely — same pattern as PDF Compress's text-only case |
| Compressed output is *larger* than the original (can happen with some PNGs at certain filter settings) | Detect this and don't hand the user a worse file — show: "Compression didn't reduce the size for this file. Your original hasn't been changed." and don't produce a misleading "smaller" output — same guard as PDF Compress |
| Corrupted or unreadable image file selected | Reject at file-select time with a specific message, same pattern as other tools |
| Unsupported image format selected | Reject at file-select time: "This file type isn't supported. Supported formats: [list]." |
| Already-heavily-compressed JPEG (e.g. re-compressing a already-low-quality JPEG) | High setting may produce visible additional artifacts — expected/acceptable, not a bug to fix, same as PDF Compress's equivalent case |
| Very large source image (e.g. 50+ MP photo) | Show progress feedback if the operation is slow enough to need it; at minimum don't let the UI appear frozen — run off the UI thread (see Controller Responsibilities) |

## Controller responsibilities (`image_compress_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImageCompressState>>` with:

- `loadImage(PlatformFile)` — validates format/readability, captures original file size and
  detected format (JPEG/PNG/WebP)
- `setCompressionLevel(CompressionLevel level)` — enum: `low`, `medium`, `high`
- `compress()` — runs the format-appropriate compression strategy **off the UI thread**
  (isolate / `compute()`, same standing pattern as PDF processing and Resize), compares output
  size to original, and emits one of: normal success (with before/after sizes), "minimal
  reduction" success variant, or the "output was larger, kept original" variant described above

`ImageCompressState` should track: source format, original file size, selected level, and (once
run) the resulting output size — with a derived getter for percentage reduction, reusing the same
before/after-formatting approach PDF Compress already established rather than inventing a second
one.

Write unit tests covering: JPEG compression at each of the 3 levels on a fixture (assert output
size < input size), a PNG fixture with little redundancy (assert the "already efficient" path
triggers), a simulated "output larger than input" case (assert original is preserved and the
correct message state is emitted), and dimension-preservation (assert output pixel dimensions
exactly match input at all 3 levels).

## Out of scope for this feature

- Resizing pixel dimensions as part of compression — that's Image Resize; this tool never changes
  dimensions, even though downsampling is a common technique for reducing file size elsewhere
- Format conversion — handled entirely by Image Format Convert; this tool always preserves the
  source's original format
- Custom/manual quality sliders — only the 3 preset levels for v1, consistent with PDF Compress
- Batch compression (multiple images in one job) — v1 of this tool is single-image, consistent
  with Resize and Format Convert
