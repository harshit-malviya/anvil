# AGENTS_ARCHIVE.md — Anvil Context Archive

> Reference file for completed, stable features and closed bug investigations.
> Read this file ONLY when historical context on past decisions or diagnostic trails is specifically needed.

---

## PDF Merge Resource Deduplication & Instance-Aliasing Investigation (2026-08-07 — Session 29)

### Issue Summary
PDF Merge suffered from file bloat (~12x size expansion) when merging documents with shared background/logo assets due to Syncfusion's `createTemplate()` copying resource dictionaries per page. An initial deduplication pass caused silent page content destruction (pages rendering blank white and collapsing file size to 60KB).

### Diagnostic Trail & Confirming Production Log Evidence
- **Log Entry `log_1786161071854004_0001`**: Failure repro (spot-check merge of `संविधान सभा #1–3`, 1,946,879 bytes input collapsed to 69,803 bytes with blank pages).
- **Log Entry `log_1786164727587532_0001`**: Spot-check production merge after identity-guard fix (1,946,879 bytes input $\to$ 1,996,647 bytes output, 29 pages intact).
- **Log Entry `log_1786164799436190_0002`**: 5-file mega-merge production run after identity-guard fix (17,009,208 bytes input $\to$ 17,149,221 bytes output, 1.008x growth, 0 bloat).

### Technical Root Cause & Clarifications
1. **Syncfusion `_saveObjects()` Mechanics**: `PdfCrossTable._saveObjects()` performs a flat, linear array iteration over `objectCollection`. If `obj.isSkip == true`, it immediately skips serializing that `IPdfPrimitive` instance. No reachability graph traversal is performed.
2. **Instance Aliasing Bug**: `createTemplate()` caches cloned objects in `_clonedObject` on source `PdfStream` instances. When multiple pages share a source catalog/resource dictionary, `createTemplate()` re-uses the `identical()` same `PdfStream` Dart object instance across page template resource dictionaries.
3. **Mutated Canonical Instance**: Setting `dup.stream.isSkip = true` on what was assumed to be a duplicate stream copy mutated `canonical.isSkip` to `true` (since `identical(canonical, dup.stream)` was `true`), causing Syncfusion's `_saveObjects()` to suppress canonical streams from saving and rendering pages blank.
4. **Test 2 Clarification (`05 - Sources of Indian Constitution`)**: The 19 pages contain 19 unique page scan images (0 distinct duplicate images existed). The earlier 1.41 MB output on unguarded dedup was itself a symptom of the aliasing bug (aliased instances within each file were set `isSkip = true`, dropping pages). With the `identical()` guard in place, all 19 page scans are safely preserved at 2.62 MB without false deduplication.


### Resolution & Fix
- Added an unconditional hard identity guard `if (identical(canonical, dup.stream)) continue;` in `_deduplicateResources` (`lib/core/services/pdf_isolate_worker.dart`) before any repointing or `isSkip` mutation.
- Aliased in-memory instances shared across pages are preserved without mutation, while distinct duplicate stream instances across separate files are safely deduplicated.
- Verified on 174-page 16.27MB real bloat file (`merged_1786120641086.pdf`), reducing output size from 42.80MB (Dedup OFF) to 10.38MB (Dedup ON with Guard), saving 32.42MB while maintaining 100% per-page content integrity (174/174 pages non-blank).
