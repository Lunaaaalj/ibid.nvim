local h = require("tests.helpers")
local tests = {}

local function entry(key, title)
  return ("@article{%s,\n  title = {%s}\n}"):format(key, title or key)
end

-- Each case exercises real bibliography detection, citation scanning, BBT's
-- export wrapper, and disk writes; only library loading and the RPC are stubbed.
local function case(name, run)
  tests[#tests + 1] = { name = "sync: " .. name, run = function()
    local config = require("ibid.config")
    local library = require("ibid.library")
    local bbt = require("ibid.source.bbt")
    local sync = require("ibid.bib.sync")
    local saved = { options = config.options, get = library.get, rpc = bbt.rpc, notify = vim.notify }
    local dir = h.tempdir()
    local buf = vim.api.nvim_create_buf(false, true)
    local ctx = { dir = dir, buf = buf, path = dir .. "/refs.bib", calls = {}, items = {}, notices = {}, sync = sync }
    local function write(path, text)
      local f = assert(io.open(path, "wb"))
      assert(f:write(text))
      assert(f:close())
    end
    function ctx.read(path)
      local f = assert(io.open(path or ctx.path, "rb"))
      local text = f:read("*a")
      f:close()
      return text
    end
    function ctx.managed(entries)
      return sync.header .. "\n\n" .. table.concat(entries, "\n\n") .. (#entries > 0 and "\n" or "")
    end
    function ctx.seed(entries)
      write(ctx.path, ctx.managed(entries))
      -- Exact, old timestamps eliminate sleeps and wall-clock races.
      assert(vim.uv.fs_utime(ctx.path, 1700000000, 1700000000))
    end
    ctx.write = write
    function ctx.document(citations, extra_bib)
      local lines = { "\\addbibresource{refs.bib}" }
      if extra_bib then lines[#lines + 1] = "\\addbibresource{" .. extra_bib .. "}" end
      lines[#lines + 1] = "\\cite{" .. table.concat(citations, ",") .. "}"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end
    function ctx.item(key, modified)
      ctx.items[key] = { key = key, modified = modified or "2020-01-01 00:00:00" }
    end
    function ctx.run(opts)
      local done, err, summary = false, nil, nil
      sync.sync(buf, opts or { quiet = true }, function(e, s)
        err, summary, done = e, s, true
      end)
      assert(vim.wait(5000, function() return done end, 10), "sync callback timed out")
      return err, summary
    end
    local ok, err = xpcall(function()
      config.setup({ bib = { sync_on_save = false } })
      vim.api.nvim_buf_set_name(buf, dir .. "/paper.tex")
      vim.bo[buf].filetype = "tex"
      ctx.document({ "a" })
      library.get = function(cb) cb(nil, { by_key = ctx.items }) end
      vim.notify = function(msg, level) ctx.notices[#ctx.notices + 1] = { msg = msg, level = level } end
      bbt.rpc = function(method, params, cb)
        ctx.calls[#ctx.calls + 1] = { method = method, params = vim.deepcopy(params) }
        -- Deferred completion checks that sync waits for the export result.
        vim.schedule(function() cb(ctx.export_error, ctx.export_text or "") end)
      end
      run(ctx)
    end, debug.traceback)
    config.options, library.get, bbt.rpc, vim.notify = saved.options, saved.get, saved.rpc, saved.notify
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    vim.fn.delete(dir, "rf")
    if not ok then error(err, 0) end
  end }
end

case("keeps existing unmodified entries without contacting BBT or changing mtime", function(c)
  c.item("a")
  c.seed({ entry("a") })
  local before = vim.uv.fs_stat(c.path)
  local err, result = c.run()
  h.eq(nil, err)
  h.eq(false, result.changed)
  h.eq(0, #c.calls)
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq(before.mtime, vim.uv.fs_stat(c.path).mtime)
end)

case("exports only new and modified entries and sorts the final keys", function(c)
  c.document({ "c", "b", "a" })
  c.item("a")
  c.item("b", "2025-01-01 00:00:00")
  c.item("c")
  c.seed({ entry("a"), entry("b", "old") })
  c.export_text = entry("c") .. "\n\n" .. entry("b", "new")
  local err, result = c.run()
  h.eq(nil, err)
  h.eq({ { method = "item.export", params = { { "b", "c" }, "Better BibLaTeX" } } }, c.calls)
  h.eq(c.managed({ entry("a"), entry("b", "new"), entry("c") }), c.read())
  h.eq(1, result.added)
  h.eq(1, result.updated)
  h.eq(true, result.changed)
end)

case("prunes uncited entries", function(c)
  c.item("a")
  c.seed({ entry("a"), entry("b") })
  local err, result = c.run()
  h.eq(nil, err)
  h.eq(1, result.removed)
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq(0, #c.calls)
end)

case("retains uncited entries when prune is disabled", function(c)
  require("ibid.config").options.bib.prune = false
  c.item("a")
  c.seed({ entry("a"), entry("b") })
  local err, result = c.run()
  h.eq(nil, err)
  h.eq(0, result.removed)
  h.eq(false, result.changed)
  h.eq(c.managed({ entry("a"), entry("b") }), c.read())
end)

case("refuses a handwritten bibliography without adoption", function(c)
  c.item("a")
  local original = entry("handwritten") .. "\n"
  c.write(c.path, original)
  local err, result = c.run()
  h.truthy(err and err:find("isn't managed", 1, true))
  h.eq(nil, result)
  h.eq(original, c.read())
  h.eq(0, #c.calls)
end)

case("explicit adoption replaces the handwritten bibliography with exported citations", function(c)
  c.item("a")
  c.write(c.path, entry("handwritten") .. "\n")
  c.export_text = entry("a")
  local err, result = c.run({ adopt = true, quiet = true })
  h.eq(nil, err)
  h.eq(true, result.changed)
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq({ { "a" }, "Better BibLaTeX" }, c.calls[1].params)
end)

case("force reexports even unmodified entries", function(c)
  c.item("a")
  c.seed({ entry("a") })
  c.export_text = entry("a", "refreshed")
  local err, result = c.run({ force = true, quiet = true })
  h.eq(nil, err)
  h.eq(1, #c.calls)
  h.eq(1, result.updated)
  h.eq(c.managed({ entry("a", "refreshed") }), c.read())
end)

case("failed exports preserve existing entries and report unexported new keys", function(c)
  c.document({ "a", "b" })
  c.item("a", "2025-01-01 00:00:00")
  c.item("b")
  c.seed({ entry("a") })
  local before = vim.uv.fs_stat(c.path).mtime
  c.export_error = "Zotero isn't running"
  local err, result = c.run()
  h.eq(nil, err)
  h.eq(false, result.changed)
  h.eq({ "b" }, result.new_missing)
  h.truthy(result.message:find("Zotero isn't running", 1, true))
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq(before, vim.uv.fs_stat(c.path).mtime)
  h.eq(vim.log.levels.WARN, c.notices[1].level)
end)

case("identical reexport keeps bytes and inode but currently advances mtime", function(c)
  -- Characterisation of the current freshness workaround, not an assertion
  -- that touching mtime satisfies the no-watcher-rebuild promise. A future
  -- freshness-cache fix should change this expectation to unchanged mtime.
  c.item("a", "2025-01-01 00:00:00")
  c.seed({ entry("a") })
  c.export_text = entry("a")
  local before = vim.uv.fs_stat(c.path)
  local err, result = c.run()
  local after = vim.uv.fs_stat(c.path)
  h.eq(nil, err)
  h.eq(false, result.changed)
  h.eq(0, result.updated)
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq(before.ino, after.ino)
  h.truthy(after.mtime.sec > before.mtime.sec, "current identical-export path touches mtime")
  c.calls = {}
  local second_err, second_result = c.run()
  h.eq(nil, second_err)
  h.eq(false, second_result.changed)
  h.eq(0, #c.calls)
end)

case("leaves foreign bibliography keys alone and reports unknown citations", function(c)
  c.document({ "a", "foreign", "unknown" }, "manual.bib")
  c.item("a")
  c.seed({ entry("a") })
  local foreign = entry("foreign") .. "\n"
  c.write(c.dir .. "/manual.bib", foreign)
  local err, result = c.run()
  h.eq(nil, err)
  h.eq({ "unknown" }, result.missing)
  h.eq(0, #c.calls)
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq(foreign, c.read(c.dir .. "/manual.bib"))
end)

case("creates a missing managed bibliography from a new citation", function(c)
  c.item("a")
  c.export_text = entry("a")
  local err, result = c.run()
  h.eq(nil, err)
  h.eq(true, result.changed)
  h.eq(1, result.added)
  h.eq(c.managed({ entry("a") }), c.read())
  h.eq(nil, vim.uv.fs_stat(c.path .. ".ibid-tmp"))
end)

return tests
