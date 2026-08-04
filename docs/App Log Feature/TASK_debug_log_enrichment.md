# Task: Debug Log Enrichment — Rich Data + Modern Browsing UI

> Depends on: `FEATURE_debug_log.md` and `TASK_debug_log_retrofit.md` (already implemented and
> shipped — see `AGENTS.md`). This task upgrades both the data captured per operation and the
> hidden screen used to browse it. Still developer-only, still hidden behind the same 7-rapid-tap
> trigger on "OFFLINE WORKSHOP" — no change to discoverability.
>
> **Supersedes one note in `FEATURE_debug_log.md`:** that spec described the hidden screen as
> "intentionally undesigned/utilitarian." Ignore that line — this task replaces it with the
> modern browsing UI described below. A developer debugging a user's report deserves a good tool,
> not a plain list.

## Part 1 — Data model change: one entry per operation, not three log lines

**Current behavior:** `logStarted` / `logSuccess` / `logError` each append a separate log line,
so one operation produces up to 3 disconnected rows.

**New behavior:** one `LogEntry` per operation, created at start and **updated in place** as the
operation progresses, so start time, end time, duration, and outcome all live on a single row.

```dart
class LogEntry {
  final String id;                  // uuid, generated at logStarted()
  final String tool;                 // e.g. "pdf_merge", "image_compress"
  final String toolDisplayName;      // e.g. "PDF Merge" — for UI, avoids re-deriving from id
  final String action;               // e.g. "merge", "export", "load_document"
  final DateTime startTime;
  DateTime? endTime;
  int? get durationMs =>
      endTime == null ? null : endTime!.difference(startTime).inMilliseconds;
  LogStatus status;                  // running | completed | failed

  // File picker / input stage
  int? filePickerLoadTimeMs;         // time from picker invoked to files read+validated
  int? inputFileCount;
  int? inputFilesCombinedSizeBytes;

  // Output stage (only populated on completed)
  int? outputFileCount;
  int? outputFilesCombinedSizeBytes;

  // User-selected options for this run — free-form, tool-specific (see Part 2)
  Map<String, dynamic> parameters;

  // Failure detail (only populated on failed)
  LogFailureStage? failureStage;     // filePicker | validation | processing | isolateExecution | fileWrite | unknown
  String? errorMessage;              // short, human-readable
  String? errorDetail;               // full exception string / stack trace

  // Context
  final String platform;             // "windows" | "android"
}

enum LogStatus { running, completed, failed }
enum LogFailureStage { filePicker, validation, processing, isolateExecution, fileWrite, unknown }
```

### Service API change (`app_log_service.dart`)

- `String logStarted(String tool, String toolDisplayName, String action, {int? inputFileCount, int? inputFilesCombinedSizeBytes, int? filePickerLoadTimeMs, Map<String, dynamic>? parameters})`
  → creates the entry, returns its `id`. Controllers hold onto this id for the duration of the
  operation.
- `void logCompleted(String id, {int? outputFileCount, int? outputFilesCombinedSizeBytes, String? message})`
  → sets `endTime`, `status = completed`.
- `void logFailed(String id, {required LogFailureStage stage, required String errorMessage, String? errorDetail})`
  → sets `endTime`, `status = failed`.
- `void updateParameters(String id, Map<String, dynamic> parameters)` — optional convenience if a
  controller only knows final parameter values partway through (e.g. after validation), so it
  doesn't have to hold everything at `logStarted()` time.

**Migration note for the agent:** update all 14 controllers already wired per
`TASK_debug_log_retrofit.md` to hold the returned `id` from `logStarted` and pass it to
`logCompleted`/`logFailed` instead of calling three independent methods.

## Part 2 — What "parameters" means per tool

`parameters` is intentionally a loose `Map<String, dynamic>` since every tool has different
options — don't try to force one shared schema. Populate it with whatever the user configured
for that run. Examples (not exhaustive — the agent should include every user-facing option each
tool exposes):

| Tool | Example parameters |
|---|---|
| PDF Merge | `{fileOrder: [...], dividerPagesEnabled: true}` |
| PDF Page Manager | `{pagesDeleted: 2, pagesRotated: 3, reordered: true}` |
| PDF Split | `{mode: "equalParts", parts: 12}` or `{mode: "customRanges", ranges: "1-3,4-10"}` |
| PDF Compress | `{level: "high"}` |
| PDF to Image | `{format: "png", resolution: "medium", dpi: 150, pagesSelected: 8, pagesTotal: 10}` |
| PDF Password | `{mode: "add"}` — never include the password value itself |
| PDF Insert Pages | `{insertAfterPage: 4, pagesInserted: 2}` |
| PDF Insert Image as Page | `{imageCount: 3, insertionPoint: 5}` |
| Images to PDF | `{imageCount: 5}` |
| Image Format Convert | `{targetFormat: "webp", sourceFormat: "png"}` |
| Image Resize | `{mode: "percentage", value: 50}` or `{mode: "exact", width: 1920, height: 1080}` |
| Image Compress | `{mode: "qualityLevel", level: "medium"}` or `{mode: "targetSizeRange", minKb: 100, maxKb: 200}` |
| Image Blur | `{regionCount: 2, style: "pixelate"}` |
| Image Crop & Rotate | `{rotationDegrees: 90, cropApplied: true, straightenAngle: 3.5}` |

