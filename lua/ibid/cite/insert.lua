-- Inserting citations. The text depends on where the cursor is:
--   inside \cite{…|          → the keys, comma-separated
--   right after @ (pandoc/Typst) → the key without its @
--   inside [@a; …| (pandoc)    → "; @key"
--   anywhere else              → the filetype's full format (config.formats)

local config = require("ibid.config")

local M = {}

-- Where the citation goes, captured before a picker steals focus. In normal
-- mode it goes after the cursor character, like `a`.
function M.capture()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  if not insert and #line > 0 then col = col + 1 + vim.str_utf_end(line, col + 1) end
  return { win = win, buf = buf, row = row - 1, col = math.min(col, #line), cursor_col = vim.api.nvim_win_get_cursor(win)[2], insert = insert,
    tick = vim.api.nvim_buf_get_changedtick(buf) }
end

local command_index = {}
local function formats(ft)
  local fmt = config.options.formats[ft] or config.options.formats.markdown
  if type(fmt) ~= "table" then return {} end
  local out, seen = {}, {}
  local function add(value) if not seen[value] then out[#out + 1], seen[value] = value, true end end
  for _, value in ipairs(fmt) do add(value) end
  for _, name in ipairs((config.options.citation or {}).commands or { "cite", "parencite", "textcite", "autocite", "citeauthor" }) do
    add("\\" .. name .. "{%s}")
  end
  return out
end
function M.cycle_command(ft)
  local list = formats(ft)
  command_index[ft] = (command_index[ft] or 1) % math.max(1, #list) + 1
  return list[command_index[ft]]
end
function M.command(ft) return formats(ft)[command_index[ft] or 1] end

local function full(keys, ft, opts)
  local fmt = config.options.formats[ft] or config.options.formats.markdown
  if type(fmt) == "function" then return fmt(keys, ft) end
  opts = opts or {}
  local each = vim.tbl_map(function(k) return fmt.key and fmt.key:format(k) or k end, keys)
  local syntax = require("ibid.cite.scan").syntax(ft)
  local pattern = fmt[1]
  if syntax == "tex" then
    pattern = opts.command and ("\\" .. opts.command .. "{%s}") or M.command(ft) or pattern
    if opts.locator and opts.locator ~= "" then
      local prefix, suffix = pattern:match("^(.-){(.*)$")
      if prefix then pattern = prefix .. "[" .. tostring(opts.locator):gsub("%%", "%%%%") .. "]{" .. suffix end
    end
  elseif opts.locator and opts.locator ~= "" then
    if syntax == "pandoc" then
      each[#each] = each[#each] .. ", " .. opts.locator
    elseif syntax == "typst" then each[#each] = each[#each] .. "[" .. opts.locator .. "]" end
  end
  return pattern:format(table.concat(each, fmt.sep or ","))
end

-- text(keys, ft, before) → string to insert after `before` (the line up to
-- the insertion point)
function M.text(keys, ft, before, opts)
  opts = opts or {}
  if opts.replace then return full(keys, ft, opts) end
  local syntax = require("ibid.cite.scan").syntax(ft)
  if syntax == "tex" then
    local inner = before:match("\\%a*[Cc]ite%a*%*?[^\\{}]*{([^}]*)$")
    if inner then
      if opts.locator and opts.locator ~= "" then return nil, "use citation replacement to add a locator inside an existing LaTeX citation" end
      local sep = (inner:match("^%s*$") or inner:match(",%s*$")) and "" or ","
      return sep .. table.concat(keys, ",")
    end
  elseif syntax == "pandoc" or syntax == "typst" then
    local joiner = syntax == "pandoc" and "; @" or " @"
    local suffix = ""
    if opts.locator and opts.locator ~= "" then suffix = syntax == "typst" and ("[" .. opts.locator .. "]") or (", " .. opts.locator) end
    if before:match("@$") then return table.concat(keys, joiner) .. suffix end
    if syntax == "pandoc" and before:match("%[[^%]]*@[^%]]*$") then
      return "; @" .. table.concat(keys, "; @") .. suffix
    end
  end
  return full(keys, ft, opts)
end

-- insert(keys, ctx?) inserts a citation of `keys` at ctx (from capture())
-- or the cursor.
function M.insert(keys, ctx, opts)
  if #keys == 0 then return end
  M.insert_text(function(ft, before) return M.text(keys, ft, before, vim.tbl_extend("force", opts or {}, { replace = ctx and ctx.range ~= nil })) end, ctx)
end

-- insert_text(text | function(ft, before) -> text, ctx?)
function M.insert_text(text, ctx)
  ctx = ctx or M.capture()
  if not vim.api.nvim_buf_is_valid(ctx.buf) or not vim.bo[ctx.buf].modifiable then return end
  if not vim.api.nvim_win_is_valid(ctx.win) or vim.api.nvim_win_get_buf(ctx.win) ~= ctx.buf then return end
  if ctx.tick and vim.api.nvim_buf_get_changedtick(ctx.buf) ~= ctx.tick then
    return vim.notify("ibid: document changed while choosing a citation; try again", vim.log.levels.WARN)
  end
  if ctx.row >= vim.api.nvim_buf_line_count(ctx.buf) then return end
  local line = vim.api.nvim_buf_get_lines(ctx.buf, ctx.row, ctx.row + 1, false)[1] or ""
  local col = math.min(ctx.col, #line)
  if type(text) == "function" then
    local err
    text, err = text(vim.bo[ctx.buf].filetype, line:sub(1, col))
    if not text then return vim.notify("ibid: " .. (err or "cannot format citation"), vim.log.levels.WARN) end
  end
  if text:find("[\r\n]") then return vim.notify("ibid: citation text must fit on one line", vim.log.levels.WARN) end
  local range = ctx.range
  local sr, sc, er, ec = ctx.row, col, ctx.row, col
  if range then
    sr, sc, er, ec = range.row, range.col, range.end_row, range.end_col
    local current = table.concat(vim.api.nvim_buf_get_text(ctx.buf, sr, sc, er, ec, {}), "\n")
    if current ~= range.text then return end
  end
  vim.api.nvim_buf_set_text(ctx.buf, sr, sc, er, ec, { text })
  ctx.row, col = sr, sc
  if not vim.api.nvim_win_is_valid(ctx.win) then return end
  vim.api.nvim_set_current_win(ctx.win)
  local after = col + #text
  line = vim.api.nvim_buf_get_lines(ctx.buf, ctx.row, ctx.row + 1, false)[1] or ""
  if ctx.insert then
    -- back to insert mode after the citation
    if after >= #line then
      vim.cmd("startinsert!")
    else
      vim.api.nvim_win_set_cursor(ctx.win, { ctx.row + 1, after })
      vim.cmd("startinsert")
    end
  else
    vim.api.nvim_win_set_cursor(ctx.win, { ctx.row + 1, math.max(after - 1, 0) })
  end
end

-- Shared browser/picker path. Cancelling an optional locator leaves the text alone.
function M.choose(keys, ctx, opts)
  ctx = ctx or M.capture()
  opts = vim.tbl_extend("force", {}, opts or {})
  if opts.locator == nil then opts.locator = (config.options.citation or {}).locator end
  if opts.locator == true then
    vim.ui.input({ prompt = "Citation locator (e.g. p. 12): " }, function(value)
      if value == nil then return end
      opts.locator = value
      M.insert(keys, ctx, opts)
    end)
  else M.insert(keys, ctx, opts) end
end

return M
