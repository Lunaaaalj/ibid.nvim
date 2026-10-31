# Test suite and CI

Labels: testing

The prototype was verified with headless scripts against a real library. Turn them into a suite that runs in CI.

- **Unit tests, no Zotero needed:**
  - `scan.scan_lines` (comments, fences, multicites, multi-line `\cite`, Quarto cross-refs, Typst labels, emails)
  - `insert.text` contexts
  - `detect.bibs` for each syntax
  - `sync.entries` parsing
- **Fixture database:** a tiny `zotero.sqlite` built from SQL, so the library query and normalisation run in CI.
- **Sync, with a stubbed BBT:** an `rpc` stub returning canned exports. Check the incremental rules: keep, re-export when the item's modified date is newer than the file, prune, and don't rewrite unchanged files.
- GitHub Actions: Neovim stable + nightly, `nvim --headless -l tests/run.lua`.
