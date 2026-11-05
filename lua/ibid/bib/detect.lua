-- Which .bib files a document uses, from the document itself:
--   LaTeX    \addbibresource{x.bib} (BibLaTeX), \bibliography{a,b} (BibTeX),
--            read from VimTeX's main file when there is one
--   pandoc   `bibliography:` in the YAML front matter, else in _quarto.yml
--   Typst    #bibliography("x.bib") or #bibliography(("a.bib", "b.bib"))
-- then config.bib.fallback(buf), then b:ibid_bib.

local config = require("ibid.config")
local scan = require("ibid.cite.scan")

local M = {}

local function resolve(dir, p)
  p = vim.trim(p)
  p = p:gsub("^[\"']", ""):gsub("[\"']$", "")
  local profile = require("ibid.profile")
  p = profile.normalize(vim.fn.expand(profile.normalize(p)))
  if not profile.is_absolute(p) then p = dir .. "/" .. p end
  return profile.normalize(p)
end

local function tex(buf)
  local project = require("ibid.project").discover(buf)
  local main = project.root
  local dir = vim.fs.dirname(main)
  local text = table.concat(require("ibid.project").lines(main) or {}, "\n")
  text = text:gsub("%%[^\n]*", "")
  local out = {}
  for list in text:gmatch("\\addbibresource%s*%b[]%s*(%b{})") do
    table.insert(out, { path = resolve(dir, list:sub(2, -2)), translator = "Better BibLaTeX" })
  end
  for list in text:gmatch("\\addbibresource%s*(%b{})") do
    table.insert(out, { path = resolve(dir, list:sub(2, -2)), translator = "Better BibLaTeX" })
  end
  for list in text:gmatch("\\bibliography%s*(%b{})") do
    for name in list:sub(2, -2):gmatch("[^,]+") do
      name = vim.trim(name)
      if not name:match("%.bib$") then name = name .. ".bib" end
      table.insert(out, { path = resolve(dir, name), translator = "Better BibTeX" })
    end
  end
  return out
end

-- `bibliography:` from YAML lines (a scalar, [a, b] or a "- item" list)
local function yaml_bib(lines, first, last)
  for i = first, last do
    local v = lines[i]:match("^bibliography:%s*(.-)%s*$")
    if v then
      if v == "" then
        local out = {}
        for j = i + 1, last do
          local item = lines[j]:match("^%s+%-%s*(.-)%s*$")
          if not item then break end
          table.insert(out, item)
        end
        return out
      end
      if v:match("^%[") then return vim.split(v:sub(2, -2), ",", { trimempty = true }) end
      return { v }
    end
  end
end

local function pandoc(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
  local names
  if lines[1] == "---" then
    for i = 2, #lines do
      if lines[i] == "---" or lines[i] == "..." then
        names = yaml_bib(lines, 2, i - 1)
        break
      end
    end
  end
  if not names then
    local proj = vim.fs.find("_quarto.yml", { upward = true, path = dir, stop = vim.uv.os_homedir() })[1]
    if proj then
      local pl = require("ibid.project").lines(proj) or {}
      names = yaml_bib(pl, 1, #pl)
      dir = vim.fs.dirname(proj)
    end
  end
  return vim.tbl_map(function(n) return { path = resolve(dir, n), translator = config.options.bib.translator } end,
    names or {})
end

local function typst(buf)
  local root = require("ibid.project").discover(buf).root
  local text = table.concat(require("ibid.project").lines(root) or {}, "\n")
  local dir = vim.fs.dirname(root)
  local out = {}
  for args in text:gmatch("#bibliography(%b())") do
    local first = args:match('^%(%s*(%b())') or args
    for name in first:gmatch('"([^"]+%.bib)"') do
      table.insert(out, { path = resolve(dir, name), translator = config.options.bib.translator })
    end
  end
  return out
end

local detectors = { tex = tex, pandoc = pandoc, typst = typst }

-- bibs(buf) → { { path, translator }, … } (may be empty)
function M.bibs(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local syntax = scan.syntax(vim.bo[buf].filetype)
  local out = syntax and detectors[syntax](buf) or {}
  if #out == 0 then
    local p = config.options.bib.fallback and config.options.bib.fallback(buf) or vim.b[buf].ibid_bib
    if p then
      out = { { path = resolve(vim.fs.dirname(vim.api.nvim_buf_get_name(buf)), p),
        translator = config.options.bib.translator } }
    end
  end
  local seen, uniq = {}, {}
  for _, b in ipairs(out) do
    if not seen[b.path] then
      seen[b.path] = true
      table.insert(uniq, b)
    end
  end
  return uniq
end

return M
