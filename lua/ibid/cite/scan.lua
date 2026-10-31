-- Finds the citation keys a document uses, with their positions.
--
-- The buffer is scanned as one string (so `\cite{a,\n b}` works), after
-- blanking comments and code with spaces so byte offsets still map back to
-- (line, col). Per syntax:
--   LaTeX    any \…cite…{a,b} (biblatex multicites \cites[..]{a}{b} too)
--   pandoc   @key, @{key} and [@a; @b], minus Quarto cross-refs (@fig-x)
--   Typst    @key, #cite(<key>), cite(label("key")), minus <labels> the
--            document defines (those @refs point at headings/figures)

local M = {}

local pandoc_ft = { markdown = true, quarto = true, rmd = true }
local tex_ft = { tex = true, plaintex = true }

M.syntax = function(ft)
  if tex_ft[ft] then return "tex" end
  if pandoc_ft[ft] then return "pandoc" end
  if ft == "typst" then return "typst" end
end

local crossref = {}
for _, p in ipairs({ "fig", "tbl", "sec", "eq", "lst", "thm", "lem", "cor", "prp", "cnj", "def",
  "exm", "exr", "sol", "rem", "alg", "nte", "tip", "wrn", "imp", "cau" }) do
  crossref[p] = true
end

local function blank(s) return (s:gsub("[^\n]", " ")) end

-- Comments/code → spaces, line by line (lengths unchanged).
local function sanitise(lines, syntax)
  local out, fence = {}, nil
  for i, l in ipairs(lines) do
    if syntax == "tex" then
      -- an unescaped % starts a comment
      local s, p = nil, 1
      while true do
        local q = l:find("%", p, true)
        if not q then break end
        local bs = 0
        while q - bs - 1 >= 1 and l:sub(q - bs - 1, q - bs - 1) == "\\" do bs = bs + 1 end
        if bs % 2 == 0 then s = q break end
        p = q + 1
      end
      out[i] = s and (l:sub(1, s - 1) .. blank(l:sub(s))) or l
    elseif syntax == "pandoc" then
      local f = l:match("^%s*(```+)") or l:match("^%s*(~~~+)")
      if fence then
        if f and f:sub(1, 1) == fence:sub(1, 1) and #f >= #fence then fence = nil end
        out[i] = blank(l)
      elseif f then
        fence = f
        out[i] = blank(l)
      else
        out[i] = l:gsub("(`+)(.-)%1", function(t, body) return blank(t .. body .. t) end)
      end
    else -- typst
      if fence then
        if l:find("```", 1, true) then fence = nil end
        out[i] = blank(l)
      elseif l:match("^%s*```") then
        fence = "```"
        out[i] = blank(l)
      else
        local c = l:find("//", 1, true)
        -- not inside a URL ("https://…")
        if c and l:sub(c - 1, c - 1) == ":" then c = nil end
        l = c and (l:sub(1, c - 1) .. blank(l:sub(c))) or l
        out[i] = l:gsub("(`+)(.-)%1", function(t, body) return blank(t .. body .. t) end)
      end
    end
  end
  return out
end

-- byte offset (1-based, in the joined text) → 0-based line, col
local function locator(lines)
  local starts, pos = {}, 1
  for i, l in ipairs(lines) do
    starts[i] = pos
    pos = pos + #l + 1
  end
  return function(off)
    local lo, hi = 1, #starts
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if starts[mid] <= off then lo = mid else hi = mid - 1 end
    end
    return lo - 1, off - starts[lo]
  end
end

local function tex(text, add)
  local pos = 1
  while true do
    local s, e, cmd = text:find("\\(%a*[Cc]ite%a*)%*?", pos)
    if not s then break end
    pos = e + 1
    local multi = cmd:sub(-1) == "s"
    while true do
      local ws = text:match("^%s*", pos)
      local p = pos + #ws
      local c = text:sub(p, p)
      if c == "[" or c == "(" then
        local close = text:find(c == "[" and "]" or ")", p, true)
        if not close then break end
        pos = close + 1
      elseif c == "{" then
        local close = text:find("}", p, true)
        if not close then break end
        local inner, base = text:sub(p + 1, close - 1), p + 1
        local i = 1
        while i <= #inner do
          local ks, ke = inner:find("[^,%s]+", i)
          if not ks then break end
          add(inner:sub(ks, ke), base + ks - 1, base + ke - 1)
          i = ke + 1
        end
        pos = close + 1
        if not multi then break end
      else
        break
      end
    end
  end
