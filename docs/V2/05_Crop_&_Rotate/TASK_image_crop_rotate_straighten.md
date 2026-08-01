# Task: Fine-angle "Straighten" rotation — Image Crop & Rotate

> Incremental addition to the shipped Image Crop & Rotate feature
> (`FEATURE_image_crop_rotate.md`). Standalone task doc — no rewrite of that spec. This was
> explicitly called out as out-of-scope in the original spec ("Arbitrary-angle straighten
> rotation... can be a fast-follow if requested") — this task is that fast-follow.

## What's being added

A **Straighten** slider, independent from the existing 90°-step Rotate button, letting the user
rotate the image by any angle in a small range to level a tilted horizon or straighten a crooked
shot — the thing people usually mean when they ask for "any degree" rotation, as opposed to
turning the whole photo a quarter-turn.

## UI additions

1. New slider control, labeled **Straighten**, range **−45° to +45°**, default **0°**, with a
   live numeric readout next to it (e.g. "+3.5°") and a **Reset** tap target that snaps it back to
   0°
2. Positioned separately from the existing Rotate button, with distinguishing microcopy so the two
   aren't confused: "Rotate turns the photo a quarter turn. Straighten levels a tilted photo."
3. Canvas preview updates live as the slider moves. If full-resolution live preview proves too
   slow on large images, render the drag-preview at a reduced resolution and only do the full-res
   transform at Apply time — `// ASSUMPTION:` flagging this as an implementation detail the agent
   should verify is actually necessary before adding the complexity; skip it if performance is
   fine at full res
4. Optional: a rule-of-thirds grid overlay on the canvas while adjusting Straighten, to help the
   user visually judge level — genuinely useful for this specific control, but not load-bearing;
   add if it's cheap, skip if it adds meaningful complexity

## Functional requirements

- **Transform order at Apply time is now fixed as:** EXIF orientation bake-in → 90°-step rotation
  → fine-angle (Straighten) rotation → crop. This order matters — fine rotation must happen after
  the 90° step (so the slider always operates on an already-correctly-oriented image) and before
  crop (so the crop rectangle is defined against the final, straightened canvas)
- Fine rotation is not axis-aligned, so it needs proper interpolation (bilinear/bicubic) rather
  than simple pixel remapping — same quality bar as Resize's interpolation choice; reuse that
  logic/constant if it's already centralized rather than picking a second interpolation method
- **Empty-corner problem:** rotating by a non-zero fine angle leaves the canvas's corners without
  real image content (the rotated image doesn't fill its own bounding box). This tool must never
  export an image with visible empty/blank corners. The fix: whenever the fine angle is non-zero,
  the crop rectangle's *maximum allowed bounds* are constrained to the **largest axis-aligned
  rectangle that fits entirely within the rotated image content** (the standard "largest inscribed
  rectangle in a rotated rectangle" geometry problem — well-documented formula, implement directly
  rather than approximating)
- When the Straighten angle changes, if the current crop rectangle no longer fits within the new
  inscribed bounds, **automatically shrink/recenter it to fit** — do not reset it to full bounds
  the way a 90°-step rotation does. Straighten is typically many small incremental slider drags,
  not one discrete action; resetting the crop on every tick would make fine adjustment unusable.
  This is a deliberately different behavior from the existing "90° rotation resets crop" rule, and
  that difference is intentional — leave a code comment explaining why so a future session doesn't
  "fix" it into consistency by accident
- Aspect ratio lock (Square/4:3/16:9/3:2/Original) continues to work during Straighten, but its
  available area is bounded by the inscribed-rectangle constraint at the current angle — e.g.
  "Square" at a 5° straighten angle still returns a valid square, just smaller than at 0°
- The Straighten slider and the 90°-step Rotate button are **independent, composed transforms** —
  changing one does not reset or interact with the other, aside from the fixed apply-order above

## Edge cases

| Case | Required behavior |
|---|---|
| Straighten set near the ±45° extremes on a non-square source image | The inscribed rectangle shrinks significantly relative to the original — expected and correct, not a bug. The live "Output: W×H" readout should make this tradeoff visible as the user drags, so it's never a surprise at Apply time |
| Angle + locked aspect ratio combination leaves very little usable area | Clamp to the best-fit rectangle as already specified; if the result is small enough to likely be unintentional (e.g. under some reasonable threshold — flag exact threshold as `// ASSUMPTION:` if pinning one), consider a soft inline note: "This angle and aspect ratio don't leave much of the image — try a smaller angle." Not blocking, just informative |
| User taps Reset | Straighten returns to 0°, crop bounds return to whatever they were constrained to under the 90°-step rotation alone (no fine-angle constraint) |
| User adjusts Straighten, then changes the 90°-step Rotate | Per the parent spec's existing rule, changing 90°-step rotation resets the crop rectangle — this now also implicitly resets relative to the fine angle's constraint at the point the 90° rotation was applied, since the whole crop is being reset anyway. No new special case needed here, just confirming the existing reset rule still fully covers this combination |
| Corrupted/unreadable file, other file-level errors | Unchanged from the parent spec |

## Controller additions (`image_crop_rotate_controller.dart`)

- `setFineRotationAngle(double degrees)` — clamps to `[-45.0, 45.0]`; recalculates the inscribed
  crop bounds and shrinks/recenters the current crop rect if it no longer fits
- `resetFineRotation()` — sets angle back to 0° and recalculates crop bounds accordingly
- `apply()` — updated to run the four transforms in the fixed order above, still off the UI thread
  per the standing pattern

`ImageCropRotateState` additions: `fineRotationAngle` (double), plus a derived getter for the
current inscribed crop bounds (a function of both the 90°-step rotation and the fine angle
together) so the UI, the crop-clamping logic, and the apply-time logic all read from one
calculation rather than three.

## Tests to add

- Fine angle accepted within `[-45, 45]`, clamped outside that range
- Crop rectangle auto-shrinks to fit inscribed bounds when the angle increases past what the
  current rect allows
- Crop rectangle is *not* reset (only resized/recentered if necessary) across a Straighten change,
  contrasted with a test confirming 90°-step rotation still fully resets it
- Aspect-ratio lock produces a valid, bounds-respecting rectangle at a representative non-zero
  angle (e.g. 10°)
- Reset restores full 90°-step-only bounds
- Final output dimensions are correct for a combined 90° + fine-angle + crop session

## Out of scope for this task

- Auto-straighten (automatic horizon/edge detection to suggest an angle) — would require an
  on-device CV model, which conflicts with the no-ML-model precedent already set for Blur's
  no-auto-detection decision. Worth a fully separate conversation if ever wanted
- Extending the angle range beyond ±45° — past that point the 90°-step Rotate button is the
  correct tool, not Straighten
