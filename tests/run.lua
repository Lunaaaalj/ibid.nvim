-- -l runs before user configuration. Isolate every writable Neovim directory
-- before loading the plugin (which captures cache paths at require time).
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local sandbox = vim.fn.tempname()
for _, name in ipairs({ "CONFIG", "DATA", "STATE", "CACHE" }) do
  vim.env["XDG_" .. name .. "_HOME"] = sandbox .. "/" .. name:lower()
end
vim.env.XDG_CONFIG_DIRS = sandbox .. "/config-dirs"
vim.env.XDG_DATA_DIRS = sandbox .. "/data-dirs"
vim.fn.mkdir(sandbox, "p")
vim.opt.runtimepath = { root, vim.env.VIMRUNTIME }
vim.opt.packpath = {}
package.path = root .. "/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local helpers = require("tests.helpers")
local config = require("ibid.config")
config.defaults.data_dir = sandbox .. "/zotero"
config.setup({})
-- All external calls in this suite must be fixture SQLite queries. Accidental
-- BBT requests fail immediately instead of reaching a running Zotero instance.
local system = vim.system
vim.system = function(cmd, ...)
  assert(type(cmd) == "table" and vim.fs.basename(cmd[1]) == "sqlite3", "unexpected external command: " .. vim.inspect(cmd))
  return system(cmd, ...)
end
local files = vim.fn.glob(root .. "/tests/unit/*_test.lua", false, true)
for _, name in ipairs({ "library_test.lua", "sync_test.lua" }) do
  local path = root .. "/tests/" .. name
  if vim.uv.fs_stat(path) then files[#files + 1] = path end
end
table.sort(files)
local passed, failed = 0, 0
for _, file in ipairs(files) do
  local ok, cases = pcall(dofile, file)
  if not ok then
    failed = failed + 1
    io.stderr:write("FAIL loading " .. file .. ": " .. tostring(cases) .. "\n")
  else
    if type(cases) ~= "table" or #cases == 0 then
      failed = failed + 1
      io.stderr:write("FAIL empty or malformed suite: " .. file .. "\n")
      cases = {}
    end
    for _, case in ipairs(cases) do
      local success, err = xpcall(function()
        assert(type(case) == "table" and type(case.name) == "string" and type(case.run) == "function", "malformed test case")
        case.run()
      end, debug.traceback)
      if success then
        passed = passed + 1
        print("PASS " .. case.name)
      else
        failed = failed + 1
        io.stderr:write("FAIL " .. tostring(type(case) == "table" and case.name or case) .. "\n" .. tostring(err) .. "\n")
      end
    end
  end
end
if passed + failed == 0 then
  failed = 1
  io.stderr:write("FAIL no tests discovered\n")
end
helpers.cleanup()
vim.fn.delete(sandbox, "rf")
print(("%d passed, %d failed"):format(passed, failed))
vim.cmd("cquit " .. (failed > 0 and 1 or 0))