end

local function at_keys(text, add, chars, skip)
  local pos = 1
  while true do
    local s = text:find("@", pos, true)
    if not s then break end
    pos = s + 1
    local prev = s > 1 and text:sub(s - 1, s - 1) or ""
    if not prev:match("[%w_%.%-]") then
      local brace = text:match("^{([^}%s]+)}", s + 1)
      if brace then
        add(brace, s + 2, s + 1 + #brace)
      else
        local key = text:match("^[%w_]" .. chars, s + 1)
        if key then
          key = key:gsub("[^%w_]+$", "")
          if key ~= "" and not (skip and skip(key)) then add(key, s + 1, s + #key) end
        end
      end
    end
  end
end

local function pandoc(text, add)
  at_keys(text, add, "[%w_:%.#%$%%&%-%+%?<>~/]*", function(key)
    local prefix = key:match("^(%a+)%-")
    return prefix and crossref[prefix]
  end)
end

local function typst(text, add)
  local labels = {}
  for s, l in text:gmatch("()<([%w_:%.%-]+)>") do
    if not text:sub(math.max(1, s - 6), s - 1):find("cite%($") then labels[l] = true end
  end
  at_keys(text, add, "[%w_:%.%-]*", function(key) return labels[key] end)
  for s, key in text:gmatch("cite%(<()([%w_:%.%-]+)>") do add(key, s, s + #key - 1) end
  for s, key in text:gmatch('cite%(%s*label%(%s*"()([^"]+)"') do add(key, s, s + #key - 1) end
end

local scanners = { tex = tex, pandoc = pandoc, typst = typst }

-- scan_lines(lines, syntax) → { { key, lnum, col, end_col }, … } (0-based,
-- end exclusive)
function M.scan_lines(lines, syntax)
  local fn = scanners[syntax]
  if not fn then return {} end
  local clean = sanitise(lines, syntax)
  local text = table.concat(clean, "\n")
  local locate = locator(clean)
  local found = {}
  fn(text, function(key, s, e)
    if key:find("[#*\\]") then return end -- \cite{#1} in macros, \nocite{*}
    local lnum, col = locate(s)
    local elnum, ecol = locate(e)
    table.insert(found, { key = key, lnum = lnum, col = col, end_lnum = elnum, end_col = ecol + 1 })
  end)
  return found
end

function M.scan(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  return M.scan_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false), M.syntax(vim.bo[buf].filetype))
end

-- The citation key under the cursor (or nil).
function M.key_at(buf, row, col)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  if not row then
    local cur = vim.api.nvim_win_get_cursor(0)
    row, col = cur[1] - 1, cur[2]
  end
  for _, f in ipairs(M.scan(buf)) do
    if f.lnum == row and col >= f.col - 1 and col < f.end_col then return f.key end
  end
end

-- Every key cited by the document: the buffer, plus (LaTeX with VimTeX) the
-- project's other source files. Returns a sorted list.
function M.project_keys(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local syntax = M.syntax(vim.bo[buf].filetype)
  local seen = {}
  for _, f in ipairs(M.scan(buf)) do seen[f.key] = true end
  local vt = syntax == "tex" and vim.b[buf].vimtex
  if type(vt) == "table" and type(vt.sources) == "table" and vt.root then
    local this = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
    for _, src in ipairs(vt.sources) do
      local path = vim.fs.normalize(src:sub(1, 1) == "/" and src or (vt.root .. "/" .. src))
      if path ~= this then
        local b = vim.fn.bufnr(path)
        local lines = (b > 0 and vim.api.nvim_buf_is_loaded(b)) and vim.api.nvim_buf_get_lines(b, 0, -1, false)
          or (vim.uv.fs_stat(path) and vim.fn.readfile(path)) or {}
        for _, f in ipairs(M.scan_lines(lines, "tex")) do seen[f.key] = true end
      end
    end
  end
  local keys = vim.tbl_keys(seen)
  table.sort(keys)
  return keys
end

return M
