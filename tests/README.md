# Tests

Run from the repository root with Neovim and `sqlite3` installed:

```sh
nvim --headless -l tests/run.lua
```

The suite uses a small dependency-free runner, generated SQLite databases, and
stubbed Better BibTeX responses. It does not require Zotero, optional Neovim
plugins, or network access. Test data and Neovim cache/state are temporary; the
suite must never point at a personal Zotero profile.

Test modules return a list of `{ name = "description", run = function() ... end }`
cases. Shared assertions and temporary-directory helpers live in `tests/helpers.lua`.
The runner discovers `tests/unit/*_test.lua`, `tests/library_test.lua`, and
`tests/sync_test.lua`. Failures produce a nonzero exit status.

GitHub Actions runs the suite against Neovim stable and nightly. Local results
only establish compatibility with the locally installed version; inspect remote
CI results before closing issue #11.

## Timestamp behavior

An ordinary sync with unchanged entries preserves the bibliography's contents
and modification time. Currently, re-exporting an entry whose exported text is
identical still advances the file's modification time, to avoid re-exporting it
on every subsequent save. Tests characterize this existing behavior explicitly.
It can wake build watchers even though the contents did not change. Moving the
freshness marker outside the bibliography is a separate behavior change, not a
promise made by the baseline test suite.
