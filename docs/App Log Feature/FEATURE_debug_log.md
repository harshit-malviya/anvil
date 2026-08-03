# Feature: Debug Log (Developer-Only, Hidden)

> Depends on: `PROJECT_OVERVIEW.md`, `AGENTS.md` (read both first).
> Files to create: `lib/core/services/app_log_service.dart`,
> `lib/core/debug/debug_log_screen.dart`, plus a hidden route + tap-trigger wiring
> in `home_screen.dart`. This feature is NOT registered in `lib/tools/registry.dart` —
> it must never appear as a visible tool card.

## Purpose

A local, developer-facing diagnostic log of every tool operation (attempt, success, or
failure), used to reproduce bugs from user reports. This is **not** a user-facing feature —
there is no menu entry, no settings toggle, no mention of it anywhere in normal UI. It exists
purely so a user having a problem can be asked "tap X 7 times on the home screen, then share
the log with us."

This does not conflict with the "no telemetry" principle in `PROJECT_OVERVIEW.md` §3 — nothing
is ever transmitted automatically. The log stays on-device until the user explicitly shares it
via the OS share sheet, exactly like every other file output in this app.

## Entry point

- On the home screen, the **"OFFLINE WORKSHOP"** tagline text is wrapped in a `GestureDetector`
  that counts rapid taps.
- **7 taps within 3 seconds** opens the hidden `DebugLogScreen` via `go_router` (route not
  listed in any visible nav — push directly, e.g. `context.push('/debug-log')`).
  // ASSUMPTION: 7 taps / 3s window chosen to match the common "hidden developer menu" pattern
  (cf. Android's own Settings > About > tap Build Number) — low enough to be findable if told
  the number, high enough to never trigger by accident during normal use. Reset the tap counter
  if more than 3 seconds pass between taps.
- No visual feedback during the tap sequence (no counter shown, no toast) — the whole point is
  that it's not discoverable by observation.

## What gets logged

**Every tool operation, successes and errors alike.** One log entry per meaningful lifecycle
event:

- Operation started (tool id + action, e.g. "PDF Merge — merge started, 3 files")
- Operation succeeded (tool id + action + brief result, e.g. "PDF Merge — success — output:
  merged_20260803_1402.pdf")
- Operation failed (tool id + action + error type/message, e.g. "PDF Password — error — wrong
  password on remove")
- File-load rejections (e.g. password-protected file rejected at add-time) — these matter for
  bug reports too, not just terminal success/failure

Log entries are structured, not free-text dumps:

```
{
  timestamp: DateTime,      // local device time
  tool: String,             // e.g. "pdf_merge", "image_convert"
  action: String,           // e.g. "merge", "load_document", "export"
  result: LogResult,        // enum: started | success | error
  message: String,          // short human-readable summary
  errorDetail: String?,     // stack trace / exception string, only when result == error
}
```

## What must NEVER be logged (non-negotiable)

- **Passwords.** This repeats the hard rule already established in `FEATURE_pdf_password.md` —
  it applies globally to this logger, not just that one feature. No password value, in any
  form, at any log level, ever.
- **File contents.** Only filenames, page counts, sizes, and outcomes — never the bytes of a
  user's document or image.
- Full file paths are permitted in this log (unlike a user-facing history would be) since this
  screen is developer-only and the user must take an explicit action to share it — but the
  agent should still avoid logging anything beyond what's useful for reproducing a bug.

## Hidden screen (`debug_log_screen.dart`)

- Plain reverse-chronological list, `mono` type style, one line per entry (tap to expand
  `errorDetail` if present) — no fancy UI, this screen is intentionally undesigned/utilitarian
  and doesn't need to follow the tool-card visual polish elsewhere in the app
- Top bar actions:
  - **Copy to Clipboard** — copies the full visible log as plain text
  - **Share Log File** — uses `share_plus`, same pattern as every other file output, to let the
    user send the raw log file to wherever (e.g. attach to a GitHub issue)
  - **Clear Log** — destructive action, requires a confirm dialog ("Clear all N log entries?
    This can't be undone.") per the non-destructive-by-default principle
- No filtering/search for v1 — a plain scrollable list is enough; add filtering later only if
  it turns out to be needed

## Storage & retention

- Stored as a local file (e.g. JSON Lines, one entry per line) in the app's local storage
  directory (`path_provider`'s app-support directory) — not in a user-visible/user-chosen
  location, since this isn't a user-facing output
- Retention cap: keep the most recent **500 entries**, drop oldest on overflow.
  // ASSUMPTION: 500 entries chosen as a reasonable window to capture "what happened right
  before the bug" without the file growing unbounded — revisit if bug reports need more history
- Writes are append-only and must not block the UI thread — write asynchronously, and a failure
  to write a log entry must never crash or interrupt the actual tool operation it's describing
  (logging failures fail silently, they must never surface as user-facing errors)

## Service responsibilities (`app_log_service.dart`)

Expose a simple singleton-style service (wrapped in a Riverpod `Provider`) with:

- `logStarted(String tool, String action, {String? message})`
- `logSuccess(String tool, String action, {String? message})`
- `logError(String tool, String action, {required String message, String? errorDetail})`
- `getEntries() → List<LogEntry>` (most recent first)
- `clear()`
- `exportAsFile() → File` (writes current log to a shareable temp file for the Share action)

Every tool controller calls into this at the start, success, and error points of its primary
operations. This is the same shape of call across all controllers, so it should be trivial to
wire — see companion task doc `TASK_debug_log_retrofit.md` for retrofitting the already-shipped
PDF tools.

## Edge cases

| Case | Required behavior |
|---|---|
| Log write fails (disk full, permission issue) | Fail silently — never block or error the actual tool operation on a logging failure |
| User taps the trigger sequence but with >3s gaps | Counter resets, screen does not open |
| Log file grows past the 500-entry cap mid-session | Oldest entries drop automatically, no user action needed |
| Share Log File tapped with zero entries | Still allow it — share an (nearly) empty file rather than disabling the button; simplest behavior, avoids an extra empty-state to design for a dev-only screen |
| Clear Log tapped | Confirm dialog required before clearing — matches non-destructive-by-default principle |

## Out of scope for this feature

- Any user-facing surfacing of this log (no home-screen entry, no settings toggle) — if a
  user-facing activity history is wanted later, that's a separate future feature reusing the
  same underlying event stream, not this screen
- Remote log shipping / crash reporting services (e.g. Sentry) — stays fully local and manual,
  per the offline-first, no-telemetry principle
- Log levels / verbosity configuration — v1 logs everything, no filtering knobs
