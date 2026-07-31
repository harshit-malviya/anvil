# Feature: Image Resize

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `AGENTS.md` (read all first).
> Files to create: `lib/tools/image_resize/image_resize_screen.dart`,
> `lib/tools/image_resize/image_resize_controller.dart`, plus registry + route entries.
> This is the second of three v2 image tools (after Image Format Convert). Third tool remains
> unspecced.

## Scope boundary — read this first

This feature changes an image's **pixel dimensions only**. It does not change file format (that's
Image Format Convert's job) and does not crop or reframe content (no canvas cropping in this
feature — see Out of Scope). Keeping this single-purpose means Resize and Format Convert never
duplicate each other's responsibility, matching the composable-tools principle already established
for the PDF tools.

## User story

"I have one image that's too big (or too small) for where I need to put it — a form upload limit,
a specific pixel size a website wants, a rough percentage shrink — and I want to resize it without
distorting it by accident."

## User flow

1. User taps "Resize Image" tool card, picks a single image file (drop zone or picker, filtered to
   supported image types — same type list as Image Format Convert's input side)
2. Screen shows the source image thumbnail preview plus its current dimensions and file size
   (`mono` style, e.g. "3840 × 2160 px · 4.1 MB")
3. User picks a **resize mode** via a segmented control:
   - **Exact Dimensions** — width + height number fields
   - **Percentage** — a single scale field (e.g. 50%), quick-pick chips for 25/50/75/100
   - **Presets** — a list of common target sizes (see Functional Requirements for the exact set)
4. An **aspect ratio lock** toggle (default **on**) sits next to the dimension fields:
   - Locked: editing width auto-computes height (and vice versa) to preserve the source's aspect
     ratio; selecting a preset or percentage always respects the lock
   - Unlocked: width and height can be set independently, which will distort the image — show a
     small inline warning when unlocked ("Unlocking may stretch or squash the image")
5. Live preview line updates as the user adjusts values: "New size: 1920 × 1080 px" — no live
   re-render of the thumbnail is required (that would be expensive per-keystroke), just the
   numeric readout
6. If the target dimensions are larger than the source in either axis, show a persistent inline
   note: "Upscaling beyond the original size may reduce quality" — informational, never blocking
7. "Resize" primary button triggers processing
8. Processing state: "Resizing…" with progress bar (single image, so this should be fast — an
   indeterminate spinner is acceptable if the underlying `image` package call is synchronous and
   sub-second for typical file sizes, but still run it off the UI thread per Rule #7-equivalent
   for image work — see Controller Responsibilities)
9. Success state (stamp): shows new dimensions and new file size next to the original for
   comparison (e.g. "3840×2160 (4.1 MB) → 1920×1080 (1.2 MB)"), plus Save As / Open Folder /
   Share actions, consistent with other tools
10. Output file keeps the **original format and extension** — this feature never changes format

## Functional requirements

- Original file is never modified; output is always a new file
- Default output filename: `[name]_resized.[ext]` in the same directory as the source, `[ext]`
  matching the source's original extension; user can rename via Save As
- Resizing uses proper interpolation (not nearest-neighbor) for quality — use the `image`
  package's built-in resize with a smooth interpolation option (e.g. `interpolation:
  img.Interpolation.cubic` or the package's linear/average equivalent); document the exact
  interpolation constant chosen as a `// ASSUMPTION:` comment if not pinned here, so it's
  reviewable
- Preset list (fixed set for v1, not user-editable):
  | Preset | Dimensions |
  |---|---|
  | HD | 1280 × 720 |
  | Full HD | 1920 × 1080 |
  | 4K | 3840 × 2160 |
  | Square (social) | 1080 × 1080 |
  | Story / Portrait (social) | 1080 × 1920 |
  | Web banner | 1200 × 630 |
- **Presets are a starting width, not a forced crop.** When aspect ratio lock is on (the default)
  and a preset is chosen, only the preset's width is applied directly; height is recalculated to
  preserve the source's aspect ratio. If the user unlocks aspect ratio after picking a preset, the
  preset's exact height then applies too (and the distortion warning from step 4 applies). This
  avoids silently cropping or letterboxing content, which is out of scope for this tool —
  `// ASSUMPTION:` this behavior since the spec doesn't otherwise define how a preset's fixed
  aspect ratio reconciles with a source image of a different aspect ratio
- Minimum output dimension: 1×1px is technically valid to the `image` package but useless in
  practice — enforce a sane floor (e.g. 10px per side) with inline validation, since anything
  smaller is almost certainly a user typo, not an intended size
- EXIF orientation must be respected/baked in before resizing (so a phone photo doesn't come out
  sideways) — reuse whatever orientation-handling logic Image Format Convert already implements
  if it exists; otherwise implement once here and note it for Format Convert to reuse rather than
  duplicating

## Edge cases

| Case | Required behavior |
|---|---|
| Target dimensions identical to source | Resize button still enabled (it's a valid no-op), but processing effectively re-encodes the image unchanged — no special-casing needed, just let it run |
| User types a non-numeric or empty value in a dimension field | Resize button disabled, inline validation: "Enter a width and height" |
| User enters a dimension below the minimum floor (e.g. "5") | Inline validation: "Minimum size is 10×10px" |
| Aspect ratio locked, user edits width to an extreme value (e.g. 20000px) | Allowed (no artificial upper cap beyond memory reality), but the upscale-quality note from the flow applies; if the underlying resize throws an out-of-memory-class exception, catch it and show: "This image is too large to resize at this size on this device. Try a smaller target size." |
| Corrupted or unreadable image file selected | Reject at file-select time with a specific message, same pattern as other tools |
| Unsupported image format selected (outside the type list Format Convert also uses) | Reject at file-select time: "This file type isn't supported. Supported formats: [list]." |
| User switches resize mode after entering values (e.g. Exact → Percentage) | Preserve intent as best as possible: compute the equivalent percentage from the current exact values (or vice versa) rather than resetting to a blank/default state — avoids the user re-entering everything |
| Disk full / write permission denied at save time | Error state: "Couldn't save the file — [specific OS error]. Try a different location." |

## Controller responsibilities (`image_resize_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImageResizeState>>` with:

- `loadImage(PlatformFile)` — validates format/readability, captures source dimensions, file size,
  and EXIF orientation
- `setMode(ResizeMode mode)` — enum: `exactDimensions`, `percentage`, `preset`
- `setWidth(int width)` / `setHeight(int height)` — respects aspect ratio lock when computing the
  linked dimension
- `setPercentage(double percent)`
- `selectPreset(ImagePreset preset)` — enum of the six presets above
- `toggleAspectRatioLock()`
- `resize()` — runs the actual resize via the `image` package **off the UI thread** (isolate /
  `compute()`, matching the standing pattern already used for PDF processing — image resize on a
  large source can block the UI thread just as easily as PDF work does), writes output, emits
  success (with before/after size comparison) or a typed error

`ImageResizeState` should track: source image metadata, current mode, current target
width/height/percentage, aspect ratio lock state, and computed target dimensions — with a derived
getter for "is this upscaling" so the UI warning and the controller logic share one source of
truth rather than recalculating the comparison in two places.

Write unit tests covering: aspect-ratio-locked width edit auto-computes height, unlocked
independent width/height, percentage-to-exact mode switch preserves equivalent size, preset
selection respects aspect ratio lock, minimum-dimension-floor validation, and out-of-memory
exception handling on resize.

## Out of scope for this feature

- Cropping or canvas reframing (letterboxing, center-crop-to-fit a preset's exact aspect ratio) —
  a future "Crop" tool territory, not this one
- Format conversion — handled entirely by Image Format Convert; this tool always preserves the
  source's original format
- Batch resize (multiple images in one job) — v1 of this tool is single-image, consistent with the
  rest of the app; could be a fast-follow if requested later
- Custom/manual interpolation algorithm choice — one fixed high-quality interpolation method for
  all resizes, no user-facing quality slider
