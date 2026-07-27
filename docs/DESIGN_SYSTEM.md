# Anvil — Design System

> Implement this as `lib/core/theme/` (a `ThemeData` builder + constants file). Every screen must
> pull colors/type/spacing from here — no hardcoded hex values or font sizes in widget files.

## 1. Concept

Anvil takes raw, messy files and shapes them into what you need — the visual identity leans
into a **workshop / forge** metaphor: tools hung on a pegboard, work getting stamped as "done."
This is deliberately *not* the generic cream-background/serif-hero AI-app look, and *not* a
neon-on-black tech look. It should feel like a well-organized physical workshop: warm, sturdy,
a little tactile, zero clutter.

**Signature element:** when a job completes (merge done, pages deleted, etc.), the result is
marked with a **stamp interaction** — a circular mark that presses down onto the file card with a
short, weighty animation (scale + slight rotation + ink-transfer opacity fade), rather than a
generic checkmark toast. This is the one moment of flourish in the app — everything else stays quiet.

## 2. Color tokens

Named, not generic — use these exact roles:

| Token | Hex | Usage |
|---|---|---|
| `ink` | `#1E2226` | Primary text, icons (light mode) |
| `workshopGrey` | `#ECEAE4` | App background (light mode) — warm grey, not cream |
| `forgeBlack` | `#15171A` | App background (dark mode) |
| `paperCard` | `#F7F6F2` | Card/surface background (light mode) |
| `steelCard` | `#1F2327` | Card/surface background (dark mode) |
| `emberCopper` | `#B5502D` | Primary action color (buttons, active states, stamp mark) |
| `anvilTeal` | `#3A6B6B` | Secondary accent — links, secondary buttons, selected states |
| `sparkYellow` | `#E8B33D` | Warning / in-progress states only — used sparingly |
| `rustRed` | `#A63A2E` | Error states only |
| `pegGrey` | `#C7C4BC` | Borders, dividers, disabled states |

Dark mode: swap `workshopGrey`→`forgeBlack`, `paperCard`→`steelCard`, `ink`→`#EDEBE6`. Accent
colors (`emberCopper`, `anvilTeal`) stay the same in both modes for brand consistency, but raise
their luminance ~8% in dark mode so they don't look muddy.

**Do not use:** `#D97757` (or near-variants), warm cream `#F4F1EA` backgrounds paired with serif
display type, or near-black-with-neon-accent — these read as generic AI-generated defaults.

## 3. Typography

- **Display face** (screen titles, tool names on cards): **Space Grotesk** — has enough
  industrial/technical character for the workshop concept without being a cliché serif hero
- **Body face** (all body text, labels, buttons): **Inter**
- **Utility face** (file sizes, page counts, technical metadata like "2.4 MB" or "Page 3 of 12"):
  **IBM Plex Mono** — gives technical data a distinct, legible, monospaced treatment that visually
  separates "data about the file" from "instructions to the user"

Type scale (use consistently, don't introduce ad-hoc sizes):

| Style | Size | Weight | Face |
|---|---|---|---|
| `displayLarge` | 32 | 600 | Space Grotesk |
| `displayMedium` | 24 | 600 | Space Grotesk |
| `titleMedium` | 18 | 500 | Space Grotesk |
| `bodyLarge` | 16 | 400 | Inter |
| `bodyMedium` | 14 | 400 | Inter |
| `labelSmall` | 12 | 500 | Inter (uppercase, letter-spacing 0.5) |
| `mono` | 13 | 400 | IBM Plex Mono |

## 4. Spacing & shape

- Spacing scale (multiples of 4): 4, 8, 12, 16, 24, 32, 48, 64 — no arbitrary values
- Corner radius: **6px** across cards, buttons, inputs — sturdy, not soft/pill-shaped, not sharp
- Elevation: avoid heavy drop shadows. Use a 1px `pegGrey` border on light mode cards instead of
  shadow-based elevation — it reads as more workshop/tactile than floating glassy cards
- Icons: outline style (not filled), 1.5px stroke weight, consistent across all tool icons

## 5. Component patterns

**Tool Card** (home screen grid): icon in a 40x40 rounded square with `pegGrey` background,
tool name in `titleMedium`, one-line description in `bodyMedium` at 70% opacity. Entire card is
tappable, subtle `emberCopper` border appears on hover/focus (desktop) or press (mobile).

**File Drop Zone**: dashed 1.5px `pegGrey` border, centered icon + "Drop files here or click to
browse" in `bodyMedium`. On drag-over (Windows), border becomes solid `emberCopper` and background
tints 5% ember. This component is shared across all tools — build once in `core/widgets/`.

**Primary Button**: filled `emberCopper`, white text, 6px radius, 44px min height (touch target).
**Secondary Button**: outline `anvilTeal`, `anvilTeal` text.
**Destructive action** (e.g. "Delete page," "Remove file"): outline `rustRed`, `rustRed` text —
never filled red for destructive actions, filled is reserved for the primary path only.

**Progress/Processing state**: linear progress bar in `emberCopper` beneath the action button,
label above it states exactly what's happening ("Merging 3 files…" not "Processing…").

**Success state**: the stamp interaction described in §1, then a `bodyMedium` confirmation line
with the output filename and a "Save As" / "Open folder" pair of actions.

**Error state**: `rustRed` left-border card, bold one-line summary of what failed, a `bodyMedium`
plain-language explanation, and — where possible — a concrete next step ("This PDF appears
password-protected. Remove the password and try again.").

**Empty state** (no tools yet, or a list with nothing in it): friendly, direct, one action button
— never a bare "No items" text with nothing to do next.

## 6. Accessibility floor (non-negotiable, don't skip)

- All interactive elements have visible keyboard focus rings (`emberCopper`, 2px)
- Minimum contrast ratio 4.5:1 for body text against its background in both light and dark mode
- Respect system "reduce motion" setting — the stamp animation becomes a simple fade when reduce
  motion is on
- All icons paired with text labels or accessible semantic labels — never icon-only buttons
  without a tooltip/label
