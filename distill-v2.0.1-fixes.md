# Distill v2.0.1 — Fix Punch-List

Three items found during the v2.0.0 release test pass. Item 1 is the real
one (a measured performance bug); items 2 and 3 are small verifications.
Keep the harness green throughout; add fixtures where noted.

---

## 1. Batch/preview/clear lag — main-thread SwiftUI overload

### Evidence (Time Profiler, Distill app, real workload)
- 95.9% of CPU time (34.74s of 36.22s) is on the **Main Thread**.
- Hangs instrument shows multiple **Severe Hang** bars at preview-select
  and clear.
- Heaviest stacks are all SwiftUI/AppKit view work:
  `closure in ViewGraph` (20.48s), `GraphHost.flushTransactions` (13.94s),
  `AG::Subgraph::update` (13.44s), `AG::Graph::invalidate` (9.30s),
  `-[NSView _removeFromSuperview]` (8.82s) and `_removePre...` (4.36s).

The `_removeFromSuperview` + AttributeGraph cost during **Clear**, and the
`GraphHost.flushTransactions` cost during **preview**, indicate the view
tree is far too heavy — consistent with the file-queue model holding each
file's full converted Markdown in memory and the preview re-rendering it on
the main actor.

### Symptoms reported by user
Lag specifically when (a) previewing a converted file and (b) clearing the
queue after converting a large batch.

### Fixes (in priority order)
1. **`QueuedFile` should hold the output file *path*, not its Markdown
   content.** Load Markdown lazily only when a file is selected for preview.
   This should make Clear near-instant (lightweight view tree to tear down)
   and cut memory sharply. Verify: after fix, clearing a large batch shows
   no Severe Hang.
2. **Render the preview off the main actor, and cap it.** Parse/render on a
   background task; for outputs over ~50 KB render a capped preview with a
   "Show full output" control. Verify: selecting a large converted file
   produces no `GraphHost.flushTransactions` spike / no hang.
3. **Confirm the file list uses a lazy container** (`List` or `LazyVStack`
   in a `ScrollView`), not an eager `VStack` that realizes every row. If
   it's eager, switch it — this alone reduces the view-graph weight a lot.
4. **Copy / auto-copy correctness guard:** now that the model no longer
   holds content, ensure the Copy button and the auto-copy-after-conversion
   path read the Markdown from the file (or a lazy accessor), not from a
   removed in-memory field. Don't let this fix silently break copy.

### Verification
- Re-run the Time Profiler on the same workload (big batch → preview large
  file → clear). Main Thread % should drop substantially and the Severe
  Hang bars should largely disappear. Keep the before/after numbers.
- Harness stays green; preview output for small files stays byte-identical.

---

## 2. CLI — spaces in filenames

`distill convert Ch25 textbook.pdf` was parsed as two arguments and failed
with "no such file" (twice). Confirm the CLI handles quoted paths
(`distill convert "Ch25 textbook.pdf"`) and paths with spaces passed as a
single argv entry. If quoted paths already work, no code change — just note
it in the README's CLI section. If even a single quoted arg with spaces
breaks, fix the argument handling. Add a fixture/test with a spaced
filename.

---

## 3. DOCX hyperlink text verification

`distill convert linktest.docx --stdout` emitted:
`[https://www.google.com/](https://www.google.com/)` — URL as both the link
text and the target. Determine whether this is correct (the source doc
literally had the bare URL as visible text) or a bug (the extractor is
falling back to the URL when real anchor text like "Google" exists). Test
with a DOCX whose hyperlink has distinct display text; the output should be
`[display text](url)`. Fix only if the anchor text is being dropped.

---

## Release
If item 1 lands cleanly, tag v2.0.1, regenerate the zip, update CHANGELOG
(performance fix headline), and it supersedes v2.0.0 as the published
release. Items 2–3 fold into the same tag.
