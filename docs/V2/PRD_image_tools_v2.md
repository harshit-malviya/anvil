# PRD: Image Tools (v2)

> Read `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md`, and `AGENTS.md` first — this document sits
> above the individual `FEATURE_*.md` files and exists to sequence v2 work into sprints so the
> agent works on exactly one tool at a time, end-to-end, before touching the next.
> This file does not replace `FEATURE_*.md` docs — each tool still gets its own spec, written
> at the start of its sprint (see §4).

## 1. Purpose

v1 shipped nine PDF tools. v2 adds **image tools** to Anvil, using the same self-contained
screen+controller pattern and the same non-negotiable principles (offline, non-destructive,
fail loudly, no dark patterns — see `PROJECT_OVERVIEW.md` §3).

This PRD exists because image tools are being scoped and built as a *batch of related work*
across multiple sessions, and — unlike the PDF tools, which were built and stabilized one at a
time somewhat organically — we want an explicit sprint structure up front so nothing gets
half-implemented across tools simultaneously.

## 2. v2 tool set (in scope now)

Three tool cards, added to the home screen grid alongside the existing PDF tools:

| Tool | One-line job |
|---|---|
| **Image Format Convert** | Convert an image (or batch) from one format to another (e.g. PNG → JPEG) |
| **Image Resize** | Change an image's height/width (with aspect-ratio lock option) |
| **Image Compress** | Reduce file size of an image via quality/dimension reduction, with before/after comparison |

These three were the original v2 vision named in `PROJECT_OVERVIEW.md` §7 ("image tools —
compress/resize/convert") and match the "one card per tool" home screen pattern already
established for PDFs.

## 3. Backlog — named but explicitly NOT in v2

You named a longer-term roadmap. Recording it here so it isn't lost, but none of this is
scoped or built until a deliberate "start v3" decision is made:

| Future tool | Feasibility note |
|---|---|
| Blur Tool | Straightforward with the `image` package — good v3 candidate |
| Crop & Rotate | Straightforward, similar interaction pattern to PDF Page Manager's rotate |
| Background Remover | **Needs a segmentation ML model.** Conflicts with "fully offline, no bundled bloat" unless a small on-device model is deliberately chosen and its size/licensing is acceptable — needs its own feasibility spike before it's speccable |
| Collage | Multi-image layout/canvas tool — meaningfully bigger UI surface than the others, closer to the Photo Editor in complexity |
| Basic Photo Editor (text/shapes/elements + customization) | Largest scope item on the list by far — effectively its own mini-app (canvas, layers, undo/redo). Should probably be broken into its own multi-sprint PRD when it's picked up, not a single `FEATURE_*.md` |

**Do not build any of these during v2 sprints below.** If implementation work on Convert/Resize/
Compress surfaces a natural shared-service opportunity for one of these (e.g. a shared canvas
renderer), note it in that sprint's Decisions Log — don't build ahead of scope.

## 4. Sprint structure — how each tool gets built

Each of the 3 v2 tools is **one sprint**. A sprint has five phases, run in strict order. The
agent does not start phase *N+1* until phase *N*'s exit criteria are met, and does not start the
next tool's Sprint until the current tool's Audit phase is signed off. This mirrors and
formalizes `AGENTS.md` Rule #6 ("don't start a new FEATURE_*.md file's work until the previous
one is fully checked off").

### Phase 1 — Scope
- A `FEATURE_image_*.md` doc is written (or finalized, for Convert, which has a draft) for this
  tool only, following the same structure as existing `FEATURE_pdf_*.md` docs: user story, user
  flow, functional requirements, edge case table, controller responsibilities, out-of-scope list
- Any open technical assumptions (e.g. Convert's WebP-support question) are resolved or
  explicitly marked `// ASSUMPTION:` with a fallback
- **Exit criteria:** spec file exists in the project folder, human has reviewed it

### Phase 2 — Implementation
- Agent builds screen + controller pair per the spec, registry + route entries added
- Reuses shared services where they already exist; extracts a new shared service if 2+ tools
  need the same logic (mirroring the `pdf_thumbnail_service.dart` extraction pattern from v1)
- **Exit criteria:** feature builds and runs; manual smoke test of the primary happy path passes

### Phase 3 — Testing
- Unit tests written per `AGENTS.md` Rule #3 and the spec's "write unit tests covering..."
  section — happy path, empty/edge input, at least one realistic failure case
- **Exit criteria:** full test suite for this tool passes; edge case table in the spec is fully
  covered by a test or a documented manual-verification note

### Phase 4 — Debug
- Human manually verifies the feature in the running app (per established project habit — not
  just trusting green tests)
- Any bugs found are fixed and re-tested before moving on; this phase is not "fix the first bug
  and move on," it's "verify the feature is actually solid"
- **Exit criteria:** human confirms manual verification passed, no known open bugs for this tool

### Phase 5 — Audit
- Quick pass against the non-negotiables: offline-only, non-destructive, error states specific
  (not generic), design tokens used (no hardcoded colors/type), accessibility floor met
- `AGENTS.md` updated: Progress Log entry, Feature Status Tracker row flipped to `Done`,
  Decisions Log entry for any spec deviations, Known Issues updated if anything is deliberately
  deferred
- **Exit criteria:** `AGENTS.md` updated and human has signed off; only then does the next
  sprint's Phase 1 begin

## 5. Sprint order

| Sprint | Tool | Status |
|---|---|---|
| 1 | Image Format Convert | Not started |
| 2 | Image Resize | Not started |
| 3 | Image Compress | Not started |


## 6. Shared technical foundations (apply to all 3 tools)

- All three tools operate on the `image` package (pure Dart) per `PROJECT_OVERVIEW.md` §2 — no
  new native-dependency packages introduced without flagging it back to the human first, same
  bar as the Syncfusion license question in v1
- Expect a shared `image_io_service.dart` (load/decode/encode/write, format detection) to emerge
  by Sprint 2 at the latest, following the same "extract once 2+ tools need it" pattern as
  `pdf_thumbnail_service.dart` — don't force the extraction prematurely in Sprint 1 if only one
  tool needs it yet
- All three inherit the standing non-negotiables: never overwrite the original file, save-as by
  default, specific/actionable error states, no network calls
- Large image handling (very high resolution source images) should get the same "don't freeze
  the UI" treatment PDF tools gave large page counts — background/isolate processing per
  `AGENTS.md` Rule pattern (see PDF processing isolate rule)

## 7. Open questions / assumptions carried into Sprint 1

- **WebP encoding support in the `image` package** — unresolved from the earlier Convert draft.
  Must be verified (via package docs/source, not assumed) at the start of Sprint 1 Phase 1
  before the spec is finalized. Fallback if unsupported: drop WebP from the initial format list,
  note it as a future addition once a WebP-capable package is evaluated.
- **Companion edits to `PROJECT_OVERVIEW.md` and `AGENTS.md`** flagged during the earlier Convert
  draft (adding the image tools section, updating the repo structure example) are still pending
  and should be written as part of Sprint 1 Phase 1, since they're prerequisites for the agent
  understanding where image tool code lives.
