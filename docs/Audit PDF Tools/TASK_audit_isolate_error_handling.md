# Task: Audit — Isolate Error Handling

> Depends on: `AGENTS.md` §2 Rule #7, `lib/core/services/pdf_isolate_worker.dart`.
> This is a **verification and hardening task**, not a new feature — no new UI, no new specs to
> follow. Fix what's found; don't redesign anything that's already correct.

## Why this task exists

Session 13 moved all Syncfusion PDF work into background isolates via `compute()` across every
controller at once. That's exactly the kind of sweeping refactor that can silently introduce a
regression: an isolate throwing an exception behaves differently from the same code throwing on
the main thread, and if the calling controller doesn't explicitly catch it, the failure mode can
be a stuck "Processing…" spinner, a raw uncaught-exception crash, or a red-screen debug error —
none of which match the app's "fail loudly and clearly with an actionable message" principle
(`PROJECT_OVERVIEW.md` §3.4).

This task checks that every isolate call in every tool degrades to a proper typed error state,
never a crash or a hang.

## Tools in scope (all controllers currently using `compute()`)

- PDF Merge (`isolateMergePdfs`)
- PDF Merge Dividers (shares the merge isolate path — verify divider-specific params are covered too)
- PDF Page Manager (`isolateArrangePages`)
- PDF Split (`isolateSplitPdf`)
- PDF Compress (`isolateCompressPdf`)
- PDF Password — Add (`isolateAddPassword`)
- PDF Password — Remove (`isolateRemovePassword`)
- PDF Insert Pages (`isolateInsertPages`)
- PDF Insert Image as Page (`isolateInsertImageAsPage`)
- Images to PDF (`isolateImagesToPdf`)

(Note: PDF to Image uses `pdfx` platform channels, not Syncfusion/`compute()` — confirmed
separately in Session 13's log. Include it in this audit anyway to double check its async error
path is equally solid, even though the mechanism differs.)

## What to verify, per tool

For **each** controller listed above:

1. **The `compute()` call site is wrapped in `try/catch`.** Dart's `compute()` rethrows any
   exception the isolate function throws back into the calling isolate — if that call isn't
   inside a `try/catch`, the exception propagates as an unhandled error. Confirm every call site
   catches it.
2. **The catch block maps to a typed error state**, not a generic fallback. It should emit the
   same class of specific, actionable message the tool's `FEATURE_*.md` edge-case table already
   defines for that failure (e.g. Compress's "output larger than original" message, Merge's
   "too large to process on this device" message) — the isolate boundary shouldn't cause these to
   degrade into a generic string.
3. **No partial/orphaned output file is left on disk** if the isolate fails mid-write. Confirm
   the write-then-verify or write-to-temp-then-rename pattern (whichever is in use) still holds
   across the isolate boundary — this was an explicit requirement in `FEATURE_pdf_merge.md` and
   `FEATURE_pdf_split.md` and should hold everywhere isolates now do the writing.
4. **Processing state always resolves** — never gets stuck. Confirm the `AsyncValue` state
   transitions out of loading in both the success and failure path; a bug here would show as a
   permanent spinner with no error, no crash, just silence.
5. **A simulated isolate-thrown exception is caught, not crashed.** Add or confirm a unit test per
   controller that injects/mocks a failure inside the isolate function (or calls the isolate
   function directly with input designed to throw) and asserts the controller's state ends in a
   typed error, not an unhandled exception bubbling out of the test.

## Specific known-risk scenarios to test explicitly

| Scenario | Expected behavior |
|---|---|
| A file passes initial validation (e.g. header check) but the isolate's deeper parse throws (e.g. subtly corrupted mid-file) | Typed error surfaced with a specific message, not a stack trace or generic crash |
| Disk fills up / permission denied *during* the isolate's write step (not before) | Same "[specific OS error]" message pattern as the main-thread version used to produce, no orphaned partial file |
| User navigates away from the screen while an isolate is running | The isolate's eventual result (success or failure) is safely discarded rather than trying to update a disposed provider/widget and throwing a "used after dispose" error |
| Isolate function itself has a bug causing a `null` or malformed return value | Controller doesn't crash on decoding the isolate's result — validate the shape before using it |

## Deliverable

- Fix any controller found not catching isolate exceptions correctly
- Add the missing unit test(s) for any tool that doesn't yet have isolate-failure coverage
- Update `AGENTS.md` §5 Decisions Log with what was found and fixed (or confirmed already correct)
- Update `AGENTS.md` §6 Known Issues if anything is found that can't be fixed immediately — don't
  silently leave a known gap unlogged
