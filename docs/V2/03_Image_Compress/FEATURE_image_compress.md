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
2. Screen shows the file's current size prominently, plus a **compression mode** segmented
   control:
   - **Quality Level** (default) — the Low/Medium/High preset picker described below
   - **Target Size Range** — user sets a min/max output size instead of a named level
3. **Quality Level mode:**
   - **Low** (minimal size reduction, highest visual quality preserved)
   - **Medium** (balanced — recommended default, pre-selected)
   - **High** (maximum size reduction, visible quality loss is expected and acceptable)
4. **Target Size Range mode:**
   - Two fields, **Minimum** and **Maximum**, each with a unit toggle (**KB** / **MB**)
   - Minimum has a hard floor of **5 KB** — the field cannot be set (or typed) below this; if the
     user tries, clamp to 5 KB and show inline text: "Minimum can't be set below 5 KB"
   - Maximum must be greater than Minimum — inline validation error otherwise: "Maximum must be
     greater than minimum"
   - A short explanatory line: "We'll find the compression level that lands your image inside
     this size range." — sets expectations that this is best-effort search, not a guarantee (see
     Functional Requirements)
5. A short explanatory line under the mode selector (Quality Level mode only): "Compression
   reduces image quality to save space. Dimensions and format stay the same." — sets expectations
   up front, same pattern as PDF Compress
6. "Compress" primary button triggers processing
7. Processing state: "Compressing…" with progress bar (or indeterminate spinner if the operation
   is fast enough that a determinate bar would just flash). In Target Size Range mode, this step
   may take longer since the app is trying multiple quality settings internally — the label can
   say "Finding the right size…" instead of "Compressing…" to set the right expectation
