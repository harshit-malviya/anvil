# Task: Fix color destruction in Image Compress — Target Size Range mode

> Incremental fix against the shipped Image Compress feature (`FEATURE_image_compress.md`). This
> is a standalone task doc, not a rewrite of that spec — only the Target Size Range search
> behavior changes.

## Problem

In Target Size Range mode, the binary search over quality (JPEG/WebP) and palette size (PNG) has
no floor — it will keep pushing quality/palette lower and lower until the output size lands
inside the requested range, even if that means visually destroying the image to get there:

- **JPEG/WebP**: quality searched all the way down toward 1, producing severe color banding and
  chroma subsampling artifacts well past the point of "acceptable High-level quality loss"
- **PNG**: palette quantization searched down toward very small palettes (e.g. 16 colors or
  fewer), producing visible color destruction rather than the intended lossless-first,
  minimal-loss-fallback behavior

The original spec's `// ASSUMPTION:` around palette quantization anticipated this needing a floor
but didn't pin one — this task pins it, plus adds the equivalent floor for the JPEG/WebP quality
search that the original spec was missing entirely.

## Required fix

### 1. JPEG / WebP quality floor

- The binary search range is no longer `[1, 100]` — it's `[QUALITY_FLOOR, 100]`, where
  `QUALITY_FLOOR = 30` — `// ASSUMPTION:` pinning 30 as the floor below which JPEG/WebP quality
  is considered destructive rather than merely low-quality; review against a few real test images
  if 30 still looks too aggressive or too conservative once implemented
- If the search reaches `QUALITY_FLOOR` and the output is still above the requested Maximum, stop
  searching — don't go lower. Treat `QUALITY_FLOOR`'s output as the closest-effort result (same
  "couldn't land in range" messaging already defined in the parent spec)

### 2. PNG palette floor + dithering

- Palette quantization search is bounded to a minimum of `PNG_PALETTE_FLOOR = 64` colors —
  `// ASSUMPTION:` pinning 64 as the floor; below this, color banding becomes visually obvious on
  most photographic PNGs. Simple flat-color PNGs (icons, screenshots with few colors) may still
  compress well within this floor since they don't need many colors to begin with
- Always apply **dithering** (e.g. Floyd–Steinberg, if the `image` package's quantizer supports
  it) when palette-quantizing for Target Size Range mode — dithering distributes quantization
  error instead of producing hard color bands, which meaningfully improves perceived quality at
  the same palette size. If the `image` package's quantizer doesn't expose a dithering option,
  flag this back to the human — it may mean switching quantization approach or accepting the
  visual quality hit as a known limitation
- If the search reaches `PNG_PALETTE_FLOOR` and the output is still above the requested Maximum,
  stop — same closest-effort fallback as above

### 3. Quality Level mode is unaffected

- These floors apply **only** to Target Size Range mode's search. Quality Level mode's fixed
  Low/Medium/High parameters (JPEG quality 85/65/40, PNG lossless-only, per the parent spec)
  already sit well above `QUALITY_FLOOR` / don't use palette quantization at all — no change
  needed there, and this task must not touch that code path

### 4. Messaging update

- When a result is returned at the floor (quality or palette) and still outside the requested
  range, the existing "couldn't land in range" success message should make clear *why*: "Couldn't
  land in your target range without visibly degrading the image — closest safe result is 2.1 MB
  (target was 1–2 MB)." This is a wording change to the existing closest-effort variant from the
  parent spec, not a new state

## Edge cases to add to the existing test suite

| Case | Required behavior |
|---|---|
| Requested Maximum is only reachable below `QUALITY_FLOOR` (JPEG/WebP) | Search stops at the floor, returns closest-effort result with the "without visibly degrading" messaging — never crosses the floor |
| Requested Maximum is only reachable below `PNG_PALETTE_FLOOR` (PNG) | Same as above, palette-specific |
| PNG source is naturally low-color (e.g. a flat-color screenshot or icon) | Quantizing to `PNG_PALETTE_FLOOR` or fewer colors may still look fine since the source didn't need many colors — this isn't a bug, just note it's expected that some PNGs hit the floor without visible quality loss |
| Dithering unsupported by the `image` package's quantizer | Flag to the human at implementation time rather than silently shipping banding — don't guess |

## Out of scope for this task

- Changing the JPEG quality / PNG behavior for Quality Level mode — untouched
- Making the floors user-configurable — they're fixed constants for now, same as the rest of
  Image Compress's parameters
- Re-deriving the binary search algorithm itself — only its bounds change
