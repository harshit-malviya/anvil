# Task: Fix PDF Merge Output Bloat from Duplicated Shared Resources

> Depends on: `PROJECT_OVERVIEW.md`, `AGENTS.md`, `FEATURE_pdf_merge.md` (read all first).
> This is a bug-fix task against the **already-shipped** PDF Merge feature — per `AGENTS.md`
> rule #6, do not re-spec or rewrite `pdf_merge_controller.dart` wholesale. Modify only what's
> needed to fix the behavior described below, and document any structural change in the
> Decisions Log per the usual process.

## Problem statement

PDF Merge is producing output files dramatically larger than expected when source PDFs contain
images/resources that repeat across multiple pages of the same source document (e.g. a fixed
logo or background graphic on every slide of a lecture-note-style PDF).

**Observed evidence (debug log + file inspection):**

| Merge | Pages | Output size | Bytes/page |
|---|---|---|---|
| Single-topic merges (e.g. संविधान सभा #1–3) | ~29 | ~1.99 MB | ~68 KB/page |
| Mega-merge combining 5 already-merged files | 174 | **149.8 MB** | **~861 KB/page** |

The mega-merge's per-page footprint is ~12x heavier than the *same underlying content* produced
by its own component merges. Inspecting the 150MB output's embedded images directly shows the
cause: within runs of consecutive pages that came from the same source document, the exact same
image bytes are embedded **once per page** rather than once per document. E.g. an 11-image
background/logo set appears identically across 11 consecutive pages instead of being stored once
and referenced 11 times.

## Root cause

`pdf_isolate_worker.dart`'s merge logic uses `sourcePage.createTemplate()` +
`destinationPage.graphics.drawPdfTemplate()` (decision logged 2026-07-27, originally adopted to
fix a page-cropping bug on non-A4/landscape pages — see Known Issues in `AGENTS.md`, still valid
and must not regress).

`createTemplate()` snapshots a page into a self-contained `PdfTemplate` with its **own private
resource dictionary**. When multiple pages in a source document reference the same image
XObject, each page's template captures an independent copy of that image rather than a shared
reference. Drawing N such templates into the output bakes in N copies of the same bytes instead
of N references to one shared object. This is invisible on small test fixtures (no repeated
large assets across pages) but compounds badly on documents where pages share background
graphics — and compounds *again* when merging already-merged output (re-templating content that
has already been re-templated once).

## Functional requirement

Merging documents whose pages share embedded resources (images, fonts) must not multiply the
size of those shared resources by page count. Output size should scale with the amount of
*distinct* content, not with (pages × shared-asset size).

The existing page-size/orientation-preservation fix (dedicated `PdfSection` per page, zero
margins, explicit page size/orientation matching) must be preserved — this task must not
reintroduce the cropping bug it originally fixed.

## Investigation / implementation approach

1. **First, check whether Syncfusion offers a page-level import method** (e.g.
   `PdfDocument.importPage` / `importPageRange`, if available in the Dart binding) that copies a
   page while preserving the source object graph, including shared XObjects, rather than
   flattening it into a private template. If such an API exists and can be combined with the
   existing per-page `PdfSection`/page-size logic, prefer it over `createTemplate()` +
   `drawPdfTemplate()`.
2. **If no such API exists** or it can't be reconciled with the section-per-page fix, implement a
   post-merge deduplication pass: hash each embedded image stream during/after assembly, and
   replace byte-identical duplicates with a shared indirect reference before writing final output.
3. Either way, verify the fix doesn't regress the divider-page feature (`TASK_pdf_merge_divider.md`)
   — divider images are already legitimately unique per divider, so no over-eager deduplication
   should merge visually-different dividers.
4. Leave a `// ASSUMPTION:` comment documenting which approach was taken and why, since the specific
   Syncfusion API surface for this isn't pinned by this spec.

## Edge cases

| Case | Required behavior |
|---|---|
| Source documents with no repeated resources across pages (typical case) | No behavior change, no size regression |
| Source document where every page shares one background image | Output stores that image once (or close to it), not once per page |
| Merging multiple already-merged files (compounding case from the bug report) | Output size scales with distinct content, not multiplicatively |
| Two source documents happen to embed byte-identical images independently (coincidental match, not a shared reference) | Fine to deduplicate — result is still visually and functionally identical, this isn't a correctness issue |
| Divider pages (from `TASK_pdf_merge_divider.md`) | Must remain visually distinct per divider; dedup must not corrupt legitimately different divider content |
| Non-A4 / landscape source pages | Must still render without cropping (regression check against the original fix) |

## Testing

- Add a new fixture: a small multi-page PDF (3–4 pages) where every page embeds the same image
  object, sized large enough (e.g. a few hundred KB) that duplication is easy to detect.
- Assert that merging this fixture alone produces output whose size is close to
  `single-image-size + small-per-page-overhead`, not `single-image-size × page-count`.
- Assert that merging two copies of the existing mixed-orientation fixture PDFs (already used for
  the page-size regression tests) still preserves page size and orientation — no regression.
- Assert divider-page tests (`test/tools/pdf_merge/pdf_merge_controller_test.dart`, divider
  section) still pass unmodified.
- Manually verify: re-run the exact merge sequence from the bug report (merge the 5 already-merged
  topic PDFs together with dividers enabled) and confirm output size lands in a sane range
  relative to input size, not an 8x+ blowup.

## Out of scope

- General PDF compression (image re-encoding, quality reduction) — that's `FEATURE_pdf_compress.md`'s
  job, not this task's. This is strictly about eliminating *accidental* duplication introduced by
  the merge process itself, not lossy size reduction.
- Deduplicating resources *across* unrelated source documents that don't already share a common
  reference in their original files (only applies within-document sharing being preserved, plus
  the safe cross-document dedup described in the edge case table above).
- Any change to divider page generation/rendering logic itself.
