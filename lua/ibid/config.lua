-- Defaults, merged with setup() opts into M.options.

local M = {}

M.defaults = {
  -- Zotero data directory (holds zotero.sqlite and storage/). nil = read
  -- `extensions.zotero.dataDir` from the Zotero profile, else ~/Zotero.
  data_dir = nil,
  -- Zotero's HTTP server (connector, Better BibTeX JSON-RPC, CAYW)
  port = 23119,
  -- ms before a request to Zotero is killed
  timeout = 8000,
  -- filetypes where citing, completion, diagnostics and hover apply
  filetypes = { "tex", "plaintex", "markdown", "quarto", "rmd", "typst" },
  -- citation inserted by the picker, per filetype; %s = the keys joined by
  -- `sep`. A function(keys, ft) may return the whole string instead.
  formats = {
    tex = { "\\cite{%s}", sep = "," },
    plaintex = { "\\cite{%s}", sep = "," },
    markdown = { "[%s]", sep = "; ", key = "@%s" },
    quarto = { "[%s]", sep = "; ", key = "@%s" },
    rmd = { "[%s]", sep = "; ", key = "@%s" },
    typst = { "%s", sep = " ", key = "@%s" },
  },
  -- managed bibliography files
  bib = {
    -- BBT translator used when the document doesn't imply one
    -- (\bibliography{} in LaTeX implies BibTeX, everything else BibLaTeX)
    translator = "Better BibLaTeX",
    -- sync the managed .bib on :w when the buffer already has one
    -- (the first sync, which creates the file, is always :Ibid sync)
    sync_on_save = true,
    -- drop entries that are no longer cited
    prune = true,
    -- function(bufnr) -> path|nil, used when the document declares no
    -- bibliography (no \addbibresource, front matter or #bibliography)
    fallback = nil,
  },
  -- warn about cited keys that are neither in Zotero nor in an unmanaged .bib
  diagnostics = true,
  -- library metadata checks (:Ibid lint)
  lint = { max_key_length = 100 },
  -- literature notes and source-document backlinks
  notes_dir = nil,
  note_format = "markdown",
  backlink_roots = {},
  citation = {
    commands = { "cite", "parencite", "textcite", "autocite", "citeauthor" },
    command_key = "<C-t>",
    locator = false,
    completion_limit = 50,
  },
  -- opt-in buffer-local insert-mode citation trigger, e.g. "<C-g>c"
  insert_mapping = false,
  -- CSL style for "yank formatted reference"
  style = "http://www.zotero.org/styles/apa",
  -- function(path, item) opening an attachment; nil = vim.ui.open
  open_pdf = nil,
  -- highlight overrides: { IbidKey = { link = "Constant" }, ... }
  highlights = {},
  -- picker keys (Telescope); set one to false to disable it
  keys = {
    yank_key = "<C-y>",
    yank_bibtex = "<C-b>",
    yank_reference = "<C-r>",
    open_pdf = "<C-o>",
    show_in_zotero = "<C-z>",
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  require("ibid.profile").invalidate()
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

-- Profile discovery also supplies linked-attachment preferences.
function M.data_dir()
  return require("ibid.profile").current(M.options.data_dir).data_dir
end

return M
