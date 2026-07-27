# Feature: PDF Password Protection (Add / Remove)

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_password/pdf_password_screen.dart`,
> `lib/tools/pdf_password/pdf_password_controller.dart`, plus registry + route entries.

## Scope boundary — read this first

This feature has two modes: **Add Password** and **Remove Password**. Remove Password requires
the user to type in the file's *existing, correct* password before anything happens — this tool
must never attempt to guess, brute-force, or otherwise bypass a password on a file the user
doesn't already have the password for. If the wrong password is entered, the operation fails with
a clear error and nothing about the file changes. This is a hard requirement, not a nice-to-have —
don't build any "remove protection without password" path, even as a hidden/debug option.

## User story

- "I want to add a password to a PDF before sending it somewhere sensitive."
- "I have a password-protected PDF and I know the password, but I'm tired of typing it every time
  — I want to remove the protection since I'm the one who set it (or I was given the password)."

## User flow

1. User taps "Password Protect PDF" tool card, picks a single PDF file
2. App detects whether the file is currently password-protected (attempt to read metadata without
   a password; if it requires one, treat as protected) and shows the matching mode automatically:

   **If file is NOT protected → Add Password mode:**
   - Password field + Confirm Password field (must match before "Protect" button enables)
   - Minimum password guidance shown as helper text (e.g. "Use at least 6 characters") — don't
     block on complexity rules beyond a basic minimum length, this isn't a security product,
     it's a convenience feature
   - "Protect" primary button

   **If file IS protected → Remove Password mode:**
   - Single password field: "Enter the current password to remove protection"
   - "Remove Protection" primary button, disabled until a password is typed
3. Processing state, then success (stamp) with Save As / Open Folder, consistent with other tools
4. Original file is never modified — output is always a new file (e.g. `document_protected.pdf`
   or `document_unprotected.pdf`)

## Functional requirements

- Add Password: encrypts the output PDF so opening it in any standard PDF viewer requires the
  password the user set
- Remove Password: only proceeds if the supplied password successfully decrypts the file; output
  is a fully unprotected copy
- Page content, order, and dimensions are completely unchanged by either operation — this is
  purely a protection-layer change, not a content operation
- Password is never logged, cached, or written to disk anywhere (not in `AGENTS.md`, not in debug
  logs, not in `shared_preferences`) — it exists only in memory for the duration of the operation

## Edge cases

| Case | Required behavior |
|---|---|
| Remove Password: wrong password entered | Clear error: "Incorrect password — the file wasn't changed." Allow retry, no artificial attempt limit needed for v1 (this isn't a security-hardened login system) |
| Add Password: passwords don't match in the two fields | Inline validation error before the button enables: "Passwords don't match" |
| Add Password: password field left too short | Inline validation: state the minimum clearly, don't let the button enable until met |
| File is already protected and user tries to add another password on top | Not applicable per the flow above — the app auto-detects and shows Remove mode instead. If for some reason detection is ambiguous, default to Remove mode and let the "wrong password" error path handle it rather than guessing |
| User picks a file that turns out to be corrupted (not a real PDF) | Reject at file-select time with a specific message, same pattern as other PDF tools |
| Empty file (0 pages) | Reject: "This file doesn't contain readable PDF content." |

## Controller responsibilities (`pdf_password_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PdfPasswordState>>` with:

- `loadDocument(PlatformFile)` — determines protected/unprotected status, sets mode accordingly
- `setPassword(String password)` / `setConfirmPassword(String password)` — Add mode
- `setRemovalPassword(String password)` — Remove mode
- `submit()` — runs the appropriate operation based on current mode; on Remove mode failure
  (wrong password), emits a typed error state without touching the file; on success, writes the
  new output file

Write unit tests covering: add-password happy path, mismatched-confirmation rejection, remove-
password with correct password (happy path), remove-password with incorrect password (must emit
error, must NOT produce any output file), and corrupted-file rejection at load time.

## Out of scope for this feature

- Setting granular permissions (disable printing, disable copying text, etc.) — this feature is
  only about the open-password (whether the file requires a password to view at all), not
  permission-level restrictions. Could be a future fast-follow if requested.
- Password strength meters or complexity enforcement beyond a basic minimum length
- Bulk password operations across multiple files at once
