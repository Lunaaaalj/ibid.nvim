-- Literature notes preserve user writing; annotation IDs are append-only markers.
local M = {}
local function encode(value) return vim.json.encode(tostring(value or "")) end
local function hex(value) return (tostring(value):gsub('.', function(c) return ('%02x'):format(c:byte()) end)) end
local function marker(item, annotation, format)
  local id = hex(tostring(item.lib or "") .. ":" .. (annotation.id or annotation.zkey or ""))
  return format == "typst" and ("// ibid-annotation:" .. id) or ("<!-- ibid-annotation:" .. id .. " -->")
end
local function annotations(item, format, existing)
  local groups, colors, seen = {}, {}, {}
  for _, a in ipairs(item.annotations or {}) do
    local mark = marker(item, a, format)
    if not seen[mark] and not existing:find(mark, 1, true) then
      seen[mark] = true
      local color = a.color or "uncoloured"
      if not groups[color] then groups[color] = {}; colors[#colors + 1] = color end
      groups[color][#groups[color] + 1] = a
    end
  end
  table.sort(colors)
  local out = {}
  for _, color in ipairs(colors) do
    out[#out + 1] = format == "typst" and ("== #text(" .. encode(color) .. ")") or ("## " .. color)
    out[#out + 1] = ""
    for _, a in ipairs(groups[color]) do
      out[#out + 1] = marker(item, a, format)
      local page = a.page_label or (a.page and tostring(a.page))
      if page and page ~= "" then out[#out + 1] = format == "typst" and ("#text(" .. encode("Page " .. page) .. ")") or ("Page " .. page) end
      -- Treat source strings as literal text in Typst, not executable markup.
      for _, text in ipairs({ a.text or "", a.comment or "" }) do
        if text ~= "" then
          if format == "typst" then out[#out + 1] = "#text(" .. encode(text) .. ")"
          else vim.list_extend(out, vim.split(text, "\n", { plain = true })) end
        end
      end
      out[#out + 1] = ""
    end
  end
  return out
end

function M.render(item, format)
  format = format or "markdown"
  local metadata = {
    { "key", item.key }, { "title", item.title }, { "authors", item.author_list or item.authors },
    { "year", item.year }, { "doi", item.doi }, { "zotero", require("ibid.library").select_url(item) },
  }
  local out = format == "typst" and {} or { "---" }
  for _, pair in ipairs(metadata) do out[#out + 1] = (format == "typst" and "// " or "") .. pair[1] .. ": " .. encode(pair[2]) end
  if format ~= "typst" then out[#out + 1] = "---" end
  out[#out + 1] = ""
  out[#out + 1] = format == "typst" and ("= #text(" .. encode(item.title) .. ")") or ("# " .. (item.title or ""))
  out[#out + 1] = ""
  if item.abstract and item.abstract ~= "" then
    if format == "typst" then out[#out + 1] = "#text(" .. encode(item.abstract) .. ")"
    else vim.list_extend(out, vim.split(item.abstract, "\n", { plain = true })) end
    out[#out + 1] = ""
  end
  vim.list_extend(out, annotations(item, format, ""))
  return out
end

-- update(item, {dir?,format?}) -> path|nil, error. Loaded buffers win over disk.
local function update(item, opts)
  opts = opts or {}
  local config = require("ibid.config").options
  local dir = opts.dir or config.notes_dir
  if not dir or dir == "" then return nil, "set notes_dir before creating literature notes" end
  local format = opts.format or config.note_format or "markdown"
  if format ~= "markdown" and format ~= "typst" then return nil, "note format must be markdown or typst" end
  local key = item.key
  if type(key) ~= "string" or key == "" then return nil, "item has no citation key" end
  -- Percent encoding is injective and keeps arbitrary keys inside notes_dir.
  local filename = key:gsub('[^%w_-]', function(c) return ('%%%02X'):format(c:byte()) end)
  if filename:upper():match("^(CON)$") or filename:upper():match("^(PRN)$") or filename:upper():match("^(AUX)$") or filename:upper():match("^(NUL)$") or filename:upper():match("^COM[1-9]$") or filename:upper():match("^LPT[1-9]$") then
    filename = ('%%%02X'):format(filename:byte(1)) .. filename:sub(2)
  end
  dir = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p"))
  local ok, err = pcall(vim.fn.mkdir, dir, "p")
  if not ok then return nil, tostring(err) end
  local path = dir .. "/" .. filename .. (format == "typst" and ".typ" or ".md")
  local st = vim.uv.fs_lstat(path)
  if st and st.type ~= "file" then return nil, "refusing non-regular note path: " .. path end
  local buf = vim.fn.bufnr(path)
  local loaded = buf > 0 and vim.api.nvim_buf_is_loaded(buf)
  local lines = loaded and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or (st and vim.fn.readfile(path))
  local content
  if lines then
    local extra = annotations(item, format, table.concat(lines, "\n"))
    if #extra == 0 then return path end
    content = vim.list_extend(vim.list_extend({}, lines), vim.list_extend({ "" }, extra))
  else content = M.render(item, format) end
  if loaded then
    if not vim.bo[buf].modifiable then return nil, "note buffer is not modifiable" end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  else
    local temp = path .. ".ibid-" .. vim.uv.os_getpid() .. ".tmp"
    if vim.uv.fs_lstat(temp) then return nil, "note temporary path already exists" end
    local wrote, werr = pcall(vim.fn.writefile, content, temp)
    if not wrote then return nil, tostring(werr) end
    local renamed, rerr = os.rename(temp, path)
    if not renamed then os.remove(temp); return nil, rerr end
  end
  return path
end

function M.update(item, opts)
  local ok, path, err = pcall(update, item, opts)
  if not ok then return nil, tostring(path) end
  return path, err
end

function M.open(item, opts)
  local path, err = M.update(item, opts)
  if not path then vim.notify("ibid: " .. err, vim.log.levels.ERROR); return nil, err end
  vim.cmd.edit(vim.fn.fnameescape(path))
  return path
end

-- Optional rich conversion for browser/card consumers; never executes note HTML.
function M.child_text(note, cb)
  local html = note.html or ""
  if vim.fn.executable("pandoc") == 1 then
    return vim.system({ "pandoc", "--from=html", "--to=gfm" }, { stdin = html, text = true, timeout = 3000 }, vim.schedule_wrap(function(res)
      if res.code == 0 then return cb(nil, vim.trim(res.stdout)) end
      cb(nil, M.plain_text(html))
    end))
  end
  cb(nil, M.plain_text(html))
end
function M.plain_text(html)
  return vim.trim((html:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.-</[Ss][Cc][Rr][Ii][Pp][Tt]>", "")
    :gsub("</[pP]>", "\n\n"):gsub("<[bB][rR]%s*/?>", "\n"):gsub("<[^>]+>", "")
    :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&#39;", "'"):gsub("&nbsp;", " "):gsub("&amp;", "&")))
end
return M
