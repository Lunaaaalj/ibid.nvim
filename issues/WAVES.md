# Multi-agent execution plan

Planning baseline: 2026-11-05. All eleven GitHub issues are open and match
the numbered backlog files in this directory. This plan schedules work;
it does not start implementation or close issues.

## Execution model

Use one coordinator plus up to three worker agents per wave (four concurrent
agents total). Starting with the next wave, each worker uses an isolated
branch/worktree based on the same accepted baseline, commits and pushes its own
changes, and opens its own pull request. The coordinator assigns file ownership,
reviews each PR's diff and checks, requests fixes from the owning agent, and
runs the combined checks before the next wave. Deliver work through PRs rather
than copying files from agent worktrees into the coordinator's checkout.
Integrate accepted PRs in dependency order under the session's merge authorization.
Unused worker slots can review completed work; three implementation lanes are
a ceiling, not a requirement.

The coordinator owns shared integration edits in `lua/ibid/init.lua`,
`plugin/ibid.lua`, configuration defaults, `README.md`, and `doc/ibid.txt`.
Workers describe proposed API/config/command changes in their PRs; the coordinator
implements shared wiring in a separate integration PR after the contracts settle. Assign
other shared files to exactly one worker within each wave. Feature tests live
beside each feature's fixtures; only the test-harness owner edits the runner.

Every assignment includes: issue/subtask, base commit, owned paths, API contract,
dependencies, acceptance cases, and explicit exclusions. Every handoff includes:
branch, worktree, commit, PR URL, changed paths, checks run and results, remaining limitations, and which
issue acceptance criteria are satisfied. A failing gate produces a repair pass
before downstream work begins.

## Wave 0 — Establish a reliable baseline

Wave 0 merged in PR #12. All 48 tests passed on Neovim 0.11.6, with a generated
SQLite fixture and deferred stubbed BBT exports. Stable and nightly CI both
passed in GitHub Actions run 42059650360. See `tests/README.md` for the
identical-re-export timestamp caveat. Database
tests cover WAL signatures, not concurrent live WAL replay. Production behavior
is unchanged.

| Worker | Assignment | Owned area |
| --- | --- | --- |
| A | #11: headless test runner, scan/insert/detect/entry-parser tests, stable + nightly CI | `tests/run.lua`, pure-unit tests, `.github/workflows/` |
| B | #11: generated SQLite fixture, query/normalisation tests, group and attachment cases | database fixture and library/source test files |
| C | #11: stubbed BBT sync tests for keep, update, prune, adoption, failed export, unchanged output | sync tests and BBT test fixtures |

Agree on the runner/test registration contract before parallel test writing.
Production fixes discovered by tests are assigned explicitly by the coordinator.
Keep tests independent of a real Zotero installation, user data, and network.

Gate: `nvim --headless -l tests/run.lua` passes locally and CI is configured;
CI results must be checked before treating #11 as complete. Pin down both output
content and filesystem timestamp expectations: current sync deliberately touches
mtime after an identical re-export, which may still trigger document watchers.
Record the intended behavior rather than silently enshrining it as correct.

## Wave 1 — Correctness and independent core features

