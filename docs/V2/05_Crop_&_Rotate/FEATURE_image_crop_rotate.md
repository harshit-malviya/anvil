# Feature: Image Crop & Rotate

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `AGENTS.md` (read all first).
> Files to create: `lib/tools/image_crop_rotate/image_crop_rotate_screen.dart`,
> `lib/tools/image_crop_rotate/image_crop_rotate_controller.dart`, plus registry + route entries.
> This is a fifth v2 image tool, beyond the four already specced (Format Convert, Resize,
> Compress, Blur) — flag this back to the human for `PROJECT_OVERVIEW.md`'s v2 scope list.

## Why these two share one screen

Same reasoning as PDF Page Manager combining delete/reorder/rotate: crop and rotate both operate
on the same underlying transform of a single image, and a real editing session usually needs both
together (straighten a sideways photo, *then* crop it) — splitting them into two separate tools
would mean exporting an intermediate file just to feed it into the second tool. One screen, one
Apply, one output.

## User story

"I have one photo that's sideways and has too much background around the subject — I want to fix
the rotation and crop it down to just the part I care about, in one pass."

## User flow

1. User taps "Crop & Rotate" tool card, picks a single image file (same supported-format list as
   the other image tools)
2. Screen shows the image at fit-to-screen size, with a **crop overlay** on top of it: a
   rectangle with draggable corner/edge handles, defaulting to the **full image bounds** (i.e. no
   crop until the user adjusts it — same "default no-op" pattern as Resize)
3. A **Rotate** control (icon button, top of screen): rotates the whole image 90° clockwise per
   tap, cycling 0° → 90° → 180° → 270° → 0°, same interaction as Page Manager's page rotation
