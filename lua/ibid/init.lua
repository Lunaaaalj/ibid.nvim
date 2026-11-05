-- ibid.nvim: cite from Zotero and keep each document's .bib in sync.
--
--   require("ibid").setup({ ... })   -- see config.lua
--   require("ibid").cite()           -- pick items, insert a citation
--   require("ibid").sync()           -- write the cited entries to the .bib

local config = require("ibid.config")

local M = {}

local function notify(msg, level) vim.notify("ibid: " .. msg, level or vim.log.levels.INFO) end

function M.setup(opts)
  config.setup(opts)
  require("ibid.hl").setup()
  local group = vim.api.nvim_create_augroup("ibid", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = require("ibid.hl").setup })
  require("ibid.diagnostics").setup(group)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(ev)
      if not config.options.bib.sync_on_save then return end
      if not vim.tbl_contains(config.options.filetypes, vim.bo[ev.buf].filetype) then return end
      -- only a document that already has a managed .bib; creating one is :Ibid sync
      local sync = require("ibid.bib.sync")
      local bib = sync.target(ev.buf)
      if bib and sync.is_managed(bib.path) then sync.sync(ev.buf, { quiet = true }) end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function() require("ibid.source.sqlite").cleanup() end,
  })
end

-- cite({ keys? }) — insert a citation at the cursor: of `keys`, or of the
-- items picked (several with <Tab> in Telescope)
function M.cite(opts)
  opts = opts or {}
  local insert = require("ibid.cite.insert")
  local ctx = insert.capture()
  if opts.keys then return insert.insert(opts.keys, ctx) end
  require("ibid.cite.picker").pick({
    prompt = "Cite",
    on_select = function(items)
      insert.insert(vim.tbl_map(function(it) return it.key end, items), ctx)
    end,
  })
end

local cayw_format = { tex = "biblatex", pandoc = "pandoc", typst = "typst" }

-- cayw() — cite through Better BibTeX's own picker (the Zotero window)
function M.cayw()
  local insert = require("ibid.cite.insert")
  local ctx = insert.capture()
  local syntax = require("ibid.cite.scan").syntax(vim.bo[ctx.buf].filetype)
  require("ibid.source.bbt").cayw(cayw_format[syntax] or "pandoc", function(err, text)
    if err then return notify(err, vim.log.levels.ERROR) end
    if text ~= "" then insert.insert_text(text, ctx) end
  end)
end

-- sync({ force = re-export everything, adopt = take over a hand-written .bib })
function M.sync(opts)
  opts = opts or {}
  require("ibid.bib.sync").sync(0, { force = opts.force, adopt = opts.adopt })
end

-- The item under the cursor, else one picked; then fn(item).
function M.with_item(fn, prompt)
  local library = require("ibid.library")
  local key = require("ibid.cite.scan").key_at(0)
  library.get(function(err, lib)
    if err then return notify(err, vim.log.levels.ERROR) end
    local it = key and lib.by_key[key]
    if it then return fn(it) end
    if key then notify(("'%s' isn't in Zotero"):format(key), vim.log.levels.WARN) end
    require("ibid.cite.picker").pick({ prompt = prompt, on_select = function(items) fn(items[1]) end })
  end)
end

local function action(name, prompt)
  return function() M.with_item(require("ibid.actions")[name], prompt) end
end

M.info = action("info", "Item")
M.open_pdf = action("open_pdf", "Open PDF")
M.show_in_zotero = action("show_in_zotero", "Show in Zotero")
M.open_url = action("open_url", "Open DOI/URL")
M.yank_key = action("yank_key", "Yank key")
M.yank_bibtex = action("yank_bibtex", "Yank BibTeX")
M.yank_reference = action("yank_reference", "Yank reference")

-- Metadata findings; edits remain in Zotero.
function M.lint() return require("ibid.lint").open() end

-- reload() — re-read the library now
function M.reload()
  require("ibid.profile").invalidate()
  local library = require("ibid.library")
  library.invalidate()
  library.lib = nil
  os.remove(vim.fn.stdpath("cache") .. "/ibid/library.json")
  library.get(function(err, lib)
    if err then return notify(err, vim.log.levels.ERROR) end
    notify(("%d items"):format(#lib.items))
  end)
end

-- the nvim-cmp source: cmp.register_source("ibid", require("ibid").cmp_source())
function M.cmp_source() return require("ibid.cite.cmp").new() end

-- item(key) → the normalised item, if the library is loaded
function M.item(key) return require("ibid.library").item(key) end

return M
