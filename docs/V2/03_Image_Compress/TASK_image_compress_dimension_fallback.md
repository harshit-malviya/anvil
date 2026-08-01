# Task: Reactive dimension-reduction fallback — Image Compress Target Size Range

> Incremental addition to the shipped Image Compress feature (`FEATURE_image_compress.md`) and
> its follow-up fix (`TASK_image_compress_quality_floor.md`). Standalone task doc — no rewrite of
> either prior doc.

## Why

The quality-floor fix (previous task) correctly stops the search before it visibly destroys
color, but that means some target ranges are now honestly unreachable through quality/palette
adjustment alone — the user just gets "couldn't land in range." Reducing pixel dimensions is
usually the more effective lever for hitting an aggressive size target while actually looking
*better* than a heavily quality-crushed image at full resolution. Offering it as a fallback gives
the user a real path forward instead of a dead end.

## Scope boundary — still applies

Image Compress's core promise is "dimensions stay the same." This task does not change that
default. Dimension reduction only happens if the user explicitly opts in, **after** being told
quality-only compression couldn't reach their target — never automatically, never upfront.

## Trigger & flow

1. Target Size Range search runs as already specced (quality/palette search bounded by the
   floors from the previous task)
2. If it fails to land in range, the existing "couldn't land in range" message displays as before,
   **plus** a new inline option directly beneath it:
   - Checkbox: **"Also reduce image dimensions to reach your target size"**
   - Helper text: "This will make the image smaller (e.g. 3840×2160 → 1920×1080) to hit your
     target. You'll see the new size before saving."
3. If the user checks the box, a **"Retry"** button appears (don't auto-retry on checkbox toggle —
   require an explicit action, consistent with the app's non-destructive/no-surprises pattern)
4. On Retry: re-run the search, now allowed to step down resolution (see algorithm below)
5. If this second pass lands in range: show success with **both** deltas visible — size *and*
   dimensions — e.g. "Compressed to 1.4 MB (target 1–2 MB) — dimensions reduced from 3840×2160 to
   1920×1080 to reach this." Never show a dimension change without calling it out explicitly
6. If it still can't land in range even with dimension reduction allowed (see edge cases): same
   closest-effort pattern as before, now noting both floors were hit: "Couldn't land in your
   target range even with reduced dimensions — closest safe result is 2.1 MB at 1536×864 (target
   was 1–2 MB)."

## Algorithm

- Step resolution down in fixed decrements — e.g. 90% of previous step's dimensions each time
  (`// ASSUMPTION:` pinning 90%/step; adjust if testing shows this converges too slowly or too
  coarsely)
- At each resolution step, re-run the existing quality/palette-floor search (from the previous
  task) at that resolution — the goal is always "smallest quality loss + smallest dimension loss
  that reaches the target," not "shrink dimensions as far as possible first"
- **Dimension floor: never go below 50% of the original width or height**, whichever is hit
  first — `// ASSUMPTION:` pinning 50% as the point past which the output stops being a usable
  version of the original image for most purposes; stop stepping down once this floor is reached,
  regardless of whether the target range was hit
- Reuse the **same resize/scaling logic Image Resize already implements** — do not
  reimplement proportional scaling here. If that logic isn't already extracted into a shared
  service, extract it now (e.g. `lib/core/services/image_resize_service.dart`), matching the
  precedent already set by extracting `PdfThumbnailService` out of Page Manager for Split/PDF to
  Image to share. `ImageResizeController` should be refactored to call the same shared service
  rather than having two independent scaling implementations drift apart over time
- Aspect ratio is always preserved during this fallback — no independent width/height control
  here, this isn't the user-facing Resize UI, it's an automatic proportional step-down

## Controller responsibilities — additions to `image_compress_controller.dart`

- `setDimensionFallbackEnabled(bool enabled)` — tracks the checkbox state; does not trigger a
  retry by itself
- `retryWithDimensionReduction()` — re-runs the Target Size Range search with resolution stepping
  enabled per the algorithm above, off the UI thread same as `compress()`; emits the same result
  variants as before, plus the new "landed in range, dimensions reduced" and "closest-effort, both
  floors hit" variants described above

`ImageCompressState` additions: whether the dimension fallback is enabled, and (once a retry with
resize has run) the final output dimensions alongside final output size, so the UI can show both
deltas together.

## Edge cases to add to the existing test suite

| Case | Required behavior |
|---|---|
| User enables the checkbox but never taps Retry | No resize happens — state stays as the original quality-only closest-effort result until Retry is explicitly tapped |
| Dimension stepping reaches the 50% floor without landing in range | Stop stepping, return closest-effort result at the floor, message notes both quality and dimension floors were hit |
| Dimension stepping lands in range before reaching the 50% floor | Stop as soon as in range — don't keep shrinking further than necessary just because it's allowed |
| Source image is already small (e.g. 400×300) | 50% floor is still 200×150 in absolute terms — no special-casing needed, the percentage floor applies uniformly regardless of source size |
| User unchecks the box after a successful resize-assisted result | Revert the displayed result back to the original (pre-resize) closest-effort state — don't leave a resized result showing when the option that produced it has been turned off |

## Out of scope for this task

- Making the dimension fallback available in Quality Level mode — Target Size Range mode only,
  since Quality Level mode doesn't have a size target to fail against in the first place
- User-controlled step size or dimension floor — fixed constants for now
- Manual/independent width-height control during this fallback — that's the dedicated Resize
  tool's job if the user wants that level of control instead
