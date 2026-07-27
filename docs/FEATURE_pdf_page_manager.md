# Feature: PDF Page Manager (Delete / Reorder / Rotate)

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to create: `lib/tools/pdf_page_manager/pdf_page_manager_screen.dart`,
> `lib/tools/pdf_page_manager/pdf_page_manager_controller.dart`, plus registry + route entries.

These three actions share one screen because they all operate on the same underlying model (a
list of pages the user can inspect and rearrange) — building three separate screens would
triplicate the UI for no user benefit.

## User story

"I have one PDF and I want to remove a couple of pages, put them in a different order, and fix
one page that's sideways — all before I do anything else with the file."

## User flow

1. User taps "Page Manager" tool card, picks a single PDF file (drop zone or picker, same pattern
   as Merge, but single-file only here)
2. Screen renders a **grid of page thumbnails**, one per page, in current document order, each
   labeled with its page number in `mono` style
3. Each thumbnail supports:
   - **Delete**: small × button on the thumbnail corner → page is marked for deletion (shown
     greyed out / struck through, not immediately removed from view — see below)
   - **Rotate**: rotate icon button on the thumbnail → rotates that page 90° clockwise per tap
     (repeated taps cycle 90/180/270/0)
   - **Reorder**: drag-and-drop the thumbnail to a new position in the grid
4. Deleted pages stay visible but visually marked (greyed/struck-through) with an "Undo" tap
   target on them, rather than vanishing instantly — this prevents accidental permanent removal
   before the user commits
5. A persistent bottom bar shows a running summary: "12 pages → 10 pages, 2 rotated" and an
   "Apply Changes" primary button
6. On Apply: Processing state, then success (stamp) with Save As / Open Folder, matching the
   Merge flow's success pattern for consistency
7. If the user navigates away without applying, prompt: "Discard unsaved changes?" — don't
   silently lose their arrangement

## Functional requirements

- Thumbnails must be generated from actual page content (not a generic page-icon placeholder) so
  the user can visually confirm which page is which — this matters most when pages look similar
- Original file is never modified until "Apply Changes" is tapped and a new output file is written
- Rotation is stored as a transform applied at export time, not applied destructively to the
  in-memory preview until the user commits
- Reordering, deleting, and rotating can all be combined in a single session before one Apply

## Edge cases

| Case | Required behavior |
|---|---|
| User deletes every page | Apply button disabled, message: "A PDF needs at least one page. Undo a deletion to continue." |
| Very high page count (100+) | Use lazy/virtualized thumbnail rendering (e.g. `GridView.builder`) — do not render all thumbnails eagerly, this will freeze the UI |
| Password-protected source file | Same rejection pattern as Merge: reject at file-select time with a specific message |
| User rotates a page 4 times | Cycles back to original orientation (0°) — treat this as "no change," don't count it in the "N rotated" summary if net rotation is 0 |
| Thumbnail generation fails for one page (corrupted page data) | Show a broken-page placeholder icon for that specific thumbnail with a small "Preview unavailable" label, but still allow delete/rotate/reorder on it — don't fail the whole screen for one bad page |

## Controller responsibilities (`pdf_page_manager_controller.dart`)

Expose via Riverpod `StateNotifier<AsyncValue<PageManagerState>>` with:

- `loadDocument(PlatformFile)` — validates + generates thumbnail data per page
- `togglePageDeleted(int pageIndex)`
- `rotatePage(int pageIndex)` — advances rotation state 0→90→180→270→0
- `reorderPage(int oldIndex, int newIndex)`
- `applyChanges()` — builds the new PDF from current (non-deleted, reordered, rotated) page state,
  writes output, emits success/error

`PageManagerState` should track pages as a list of value objects (`{originalIndex, rotation,
isDeleted}`) rather than mutating page order destructively, so "Undo" on a single deleted page is
trivial to implement.

Write unit tests covering: delete-then-undo, rotate-cycle-back-to-zero, reorder, and the
zero-pages-remaining guard.

## Out of scope for this feature

- Adding new pages / inserting blank pages
- Extracting selected pages as a separate output file (that's closer to "Split," a v1-fast-follow
  tool with its own future spec)
- Cropping or editing page content itself
