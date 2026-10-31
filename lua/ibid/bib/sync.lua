-- Keeps a document's .bib equal to "the Zotero entries it cites".
--
-- The file is owned by ibid (a header line marks it) and is rewritten as a
-- whole, sorted by key, only when its content changes, so latexmk/typst
-- don't recompile for nothing. It's incremental: an entry already in the
-- file is kept unless Zotero modified the item after the file was written,
-- so Better BibTeX (i.e. a running Zotero) is only needed when a newly cited
-- key appears. Entries for keys that live in the document's *other*,
-- hand-written .bib files are never pulled from Zotero.

local config = require("ibid.config")
local library = require("ibid.library")
local scan = require("ibid.cite.scan")
local detect = require("ibid.bib.detect")
local bbt = require("ibid.source.bbt")

local M = {}

M.header = "% Managed by ibid.nvim: the Zotero entries this document cites. Edit them in Zotero;"
  .. " changes made here are overwritten."

local function read(path)
  local fd = io.open(path, "r")
  if not fd then return nil end
  local s = fd:read("*a")
  fd:close()
  return s
end

function M.is_managed(path)
  local s = read(path)
  return s ~= nil and s:sub(1, #M.header) == M.header
end

-- entries(text) → { key = "@type{key,\n…}" } for every @entry in a .bib
function M.entries(text)
  local out, order = {}, {}
  if not text then return out, order end
  local starts = {}
  local pos = 1
  if text:sub(1, 1) == "@" then table.insert(starts, 1) end
  while true do
    local s = text:find("\n@", pos, true)
    if not s then break end
    table.insert(starts, s + 1)
    pos = s + 1
  end
  for i, s in ipairs(starts) do
    local e = (starts[i + 1] or (#text + 2)) - 1
    local block = vim.trim(text:sub(s, e))
    local kind, key = block:match("^@(%w+)%s*[{(]%s*([^,%s]+)%s*,")
    if key and kind:lower() ~= "comment" and kind:lower() ~= "string" and kind:lower() ~= "preamble" then
      out[key] = block
      table.insert(order, key)
    end
  end
  return out, order
end

-- Keys defined in a .bib, cached by mtime (diagnostics ask often).
local key_cache = {}
function M.keys_in(path)
  local st = vim.uv.fs_stat(path)
  if not st then return {} end
  local c = key_cache[path]
  if c and c.mtime == st.mtime.sec and c.size == st.size then return c.keys end
  local keys = {}
  for key in pairs((M.entries(read(path)))) do keys[key] = true end
  key_cache[path] = { mtime = st.mtime.sec, size = st.size, keys = keys }
  return keys
end

local function write(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = path .. ".ibid-tmp"
  local fd = assert(io.open(tmp, "w"))
  fd:write(content)
  fd:close()
  assert(os.rename(tmp, path))
  key_cache[path] = nil
end

-- target(buf, adopt) → bib, others | nil, err
-- The managed file is the first declared .bib that is managed, missing or
-- empty; a non-empty foreign file is only taken over with `adopt` (:Ibid sync!).
function M.target(buf, adopt)
  local bibs = detect.bibs(buf)
  if #bibs == 0 then
    return nil, "this document declares no bibliography"
      .. " (\\addbibresource, `bibliography:` front matter or #bibliography)"
  end
  local pick
  for _, b in ipairs(bibs) do
    local s = read(b.path)
    if M.is_managed(b.path) or not s or vim.trim(s) == "" then
      pick = b
      break
    end
  end
  if not pick and adopt then pick = bibs[1] end
  if not pick then
    return nil, vim.fn.fnamemodify(bibs[1].path, ":~:.") .. " isn't managed by ibid; :Ibid sync! takes it over"
  end
  local others = vim.tbl_filter(function(b) return b.path ~= pick.path end, bibs)
  return pick, others
end

-- sync(buf, { force, adopt, quiet }, cb?) — cb(err, summary)
function M.sync(buf, opts, cb)
  opts = opts or {}
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local function finish(err, summary, level)
    if not opts.quiet or err or (summary and summary.changed) or (summary and #summary.new_missing > 0) then
      local msg = err or summary.message
      vim.notify("ibid: " .. msg, level or (err and vim.log.levels.ERROR or vim.log.levels.INFO))
    end
    if cb then cb(err, summary) end
  end

  local bib, others = M.target(buf, opts.adopt)
  if not bib then return finish(others, nil, opts.quiet and vim.log.levels.WARN or nil) end

  library.get(function(err, lib)
    if err then return finish(err) end
    local cited = scan.project_keys(buf)
    local foreign = {}
    for _, o in ipairs(others) do
      for k in pairs(M.keys_in(o.path)) do foreign[k] = true end
    end
    local old_text = read(bib.path)
    local existing = M.is_managed(bib.path) and M.entries(old_text) or {}
    local old_keys = vim.tbl_keys(existing)
    local st = vim.uv.fs_stat(bib.path)
    local stamp = st and st.mtime.sec or 0

    local wanted, missing, need = {}, {}, {}
    for _, k in ipairs(cited) do
      local it = lib.by_key[k]
      if it then
        table.insert(wanted, k)
        if opts.force or not existing[k] or library.epoch(it.modified) > stamp then table.insert(need, k) end
      elseif not foreign[k] then
        table.insert(missing, k)
      end
    end

    local function assemble(exported, export_err)
      local entries, added, updated, kept_stale = {}, 0, 0, {}
      for _, k in ipairs(wanted) do
        local e = exported and exported[k]
        if e then
          if existing[k] then
            if existing[k] ~= e then updated = updated + 1 end
          else
            added = added + 1
          end
          entries[k] = e
        elseif existing[k] then
          entries[k] = existing[k]
        else
          table.insert(kept_stale, k) -- new key, export failed
        end
      end
      local removed = 0
      for _, k in ipairs(old_keys) do
        if not entries[k] then
          if config.options.bib.prune then removed = removed + 1 else entries[k] = existing[k] end
        end
      end
      local keys = vim.tbl_keys(entries)
      table.sort(keys)
      local body = vim.tbl_map(function(k) return entries[k] end, keys)
      local content = M.header .. "\n\n" .. table.concat(body, "\n\n") .. (#body > 0 and "\n" or "")
      local changed = content ~= old_text
      if changed then
        local ok, werr = pcall(write, bib.path, content)
        if not ok then return finish("writing " .. bib.path .. ": " .. tostring(werr)) end
      elseif exported and #need > 0 then
        -- re-exported but identical: bump the mtime so these items aren't
        -- re-exported on every save
        local now = os.time()
        vim.uv.fs_utime(bib.path, now, now)
      end

      local name = vim.fn.fnamemodify(bib.path, ":~:.")
      local parts = { ("%s: %d %s"):format(name, #keys, #keys == 1 and "entry" or "entries") }
      local delta = {}
      if added > 0 then table.insert(delta, added .. " added") end
      if updated > 0 then table.insert(delta, updated .. " updated") end
      if removed > 0 then table.insert(delta, removed .. " removed") end
      if #delta > 0 then parts[1] = parts[1] .. " (" .. table.concat(delta, ", ") .. ")" end
      if not changed and #delta == 0 then parts[1] = parts[1] .. ", up to date" end
      if #kept_stale > 0 then
        table.insert(parts, ("%d not exported (%s): %s"):format(#kept_stale, export_err or "?",
          table.concat(kept_stale, ", ")))
      end
      if #missing > 0 then table.insert(parts, "not in Zotero: " .. table.concat(missing, ", ")) end
      -- quiet syncs only speak up about keys that weren't flagged before
      local new_missing = vim.tbl_filter(function(k) return not existing[k] end, kept_stale)
      finish(nil, {
        path = bib.path, changed = changed, entries = #keys, added = added, updated = updated,
        removed = removed, missing = missing, new_missing = new_missing,
        message = table.concat(parts, "; "),
      }, (#kept_stale > 0 or #missing > 0) and vim.log.levels.WARN or nil)
    end

    if #need == 0 then return assemble({}) end
    bbt.export(need, bib.translator, function(xerr, text)
      if xerr then return assemble(nil, xerr) end
      assemble((M.entries(text)))
    end)
  end)
end

return M
