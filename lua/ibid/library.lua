-- The library in memory: normalised items indexed by citation key.
--
-- get(cb) is the only entry point. It stats zotero.sqlite (+ -wal) and only
-- re-reads when Zotero has written since the last load, so callers can ask
-- on every keystroke. The first load of a session comes from a JSON cache
-- keyed on the same signature, so completion works before sqlite3 returns.

local config = require("ibid.config")
local sqlite = require("ibid.source.sqlite")

local M = {}

local cache_file = vim.fn.stdpath("cache") .. "/ibid/library.json"

M.lib = nil -- { items, by_key, by_zkey, collections, groups, signature }
local loading, waiters = false, {}

local function year_of(date) return date and date:match("(%d%d%d%d)") end

-- Zotero stores UTC "YYYY-MM-DD HH:MM:SS"; returns epoch seconds.
local tz = os.time() - os.time(os.date("!*t"))
function M.epoch(stamp)
  local y, mo, d, h, mi, s = (stamp or ""):match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
  if not y then return 0 end
  return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s }) + tz
end

local function names(creators)
  local by_role = { author = {}, editor = {}, other = {} }
  for _, c in ipairs(creators or {}) do
    local last, first, role = c[1], c[2], c[3]
    local list = by_role[role] or by_role.other
    table.insert(list, { last = last ~= "" and last or first, first = last ~= "" and first or nil })
  end
  local people = #by_role.author > 0 and by_role.author
    or #by_role.editor > 0 and by_role.editor
    or by_role.other
  return people
end

local function short(people)
  if #people == 0 then return "" end
  if #people == 1 then return people[1].last end
  if #people == 2 then return people[1].last .. " & " .. people[2].last end
  return people[1].last .. " et al."
end

local function full(people)
  return table.concat(vim.tbl_map(function(p)
    return p.first and p.first ~= "" and (p.last .. ", " .. p.first) or p.last
  end, people), "; ")
end

local function attachment_path(a)
  local p = a.path
  if not p or p == "" then return nil end
  local name = p:match("^storage:(.+)")
  if name then return ("%s/storage/%s/%s"):format(config.data_dir(), a.zkey, name) end
  local profile = require("ibid.profile")
  local relative = p:match("^attachments:(.+)")
  if relative then
    local base = profile.current(config.options.data_dir).prefs["extensions.zotero.baseAttachmentPath"]
    if type(base) == "string" and base ~= "" and profile.is_absolute(base) then
      return profile.normalize(base .. "/" .. relative)
    end
    return nil
  end
  if profile.is_absolute(p) then return profile.normalize(p) end
  return nil -- linked URLs are not local attachments
end

local function normalise(raw)
  local f = raw.fields or {}
  local people = names(raw.creators)
  local it = {
    key = f.citationKey,
    zkey = raw.zkey,
    lib = raw.lib,
    type = raw.type,
    title = f.title or "",
    short_title = f.shortTitle,
    date = f.date and f.date:match("%S+%s+(.+)") or f.date, -- "2019-00-00 2019" → "2019"
    year = year_of(f.date) or "",
    doi = f.DOI,
    url = f.url,
    abstract = f.abstractNote,
    container = f.publicationTitle or f.bookTitle or f.proceedingsTitle or f.websiteTitle
      or f.blogTitle or f.encyclopediaTitle or f.university or f.publisher,
    publisher = f.publisher,
    people = people,
    authors = short(people),
    author_list = full(people),
    tags = raw.tags or {},
    collections = raw.collections or {},
    attachments = {},
    annotations = {},
    notes = raw.notes or {},
    added = raw.added,
    modified = raw.modified,
    fields = f,
  }
  for _, a in ipairs(raw.attachments or {}) do
    table.insert(it.attachments, { zkey = a.zkey, type = a.type, title = a.title, path = attachment_path(a) })
  end
  for _, annotation in ipairs(raw.annotations or {}) do
    local a = vim.deepcopy(annotation)
    if type(a.position) == "string" then
      local ok, position = pcall(vim.json.decode, a.position)
      a.position = ok and type(position) == "table" and position or nil
    end
    a.id = a.zkey or tostring(a.id)
    local page_index = a.position and tonumber(a.position.pageIndex)
    a.page = page_index and page_index >= 0 and page_index + 1 or nil
    table.insert(it.annotations, a)
  end
  table.sort(it.annotations, function(a, b)
    if (a.page or math.huge) ~= (b.page or math.huge) then return (a.page or math.huge) < (b.page or math.huge) end
    return a.id < b.id
  end)
  it.search = table.concat({ it.key or "", it.author_list, it.year, it.title, it.container or "",
    table.concat(it.tags, " ") }, " ")
  return it
