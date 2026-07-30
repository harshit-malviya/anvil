# Task: Audit — Error Message Consistency & Shared Validation Logic

> This is a **verification and light-refactor task**, not a new feature — no new UI beyond
> possibly tightening existing error copy. Run this **last**, after the isolate-handling and
> edge-case-fidelity audits, since fixes from those tasks may change which error paths exist.

## Why this task exists

`PROJECT_OVERVIEW.md` §3.4 is explicit: "fail loudly and clearly... never a silent failure or
generic 'Something went wrong.'" That's been honored spec-by-spec, but every spec was written and
implemented somewhat independently across 13 sessions — there's real risk of small inconsistencies
accumulating: a stray generic catch-all message, or password/corrupted-file detection logic that
was reimplemented slightly differently in each of the 9 tools that need it (every spec's edge-case
table says some version of "same rejection pattern as other PDF tools," which only holds if it's
actually one shared code path).

## Part 1 — Generic message sweep

Search the codebase for any user-facing error string that doesn't follow the DESIGN_SYSTEM.md §5
Error state pattern (bold one-line summary + plain-language explanation + concrete next step where
possible). Specifically flag anything resembling:

- "Something went wrong"
- "An error occurred"
- "Unknown error"
- Raw exception `toString()` output shown directly to the user without translation into
  plain language
- Any catch block that only logs (`print`/`debugPrint`) without setting a user-visible error state

Every one of these found should either be replaced with the specific message the tool's spec
defines for that case, or — if it's a genuinely unanticipated error type not covered by any spec —
given a clear, honest message (e.g. "This file couldn't be processed — [OS/library error]. Try a
different file.") rather than a vague placeholder.

## Part 2 — Shared validation logic de-duplication

Every one of these tools independently needs to detect "is this PDF password-protected" and/or
"is this file corrupted/unreadable":

- PDF Merge, PDF Page Manager, PDF Split, PDF Compress, PDF to Image, PDF Password (load step),
  PDF Insert Pages, PDF Insert Image as Page, PDF Merge Dividers

Confirm these all call **one shared function** (e.g. in `lib/core/services/`) rather than each
having its own copy of the exception-string-matching logic described in the original Decisions Log
entry ("Catches password protection via `PdfDocument(inputBytes: bytes)` exception string analysis
... 'encrypted' / 'password'"). If any tool has its own separate implementation of this check:

- Extract a single shared function (e.g. `PdfValidationService.checkProtectedOrCorrupted(bytes)`)
  returning a typed result (`valid` / `passwordProtected` / `corrupted`)
- Migrate every tool's load step to call it
- This matters beyond tidiness: if the detection logic ever needs a fix (e.g. a new Syncfusion
  version changes its exception message text), nine separate copies means nine separate places
  that can silently drift out of sync and start misclassifying files

## Part 3 — Disk write failure coverage

`FEATURE_pdf_merge.md` and `FEATURE_pdf_split.md` explicitly spec the "[specific OS error]"
message pattern for disk-full/permission-denied at save time. Other specs don't call this out
per-row, but the same failure class applies universally (writing a file can always fail on any
tool). Confirm:

- Every tool's final write step surfaces the actual OS error string, not a generic "couldn't save"
- This is tested somewhere for at least one representative tool per write pattern (single-file
  output vs. multi-file/folder output), not necessarily all 10 individually if the write logic is
  already shared

## Deliverable

- List of any generic messages found and fixed, with before/after text
- Confirmation (or a completed refactor) that password/corrupted detection is one shared function
  used by all applicable tools
- Confirmation that disk-write-failure messaging is consistent across single-file and
  multi-file/folder output patterns
- `AGENTS.md` §5 Decisions Log updated with what was consolidated/fixed
- `AGENTS.md` §6 Known Issues updated for anything intentionally deferred
