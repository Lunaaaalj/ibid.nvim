-- Things to do with one item. Each takes a normalised item (library.lua).

local config = require("ibid.config")
local library = require("ibid.library")
local bbt = require("ibid.source.bbt")

local M = {}

local function notify(msg, level) vim.notify("ibid: " .. msg, level or vim.log.levels.INFO) end

local function yank(text, what)
  vim.fn.setreg('"', text)
  pcall(vim.fn.setreg, "+", text)
  notify("yanked " .. what)
end

function M.yank_key(it) yank(it.key, it.key) end

function M.yank_bibtex(it)
  bbt.export({ it.key }, config.options.bib.translator, function(err, text)
    if err then return notify(err, vim.log.levels.ERROR) end
    yank(vim.trim(text), "the entry for " .. it.key)
  end)
end

function M.yank_reference(it)
  bbt.bibliography({ it.key }, config.options.style, function(err, text)
    if err then return notify(err, vim.log.levels.ERROR) end
    yank(text, "the reference for " .. it.key)
  end)
end

function M.open_pdf(it, opts)
  opts = opts or {}
  local pdf = library.pdf(it, opts.attachment_zkey)
  if not pdf then return notify(it.key .. " has no PDF attachment on disk", vim.log.levels.WARN) end
  if config.options.open_pdf then return config.options.open_pdf(pdf, it, opts) end
  vim.ui.open(pdf)
end

function M.show_in_zotero(it) vim.ui.open(library.select_url(it)) end

function M.open_url(it)
  local url = it.doi and ("https://doi.org/" .. it.doi) or it.url
  if not url then return notify(it.key .. " has no DOI or URL", vim.log.levels.WARN) end
  vim.ui.open(url)
end

-- A floating card (markdown), closed with q / <Esc> / leaving it.
function M.info(it)
  local lines = require("ibid.card").lines(it, math.min(80, vim.o.columns - 8))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor", row = 1, col = 0, style = "minimal", border = "rounded",
    width = math.min(width + 2, vim.o.columns - 4), height = math.min(#lines, vim.o.lines - 6),
    title = " " .. it.key .. " ", title_pos = "center",
  })
  vim.wo[win].wrap = true
  vim.wo[win].conceallevel = 2
  for _, k in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", k, "<cmd>close<cr>", { buffer = buf, nowait = true })
  end
  vim.keymap.set("n", "gx", function() M.open_url(it) end, { buffer = buf, desc = "Open DOI/URL" })
  vim.keymap.set("n", "o", function() vim.cmd.close() M.open_pdf(it) end, { buffer = buf, desc = "Open PDF" })
  vim.keymap.set("n", "gz", function() M.show_in_zotero(it) end, { buffer = buf, desc = "Show in Zotero" })
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end })
end

return M