end

local function index(data, signature)
  local lib = { items = {}, by_key = {}, by_zkey = {}, collections = {}, groups = {}, signature = signature }
  for _, g in ipairs(data.groups or {}) do lib.groups[g.lib] = g end
  for _, raw in ipairs(data.items or {}) do
    local it = normalise(raw)
    it.library_name = lib.groups[it.lib] and lib.groups[it.lib].name or "My Library"
    it.search = it.search .. " " .. it.library_name
    table.insert(lib.items, it)
    lib.by_zkey[it.zkey] = it
    if it.key and it.key ~= "" then lib.by_key[it.key] = it end
  end
  table.sort(lib.items, function(a, b) return (a.added or "") > (b.added or "") end)
  for _, c in ipairs(data.collections or {}) do lib.collections[c.id] = c end
  return lib
end

local function read_cache(signature)
  local fd = io.open(cache_file, "r")
  if not fd then return nil end
  local raw = fd:read("*a")
  fd:close()
  local ok, c = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if ok and type(c) == "table" and c.version == 2 and c.signature == signature and c.data then return c.data end
end

local function write_cache(signature, data)
  local ok, raw = pcall(vim.json.encode, { version = 2, signature = signature, data = data })
  if not ok then return end
  vim.fn.mkdir(vim.fs.dirname(cache_file), "p")
  vim.uv.fs_open(cache_file, "w", 420, function(err, fd)
    if err or not fd then return end
    vim.uv.fs_write(fd, raw, 0, function() vim.uv.fs_close(fd) end)
  end)
end

local function flush(err)
  local w = waiters
  waiters = {}
  for _, cb in ipairs(w) do cb(err, M.lib) end
end

-- get(cb): cb(err, lib). Synchronous when the library is current.
function M.get(cb)
  cb = cb or function() end
  local signature = sqlite.signature()
  if not signature then return cb("no Zotero database at " .. sqlite.db_path()) end
  if M.lib and M.lib.signature == signature then return cb(nil, M.lib) end
  if not M.lib then
    local cached = read_cache(signature)
    if cached then
      M.lib = index(cached, signature)
      return cb(nil, M.lib)
    end
  end
  table.insert(waiters, cb)
  if loading then return end
  loading = true
  sqlite.read(function(err, data)
    loading = false
    if not err then
      M.lib = index(data, signature)
      write_cache(signature, data)
      vim.api.nvim_exec_autocmds("User", { pattern = "IbidLibraryChanged", modeline = false })
    end
    flush(err)
  end)
end

-- The library as loaded, without checking for changes (hover's enabled(),
-- completion). Kicks off a load when there's nothing yet.
function M.current()
  if not M.lib then M.get() end
  return M.lib
end

function M.item(key) return M.lib and M.lib.by_key[key] end

-- Force a reload on the next get().
function M.invalidate() if M.lib then M.lib.signature = nil end end

-- zotero://select link for an item (group libraries have their own path).
function M.select_url(it)
  local g = M.lib and M.lib.groups[it.lib]
  if g then return ("zotero://select/groups/%d/items/%s"):format(g.id, it.zkey) end
  return "zotero://select/library/items/" .. it.zkey
end

function M.pdf(it, attachment_zkey)
  for _, a in ipairs(it.attachments or {}) do
    if (not attachment_zkey or attachment_zkey == a.zkey) and a.type == "application/pdf" and a.path and vim.uv.fs_stat(a.path) then return a.path end
  end
end

return M
