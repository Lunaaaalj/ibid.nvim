-- Read Zotero profile preferences without executing prefs.js.
local M = {}

function M.is_absolute(path)
  return type(path) == "string" and (path:match("^[/\\]") ~= nil or path:match("^%a:[/\\]") ~= nil)
end

function M.normalize(path)
  return vim.fs.normalize((path:gsub("\\", "/")))
end

local function join(base, path)
  return M.normalize(M.is_absolute(path) and path or (base .. "/" .. path))
end

local function read(path)
  local fd = io.open(path, "r")
  if not fd then return {} end
  local text = fd:read("*a")
  fd:close()
  return vim.split(text, "\n", { plain = true })
end

function M.preferences(path)
  local prefs = {}
  for _, line in ipairs(read(path)) do
    local key, value = line:match('^%s*user_pref%s*%(%s*"([^"]+)"%s*,%s*(.-)%s*%);%s*$')
    if key then
      local ok, decoded = pcall(vim.json.decode, value)
      if ok then prefs[key] = decoded end
    end
  end
  return prefs
end

function M.roots(opts)
  opts = opts or {}
  local home = opts.home or vim.uv.os_homedir()
  local platform = opts.platform or (vim.fn.has("win32") == 1 and "windows" or (vim.fn.has("mac") == 1 and "mac" or "linux"))
  if platform == "windows" then
    local appdata = opts.appdata or vim.env.APPDATA or (home .. "/AppData/Roaming")
    return { join(appdata, "Zotero/Zotero"), join(appdata, "Zotero") }
  elseif platform == "mac" then
    return { home .. "/Library/Application Support/Zotero" }
  end
  return {
    home .. "/.zotero/zotero",
    home .. "/.var/app/org.zotero.Zotero/.zotero/zotero",
    home .. "/.var/app/org.zotero.Zotero/config/zotero",
  }
end

local function profiles(root)
  local sections, section = {}, nil
  for _, line in ipairs(read(root .. "/profiles.ini")) do
    local name = line:match("^%s*%[([^]]+)%]%s*$")
    if name then
      section = { name = name }
      sections[#sections + 1] = section
    elseif section then
      local key, value = line:match("^%s*([^=]+)=(.-)%s*$")
      if key then section[vim.trim(key)] = value end
    end
  end
  local result, seen = {}, {}
  local function add(path)
    path = M.normalize(path)
    if not seen[path] then result[#result + 1], seen[path] = path, true end
  end
  -- Installation defaults override ProfileN's legacy Default flag.
  for _, s in ipairs(sections) do
    if s.name:match("^Install") and s.Default then add(join(root, s.Default)) end
  end
  for _, default in ipairs({ true, false }) do
    for _, s in ipairs(sections) do
      if s.name:match("^Profile") and s.Path and (s.Default == "1") == default then
        add(s.IsRelative == "0" and s.Path or join(root, s.Path))
      end
    end
  end
  for _, pattern in ipairs({ root .. "/Profiles/*/prefs.js", root .. "/*/prefs.js" }) do
    local paths = vim.fn.glob(pattern, false, true)
    table.sort(paths)
    for _, path in ipairs(paths) do add(vim.fs.dirname(path)) end
  end
  return result
end

-- opts.roots/home/platform/appdata allow deterministic fixtures on any host OS.
function M.discover(opts)
  opts = opts or {}
  local explicit = opts.data_dir and M.normalize(opts.data_dir)
  local fallback = M.normalize((opts.home or vim.uv.os_homedir()) .. "/Zotero")
  local flat = (opts.home or vim.uv.os_homedir()) .. "/.var/app/org.zotero.Zotero/Zotero"
  local first
  for _, root in ipairs(opts.roots or M.roots(opts)) do
    for _, path in ipairs(profiles(root)) do
      local prefs = M.preferences(path .. "/prefs.js")
      local dir = prefs["extensions.zotero.dataDir"]
      if prefs["extensions.zotero.useDataDir"] == false or type(dir) ~= "string" or dir == "" then
        dir = fallback
        if root:find("/org.zotero.Zotero/", 1, true) and not vim.uv.fs_stat(dir .. "/zotero.sqlite")
          and vim.uv.fs_stat(flat .. "/zotero.sqlite") then dir = flat end
      else
        dir = M.normalize(dir)
      end
      local candidate = { data_dir = explicit or dir, profile = path, prefs = prefs }
      if explicit then
        if dir == explicit then return candidate end
      else
        first = first or candidate
        if vim.uv.fs_stat(dir .. "/zotero.sqlite") then return candidate end
      end
    end
  end
  if explicit then return { data_dir = explicit, prefs = {} } end
  -- Flatpak may keep its default data directory under the app's private home.
  if vim.uv.fs_stat(flat .. "/zotero.sqlite") then return { data_dir = flat, prefs = {} } end
  return first or { data_dir = fallback, prefs = {} }
end

local cached, cached_dir
function M.current(data_dir)
  if not cached or cached_dir ~= data_dir then
    cached, cached_dir = M.discover({ data_dir = data_dir }), data_dir
  end
  return cached
end
function M.invalidate() cached, cached_dir = nil, nil end

return M
