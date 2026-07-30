# Task: Audit — Edge Case Fidelity vs. Original Specs

> This is a **verification task**, not a new feature — no new UI. Where a gap is found, fix it if
> it's a small, safe, spec-faithful fix; if it requires a judgment call, log it in
> `AGENTS.md` §6 Known Issues instead of guessing.
> Run this **after** `TASK_audit_isolate_error_handling.md`, since some of these edge cases are
> exactly the failure paths that task hardens.

## Why this task exists

Every `FEATURE_*.md` spec ships with an edge-case table describing exact required behavior. A
spec describes intent at the time it was written — it doesn't guarantee the implementation still
matches that intent today, especially after later cross-cutting refactors (e.g. the Session 13
isolate migration touched every tool at once). This task re-verifies each row against the current
codebase, not against memory of "this was done a few sessions ago."

## Method

For each tool below: open its edge-case table, and for every row confirm —
1. The specific code path exists that produces the specified behavior (not just "the tool doesn't
   crash" — the *exact* message/behavior described)
2. A unit test exercises that specific case (not just a happy-path test that happens to pass)
3. If either is missing, fix it now if straightforward; otherwise log it in Known Issues with the
   specific gap named

Do **not** re-verify basic happy-path functionality — that's assumed working since these are all
marked `Done`. This is specifically about the edge case rows.

## Tools and their edge-case tables to re-verify

| Tool | Spec file | Edge case count |
|---|---|---|
| PDF Merge | `FEATURE_pdf_merge.md` | 7 rows |
| PDF Page Manager | `FEATURE_pdf_page_manager.md` | 5 rows |
| PDF Split | `FEATURE_pdf_split.md` | 7 rows |
| PDF Compress | `FEATURE_pdf_compress.md` | 5 rows |
| PDF to Image | `FEATURE_pdf_to_image.md` | 6 rows |
| PDF Password | `FEATURE_pdf_password.md` | 6 rows |
| PDF Insert Pages | `docs/PHASE 3/FEATURE_pdf_insert_pages.md` | (per that spec's table) |
| PDF Insert Image as Page (v2) | `docs/PHASE 3/FEATURE_pdf_insert_image_as_page_v2.md` | (per that spec's table) |
| PDF Merge Dividers | `docs/PHASE 3/TASK_pdf_merge_divider.md` | (per that task's edge cases, if any) |
| Images to PDF | `FEATURE_images_to_pdf.md` | 8 rows |

## Extra attention areas (higher chance of drift)

These are cases most likely to have degraded silently during later refactors, so give them extra
scrutiny even if their unit test technically still passes:

- **Rollback-on-partial-failure** (PDF Split's "disk fills up on file 6 of 10" case) — confirm the
  rollback logic still runs correctly now that the write step is inside an isolate, since the
  original implementation predates the Session 13 isolate migration
- **Zero-pages-remaining guard** (Page Manager) — confirm the Apply button disable logic and the
  message still trigger correctly, not just that the underlying state calculation is correct
- **"Minimal reduction" and "output larger than original" variants** (Compress) — these are the
  two least-exercised success-adjacent paths in that tool; confirm both still produce their
  distinct messaging rather than collapsing into the generic success state
- **Wrong-password rejection produces zero output file** (Password, Remove mode) — this is a
  correctness-critical case (per that spec's hard requirement around never bypassing protection);
  explicitly confirm no output file is written on this path, don't just confirm the error message
  shows
- **Folder-name-collision handling** (PDF to Image's `_2` suffix, and check whether Images to PDF
  or any multi-file-output tool needs the same collision handling and currently has it)
- **Per-page failure skip-and-continue** (PDF to Image's "7 of 8 pages exported" case, Page
  Manager's broken-thumbnail-placeholder case) — confirm a single bad page still doesn't fail the
  whole batch

## Deliverable

- A pass/fail note against every edge-case row across all 10 tools (can be a checklist added to
  this file, committed alongside the fixes, or summarized directly in the Decisions Log — agent's
  choice, but it must be recorded somewhere durable, not just stated in a chat response)
- Fixes applied for any straightforward gaps found
- `AGENTS.md` §6 Known Issues updated for anything requiring a product decision before fixing
- `AGENTS.md` §5 Decisions Log updated summarizing what was checked and what (if anything) changed
