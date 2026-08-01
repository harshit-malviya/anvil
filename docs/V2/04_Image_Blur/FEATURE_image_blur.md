# Feature: Image Blur (Selective Redaction)

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `AGENTS.md` (read all first).
> Files to create: `lib/tools/image_blur/image_blur_screen.dart`,
> `lib/tools/image_blur/image_blur_controller.dart`, plus registry + route entries.
> This is a fourth v2 image tool, beyond the three originally scoped (Format Convert, Resize,
> Compress) — flag this back to the human for `PROJECT_OVERVIEW.md`'s v2 scope list once specced.

## Scope boundary — read this first

This tool redacts **specific user-drawn rectangular regions** of an image — it does not apply a
whole-image blur effect (that would be a different, simpler tool if ever requested), and it does
not attempt to automatically detect faces, license plates, or text. No ML model ships with this
app (offline-first, no heavy model bundling) — the user manually marks what needs hiding. Say
this plainly in the UI so nobody expects auto-detection that isn't there.

**Important security note, and why it shapes this spec:** a soft Gaussian blur alone is not a
cryptographically secure way to hide information — there are known deblurring/reconstruction
techniques that can partially recover blurred text or faces, especially at low blur strength.
Since this tool exists specifically for privacy redaction (the stated use case — faces, plates,
sensitive text before sharing), shipping *only* a blur option would give users false confidence.
This spec includes **Pixelate** and **Solid Block** as first-class alternatives, not an
afterthought, and surfaces a warning when Blur is selected for genuinely sensitive content.

## User story

"I have a screenshot or photo with someone's face, a license plate, an account number, or some
other private detail in it, and I want to hide just that part before I share it — without opening
a full image editor."

## User flow

1. User taps "Blur Image" tool card, picks a single image file (same supported-format list as the
   other image tools)
2. Screen shows the image at a fit-to-screen display size, with drawing enabled directly on it
3. User taps-and-drags to draw a rectangular region over the area to redact; releasing the drag
   finalizes that region. Multiple regions can be drawn in one session
4. Each drawn region:
   - Shows a live preview of the current redaction style applied within its bounds, so the user
     sees the actual effect, not just an outline
   - Has drag handles on its corners to resize, and can be dragged by its body to reposition
   - Has a small × button to delete it
5. A **Redaction Style** selector applies to all regions in the session (not per-region — see Out
   of Scope):
   - **Pixelate** (mosaic blocks) — default, since it's the most reliably irreversible of the
     three at typical block sizes
   - **Blur** (Gaussian) — when selected, show inline warning text: "Blur can sometimes be
     partially reversed for sensitive content like faces or text. Pixelate or Solid Block is
     safer for anything truly private."
   - **Solid Block** (flat fill color, default black, with a small color swatch picker) — the
     most secure option since it destroys the underlying pixel data completely, no reconstruction
     possible
6. An **Intensity** control appropriate to the selected style:
   - Pixelate: block size — Small / Medium / Large
   - Blur: strength — Light / Medium / Strong
   - Solid Block: no intensity control, just the color swatch
7. Bottom bar: running count ("3 regions marked") and an "Apply" primary button, disabled until at
   least one region exists
8. On Apply: Processing state, then success (stamp) with Save As / Open Folder / Share, consistent
   with other tools. Success state includes a reminder: "The original file wasn't changed — the
   redacted version is a new file. Once applied, redacted regions can't be un-redacted from this
   file, so keep the original if you might need the unredacted image again."
9. If the user navigates away without applying, prompt: "Discard unsaved regions?" — same pattern
   as Page Manager's unsaved-changes guard

## Functional requirements

