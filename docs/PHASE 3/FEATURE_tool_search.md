# Feature: Tool Search

> Depends on: `PROJECT_OVERVIEW.md`, `DESIGN_SYSTEM.md` (read both first).
> Files to modify: `lib/tools/registry.dart` (add keyword metadata),
> `lib/home/home_screen.dart` (add search bar + filtering).
> Files to create: `lib/home/tool_search_controller.dart` (or equivalent local state holder — see
> below for why this doesn't need full Riverpod `AsyncValue` treatment).

## Why this isn't a `tools/` entry

Every other feature in this repo is a self-contained tool (screen + controller pair) reachable via
its own route. This one isn't a tool — it's part of the home shell itself, filtering the existing
tool grid in place. It lives in `lib/home/`, not `lib/tools/`, and there's no new route.

## User story

"There are enough tools now that scanning the whole grid to find the one I want is slower than
just typing what I'm trying to do."

## User flow

1. Home screen shows a **search bar** above the tool grid (below the app header)
2. As the user types, the grid filters **live, on every keystroke** — no submit/enter required
3. Matching is against three fields per tool (see Matching behavior below): title, keywords, and
   description
4. Non-matching tool cards are removed from the grid entirely (not greyed out) — the grid
   reflows to fill the space, same grid layout/card component as the unfiltered state
5. If no tools match, show the standard **Empty state** pattern from `DESIGN_SYSTEM.md` §5:
   a friendly one-line message ("No tools match '[query]'") — no action button needed here since
   the obvious next step is "clear the search," which the clear button already provides
6. A clear (×) button appears inside the search field once there's any input, resetting to the
   full unfiltered grid
7. Search state does not persist across app restarts — always starts empty on launch (this isn't
   a settings/preference, just transient UI state)

## Matching behavior

- **Case-insensitive substring match** — v1 does not need fuzzy/typo-tolerant matching (e.g.
  "compres" vs "compress"); keep this simple, don't pull in a fuzzy-search package for this
- Matches if the query is a substring of **any** of: the tool's title, any entry in its keyword
  list, or its description
- Query is trimmed of leading/trailing whitespace before matching; an empty/whitespace-only query
  shows the full unfiltered grid
- Matching multiple words: split the query on whitespace, and a tool matches if **all** words are
  found (each independently, anywhere across title/keywords/description) — e.g. "shrink pdf"
  should still match Compress even though "shrink" only appears in its keyword list and "pdf"
  only appears in its title/description
- Results are not scored/ranked for v1 — matching tools keep the same fixed grid order they have
  in the unfiltered view (registry order), not reordered by relevance

## Keyword metadata (registry changes)

Add a `keywords: List<String>` field to each tool's registry entry in
`lib/tools/registry.dart`. These are the "simple, daily-language" synonyms a user might type
instead of the tool's formal name — this list is the actual product content of this feature, not
an afterthought, so use this table as the v1 baseline (extend if a tool gains new keywords later,
but don't ship with fewer than this):

| Tool | Keywords to add |
|---|---|
| PDF Merge | combine, join, attach, put together, one file |
| PDF Page Manager | remove page, delete page, rotate, reorder, rearrange, sideways, upside down |
| PDF Split | separate, break apart, cut, divide, extract pages |
| PDF Compress | shrink, reduce size, smaller, make smaller, file size |
| PDF to Image | screenshot, jpg, png, picture, export as image, convert to picture |
| PDF Password | lock, unlock, protect, encrypt, secure, remove password |
| PDF Insert Pages | add pages, combine part, insert |
| PDF Insert Image as Page | add photo, add screenshot, missing page, add picture |

## Functional requirements

- Search bar and filtering logic must not touch any tool's own screen/controller — this is purely
  a home-screen presentation concern layered on top of the existing registry data
- No network calls, no persistence beyond in-memory session state — consistent with
  `PROJECT_OVERVIEW.md` §3 offline-first principles (this one hardly needs saying for a local
  string filter, but keep it explicit since every feature doc states it)
- Search bar follows `DESIGN_SYSTEM.md` component conventions: 6px corner radius, `pegGrey` border
  at rest, `emberCopper` border on focus, `bodyMedium` type for input text and placeholder
- Placeholder text: "Search tools..." in `bodyMedium` at 70% opacity, consistent with other
  secondary-text treatments in the design system

## Edge cases

| Case | Required behavior |
|---|---|
| Query matches zero tools | Empty state message: "No tools match '[query]'" with the search bar (and its clear button) still visible so the user can adjust without navigating away |
| Query is only whitespace | Treated as empty — show full unfiltered grid, don't show the zero-match empty state |
| User pastes a very long string | No special handling needed beyond normal text field truncation/scrolling — matching still runs against the full pasted string, just won't match anything if it's nonsense |
| New tool added to registry without a `keywords` entry | Treat as an empty list (matches on title/description only) — don't crash or throw on a missing/empty keywords field, but flag it as a gap: every registry PR adding a tool should also add keywords, per the table above being "part of the tool," not optional polish |
| Very fast typing/backspacing (rapid rebuilds) | Filtering is a synchronous, cheap string operation on an in-memory list (max ~10-20 tools for the foreseeable future) — no debounce needed, don't over-engineer this with async/streams |

## Implementation notes

- This is simple enough that it doesn't need a full `StateNotifier<AsyncValue<T>>` pattern like
  the tool controllers — a plain Riverpod `StateProvider<String>` (or `NotifierProvider` holding
  just the query string) for the query, with the filtered tool list derived via a simple
  `Provider` that reads the query and filters `ToolRegistry.tools`, is sufficient. There's no
  async work, no loading/error states — using `AsyncValue` here would be over-engineering a
  synchronous string filter
- Filtering logic (the matching rules above) should live in a small pure function
  (e.g. `List<ToolMetadata> filterTools(String query, List<ToolMetadata> tools)`) so it's testable
  without spinning up widgets

## Controller/logic responsibilities

Expose via a lightweight Riverpod provider (not a full `StateNotifier<AsyncValue<...>>`
controller, per Implementation notes above):

- `setQuery(String query)` — updates the current search query
- `clearQuery()` — resets to empty
- `filterTools(String query, List<ToolMetadata> tools)` — pure function implementing the matching
  rules above (all-words, case-insensitive substring, across title/keywords/description)

Write unit tests covering: empty query returns all tools, single-word match on title, single-word
match on a keyword-only term (e.g. "shrink" → Compress), single-word match on description-only
text, multi-word query requiring all words to match, whitespace-only query treated as empty,
query matching zero tools, and a tool with an empty/missing keywords list still matching on title.

## Out of scope for this feature

- Fuzzy/typo-tolerant matching or ranked/scored relevance ordering — plain substring matching,
  fixed registry order, for v1
- Search history or recent searches
- Voice search or any input method beyond the text field
- Filtering/searching within a tool's own screen (e.g. searching pages within Page Manager) —
  this is home-screen tool discovery only
