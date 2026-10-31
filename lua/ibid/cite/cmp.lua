-- nvim-cmp source "ibid": citation keys inside \cite{…}, after @ (pandoc,
-- Typst) and inside #cite(<…>). The filter text includes authors, year and
-- title, so typing a surname or a title word finds the key.
--
--   require("cmp").register_source("ibid", require("ibid").cmp_source())

local config = require("ibid.config")
local library = require("ibid.library")
local scan = require("ibid.cite.scan")

local source = {}

function source.new() return setmetatable({}, { __index = source }) end

function source:get_debug_name() return "ibid" end

function source:is_available()
  return vim.tbl_contains(config.options.filetypes, vim.bo.filetype)
end

function source:get_trigger_characters() return { "@", "{", ",", "<" } end

function source:get_keyword_pattern() return [[\%([[:alnum:]_:.\-]\)*]] end

-- Is the cursor somewhere a key belongs?
local function in_cite(before, syntax)
  if syntax == "tex" then
    return before:match("\\%a*[Cc]ite%a*%*?[^\\{}]*{[^}]*$") ~= nil
  end
  if syntax == "typst" and before:match("cite%(<[%w_:%.%-]*$") then return true end
  local s = before:match("()@[%w_:%.%-]*$")
  if not s then return false end
  return s == 1 or not before:sub(s - 1, s - 1):match("[%w_%.%-]")
end

function source:complete(params, callback)
  local syntax = scan.syntax(vim.bo.filetype)
  if not syntax or not in_cite(params.context.cursor_before_line, syntax) then
    return callback({ items = {}, isIncomplete = false })
  end
  library.get(function(err, lib)
    if err or not lib then return callback({ items = {}, isIncomplete = false }) end
    local items = {}
    for _, it in ipairs(lib.items) do
      if it.key then
        table.insert(items, {
          label = it.key,
          filterText = table.concat({ it.key, it.author_list, it.year, it.title }, " "),
          kind = 18, -- Reference
          labelDetails = { description = ("%s %s"):format(it.authors, it.year) },
          data = { key = it.key },
        })
      end
    end
    callback({ items = items, isIncomplete = false })
  end)
end

-- the card is only built for the highlighted entry
function source:resolve(item, callback)
  local it = item.data and library.item(item.data.key)
  if it then
    item.documentation = { kind = "markdown", value = table.concat(require("ibid.card").lines(it, 72), "\n") }
  end
  callback(item)
end

return source
