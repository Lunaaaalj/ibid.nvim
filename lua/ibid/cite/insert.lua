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
  return { win = win, buf = buf, row = row - 1, col = math.min(col, #line), insert = insert }
end

local function full(keys, ft)
  local fmt = config.options.formats[ft] or config.options.formats.markdown
  if type(fmt) == "function" then return fmt(keys, ft) end
  local each = vim.tbl_map(function(k) return fmt.key and fmt.key:format(k) or k end, keys)
  return fmt[1]:format(table.concat(each, fmt.sep or ","))
end

-- text(keys, ft, before) → string to insert after `before` (the line up to
-- the insertion point)
function M.text(keys, ft, before)
  local syntax = require("ibid.cite.scan").syntax(ft)
  if syntax == "tex" then
    local inner = before:match("\\%a*[Cc]ite%a*%*?[^\\{}]*{([^}]*)$")
    if inner then
      local sep = (inner:match("^%s*$") or inner:match(",%s*$")) and "" or ","
      return sep .. table.concat(keys, ",")
    end
  elseif syntax == "pandoc" or syntax == "typst" then
    local joiner = syntax == "pandoc" and "; @" or " @"
    if before:match("@$") then return table.concat(keys, joiner) end
    if syntax == "pandoc" and before:match("%[[^%]]*@[^%]]*$") then
      return "; @" .. table.concat(keys, "; @")
    end
  end
  return full(keys, ft)
end

-- insert(keys, ctx?) inserts a citation of `keys` at ctx (from capture())
-- or the cursor.
function M.insert(keys, ctx)
  if #keys == 0 then return end
  M.insert_text(function(ft, before) return M.text(keys, ft, before) end, ctx)
end

-- insert_text(text | function(ft, before) -> text, ctx?)
function M.insert_text(text, ctx)
  ctx = ctx or M.capture()
  if not vim.api.nvim_buf_is_valid(ctx.buf) then return end
  local line = vim.api.nvim_buf_get_lines(ctx.buf, ctx.row, ctx.row + 1, false)[1] or ""
  local col = math.min(ctx.col, #line)
  if type(text) == "function" then text = text(vim.bo[ctx.buf].filetype, line:sub(1, col)) end
  vim.api.nvim_buf_set_text(ctx.buf, ctx.row, col, ctx.row, col, { text })
  if not vim.api.nvim_win_is_valid(ctx.win) then return end
  vim.api.nvim_set_current_win(ctx.win)
  local after = col + #text
  if ctx.insert then
    -- back to insert mode after the citation
    if after >= #line + #text then
      vim.cmd("startinsert!")
    else
      vim.api.nvim_win_set_cursor(ctx.win, { ctx.row + 1, after })
      vim.cmd("startinsert")
    end
  else
    vim.api.nvim_win_set_cursor(ctx.win, { ctx.row + 1, math.max(after - 1, 0) })
  end
end

return M
