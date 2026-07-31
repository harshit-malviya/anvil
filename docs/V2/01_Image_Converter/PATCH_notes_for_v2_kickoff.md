# Companion edits — apply before/during Sprint 1 Phase 1

These are small additive edits to existing project files, flagged during Image Convert scoping.
The project folder is read-only from Claude's side, so these are handed off as patch notes —
either you paste them in directly, or give this file to the Antigravity agent as its first task
in Sprint 1 Phase 1 ("apply these edits before starting implementation").

## 1. `PROJECT_OVERVIEW.md`

### §4 Repository / folder structure — add under `tools/`:

```
      image_convert/
        image_convert_screen.dart
        image_convert_controller.dart
```

(Same pattern as `pdf_merge/`, `pdf_page_manager/` — no structural changes needed elsewhere,
this just documents the new folder that Sprint 1 will create.)

### §7 Explicitly out of scope for v1 — update this line:

Old:
```
- Image tools (compress/resize/convert) — v2, separate spec doc will follow
```

New:
```
- Image tools (compress/resize/convert) — v2, see `PRD_image_tools_v2.md` and per-tool
  `FEATURE_image_*.md` files
```

## 2. `AGENTS.md`

### §4 Feature status tracker — update the placeholder row:

Old:
```
| Image tools (v2) | *(spec pending)* | Not started | |
```

New (split into per-tool rows, replacing the single placeholder):
```
| Image Format Convert | `FEATURE_image_convert.md` | Not started | Spec finalized, Sprint 1 |
| Image Resize | *(spec pending)* | Not started | Sprint 2 |
| Image Compress | *(spec pending)* | Not started | Sprint 3 |
```

### §1 What this repo is — no change needed, "image tools" is already mentioned generically.

### Optional: add a pointer near the top of §1 or §2:

```
> v2 image tools are sequenced via `PRD_image_tools_v2.md` — one sprint per tool, gated through
> Scope → Implement → Test → Debug → Audit. Read it before starting any `FEATURE_image_*.md`.
```
