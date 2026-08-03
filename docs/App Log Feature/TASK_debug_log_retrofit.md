# Task: Retrofit Debug Logging into Shipped Tools

> Depends on: `FEATURE_debug_log.md` (implement that first — this task assumes
> `app_log_service.dart` already exists).
> This is an additive task per `AGENTS.md` rule: completed features are not re-specced, only
> modified. Do not rewrite any existing `FEATURE_*.md` or `TASK_*.md` doc — this file describes
> only the logging calls to add on top of each already-shipped controller.

## What this task does

Adds `AppLogService` calls (started / success / error) at the key lifecycle points of all 14
already-shipped tool controllers (per the Feature Status Tracker in `AGENTS.md`), so the hidden
debug log captures activity across the whole app from day one, not just tools built after the
logger existed.

No UI changes, no behavior changes to any existing feature — this is purely instrumentation.

## Tools to retrofit

**PDF tools (9):**

| Tool | Controller file | `tool` id to log |
|---|---|---|
| PDF Merge | `pdf_merge_controller.dart` | `pdf_merge` |
| PDF Page Manager | `pdf_page_manager_controller.dart` | `pdf_page_manager` |
| PDF Split | `pdf_split_controller.dart` | `pdf_split` |
| PDF Compress | `pdf_compress_controller.dart` | `pdf_compress` |
| PDF to Image | `pdf_to_image_controller.dart` | `pdf_to_image` |
| PDF Password | `pdf_password_controller.dart` | `pdf_password` |
| PDF Insert Pages | `pdf_insert_pages_controller.dart` | `pdf_insert_pages` |
| PDF Insert Image as Page | `pdf_insert_image_as_page_controller.dart` | `pdf_insert_image_as_page` |
| Images to PDF | `images_to_pdf_controller.dart` | `images_to_pdf` |

**Image tools (5):**

| Tool | Controller file | `tool` id to log |
|---|---|---|
| Image Format Convert | `image_convert_controller.dart` | `image_convert` |
| Image Resize | `image_resize_controller.dart` | `image_resize` |
| Image Compress | `image_compress_controller.dart` | `image_compress` |
| Image Blur (Redaction) | `image_blur_controller.dart` | `image_blur` |
| Image Crop & Rotate | `image_crop_rotate_controller.dart` | `image_crop_rotate` |

Note: PDF Merge's divider-page option (`TASK_pdf_merge_divider.md`) and Image Compress's
dimension-reduction fallback (`TASK_image_compress_dimension_fallback.md`) are both additive
behavior on top of the controllers above — no separate log wiring needed, they're covered by
instrumenting `pdf_merge_controller.dart` and `image_compress_controller.dart` once each.

## What to log per controller

For each controller, wrap the primary operation method (the one that does the actual file
write — `merge()`, `applyChanges()`, `split()`, `compress()`, `export()`, `submit()`, or
equivalent) with:

1. `logStarted(tool, action)` at the top of the method
2. `logSuccess(tool, action, message: ...)` on the success path, with a short summary (e.g.
   output filename, page count, before/after size — whatever's most useful for reproducing a
   bug, not the full result object)
3. `logError(tool, action, message: ..., errorDetail: ...)` on every error/catch path,
   including validation rejections (e.g. password-protected file rejected, overlapping ranges
   rejected) — these are exactly the cases most likely to generate a confusing bug report

**Also log `loadDocument()` / file-add rejections** across all 14 controllers — a password-
protected or corrupted file (PDF tools) or an unreadable/unsupported image (image tools) being
rejected at select-time is a common source of "why won't this work" reports and should show up
in the log even though it's not the final operation.

## Explicit reminder — do not log

- Password values, in `pdf_password_controller.dart` — the plaintext password must never appear
  in `message` or `errorDetail`, even in an error case like "wrong password." Log only
  `"incorrect password provided"`, never the value itself.
- Full file byte content anywhere.

## Verification

- Manually trigger each of the 14 tools' happy path and at least one failure path (e.g. add a
  password-protected file to Merge, or an unsupported image format to Image Convert), then open
  the hidden debug log (7 rapid taps on "OFFLINE WORKSHOP") and confirm entries appear with
  sensible messages and no leaked password values.
- No new automated tests are required for this task specifically (logging is a side effect, not
  core business logic), but do not let this instrumentation break any existing passing test
  across the 14 controllers' test suites — run the full existing suite after retrofitting and
  confirm all green (196 workspace tests as of the last recorded session in `AGENTS.md`).

## Out of scope for this task

- The debug log screen/service itself — that's `FEATURE_debug_log.md`
- Cross-cutting features that aren't a single tool controller (Tool Search, Storage Cleanup) —
  these don't perform user-facing file operations in the same sense and don't need debug log
  entries
- Any tool built after this task lands — those get logging calls baked in at implementation
  time per standing rule #9 in `AGENTS.md`, not backfilled again later
