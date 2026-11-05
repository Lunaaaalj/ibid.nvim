# ibid.nvim

Cite from your [Zotero](https://www.zotero.org) library inside Neovim, and keep each document's `.bib` equal to exactly the entries it cites.
It covers LaTeX, Markdown/Quarto/R Markdown (pandoc citations) and Typst.

- **Pick and cite.** A Telescope picker over the whole library (authors, year, title, key, tags), with a preview card.
  `<CR>` inserts a citation in the right syntax for the filetype and for where the cursor is.
- **Completion.** An nvim-cmp source for keys inside `\cite{…}`, after `@` and inside `#cite(<…>)`.
  Matching covers author and title words, so `@casella` finds `casella2002:statisticalinference`.
- **A managed `.bib`.** `:Ibid sync` writes the cited entries to the bibliography the document already declares, using Better BibTeX's exporter.
  The sync is incremental: Zotero only has to be running when a newly cited key appears.
- **Diagnostics** on cited keys that aren't in Zotero or in one of the document's own `.bib` files.
- **Hover** (hover.nvim) shows the Zotero card for the key under the cursor. There are also actions to open the PDF, show the item in Zotero, open the DOI, and yank the BibTeX entry or a formatted reference.

Nothing ever writes to Zotero's database. Reads come from a copy of `zotero.sqlite`; exports go through Better BibTeX.

## Requirements

- Neovim ≥ 0.10
- Zotero 7+ with [Better BibTeX](https://retorque.re/zotero-better-bibtex/). Keys come from BBT; it also writes the `.bib` entries.
- `sqlite3` and `curl`
- Optional: telescope.nvim (without it, `vim.ui.select`), nvim-cmp, hover.nvim

Run `:checkhealth ibid` to check the setup.

Profile discovery supports macOS, native Linux, Flatpak and Windows, using
`profiles.ini` defaults when available. Set `data_dir` explicitly to choose a
library. Relative linked attachments (`attachments:`) use the matching profile's
`extensions.zotero.baseAttachmentPath`; unresolved paths stay unavailable.
Group names appear in the picker and are searchable. Run `:Ibid reload` after
changing profile preferences.

On Linux, `:Ibid zotero` needs a desktop handler for `zotero://` URLs. If the
desktop cannot open that scheme, use `:Ibid key` and search for the key in Zotero,
or register Zotero as the scheme's handler in your desktop settings.

## Install

lazy.nvim:

```lua
{
  "Lunaaaalj/ibid.nvim",
  ft = { "tex", "markdown", "quarto", "rmd", "typst" },
  cmd = "Ibid",
  opts = {},
  keys = {
    { "<leader>Zc", function() require("ibid").cite() end, desc = "Zotero: cite" },
    { "<leader>Zs", function() require("ibid").sync() end, desc = "Zotero: sync the .bib" },
    { "<leader>Zi", function() require("ibid").info() end, desc = "Zotero: item card" },
  },
}
```

Completion and hover are opt-in in their own plugins:

```lua
-- nvim-cmp
cmp.register_source("ibid", require("ibid").cmp_source())
cmp.setup({ sources = { { name = "ibid" }, … } })

-- hover.nvim
require("hover").config({ providers = { "ibid.hover", … } })
```

## Citing

`:Ibid` (or `require("ibid").cite()`) opens the picker. In Telescope, `<Tab>` marks several items to cite together.
What `<CR>` inserts depends on where the cursor is:

| Where the cursor is | LaTeX | pandoc | Typst |
| --- | --- | --- | --- |
| plain text | `\cite{a,b}` | `[@a; @b]` | `@a @b` |
| inside `\cite{x, ` | `a,b` (comma added if needed) | | |
| right after `@` | | `a; @b` | `a @b` |
| inside `[@x, p. 3` | | `; @a; @b` | |

The outer format is configurable per filetype (`formats`), e.g. `\parencite{%s}` for biblatex.
`:Ibid cayw` uses Better BibTeX's own picker in the Zotero window instead.

Picker keys: `<C-y>` yank key · `<C-b>` yank BibTeX · `<C-r>` yank formatted reference (APA by default) · `<C-o>` open PDF · `<C-z>` show in Zotero.

`:Ibid browse` opens the library in a two-pane float. Switch Library,
Collections, Tags, Recent and Lint with `<Tab>`/`<S-Tab>` or `1`–`5`. Move with
`j`/`k`, use `<CR>` to enter a collection/tag and `<BS>` to return. `/` filters,
`i` cites into the previous document, `o` opens a PDF, `gz` selects in Zotero,
`gx` opens the DOI/URL, and `y`/`Y`/`R` yank the key/BibTeX/reference. `r` reloads,
`?` shows help, and `q`/`<Esc>` closes. The tab, filter and cursor survive closing.

In the citation picker, `<C-t>` cycles LaTeX commands; the choice is remembered
per filetype. The native picker offers a command-cycle menu entry.
`:Ibid replace` selects a replacement for the citation under the
cursor. Enable `insert_mapping = "<C-g>c"` for a buffer-local insert-mode trigger,
and `citation.locator = true` to prompt for a page/locator after selecting items.
Cancelling the prompt leaves the document unchanged. Lua callers can also use
`require("ibid").cite({ locator = "p. 12", command = "parencite" })`.
Replacement preserves existing simple commands and locators unless overridden;
complex multicites and per-key locator forms are refused.

## Literature notes and backlinks

Set `notes_dir` and run `:Ibid note` for the cited item under the cursor (or one
chosen from the picker). Notes contain metadata, the abstract, and annotations
grouped by colour with page references. Re-running appends unseen annotation IDs
and preserves existing writing. A loaded note buffer keeps its unsaved changes;
save it normally. `note_format = "typst"` creates `.typ` notes instead of Markdown.
Citation keys are encoded when necessary to keep filenames within `notes_dir`.

`:Ibid backlinks` lists actual citations in loaded documents and configured
`backlink_roots`. Searching roots requires `rg`; matches are checked by the
citation scanner. PDF hooks can receive a third options argument with `page` and
`attachment_zkey`; existing two-argument hooks remain compatible. Child-note and
annotation providers are available for the richer card/browser view planned in
the next wave.

## Syncing the `.bib`

The target is the bibliography the document declares:

- **LaTeX:** `\addbibresource{refs.bib}` (BibLaTeX entries) or `\bibliography{refs}` (BibTeX entries). If VimTeX is installed, it is read from VimTeX's main file.
- **pandoc:** `bibliography:` in the YAML front matter, else in `_quarto.yml`.
- **Typst:** `#bibliography("refs.bib")` or `#bibliography(("a.bib", "b.bib"))`.
- Otherwise the `bib.fallback(bufnr)` option, then `b:ibid_bib`.

`:Ibid sync` writes the cited entries to that file, sorted by key, after a header line that marks it as managed by ibid.
The rules:

- **Keys** come from the document project: Typst local includes/imports, Quarto
  book chapters, or LaTeX inputs/includes (using VimTeX when available).
- **Entries already in the file are kept**, unless Zotero modified the item after the file was written. So Zotero only needs to be running when a key is cited for the first time.
- **Entries no longer cited are removed** (`bib.prune`).
- **The file is only written when its content changes**, so latexmk and typst watchers don't rebuild for nothing.
- **Keys defined in the document's other, hand-written `.bib` files** are left alone.
- **Hand-written `.bib` files are never overwritten.** If the declared `.bib` exists and isn't managed, `:Ibid sync!` takes it over. The `!` also re-exports every entry.
- **Once a document has a managed `.bib`, every `:w` syncs it** (`bib.sync_on_save`).

LaTeX also reads `% !TEX root = main.tex`. For Typst and LaTeX, automatic root
lookup checks the current directory and up to four ancestors, stopping at the
repository or home boundary. Set `b:ibid_root` to the main document's path when
it is outside that range or several roots include the chapter. Paths are
relative to the chapter. Loaded buffers supply unsaved text. Missing sources or
unsupported project expressions stop sync instead of pruning an incomplete
set of citations. Quarto supports literal chapter lists, including nested parts.
Book-wide collection applies when the bibliography comes from `_quarto.yml`;
a chapter's own front matter bibliography keeps its scope local.

## Commands

| Command | Action |
| --- | --- |
| `:Ibid [cite]` | pick items and insert a citation |
| `:Ibid cayw` | cite through Better BibTeX's picker |
| `:Ibid sync[!]` | sync the managed `.bib` (`!`: re-export all, adopt a hand-written file) |
| `:Ibid info` · `pdf` · `zotero` · `url` | the item under the cursor (else a picker): card · open PDF · show in Zotero · DOI/URL |
| `:Ibid key` · `bibtex` · `reference` | yank the key · its BibTeX entry · a formatted reference |
| `:Ibid reload` | re-read the library |
| `:Ibid lint` | list metadata findings; `<CR>` selects the item in Zotero |
| `:Ibid browse` | open the library browser |
| `:Ibid replace` | replace the citation under the cursor |
| `:Ibid note` · `backlinks` | open a literature note · find citing documents |

## Configuration

`:Ibid lint` checks missing creators/year, unusual citation keys, likely swapped
names, missing article/conference DOIs, duplicate DOI or title/year, and PDF
attachments missing on disk. Swapped-name findings are heuristics, with the
reason included in each finding. Change metadata in Zotero and reload to check
again. Crossref lookup and adding items are planned separately.

Defaults (see `lua/ibid/config.lua`):

```lua
require("ibid").setup({
  data_dir = nil,          -- nil: Zotero's dataDir pref, else ~/Zotero
  port = 23119,
  filetypes = { "tex", "plaintex", "markdown", "quarto", "rmd", "typst" },
  formats = {              -- %s = keys joined by sep; `key` wraps each key
    tex = { "\\cite{%s}", sep = "," },
    markdown = { "[%s]", sep = "; ", key = "@%s" },
    typst = { "%s", sep = " ", key = "@%s" },
    -- or a function(keys, ft) returning the whole string
  },
  bib = {
    translator = "Better BibLaTeX",
    sync_on_save = true,
    prune = true,
    fallback = nil,        -- function(bufnr) -> path
  },
  diagnostics = true,
  lint = { max_key_length = 100 },
  notes_dir = nil,         -- set a directory to enable literature notes
  note_format = "markdown", -- or "typst"
  backlink_roots = {},     -- directories searched by ripgrep
  insert_mapping = false,  -- e.g. "<C-g>c"
  citation = {
    commands = { "cite", "parencite", "textcite", "autocite", "citeauthor" },
    command_key = "<C-t>", locator = false, completion_limit = 50,
  },
  style = "http://www.zotero.org/styles/apa",
  open_pdf = nil,          -- function(path, item, opts); nil = vim.ui.open
  keys = { yank_key = "<C-y>", yank_bibtex = "<C-b>", yank_reference = "<C-r>",
           open_pdf = "<C-o>", show_in_zotero = "<C-z>" },
})
```

Highlights (all `default` links): `IbidAuthor`, `IbidYear`, `IbidTitle`, `IbidKey`, `IbidMuted`, `IbidAccent`.
The `User IbidLibraryChanged` event fires after the library is re-read.

## How it reads Zotero

Zotero keeps `zotero.sqlite` locked and in WAL mode while it runs. ibid copies the database and its `-wal` file to a per-process cache directory and reads the copy with one `sqlite3` query that returns the library as a single JSON document.
It only re-reads when the database or WAL changes, which costs a `stat` per check. A library of a few hundred items loads in about 20 ms.
Exports, formatted references and CAYW go through Better BibTeX's JSON-RPC on `127.0.0.1:23119`.

## Development

Run the test suite with `nvim --headless -l tests/run.lua` (requires `sqlite3`).
Tests use disposable databases and stubbed Better BibTeX responses; Zotero is not
required. See [tests/README.md](tests/README.md) for coverage and timestamp behavior.
