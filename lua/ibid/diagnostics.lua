-- Warnings on cited keys that are neither in Zotero nor in one of the
-- document's hand-written .bib files. LaTeX buffers are always checked;
-- pandoc and Typst only when they declare a bibliography, so a README's
-- @mentions or a Typst @label from another file don't light up.

local config = require("ibid.config")
local library = require("ibid.library")
local scan = require("ibid.cite.scan")

local M = {}

M.ns = vim.api.nvim_create_namespace("ibid")

local function apply(buf, syntax, lib)
  local bibs = require("ibid.bib.detect").bibs(buf)
  if syntax ~= "tex" and #bibs == 0 then return vim.diagnostic.reset(M.ns, buf) end
  local sync = require("ibid.bib.sync")
  local foreign = {}
  for _, b in ipairs(bibs) do
    if not sync.is_managed(b.path) then
      for k in pairs(sync.keys_in(b.path)) do foreign[k] = true end
    end
  end
  local diags = {}
  for _, f in ipairs(scan.project_scan(buf)) do
    if not lib.by_key[f.key] and not foreign[f.key] then
      table.insert(diags, {
        lnum = f.lnum, col = f.col, end_lnum = f.end_lnum, end_col = f.end_col,
        severity = vim.diagnostic.severity.WARN, source = "ibid",
        message = ("'%s' isn't in Zotero"):format(f.key),
      })
    end
  end
  vim.diagnostic.set(M.ns, buf, diags)
end

-- get() only stats the database when nothing changed, so Zotero edits
-- (a key renamed, an item added) show up on the next refresh
function M.refresh(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local syntax = scan.syntax(vim.bo[buf].filetype)
  if not syntax or not config.options.diagnostics then return vim.diagnostic.reset(M.ns, buf) end
  library.get(function(err, lib)
    if err or not lib or not vim.api.nvim_buf_is_valid(buf) then return end
    apply(buf, syntax, lib)
  end)
end

local timers = {}
function M.schedule(buf, delay)
  if timers[buf] then timers[buf]:stop() else timers[buf] = vim.uv.new_timer() end
  timers[buf]:start(delay or 400, 0, vim.schedule_wrap(function()
    if timers[buf] then
      timers[buf]:close()
      timers[buf] = nil
    end
    M.refresh(buf)
  end))
end

function M.setup(group)
  local attached = {}
  local function attach(buf)
    if attached[buf] then return end
    attached[buf] = true
    vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "TextChanged", "BufWritePost" }, {
      group = group,
      buffer = buf,
      callback = function() M.schedule(buf) end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
      group = group, buffer = buf, once = true, callback = function() attached[buf] = nil end,
    })
    M.schedule(buf, 50)
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = config.options.filetypes,
    callback = function(ev) attach(ev.buf) end,
  })
  -- buffers opened before setup() ran (lazy-loading on `ft` runs setup
  -- inside the first buffer's FileType)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.tbl_contains(config.options.filetypes, vim.bo[b].filetype) then
      attach(b)
    end
  end
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "IbidLibraryChanged",
    callback = function()
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.tbl_contains(config.options.filetypes, vim.bo[b].filetype) then
          M.schedule(b, 50)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      if timers[ev.buf] then
        timers[ev.buf]:stop()
        timers[ev.buf]:close()
        timers[ev.buf] = nil
      end
    end,
  })
end

return M