4. An **Aspect Ratio** selector for the crop rectangle:
   - **Free** (default) — any rectangle, no lock
   - **Square (1:1)**
   - **4:3**
   - **16:9**
   - **3:2**
   - **Original** — locks to the source image's own aspect ratio (accounting for current rotation
     — see Functional Requirements)
   - Selecting a locked ratio recalculates the current crop rectangle to fit that ratio
     (anchored at the rectangle's current center) rather than requiring the user to redraw it —
     `// ASSUMPTION:` center-anchored recalculation since the spec doesn't otherwise pin an anchor
5. Live readout below the canvas shows the resulting output dimensions as the user adjusts either
   control: "Output: 1920 × 1080 px"
6. "Apply" primary button triggers processing (enabled at all times — an unmodified full-bounds
   crop with no rotation is a valid, if pointless, no-op, same philosophy as Resize allowing
   identical target dimensions)
7. Processing state: "Applying changes…" with progress bar
8. Success state (stamp): shows final output dimensions, plus Save As / Open Folder / Share
   actions, consistent with other tools
9. If the user navigates away with unsaved crop/rotation changes, prompt: "Discard unsaved
   changes?" — same guard as Page Manager

## Functional requirements

- Original file is never modified; output is always a new file, `[name]_edited.[ext]`, same
  format/extension as the source (no format conversion here, same separation-of-concerns
  boundary as Resize/Compress/Blur)
- Rotation and crop are stored as **transform state, applied together at export** — not
  destructively rendered into the preview mid-session, matching Page Manager's non-destructive
  pattern for rotation
- **EXIF orientation must be baked in before any of this tool's own transforms are applied** —
  reuse the orientation-handling logic already established for Resize/Blur rather than
  reimplementing it a third time, so a phone photo's built-in rotation metadata doesn't stack
  confusingly with the user's manual rotation here
- Crop rectangle coordinates are stored in **source image pixel space** (post-EXIF-correction,
  pre-user-rotation), same rigor as Blur's region coordinates — screen-to-source mapping must stay
  accurate regardless of display scale
- **Rotation changes reset the crop rectangle** back to the new orientation's full bounds, with an
  inline note: "Changing rotation resets your crop selection." — `// ASSUMPTION:` this reset
  behavior, since trying to remap an existing crop rectangle across a 90° rotation while
  preserving user intent is both error-prone and rarely what the user actually wants (a crop
  drawn for a sideways photo usually doesn't make sense once the photo is turned upright)
- "Original" aspect ratio reflects the **current rotation state** — if the source is
  3000×2000 (3:2) and the user has rotated 90°, "Original" locks to 2:3, not 3:2, since that's the
  actual displayed orientation at that point in the session
- Minimum crop size: 10×10px in source pixel space (same floor rationale as Resize/Blur) —
  smaller selections are rejected rather than silently clamped, since a near-invisible crop is
  almost certainly a user error, not intent

## Edge cases

| Case | Required behavior |
|---|---|
| User taps Apply with no rotation and full-bounds crop (no changes made) | Allowed — processes as a valid no-op, re-encodes the image unchanged |
| Crop rectangle dragged past the image edge | Clamp to image bounds live during the drag, same pattern as Blur's region clamping |
| Crop rectangle resized below the minimum size | Rejected on release with a brief inline message; drag doesn't finalize a too-small rect |
| User selects a locked aspect ratio that can't fit the current crop rectangle's position without going off-canvas | Recalculate the rectangle to the largest size that fits the locked ratio within the image bounds, centered — never let a locked-ratio rectangle exceed the image |
| Corrupted or unreadable image file selected | Reject at file-select time with a specific message, same pattern as other tools |
| Very high-resolution source image | Run rotation + crop off the UI thread (isolate/`compute()`); the crop/rotate pixel operation itself is typically fast, but stay consistent with the standing off-thread pattern for any real image-processing work |
| User rotates 4 times (back to 0°) | Treat as no net rotation, same "cycles back, don't count as a change" logic already established in Page Manager's rotation handling |

## Controller responsibilities (`image_crop_rotate_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImageCropRotateState>>` with:

- `loadImage(PlatformFile)` — validates format/readability, bakes in EXIF orientation, captures
  corrected source dimensions
- `rotate()` — advances rotation state 0→90→180→270→0, and resets the crop rectangle to the new
  orientation's full bounds per the functional requirement above
- `setCropRect(Rect rectInSourcePixelSpace)` — validates minimum size and clamps to bounds
- `setAspectRatioLock(AspectRatioPreset preset)` — enum: `free`, `square`, `fourThree`,
  `sixteenNine`, `threeTwo`, `original`; recalculates the current rect to fit, centered
- `apply()` — runs the rotation transform then the crop, in that order, **off the UI thread**
  (isolate/`compute()`, same standing pattern as the other image tools), writes output, emits
  success (with final dimensions) or a typed error

`ImageCropRotateState` should track: corrected source dimensions (post-EXIF), current rotation
(0/90/180/270), current crop rect (in the current orientation's pixel space), and active aspect
ratio lock — with a derived getter for the final output dimensions so the live readout and the
apply-time logic share one source of truth.

Write unit tests covering: rotate-cycle-back-to-zero (no net change), crop clamped to bounds,
minimum-crop-size rejection, aspect-ratio-lock recalculation fitting within bounds, rotation
resetting an existing crop rectangle, EXIF orientation bake-in on load, and final output dimension
correctness after a combined rotate + crop.

## Out of scope for this feature

- Arbitrary-angle "straighten" rotation (fine-grained, non-90° rotation to level a tilted horizon)
  — only 90° steps for v1, consistent with Page Manager's rotation model; straighten is a
  meaningfully bigger feature (canvas expansion/fill, interpolation quality concerns) and can be a
  fast-follow if requested
- Multiple independent crop regions — crop produces one final rectangular output, not several
  (that's conceptually closer to Blur's multi-region model, which doesn't apply here)
- Perspective correction / skew / keystone adjustment
- Format conversion — same boundary already established for the other image tools
