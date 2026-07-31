# Task: Visual Differentiation — PDF Tools vs. Image Tools

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> This is a standalone incremental task, not a rewrite of any shipped `FEATURE_*.md`. PDF tools
> are already shipped and stable — this task must not change their behavior or file structure,
> only their accent color wiring and their grouping on the home screen.
> Files touched: `lib/core/theme/` (token usage, no new hex values), `lib/tools/registry.dart`,
> `lib/home/home_screen.dart`, `lib/core/widgets/tool_card.dart`, and every existing
> `*_screen.dart` / `*_controller.dart` pair that currently hardcodes `emberCopper` as its
> primary/progress/stamp color (PDF Merge, Page Manager, Split, Compress, PDF to Image,
> Password). Also applies going forward to `FEATURE_image_convert.md` and the two remaining v2
> image tools.

## Why

Anvil's tool grid is growing (9 PDF tools shipped, image tools starting now). Users should be
able to tell PDF tools and image tools apart at a glance — before reading labels — the same way a
physical workshop pegboard groups wrenches on one hook and screwdrivers on another. This is purely
a categorization/theming task: no new features, no new screens, no new color hex values.

## Design decision

Use the **existing** `DESIGN_SYSTEM.md` token set — do not introduce new colors. Assign each tool
family its own accent from the palette that's already defined as an accent-tier token:

| Tool family | Accent token | Existing role (unchanged) |
|---|---|---|
| PDF tools | `emberCopper` (`#B5502D`) | Primary action color — already used by every shipped PDF tool, no visual change for existing tools |
| Image tools | `anvilTeal` (`#3A6B6B`) | Secondary accent — repurposed as the image-tools family color |

This is additive to §2 of `DESIGN_SYSTEM.md`, not a replacement — `anvilTeal` keeps its existing
use as a secondary/link color elsewhere; it's just *also* now the family accent for anything under
the Image Tools category.

**// ASSUMPTION:** Icon *stroke* color stays `ink` (light) / `#EDEBE6` (dark) for both families —
only backgrounds, borders, buttons, progress, and stamp color shift per-family. Keeping icon
strokes neutral avoids a second axis of contrast risk on top of the new tinted backgrounds. If
this reads as too subtle once implemented, flag back for a follow-up pass — don't unilaterally
add more color to icons without checking in.

## Scope of differentiation

### 1. Accent color (family-wide)

Everywhere a tool screen currently reads `AppColors.emberCopper` for its primary button, linear
progress bar, and stamp animation color, that reference becomes
`AppColors.familyAccent(category)` (see registry change below) instead of a hardcoded constant.
For PDF tools this resolves to the same `emberCopper` value as today — **zero visual change** for
shipped PDF tools, this is a wiring change so the same mistake (hardcoding) doesn't recur when the
next tool family is added after images.

Image tools (Format Convert, and the two upcoming ones) use `anvilTeal` for: primary button fill,
linear progress bar, stamp mark color, and focus/hover ring.

Destructive actions (`rustRed`) and warning states (`sparkYellow`) are global, not
family-specific — don't reassign these.

### 2. Tool Card icon background tint

Currently: icon in a 40×40 rounded square with flat `pegGrey` background (`DESIGN_SYSTEM.md` §5),
identical for every tool card.

New behavior: the 40×40 icon container background becomes the family accent color at **12%
opacity** over the card surface (`paperCard`/`steelCard`), instead of flat `pegGrey`. This makes
the category legible at rest, without waiting for hover/focus.

- PDF tool cards: `emberCopper` @ 12% opacity icon background
- Image tool cards: `anvilTeal` @ 12% opacity icon background
- Icon stroke itself: unchanged, still `ink`/`#EDEBE6`, 1.5px outline style
- Hover/focus border on the card: unchanged mechanic, just now uses the family accent instead of
  always `emberCopper` (so an image tool card hovers with a teal border, not copper)

`// ASSUMPTION:` 12% chosen to sit between the existing 5% drop-zone drag-over tint and full
saturation — enough to read as a color, not enough to threaten the 4.5:1 text contrast floor
against `ink`/`#EDEBE6` icon strokes. Verify contrast in the real build; adjust the single opacity
constant if a contrast check fails rather than special-casing per tool.

### 3. Home screen sections

`home_screen.dart` currently renders one flat grid from `registry.dart`. Change to two grouped
sections, in this fixed order:

1. **"PDF Tools"** section header (`labelSmall` style, uppercase, `pegGrey`-adjacent tone per
   existing label conventions) followed by its grid
2. **"Image Tools"** section header, same style, followed by its grid

Section header spacing: 24px above, 12px below, per the existing spacing scale — no new spacing
values. If a third category is ever added later, this pattern extends by adding another labeled
section in registry order; don't hardcode "two sections" in a way that blocks that.

`// ASSUMPTION:` Section order is PDF first (existing, larger tool count) then Image (newer,
growing) — matches the order features were built in. Flag back if a different order is preferred.

## Registry change (`lib/tools/registry.dart`)

Add a `ToolCategory` enum and a required `category` field per entry:

```dart
enum ToolCategory { pdf, image }
```

Each existing PDF tool entry gets `category: ToolCategory.pdf` added (metadata-only change, no
behavior change). Every new image tool entry (starting with Image Format Convert) must set
`category: ToolCategory.image` at registry entry time — same "not optional polish" principle
already established for the Tool Search keyword field.

Add a small resolver used by both the card widget and tool screens:

```dart
Color familyAccent(ToolCategory category) =>
    category == ToolCategory.pdf ? AppColors.emberCopper : AppColors.anvilTeal;
```

Place this alongside the existing color tokens in `lib/core/theme/`, not inline in a widget.

## Out of scope for this task

- Any new color hex values beyond what's already in `DESIGN_SYSTEM.md`
- Distinct icon *shapes* (circle vs. square, etc.) — container shape stays the 40×40 rounded
  square with 6px radius for both families, only the fill tint changes
- Distinct typography per category — type stack is global, unaffected
- Re-theming the stamp animation's motion/shape, only its color
- A third visual axis (e.g. category badges/pills on cards) — two cues (color + section grouping)
  is the deliberate ceiling for this pass; revisit only if user testing shows it's still not
  legible enough

## Companion edits needed (not written yet, flag for a follow-up session)

- `DESIGN_SYSTEM.md` §2 and §5: document the family-accent pattern and the 12% icon-tint rule
  above as the source of truth, once implemented and contrast-checked
- `AGENTS.md` Decisions Log: record the `emberCopper`→PDF / `anvilTeal`→Image assignment as a
  standing rule so it isn't re-litigated per future tool
- `FEATURE_image_convert.md`: no content change needed (it doesn't hardcode a color), but its
  implementation must pull `familyAccent(ToolCategory.image)` rather than any hardcoded value

## Testing

No new controller logic here, so no new unit test suite — this is a theming/widget-tree change.
Manually verify (per existing project convention of running the app, not just trusting tests):

- Every shipped PDF tool screen still renders identically to before (regression check)
- Image Format Convert's primary button, progress bar, and stamp render in `anvilTeal`
- Home screen shows two labeled sections in the correct order with correct per-card tinting
- Contrast check on the 12% icon tint in both light and dark mode
