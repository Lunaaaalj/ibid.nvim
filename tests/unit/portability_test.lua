local h = require("tests.helpers")
local profile = require("ibid.profile")
local cases = {}
local function test(name, fn) cases[#cases + 1] = { name = "portability: " .. name, run = fn } end
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
end
local function pref(key, value) return 'user_pref(' .. vim.json.encode(key) .. ', ' .. vim.json.encode(value) .. ');' end
local function fixture(root, name, dir, extra)
  write(root .. "/" .. name .. "/prefs.js", pref("extensions.zotero.dataDir", dir) .. "\n" .. (extra or ""))
  write(dir .. "/zotero.sqlite", "fixture")
end

test("platform roots include native Flatpak and Windows profile locations", function()
  h.eq({ "/fixture/Library/Application Support/Zotero" }, profile.roots({ home = "/fixture", platform = "mac" }))
  h.eq("/fixture/.zotero/zotero", profile.roots({ home = "/fixture", platform = "linux" })[1])
  h.eq("/fixture/.var/app/org.zotero.Zotero/.zotero/zotero", profile.roots({ home = "/fixture", platform = "linux" })[2])
  h.eq({ "C:/Users/Test/AppData/Roaming/Zotero/Zotero", "C:/Users/Test/AppData/Roaming/Zotero" },
    profile.roots({ home = "C:/Users/Test", platform = "windows", appdata = [[C:\Users\Test\AppData\Roaming]] }))
end)

test("profiles.ini default takes priority over alphabetical profile paths", function()
  local dir = h.tempdir()
  fixture(dir, "Profiles/aaa", dir .. "/other")
  fixture(dir, "Profiles/zzz", dir .. "/selected")
  write(dir .. "/profiles.ini", "[Profile0]\nPath=Profiles/aaa\nIsRelative=1\n[Profile1]\nPath=Profiles/zzz\nIsRelative=1\nDefault=1")
  h.eq(dir .. "/selected", profile.discover({ roots = { dir }, home = dir }).data_dir)
end)

test("installation default and absolute profile path are supported", function()
  local dir = h.tempdir()
  fixture(dir, "outside", dir .. "/selected")
  fixture(dir, "Profiles/default", dir .. "/other")
  write(dir .. "/profiles.ini", "[InstallABC]\nDefault=" .. dir .. "/outside\n[Profile0]\nPath=Profiles/default\nIsRelative=1\nDefault=1")
  h.eq(dir .. "/outside", profile.discover({ roots = { dir }, home = dir }).profile)
  write(dir .. "/profiles.ini", "[Profile0]\nPath=" .. dir .. "/outside\nIsRelative=0")
  h.eq(dir .. "/selected", profile.discover({ roots = { dir }, home = dir }).data_dir)
end)

test("Flatpak profile and data directory are discovered", function()
  local dir = h.tempdir()
  local root = dir .. "/.var/app/org.zotero.Zotero/.zotero/zotero"
  fixture(root, "Profiles/default", dir .. "/flat-data")
  h.eq(dir .. "/flat-data", profile.discover({ platform = "linux", home = dir }).data_dir)
end)

test("disabled custom data directory ignores stale dataDir preference", function()
  local dir = h.tempdir()
  local root = dir .. "/.zotero/zotero"
  fixture(root, "Profiles/default", dir .. "/stale", pref("extensions.zotero.useDataDir", false))
  write(dir .. "/Zotero/zotero.sqlite", "fixture")
  h.eq(dir .. "/Zotero", profile.discover({ home = dir, platform = "linux" }).data_dir)
end)

test("existing private Flatpak data wins over a stale native profile", function()
  local dir = h.tempdir()
  local root = dir .. "/.zotero/zotero"
  write(root .. "/Profiles/default/prefs.js", pref("extensions.zotero.dataDir", dir .. "/missing"))
  local flat = dir .. "/.var/app/org.zotero.Zotero/Zotero"
  write(flat .. "/zotero.sqlite", "fixture")
  h.eq(flat, profile.discover({ home = dir, platform = "linux" }).data_dir)
end)

test("explicit data directory selects matching preferences only", function()
  local dir = h.tempdir()
  fixture(dir, "Profiles/aaa", dir .. "/other", pref("extensions.zotero.baseAttachmentPath", "/wrong"))
  fixture(dir, "Profiles/zzz", dir .. "/selected", pref("extensions.zotero.baseAttachmentPath", "/right"))
  local selected = profile.discover({ roots = { dir }, data_dir = dir .. "/selected", home = dir })
  h.eq("/right", selected.prefs["extensions.zotero.baseAttachmentPath"])
  local unknown = profile.discover({ roots = { dir }, data_dir = dir .. "/unknown", home = dir })
  h.eq(dir .. "/unknown", unknown.data_dir)
  h.eq({}, unknown.prefs)
end)

test("preferences decode Windows escapes quotes and Unicode without executing code", function()
  local dir = h.tempdir()
  write(dir .. "/prefs.js", pref("extensions.zotero.dataDir", [[C:\Users\Name\Zotero]]) .. '\n'
    .. 'user_pref("quoted", "a\\\"b\\u00e9");\nuser_pref("broken", invalid);\nos.execute("bad");')
  local prefs = profile.preferences(dir .. "/prefs.js")
  h.eq([[C:\Users\Name\Zotero]], prefs["extensions.zotero.dataDir"])
  h.eq('a"bé', prefs.quoted)
  h.eq(nil, prefs.broken)
  h.eq("C:/Users/Name/Zotero", profile.normalize(prefs["extensions.zotero.dataDir"]))
  h.truthy(profile.is_absolute([[C:\Users\Name]]))
  h.truthy(profile.is_absolute([[\\server\share\paper.pdf]]))
  h.eq(false, profile.is_absolute("relative/paper.pdf"))
end)

test("profile cache resets on invalidate", function()
  local original, calls = profile.discover, 0
  profile.discover = function(opts) calls = calls + 1; return { data_dir = opts.data_dir, prefs = {} } end
  profile.invalidate()
  local ok, err = pcall(function()
    profile.current("/one"); profile.current("/one")
    h.eq(1, calls)
    profile.invalidate(); profile.current("/one")
    h.eq(2, calls)
    profile.current("/two")
    h.eq(3, calls)
  end)
  profile.discover = original
  profile.invalidate()
  if not ok then error(err) end
end)

test("library resolves linked Windows and stored attachments and retains group keys", function()
  local cache = vim.fn.stdpath("cache") .. "/ibid/library.json"
  local saved = { library = package.loaded["ibid.library"], sqlite = package.loaded["ibid.source.sqlite"], current = profile.current }
  local ok, err = xpcall(function()
    profile.current = function() return { data_dir = require("ibid.config").options.data_dir, prefs = { ["extensions.zotero.baseAttachmentPath"] = [[D:\Papers]] } } end
    local raw = { groups = { { lib = 2, id = 42, name = "Research Group" } }, items = { {
      lib = 2, zkey = "GROUP01", fields = { citationKey = "group2020", title = "Group item" },
      attachments = {
        { path = "attachments:sub/paper.pdf", zkey = "PDF01", type = "application/pdf" },
        { path = [[C:\Papers\absolute.pdf]], zkey = "PDF02" },
        { path = [[\\server\share\paper.pdf]], zkey = "PDF03" },
        { path = "storage:paper.pdf", zkey = "PDF04" },
      },
    } } }
    write(cache, vim.json.encode({ signature = "portability-fixture", data = raw }))
    package.loaded["ibid.source.sqlite"] = { signature = function() return "portability-fixture" end }
    package.loaded["ibid.library"] = nil
    local library = require("ibid.library")
    local called = false
    library.get(function(e, lib)
      h.eq(nil, e)
      local it = lib.by_key.group2020
      h.eq("Research Group", it.library_name)
      h.truthy(it.search:find("Research Group", 1, true))
      h.eq("D:/Papers/sub/paper.pdf", it.attachments[1].path)
      h.eq("C:/Papers/absolute.pdf", it.attachments[2].path)
      h.eq("//server/share/paper.pdf", it.attachments[3].path)
      h.eq(require("ibid.config").data_dir() .. "/storage/PDF04/paper.pdf", it.attachments[4].path)
      h.eq("zotero://select/groups/42/items/GROUP01", library.select_url(it))
      called = true
    end)
    h.truthy(called)
  end, debug.traceback)
  package.loaded["ibid.library"], package.loaded["ibid.source.sqlite"], profile.current = saved.library, saved.sqlite, saved.current
  vim.fn.delete(cache)
  if not ok then error(err) end
end)

test("fallback picker shows library identity", function()
  local saved = { library = package.loaded["ibid.library"], picker = package.loaded["ibid.cite.picker"], select = vim.ui.select }
  local ok, err = xpcall(function()
    local item = { key = "group2020", authors = "Author", year = "2020", title = "Title", library_name = "Research Group" }
    package.loaded["ibid.library"] = { get = function(cb) cb(nil, { items = { item } }) end }
    package.loaded["ibid.cite.picker"] = nil
    vim.ui.select = function(items, opts)
      h.eq("Author (2020)  Title  [Research Group]", opts.format_item(items[1]))
    end
    require("ibid.cite.picker").pick({ on_select = function() end })
  end, debug.traceback)
  package.loaded["ibid.library"], package.loaded["ibid.cite.picker"], vim.ui.select = saved.library, saved.picker, saved.select
  if not ok then error(err) end
end)

test("Telescope picker displays and searches group identity", function()
  local modules = { "ibid.library", "ibid.cite.picker", "telescope", "telescope.pickers", "telescope.finders", "telescope.config", "telescope.previewers", "telescope.actions", "telescope.actions.state", "telescope.pickers.entry_display" }
  local saved = {}
  for _, name in ipairs(modules) do saved[name] = package.loaded[name] end
  local ok, err = xpcall(function()
    local item = { key = "key", authors = "Author", year = "2020", title = "Title", library_name = "Group", search = "Title Group" }
    package.loaded["ibid.library"] = { get = function(cb) cb(nil, { items = { item } }) end }
    package.loaded["ibid.cite.picker"] = nil
    package.loaded["telescope"] = {}
    package.loaded["telescope.finders"] = { new_table = function(opts) return opts end }
    package.loaded["telescope.config"] = { values = { generic_sorter = function() return {} end } }
    package.loaded["telescope.previewers"] = { new_buffer_previewer = function() return {} end }
    package.loaded["telescope.actions"] = {}
    package.loaded["telescope.actions.state"] = {}
    package.loaded["telescope.pickers.entry_display"] = { create = function() return function(parts) return parts end end }
    local displayed = false
    package.loaded["telescope.pickers"] = { new = function(_, opts)
      return { find = function()
        local entry = opts.finder.entry_maker(opts.finder.results[1])
        h.eq("Title Group", entry.ordinal)
        h.eq("Title  [Group]", entry.display(entry)[3][1])
        displayed = true
      end }
    end }
    require("ibid.cite.picker").pick({ on_select = function() end })
    h.truthy(displayed)
  end, debug.traceback)
  for _, name in ipairs(modules) do package.loaded[name] = saved[name] end
  if not ok then error(err) end
end)

test("project and bibliography paths preserve Windows drives and UNC shares", function()
  local project = require("ibid.project")
  h.eq("C:/refs/papers.bib", project.path("/document", [[C:\refs\papers.bib]]))
  h.eq("//server/share/main.typ", project.path("/document", [[\\server\share\main.typ]]))
  local buf = vim.api.nvim_create_buf(false, true)
  local ok, err = xpcall(function()
    vim.api.nvim_buf_set_name(buf, h.tempdir() .. "/chapter.md")
    vim.bo[buf].filetype = "markdown"
    for _, path in ipairs({ "C:/refs/papers.bib", [[C:\refs\papers.bib]], [[\\server\share\papers.bib]] }) do
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "---", "bibliography: " .. path, "---" })
      h.eq(profile.normalize(path), require("ibid.bib.detect").bibs(buf)[1].path)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Standalone" })
    vim.b[buf].ibid_bib = [[C:\refs\papers.bib]]
    h.eq("C:/refs/papers.bib", require("ibid.bib.detect").bibs(buf)[1].path)
  end, debug.traceback)
  vim.api.nvim_buf_delete(buf, { force = true })
  if not ok then error(err) end
end)

return cases
