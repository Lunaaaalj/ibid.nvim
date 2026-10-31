-- :checkhealth ibid

local M = {}

local function run(cmd)
  local ok, res = pcall(function() return vim.system(cmd, { text = true, timeout = 5000 }):wait() end)
  if not ok or res.code ~= 0 then return nil end
  return vim.trim(res.stdout or "")
end

function M.check()
  local h = vim.health
  local config = require("ibid.config")
  h.start("ibid.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim >= 0.10 is required")
  end

  for _, bin in ipairs({ "sqlite3", "curl" }) do
    if vim.fn.executable(bin) == 1 then
      h.ok(bin .. ": found")
    else
      h.error(bin .. " not found", { bin == "sqlite3" and "Reads the Zotero library" or "Talks to Zotero" })
    end
  end

  local db = require("ibid.source.sqlite").db_path()
  if vim.uv.fs_stat(db) then
    h.ok("Zotero database: " .. db)
  else
    h.error("no Zotero database at " .. db, { "Set data_dir in setup()" })
  end

  local port = config.options.port
  local ping = run({ "curl", "-s", "-m", "2", ("http://127.0.0.1:%d/connector/ping"):format(port) })
  if ping and ping:find("Zotero is running") then
    h.ok("Zotero is running (port " .. port .. ")")
    local body = '{"jsonrpc":"2.0","method":"api.ready","params":[],"id":1}'
    local res = run({ "curl", "-s", "-m", "3", "-X", "POST", "-H", "Content-Type: application/json", "-d", body,
      ("http://127.0.0.1:%d/better-bibtex/json-rpc"):format(port) })
    local ok, data = pcall(vim.json.decode, res or "")
    if ok and type(data) == "table" and data.result then
      h.ok(("Better BibTeX %s (Zotero %s)"):format(data.result.betterbibtex or "?", data.result.zotero or "?"))
    else
      h.error("Better BibTeX isn't answering", {
        "Install it: https://retorque.re/zotero-better-bibtex/",
        "Needed to write .bib files and for :Ibid cayw/bibtex/reference",
      })
    end
  else
    h.warn("Zotero isn't running", {
      "Citing, completion and hover work from the database alone;",
      "syncing newly cited keys and yanking BibTeX need Zotero open",
    })
  end

  local lib = require("ibid.library")
  local done, err, n = false, nil, 0
  lib.get(function(e, l)
    err, n, done = e, l and #l.items or 0, true
  end)
  vim.wait(5000, function() return done end, 20)
  if err then
    h.error("reading the library: " .. err)
  elseif done then
    local nokey = 0
    for _, it in ipairs(lib.lib.items) do if not it.key then nokey = nokey + 1 end end
    h.ok(("library: %d items"):format(n))
    if nokey > 0 then
      h.warn(("%d items have no citation key"):format(nokey), { "Better BibTeX assigns keys; check its settings" })
    end
  end

  for _, mod in ipairs({ "telescope", "cmp", "hover" }) do
    if pcall(require, mod) then h.ok(mod .. ": found") else h.info(mod .. ": not installed (optional)") end
  end
end

return M