Implemented locally on `feat/wave-1-core`: multi-file project discovery with
incomplete-project sync protection (#8), profile/attachment portability and group
picker identity (#10), and lint/identity providers plus `:Ibid lint` (#2).
The integrated suite has 80 passing tests on Neovim 0.11.6 (32 new cases).
Wave 1 remote CI and native Windows/Linux desktop smoke checks remain pending.
The lint browser tab depends on #1, and Crossref/add actions depend on #3;
those portions of #2 remain scheduled for later waves. Automatic root discovery
is bounded and can be overridden with `b:ibid_root`; Quarto chapter syntax is
limited to literal lists/parts. Unsupported discovery stops sync.

| Worker | Assignment | Owned area |
| --- | --- | --- |
| A | #8: shared project discovery for Typst, Quarto, and LaTeX without VimTeX; project-wide labels and citations | project module, `cite/scan.lua`, `bib/detect.lua`, `diagnostics.lua` |
| B | #10: profile discovery, linked attachments, group identity and picker display | profile helper, `library.lua`, `cite/picker.lua`, relevant health checks |
| C | #2: lint engine and quickfix presentation; shared DOI/title-year identity helper for duplicate checks | new lint and identity modules |

Coordinator integrates config/commands/docs. Treat swapped-name findings as
heuristics with explanations. The Crossref/add action remains a follow-up to #3.

Gate: syncing from any chapter preserves citations in sibling chapters; include
cycles terminate, missing sources are reported, loaded unsaved buffers are used,
and Typst labels in sibling files do not become citations. If discovery is
incomplete, pruning must not silently remove entries. Test profile precedence,
Windows absolute paths, linked attachment resolution, and group selection URLs.
Use platform fixtures; distinguish those from real OS smoke tests in reporting.
Lint must handle incomplete metadata and duplicate identities deterministically.

## Wave 2 — Build the browser's providers and citation UX

| Worker | Assignment | Owned area |
| --- | --- | --- |
| A | #5: annotation/child-note extraction, page-aware PDF actions, note generation and backlinks | `source/sqlite.lua`, `library.lua`, `actions.lua`, new notes/backlinks modules |
| B | #1: browser shell, list/detail layout, collection tree, tags/recent/lint tabs, persistent session state | new browser modules; consumes existing card without editing it |
| C | #9: command variants, insert-mode flow, locators, citation replacement, empty-query completion cap | `cite/insert.lua`, `cite/picker.lua`, `cite/cmp.lua`, citation-range helpers |

Freeze provider contracts before starting: annotation identity and page data,
child-note data, backlink hits, lint findings, and browser selection/citation
callbacks. Citation-range helpers must reuse the scanner's positional contract.
Browser and picker must share the same insertion API rather than duplicating it.

Gate: citation edits preserve surrounding text and correctly resume insert mode;
cancellation makes no edit. Note regeneration appends only unseen annotations
and preserves user writing. Existing two-argument `open_pdf` hooks still work.
Browser closes cleanly, restores focus, retains selection/filter state, and
handles empty libraries, resize, and missing optional dependencies. Provider
integration in the detail card is completed in wave 3, so #1 stays open here.

## Wave 3 — Integrate the browser and verify Zotero write APIs

| Worker | Assignment | Owned area |
| --- | --- | --- |
| A | Finish #1: notes, annotation counts, page actions, backlinks and lint integration | browser modules and `card.lua` |
| B | #3 investigation and shared connector implementation: verify import/collection behavior, metadata resolution, deduplication and bounded key polling | new connector/resolver/add modules |
| C | #7: BBT auto-export registration, discovery, sync ownership protection and project health display | `source/bbt.lua`, `bib/sync.lua`, `health.lua` |

For #3, first verify the candidate connector endpoints and collection targeting
against a disposable Zotero profile. The issue explicitly leaves this unresolved.
Do not assume a missing-argument response proves an API's full semantics. Share
verified request/response fixtures and an import contract for #4. Implement
identifier types incrementally, retaining the issue's full acceptance checklist.
Validate URL translation separately from DOI/arXiv/ISBN metadata resolution.

Gate: the complete browser consumes providers without duplicating their logic.
Auto-export files cannot be overwritten by either normal or forced ibid sync;
mixed managed/auto-export declarations select the appropriate behavior. Test
Zotero/BBT unavailable responses. Connector tests cover duplicates, cancellation,
collection targeting, partial failures, and a citation-key polling timeout.
No direct writes to Zotero databases. If endpoint verification fails, report
that lane's blocker and continue unrelated lanes; do not fabricate completion.

## Wave 4 — Finish ingestion and add source context

| Worker | Assignment | Owned area |
| --- | --- | --- |
| A | #4: BibTeX/RIS import, preview/dedup, old-to-new key reconciliation, optional source rewrite and managed-file adoption | new import/parser modules, using verified connector contract |
| B | #6: context API, full-text/cache access, Claude transport, summary caching and find-support ranking | new context/fulltext/Claude modules |
| C | Finish #3 and #2 integration: browser add action and diagnostic/Crossref actions; review ingestion edge cases | browser action adapter, diagnostics/action adapters |

If #3 needs more core implementation, finish that before starting dependent #4
work; parser work and #6 can proceed independently. `sync.entries()` only splits
BibTeX blocks today: metadata-aware deduplication and RIS need actual parsing,
not reuse of that function as though it provided DOI/title fields.

Coordinator owns final command argument handling: current `:Ibid` uses `nargs =
"?"`, so `add <id>` and `import [file]` need explicit dispatch/completion support.
For #6, freeze the context API contract first; keep host writing-review glue in
the host config as the issue requests. Source context must distinguish an
abstract, a full-text excerpt, and a generated summary. Cache by item identity,
modification time and relevant request inputs. Claude is opt-in and optional.

Gate: imports preview new/duplicate counts, support both formats, and cannot
silently rewrite source keys or adopt files. Test unmatched/ambiguous key mapping
and interrupted imports. AI tests use a stub executable; cover missing CLI,
timeout, malformed output, cache invalidation, and absent full text. Exercise a
real disposable-profile import flow before declaring ingestion complete.

## Wave 5 — Independent review and release readiness

| Worker | Assignment |
| --- | --- |
| A | Review project discovery, sync ownership, pruning, import reconciliation and asynchronous failure paths |
| B | Review browser/citation interaction and optional-plugin fallbacks; run UI smoke cases |
| C | Audit portability, command/config documentation, fixtures, and all eleven issue acceptance checklists |

Reviewers inspect work they did not primarily author. Coordinator assigns fixes
without overlapping ownership, reruns affected checks and the complete suite,
and checks stable/nightly results on the integrated commit. Exercise one full
flow: add/import → refresh library → lint/browser → cite → project sync →
annotations/note → source context. Use disposable data for write operations.

Gate: every issue criterion has implementation and verification evidence, or
an explicitly recorded remaining item. Do not close a broad issue because only
its first slice landed. Document actual platform coverage and remaining manual
checks. Publishing, merging PRs, and closing GitHub issues are separate execution
actions; this planning task makes no remote changes.

## Dependency summary

- #11 establishes the harness used by every later lane.
- #8 project discovery supports #5 backlinks and #1 citation locations.
- #10 attachment handling supports #2 missing-file lint and #5 PDF navigation.
- #2 supplies lint findings and a shared duplicate-identity helper.
- #5 supplies browser notes, annotations, and backlinks; #9 supplies insertion UX.
- #3 verifies the shared connector used by #4 and the add/Crossref actions.
- #7 establishes bibliography ownership rules that import/adoption must respect.
- #6 can proceed alongside ingestion after the library/provider contracts settle.

Recommended first execution: wave 0 only, then reassess the estimates and lane
boundaries using baseline test results. Later waves describe intended ordering,
not permission to skip their entry gates.