- Original file is never modified; output is always a new file, `[name]_blurred.[ext]`, same
  format/extension as the source (this tool doesn't convert format)
- Region coordinates must be stored and applied in **source image pixel space**, not on-screen
  display coordinates — the display canvas is very likely scaled down from the actual image
  resolution, so drawing must map screen taps back to real pixel coordinates accurately regardless
  of how the image is scaled to fit the screen. Get this wrong and redactions land in the wrong
  place on the real output, which defeats the entire point of the tool
- Redaction is destructive to the affected pixels at Apply time — this must actually overwrite
  the pixel data in those regions (not just draw an overlay), so the original content is
  genuinely unrecoverable from the output file for Pixelate/Solid Block, and meaningfully degraded
  for Blur
- Minimum region size (e.g. 10×10px in source pixel space) — same rationale as Resize's dimension
  floor, prevents accidental near-invisible regions that don't actually redact anything useful
- Regions that extend past the image's edges during drawing are clamped to the image bounds
  automatically — never allow a region rect outside the actual image
- The three intensity presets per style should map to concrete, testable parameters (e.g. Pixelate
  block size in pixels, Blur radius in pixels) — pin exact values as `// ASSUMPTION:` comments if
  not otherwise decided, same requirement already established for Compress's levels
- Blur radius should be capped relative to the region's own smaller dimension (e.g. never exceed
  ~40% of the region's shorter side) so a strong blur setting on a small region doesn't produce a
  visually broken result — `// ASSUMPTION:` this cap since the base spec doesn't otherwise define
  behavior for small regions at high blur strength

## Edge cases

| Case | Required behavior |
|---|---|
| User taps Apply with zero regions drawn | Apply button stays disabled: "Draw at least one region to redact" |
| Region drawn extends past the image edge during the drag | Clamp to image bounds live, so the user sees the actual clamped region while still dragging, not a surprise after release |
| Region drawn smaller than the minimum size | Region is rejected on release with a brief inline message; drag doesn't finalize a too-small box |
| Corrupted or unreadable image file selected | Reject at file-select time with a specific message, same pattern as other tools |
| User selects Blur style for what looks like sensitive content | Can't be detected automatically — the warning text from the flow above is always shown whenever Blur is the active style, regardless of content, since the app has no way to know what's "sensitive" |
| Very high-resolution image with many regions (e.g. 15+ regions on a 50MP photo) | Run the pixel-level redaction off the UI thread (isolate/`compute()`); show progress if the operation is slow enough to warrant it |
| User resizes a region to overlap another region | Allowed — overlapping regions just both get redacted, no special merge logic needed, the effect is applied per-region independently |
| User switches Redaction Style after drawing regions | All existing regions update their live preview to the new style immediately — don't require redrawing |

## Controller responsibilities (`image_blur_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImageBlurState>>` with:

- `loadImage(PlatformFile)` — validates format/readability, captures source dimensions
- `addRegion(Rect regionInSourcePixelSpace)` — validates minimum size and clamps to bounds before
  adding
- `updateRegion(String regionId, Rect newRect)` — resize/move, same validation as add
- `removeRegion(String regionId)`
- `setRedactionStyle(RedactionStyle style)` — enum: `pixelate`, `blur`, `solidBlock`
- `setIntensity(RedactionIntensity intensity)` — enum: `small`/`light`, `medium`, `large`/`strong`
  (label depends on active style, same underlying enum ordinality)
- `setSolidBlockColor(Color color)` — Solid Block mode only
- `apply()` — runs the actual pixel redaction for every region **off the UI thread**
  (isolate/`compute()`, same standing pattern as PDF processing, Resize, and Compress), writes
  output, emits success or a typed error

`ImageBlurState` should track: source image metadata, list of regions (each with id and rect in
source pixel space), active style, active intensity/color — mirroring the value-object list
pattern Page Manager already established for its page state, so adding/removing/updating a region
is straightforward and testable in isolation.

Write unit tests covering: add/update/remove region, minimum-size rejection, clamp-to-bounds on a
region drawn past the edge, screen-to-source coordinate mapping accuracy at a non-1:1 display
scale, and pixel-level verification that Apply actually alters pixel data within each region for
all three styles (not just an overlay that happens to render correctly).

## Out of scope for this feature

- Automatic face/license-plate/text detection — no ML model ships with this app; regions are
  always manually drawn by the user
- Freehand/brush-shaped regions — rectangles only for v1; freehand masking is a meaningfully
  bigger feature (path storage, anti-aliased masking) and can be a fast-follow if requested
- Per-region independent style/intensity — one style and intensity apply to the whole session's
  regions for v1
- Undo-after-export / storing "what was redacted" for later reversal — this tool is intentionally
  one-way once applied, consistent with its purpose as a privacy tool
- Whole-image blur as an artistic effect — a different, simpler tool if ever requested; this
  feature is specifically the region-based redaction use case