8. Success state (stamp) shows **before → after size comparison** prominently (e.g. "8.4 MB → 2.1
   MB, 75% smaller") plus Save As / Open Folder / Share actions — this comparison is the whole
   point of the feature, same as PDF Compress, don't bury it. In Target Size Range mode, also
   confirm the result landed in range: "Compressed to 1.8 MB — within your 1–2 MB target."
9. If the compressed result isn't meaningfully smaller (Quality Level mode) or couldn't land
   inside the requested range (Target Size Range mode) — see edge cases — success state instead
   shows a neutral/explanatory message rather than a misleading claim

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

### Target Size Range mode — search behavior

- **Minimum floor is hard-coded at 5 KB**, enforced in the UI (can't type or drag below it) and
  again in the controller before `compress()` runs (never trust UI-only validation) — this floor
  exists because anything smaller risks compressing an image into unusable/corrupt-looking
  quality territory, and it's an explicit product requirement, not just a suggestion
- **JPEG / WebP**: use a binary search over the encoder's quality parameter (1–100) to find a
  quality setting whose output size falls within `[min, max]`. Cap the search at a fixed number of
  iterations (e.g. 8) — `// ASSUMPTION:` this iteration count since the spec doesn't pin one;
  8 iterations is enough to narrow a 1–100 range to single-digit precision while keeping the
  operation fast
- **PNG**: PNG has no continuous quality knob, only a small number of discrete lossless
  compression levels — hitting an arbitrary size range with lossless-only encoding will often be
  impossible. To make range-targeting actually useful for PNG, add **palette quantization**
  (reducing to an indexed color palette, e.g. 256 → down to as few as 16 colors) as an additional,
  range-mode-only technique, searched similarly to quality — `// ASSUMPTION:` this expands PNG's
  toolset specifically for Target Size Range mode (Quality Level mode for PNG stays purely
  lossless, per the section above) since without a lossy fallback PNG range-targeting would fail
  far more often than succeed; flag this clearly to the human as a scope decision worth reviewing,
  since it's a step beyond "purely lossless" for PNG
- If the search finds a result **within range**, use it and report success normally
- If the search **exhausts its iteration budget without landing in range**, use the closest result
  achieved and clearly label it as such in the success state rather than claiming it's in range
  (see edge cases) — never silently present an out-of-range result as if it satisfied the request
- If the **original file is already within the requested range**, skip compression entirely — no
  point degrading quality for no size benefit — and tell the user directly (see edge cases)

## Edge cases

| Case | Required behavior |
|---|---|
| PNG source with little redundancy (already well-optimized) | If size reduction is under ~5%, show: "This image is already efficient — there wasn't much to compress." Still offer the (barely smaller, or same-size) output rather than blocking the action entirely — same pattern as PDF Compress's text-only case |
| Compressed output is *larger* than the original (can happen with some PNGs at certain filter settings) | Detect this and don't hand the user a worse file — show: "Compression didn't reduce the size for this file. Your original hasn't been changed." and don't produce a misleading "smaller" output — same guard as PDF Compress |
| Corrupted or unreadable image file selected | Reject at file-select time with a specific message, same pattern as other tools |
| Unsupported image format selected | Reject at file-select time: "This file type isn't supported. Supported formats: [list]." |
| Already-heavily-compressed JPEG (e.g. re-compressing a already-low-quality JPEG) | High setting may produce visible additional artifacts — expected/acceptable, not a bug to fix, same as PDF Compress's equivalent case |
| Very large source image (e.g. 50+ MP photo) | Show progress feedback if the operation is slow enough to need it; at minimum don't let the UI appear frozen — run off the UI thread (see Controller Responsibilities) |
| Target Size Range: user tries to set Minimum below 5 KB | Clamp to 5 KB, inline text explains the floor — never silently accept a lower value |
| Target Size Range: Maximum ≤ Minimum | Compress button disabled, inline validation: "Maximum must be greater than minimum" |
| Target Size Range: original file is already within `[min, max]` | Skip compression, show: "Your image is already within your target range (e.g. 1.4 MB, target 1–2 MB) — no changes needed." Don't run a pointless quality-loss pass just to reproduce a same-size file |
| Target Size Range: original file is already **smaller** than Minimum | Compression can only shrink, never grow, a file — reject with: "This image is already smaller than your minimum size. Lower the minimum or use the original file." |
| Target Size Range: search can't land inside the range within its iteration budget (most likely on PNGs even with palette quantization, or JPEGs where min/max is an unrealistically narrow band) | Use the closest achievable result and say so plainly: "Couldn't land exactly in your target range — closest we could get is 2.3 MB (target was 1–2 MB)." Still offer Save As for that closest result rather than a dead end |
| Target Size Range: Maximum is set higher than the original file size | Allowed, but functionally equivalent to "already within range" once original ≤ max and ≥ min — same skip-compression behavior applies if Minimum is also satisfied |

## Controller responsibilities (`image_compress_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImageCompressState>>` with:

- `loadImage(PlatformFile)` — validates format/readability, captures original file size and
  detected format (JPEG/PNG/WebP)
- `setMode(CompressionMode mode)` — enum: `qualityLevel`, `targetSizeRange`
- `setCompressionLevel(CompressionLevel level)` — enum: `low`, `medium`, `high` (Quality Level
  mode)
- `setMinSize(double value, SizeUnit unit)` / `setMaxSize(double value, SizeUnit unit)` — enum
  `SizeUnit`: `kb`, `mb` (Target Size Range mode); `setMinSize` enforces the 5 KB floor at the
  controller level regardless of what the UI already enforced
- `compress()` — runs **off the UI thread** (isolate / `compute()`, same standing pattern as PDF
  processing and Resize):
  - Quality Level mode: runs the format-appropriate compression strategy at the fixed
    quality/level mapping, compares output size to original, and emits one of: normal success
    (with before/after sizes), "minimal reduction" variant, or "output was larger, kept original"
    variant
  - Target Size Range mode: runs the binary-search-over-quality (and, for PNG, palette
    quantization) loop described above, up to the fixed iteration cap, and emits one of: in-range
    success (with before/after sizes and explicit range confirmation), closest-effort success
    (clearly labeled as not-quite-in-range, with the closest size achieved), "already within
    range, skipped" variant, or the "original smaller than minimum, rejected" error

`ImageCompressState` should track: source format, original file size, current mode, selected
level (Quality Level mode) or min/max/unit (Target Size Range mode), and (once run) the resulting
output size plus whether it landed in range — with a derived getter for percentage reduction,
reusing the same before/after-formatting approach PDF Compress already established rather than
inventing a second one.

Write unit tests covering: JPEG compression at each of the 3 quality levels on a fixture (assert
output size < input size), a PNG fixture with little redundancy (assert the "already efficient"
path triggers), a simulated "output larger than input" case (assert original is preserved and the
correct message state is emitted), dimension-preservation (assert output pixel dimensions exactly
match input at all 3 levels), Target Size Range binary search landing in range on a fixture,
Target Size Range where original is already in range (assert compression is skipped), Target Size
Range where original is smaller than minimum (assert rejection, no output produced), Target Size
Range exhausting its iteration budget without landing in range (assert closest-effort result is
returned and clearly labeled), and the 5 KB minimum floor being enforced at the controller level
even if a test bypasses UI validation.

## Out of scope for this feature

- Resizing pixel dimensions as part of compression — that's Image Resize; this tool never changes
  dimensions, even though downsampling is a common technique for reducing file size elsewhere
- Format conversion — handled entirely by Image Format Convert; this tool always preserves the
  source's original format
- Custom/manual quality sliders — quality is only ever set indirectly, via the 3 preset levels or
  via a target size range; there's no raw "set JPEG quality to 73" control exposed to the user
- Guaranteeing an exact byte-perfect result inside the target range — Target Size Range mode is
  best-effort search within a fixed iteration budget, not a mathematical guarantee, and the spec
  above defines the clearly-labeled fallback when it can't land inside the range
- Batch compression (multiple images in one job) — v1 of this tool is single-image, consistent
  with Resize and Format Convert