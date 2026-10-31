-- Better BibTeX over Zotero's local HTTP server (needs Zotero running):
-- JSON-RPC for exports and formatted references, and CAYW, BBT's own
-- citation picker. Writes nothing; every call is a read.

local config = require("ibid.config")

local M = {}

local function base() return ("http://127.0.0.1:%d"):format(config.options.port) end

local function curl(args, timeout, cb)
  local cmd = { "curl", "-sS", "--max-time", tostring(math.ceil(timeout / 1000)) }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      local msg = vim.trim(res.stderr or "")
      if res.code == 7 then msg = "Zotero isn't running" end
      return cb(msg ~= "" and msg or ("curl exited " .. res.code))
    end
    cb(nil, res.stdout)
  end))
end

-- rpc(method, params, cb, timeout?): cb(err, result)
function M.rpc(method, params, cb, timeout)
  timeout = timeout or config.options.timeout
  local body = vim.json.encode({ jsonrpc = "2.0", method = method, params = params, id = 1 })
  vim.system({ "curl", "-sS", "--max-time", tostring(math.ceil(timeout / 1000)),
    "-X", "POST", "-H", "Content-Type: application/json", "--data-binary", "@-",
    base() .. "/better-bibtex/json-rpc" }, { text = true, stdin = body }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then
      return cb(res.code == 7 and "Zotero isn't running" or vim.trim(res.stderr or "curl failed"))
    end
    local ok, out = pcall(vim.json.decode, res.stdout)
    if not ok or type(out) ~= "table" then
      return cb((res.stdout or ""):find("No endpoint") and "Better BibTeX isn't installed"
        or "bad response from Zotero")
    end
    if out.error then return cb(out.error.message or vim.inspect(out.error)) end
    cb(nil, out.result)
  end))
end

-- export(keys, translator, cb): cb(err, text). translator is a BBT
-- translator name ("Better BibLaTeX", "Better BibTeX", "Better CSL JSON").
function M.export(keys, translator, cb)
  M.rpc("item.export", { keys, translator }, cb)
end

-- bibliography(keys, style, cb): cb(err, text) formatted with a CSL style id
function M.bibliography(keys, style, cb)
  M.rpc("item.bibliography", { keys, { id = style or config.options.style } }, function(err, text)
    cb(err, text and vim.trim(text))
  end)
end

-- ready(cb): cb(err, { zotero, betterbibtex })
function M.ready(cb) M.rpc("api.ready", {}, cb, 3000) end

-- cayw(format, cb): opens BBT's picker in Zotero and returns the citation it
-- formats ("biblatex", "pandoc", "typst", …). Waits for the user, so no
-- short timeout.
function M.cayw(format, cb)
  curl({ "-G", base() .. "/better-bibtex/cayw", "--data-urlencode", "format=" .. format,
    "--data-urlencode", "minimize=true" }, 600000, function(err, out)
    if err then return cb(err) end
    cb(nil, vim.trim(out or ""))
  end)
end

return M