**Hard rule carried over unchanged:** never put a password value, or raw file bytes, into
`parameters`, `errorMessage`, or `errorDetail` — string values only, describing the *shape* of
the choice, never sensitive content.

## Part 3 — File picker timing & combined input size

Every controller's file-load path should measure:
- `filePickerLoadTimeMs`: wall-clock time from the moment the file picker (or drop-zone drop
  event) returns a file/list of files, to the moment those files are read off disk and validated
  (e.g. password-check, corruption-check) — this isolates "OS picker was slow" or "big file took
  a while to read" from the actual processing step
- `inputFilesCombinedSizeBytes`: sum of all input file sizes for that operation (e.g. all 3 PDFs
  being merged, or the single image being compressed)

These get passed into `logStarted()` once file loading completes, alongside `inputFileCount`.

## Part 4 — Failure stage tracking

Every catch block across every controller must classify which `LogFailureStage` it's in when
calling `logFailed()`, rather than one generic "error" bucket:

- `filePicker` — file selection itself failed (OS-level picker error)
- `validation` — file rejected at load time (password-protected, corrupted, unsupported format,
  invalid range input, etc.)
- `processing` — synchronous logic failure outside the isolate (e.g. a state calculation)
- `isolateExecution` — the `compute()` call itself threw (Syncfusion exception, image codec
  error, out-of-memory)
- `fileWrite` — output file write/save failed (disk full, permission denied)
- `unknown` — fallback only when none of the above clearly applies; treat frequent use of this
  bucket as a signal to add a more specific stage later

## Part 5 — Hidden screen redesign (`debug_log_screen.dart`)

Still reached only via 7 rapid taps on "OFFLINE WORKSHOP." Replace the plain list with:

**Top stat strip** (4 metric cards): total operations logged, success rate %, average duration,
and the tool with the most failures in the current log window. Computed client-side from the
current entry set — no separate aggregation storage needed.

**Filter/search bar:**
- Free-text search across tool name, action, and error message
- Tool filter (dropdown/chips, all 14 tools)
- Status filter: All / Completed / Failed
- (Optional, nice-to-have) date range if the log ever spans multiple days

**Entry list** — one row per operation, columns: status badge (green "Completed" / red
"Failed"), tool + action, start time (`mono`), duration (`mono`), input file count, combined
input size (`mono`, human-readable e.g. "14.2 MB"). Failed rows get a subtle red-tinted row
background so they're scannable at a glance without reading the badge text.

**Row expansion (tap to expand in place, not a separate screen):** reveals a detail panel below
the row showing:
- File picker load time
- Output file count/size (if completed)
- Full `parameters` map, rendered as readable key: value lines (not raw JSON dump) — pretty-print
  it, e.g. `mode: equalParts` / `parts: 12`, one per line
- If failed: failure stage, error message, and a monospace error-detail block (scrollable if long)
- A "Copy entry as JSON" button — copies the full structured entry (including raw `errorDetail`)
  to clipboard, for pasting into a GitHub issue

**Top bar actions** (unchanged from `FEATURE_debug_log.md`, still present): Copy to Clipboard
(now copies the currently filtered set), Share Log File, Clear Log (with confirm dialog).

**Visual direction:** this screen can break from the workshop/forge design language in
`DESIGN_SYSTEM.md` since it's developer-only tooling, not user-facing product surface — go for a
clean, dense, dark-friendly developer-console aesthetic: monospace for all timestamps/durations/
sizes, clear status color coding (green/red), generous but not wasteful spacing, no decorative
elements. Respect the system light/dark mode toggle already in the app rather than forcing one
mode. Virtualize the list (`ListView.builder`) since entry count can reach the retention cap.

## Part 6 — Retention

Raise the retention cap from 500 to **2,000 entries** given entries are now more valuable
individually (richer data per row) and the file remains lightweight (structured fields, no
verbose text dumps except `errorDetail`). Same drop-oldest-on-overflow behavior as before.

## Verification

- Trigger a happy-path and a failure-path run on at least 3 different tools (one PDF, one image,
  one that exercises `fileWrite` or `isolateExecution` failure if reproducible), then open the
  debug log and confirm: single row per operation (not 3), correct duration, correct file
  picker timing, correct parameters displayed, and — for the failure case — correct failure
  stage and no leaked sensitive values.
- Confirm existing 196+ workspace tests still pass; add unit tests for the new
  `logStarted`/`logCompleted`/`logFailed` id-correlation flow in `app_log_service_test.dart`.

## Out of scope for this task

- Any user-facing surfacing of this data (still fully hidden, dev-only)
- Persisting aggregate stats separately — the stat strip is computed live from current entries,
  not stored
- Remote log shipping — still fully local and manual export only
