-- Conservative complete citation ranges. Unsupported/malformed forms are not
-- replaced; byte offsets match nvim_buf_set_text and scanner positions.
local M = {}
local function position(text, offset)
  local before = text:sub(1, offset - 1)
  local _, row = before:gsub('\n', '')
  return row, #(before:match('[^\n]*$') or '')
end
function M.at(buf, row, col)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local syntax = require('ibid.cite.scan').syntax(vim.bo[buf].filetype)
  local clean = table.concat(require('ibid.cite.scan').clean_lines(lines, syntax), '\n')
  local raw = table.concat(lines, '\n')
  local offset = col + 1
  for i = 1, row do offset = offset + #lines[i] + 1 end
  local scan = require('ibid.cite.scan')
  local global = scan.project_scan(buf)
  local function byte_offset(lnum, column)
    local value = column + 1
    for i = 1, lnum do value = value + #lines[i] + 1 end
    return value
  end
  -- Mask string literals while retaining byte positions; escaped quotes do not
  -- terminate a literal. Code examples are not editable citations.
  local chars, quoted, escaped = {}, false, false
  for i = 1, #clean do
    local c = clean:sub(i,i)
    if quoted then
      chars[i] = c == '\n' and c or ' '
      if c == '"' and not escaped then quoted = false end
      if c == '\\' and not escaped then escaped = true else escaped = false end
    elseif c == '"' then quoted = true; chars[i] = ' '
    else chars[i] = c end
  end
  local outside = table.concat(chars)
  local candidates = {}
  local function add(s, e)
    if s <= offset and offset <= e then
      local genuine = false
      for _, cited in ipairs(global) do
        local pos = byte_offset(cited.lnum, cited.col)
        if pos >= s and pos <= e then genuine = true; break end
      end
      if not genuine then return end
      local fragment = raw:sub(s, e)
      local found = require('ibid.cite.scan').scan_lines(vim.split(fragment, '\n', { plain = true }), syntax)
      local keys = {}
      for _, item in ipairs(found) do keys[#keys + 1] = item.key end
      if #keys > 0 then
        local sr, sc = position(raw, s)
        local er, ec = position(raw, e + 1)
        candidates[#candidates + 1] = { row = sr, col = sc, end_row = er, end_col = ec, keys = keys, text = fragment }
      end
    end
  end
  if syntax == 'tex' then
    for s, e in clean:gmatch('()\\%a*[Cc]ite%a*%*?[^\\{}]-{[^{}]*}()') do
      -- Multicite tails cannot be represented as a single simple citation.
      local after = clean:sub(e):match('^%s*(.)')
      local cmd = clean:sub(s, e):match('^\\(%a+)') or ''
      if cmd:sub(-1) ~= 's' and after ~= '{' then add(s, e - 1) end
    end
  elseif syntax == 'pandoc' then
    for s, e in clean:gmatch('()%[[^%[%]\n]*@[^%[%]\n]*%]()') do add(s, e - 1) end
    for s, e in clean:gmatch('()@[%w_][%w_:%.#%$%%&%-%+%?<>~/]*()') do
      local prev = clean:sub(s - 1, s - 1)
      if s == 1 or not prev:match('[%w_%.%-]') then
        local token = raw:sub(s, e - 1):gsub('[^%w_]+$', '')
        add(s, s + #token - 1)
      end
    end
  elseif syntax == 'typst' then
    for s, e in clean:gmatch('()#cite%s*%(%s*<[%w_:%.%-]+>%s*%)()') do if outside:sub(s,s) ~= ' ' then add(s, e - 1) end end
    for s, e in clean:gmatch('()#cite%s*%(%s*label%s*%(%s*"[^"]+"%s*%)%s*%)()') do if outside:sub(s,s) ~= ' ' then add(s, e - 1) end end
    for s, e in outside:gmatch('()@[%w_][%w_:%.%-]*%b[]()') do add(s, e - 1) end
    for s, e in outside:gmatch('()@[%w_][%w_:%.%-]*()') do
      local prev = clean:sub(s - 1, s - 1)
      if s == 1 or not prev:match('[%w_%.%-]') then
        local token = raw:sub(s, e - 1):gsub('[^%w_]+$', '')
        add(s, s + #token - 1)
      end
    end
  end
  table.sort(candidates, function(a, b) return #a.text > #b.text end)
  return candidates[1]
end
return M
