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
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

-- Zotero's data directory: the option, the profile's dataDir pref, ~/Zotero.
local data_dir
function M.data_dir()
  if M.options.data_dir then return vim.fs.normalize(M.options.data_dir) end
  if data_dir then return data_dir end
  local profiles = vim.fn.expand("~/Library/Application Support/Zotero/Profiles")
  if vim.fn.has("mac") == 0 then profiles = vim.fn.expand("~/.zotero/zotero") end
  for _, prefs in ipairs(vim.fn.glob(profiles .. "/*/prefs.js", false, true)) do
    for line in io.lines(prefs) do
      local dir = line:match('^user_pref%("extensions%.zotero%.dataDir", "(.-)"%);')
      if dir and vim.uv.fs_stat(dir .. "/zotero.sqlite") then
        data_dir = dir
        return dir
      end
    end
  end
  data_dir = vim.fn.expand("~/Zotero")
  return data_dir
end

return M
