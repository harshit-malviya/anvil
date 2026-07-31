# Feature: Image Format Convert

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, `PRD_image_tools_v2.md` (read all three
> first). This is Sprint 1 of the v2 Image Tools PRD.
> Files to create: `lib/tools/image_convert/image_convert_screen.dart`,
> `lib/tools/image_convert/image_convert_controller.dart`, plus a registry entry in
> `lib/tools/registry.dart` and a route in `lib/core/router.dart`.

## Confirmed technical constraint — read this first

The `image` package (current: 4.8.0) has **asymmetric WebP support**: it can *decode* WebP
(including animated WebP) but cannot *encode* it — WebP is read-only in this library. Verified
directly against the package's supported-formats list, not assumed.

This means:
- WebP **can** be a source/input format
- WebP **cannot** be offered as a target/output format in this feature
- No `// ASSUMPTION:` comment needed here — this is a confirmed library constraint, document it
  as a plain code comment (`// WebP encoding unsupported by package:image 4.8.0 — see pub.dev`)

## User story

"I have an image in one format and I need it in another — usually because something I'm
uploading it to only accepts specific formats, or I want a smaller/more compatible file type."

## User flow

1. User taps "Convert Image" tool card on the home screen
2. Screen shows an empty **File Drop Zone**, filtered to accepted input image types (drag-drop on
   Windows, picker on both platforms)
3. On file select: screen shows the source image thumbnail preview, detected format, dimensions,
   and file size (in `mono` style, consistent with PDF tools)
4. **Target format selector**: a set of pill/chip options —
   `PNG` / `JPEG` / `BMP` / `GIF` / `TIFF` — the source format's own chip is disabled (can't
   convert a format to itself; see edge cases)
5. If `JPEG` is selected as target: a quality slider appears (0–100, default 90), since JPEG is
   the only lossy target option
6. If the source image has transparency (PNG/GIF/BMP/TIFF with alpha) and `JPEG` is selected:
   inline note appears — "JPEG doesn't support transparency. Transparent areas will become
   white." (JPEG has no alpha channel; flattening is mandatory, not optional — see functional
   requirements)
7. Live summary: "Convert `photo.png` (2.4 MB) → JPEG"
8. "Convert" primary button triggers processing
9. Success state (stamp): shows output filename, before/after size if notably different, Save As
   / Open Folder actions — consistent with existing tool success patterns

## Functional requirements

- Original file is never modified — output is always a new file
- Default output filename: `<original_name>_converted.<ext>` in the same directory as the source,
  user can rename via Save As
- Output image dimensions are identical to the source — this feature does **not** resize (that's
  the separate Image Resize tool; don't duplicate that responsibility here)
- Transparency handling: converting a source with an alpha channel to a target format without
  alpha support (JPEG) flattens transparent pixels onto a **white background** —
  `// ASSUMPTION:` comment noting this choice, since the spec doesn't pin an exact color; white
  is the safest default and matches common converter behavior elsewhere
- Animated sources (animated GIF, animated WebP): only the **first frame** is used for
  conversion; animation is not preserved. This is a hard limitation of a single-image conversion
  tool, not a bug — communicate it clearly (see edge cases)
- EXIF/metadata: not guaranteed to be preserved across formats (the `image` package's metadata
  handling varies per format). Don't promise metadata preservation in any UI copy.

## Supported formats

| | Source (input) | Target (output) |
|---|---|---|
| PNG | ✅ | ✅ |
| JPEG | ✅ | ✅ |
| BMP | ✅ | ✅ |
| GIF | ✅ | ✅ |
| TIFF | ✅ | ✅ |
| WebP | ✅ (decode only) | ❌ not offered — package can't encode WebP |
| ICO, TGA, PVR, PSD, EXR, PNM | not offered as input in v1 UI — technically decodable/some encodable, but excluded to keep the format picker to common, everyday formats | — |

## Edge cases

| Case | Required behavior |
|---|---|
| Source format same as selected target | That target chip is disabled/unselectable with a tooltip: "Already this format" — don't allow a no-op conversion |
| Source file corrupted/unreadable | Reject at file-select time with a specific message, same pattern as PDF tools: "This file couldn't be read as an image." |
| Animated GIF/WebP source | Proceed using first frame only, but show an inline notice before conversion: "This is an animated image — only the first frame will be converted." Require the user to see this before the Convert button is enabled (not a blocking modal, just visible copy) |
| PNG/GIF/BMP/TIFF with transparency → JPEG target | Auto-flatten to white background per functional requirements; inline notice shown pre-conversion (see user flow step 6) |
| Very large source image (memory pressure) | Catch OOM-class exceptions, show: "This image is too large to convert on this device." — don't crash the app, same pattern as PDF Merge's large-file handling |
| Disk full / write permission denied at save time | "Couldn't save the file — [specific OS error]. Try a different location." |
| User picks a non-image file (wrong extension smuggled in, or truly unsupported format) | Reject at file-select time: "This file type isn't supported for conversion." |
| WebP source, no valid target available (theoretically all 5 targets are always valid since none of them is "WebP") | Not actually reachable — WebP is never a target option, so this case doesn't occur. No special handling needed. |

## Controller responsibilities (`image_convert_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<ImageConvertState>>` with:

- `loadImage(PlatformFile)` — decodes, detects source format, captures dimensions/size, detects
  alpha channel presence, detects animated-source flag
- `setTargetFormat(ImageOutputFormat format)` — enum: `png`, `jpeg`, `bmp`, `gif`, `tiff`
  (deliberately excludes webp — see constraint above)
- `setJpegQuality(int quality)` — only meaningful when target is `jpeg`; ignored otherwise
- `convert()` — runs the encode, flattens transparency onto white if needed, writes output file,
  emits success with output path/size or a typed error

`ImageConvertState` should track: source file info (format, dimensions, size, hasAlpha,
isAnimated), selected target format, JPEG quality (if applicable), and conversion result.

Write unit tests covering: PNG→JPEG with transparency flattening, PNG→BMP without transparency
concerns, same-format-selection prevention, corrupted file rejection at load, animated GIF
first-frame extraction, and a simulated large-file/OOM failure path.

## Out of scope for this feature

- Batch conversion of multiple images at once (consistent with the v1 single-file/single-job
  principle in `PROJECT_OVERVIEW.md` §7 — could be a v3 fast-follow if there's demand)
- Resizing during conversion (that's the Image Resize tool — don't duplicate it here)
- WebP as an output format (blocked by the `image` package's read-only WebP support; would
  require bundling a native encoder like `cwebp`, which conflicts with the "pure Dart, no native
  build dependency headaches" reasoning in `PROJECT_OVERVIEW.md` §2 — flag back to human if this
  becomes a hard requirement later)
- Preserving animation across formats (GIF↔WebP animated conversion, etc.)
- ICO, TGA, PVR, PSD, EXR, PNM as source or target — kept out of the v1 format picker to stay
  focused on common everyday formats; can be added later without restructuring the feature
- EXIF/metadata editing or guaranteed preservation
