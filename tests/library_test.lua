local h = require('tests.helpers')
local uv = vim.uv
local fixture = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h') .. '/fixtures/library.sql'

local function with_library(fn)
  local dir = h.tempdir()
  local config = require('ibid.config')
  local saved = config.options
  local saved_library = package.loaded['ibid.library']
  local saved_sqlite = package.loaded['ibid.source.sqlite']
  local cache = vim.fn.stdpath('cache') .. '/ibid/library.json'
  local original_open, original_close = uv.fs_open, uv.fs_close
  local pending, cache_fds = 0, {}
  -- Count a cache write from submission of fs_open through completion of
  -- fs_close, so cleanup never races a callback recreating the cache file.
  uv.fs_open = function(path, flags, mode, cb)
    if path ~= cache or not cb then return original_open(path, flags, mode, cb) end
    pending = pending + 1
    return original_open(path, flags, mode, function(err, fd)
      if fd then cache_fds[fd] = true else pending = pending - 1 end
      cb(err, fd)
    end)
  end
  uv.fs_close = function(fd, cb)
    if not cache_fds[fd] then return original_close(fd, cb) end
    return original_close(fd, function(err)
      cache_fds[fd] = nil
      pending = pending - 1
      if cb then cb(err) end
    end)
  end
  local sqlite
  local ok, err = xpcall(function()
    config.setup({ data_dir = dir })
    vim.fn.delete(cache)
    package.loaded['ibid.library'] = nil
    package.loaded['ibid.source.sqlite'] = nil
    sqlite = require('ibid.source.sqlite')
    local lib = require('ibid.library')
    local res = vim.system({ 'sqlite3', dir .. '/zotero.sqlite' }, {
      text = true, stdin = table.concat(vim.fn.readfile(fixture), '\n'),
    }):wait()
    h.eq(0, res.code)
    fn(dir, sqlite, lib, cache)
  end, debug.traceback)
  local drained, drain_err = pcall(h.wait, function() return pending == 0 end)
  uv.fs_open, uv.fs_close = original_open, original_close
  if sqlite then sqlite.cleanup() end
  vim.fn.delete(cache)
  vim.fn.delete(dir, 'rf')
  config.options = saved
  package.loaded['ibid.library'] = saved_library
  package.loaded['ibid.source.sqlite'] = saved_sqlite
  if not ok then error(err) end
  if not drained then error(drain_err) end
end

local function load(lib)
  local done, err, value = false, nil, nil
  lib.get(function(e, v) err, value, done = e, v, true end)
  h.wait(function() return done end)
  h.eq(nil, err)
  return value
end

return {
  { name = 'SQLite query reads a copied fixture and excludes deleted/child records', run = function()
    with_library(function(dir, sqlite)
      local original = table.concat(vim.fn.readfile(sqlite.db_path(), 'b'), '\n')
      local signature = sqlite.signature()
      local done, err, raw = false, nil, nil
      sqlite.read(function(e, value) err, raw, done = e, value, true end)
      h.wait(function() return done end)
      h.eq(nil, err)
      h.eq(3, #raw.items)
      local by_key = {}
      for _, item in ipairs(raw.items) do by_key[item.zkey] = item end
      h.eq({{'Doe','Jane','author'},{'Roe','Richard','author'},{'Ignored','Editor','editor'}}, by_key.ARTICLE1.creators)
      h.eq({'methods','review'}, by_key.ARTICLE1.tags)
      h.eq({2}, by_key.ARTICLE1.collections)
      h.eq(1, #by_key.ARTICLE1.attachments)
      h.eq('PDF00001', by_key.ARTICLE1.attachments[1].zkey)
      h.eq('Highlighted text', by_key.ARTICLE1.annotations[1].text)
      h.eq('PDF00001', by_key.ARTICLE1.annotations[1].attachment_zkey)
      h.eq('NOTE0001', by_key.ARTICLE1.notes[1].zkey)
      h.eq(3, #raw.collections)
      h.eq({{lib=2,id=42,name='Fixture Group'}}, raw.groups)
      h.eq(signature, sqlite.signature())
      h.eq(original, table.concat(vim.fn.readfile(sqlite.db_path(), 'b'), '\n'))
      h.truthy(uv.fs_stat(vim.fn.stdpath('cache') .. '/ibid/db-' .. uv.os_getpid() .. '/zotero.sqlite'))
    end)
  end },
  { name = 'Library normalises creators metadata collections groups and attachments', run = function()
    with_library(function(dir, _, lib)
      local data = load(lib)
      h.eq({'EMPTY001','GROUPBK1','ARTICLE1'}, vim.tbl_map(function(it) return it.zkey end, data.items))
      local article = data.by_key.doe2020
      h.eq(article, data.by_zkey.ARTICLE1)
      h.eq('Doe & Roe', article.authors)
      h.eq('Doe, Jane; Roe, Richard', article.author_list)
      h.eq('2020', article.year)
      h.eq(4, article.annotations[1].page)
      h.eq('iv', article.annotations[1].page_label)
      h.eq('ANNOT001', article.annotations[1].id)
      h.eq({pageIndex=3}, article.annotations[1].position)
      h.eq('<p>A child <strong>note</strong>.</p>', article.notes[1].html)
      h.eq('2020', article.date)
      h.eq('Journal of Fixtures', article.container)
      h.eq('10.1234/example', article.doi)
      h.eq('An abstract.', article.abstract)
      h.eq(dir .. '/storage/PDF00001/paper.pdf', article.attachments[1].path)
      h.eq('Research Council', data.by_key.group2021.authors)
      h.eq('/fixture/linked.pdf', data.by_key.group2021.attachments[1].path)
      h.eq(1, data.collections[2].parent)
      h.eq('Fixture Group', data.groups[2].name)
      h.eq('zotero://select/groups/42/items/GROUPBK1', lib.select_url(data.by_key.group2021))
      h.eq('zotero://select/library/items/ARTICLE1', lib.select_url(article))
      local empty = data.by_zkey.EMPTY001
      h.eq('', empty.title)
      h.eq('', empty.year)
      h.eq('', empty.authors)
      h.eq({}, empty.attachments)
      h.eq(2, vim.tbl_count(data.by_key))
      h.truthy(article.search:find('methods', 1, true))
      h.eq(nil, lib.pdf(article))
      vim.fn.mkdir(dir .. '/storage/PDF00001', 'p')
      vim.fn.writefile({'fixture'}, article.attachments[1].path)
      h.eq(article.attachments[1].path, lib.pdf(article))
    end)
  end },
  { name = 'Library coalesces first-load callbacks and reuses unchanged memory', run = function()
    with_library(function(_, sqlite, lib)
      local reads, calls = 0, 0
      local read = sqlite.read
      sqlite.read = function(cb) reads = reads + 1; read(cb) end
      local values = {}
      for i = 1, 2 do lib.get(function(err, value) h.eq(nil, err); values[i] = value; calls = calls + 1 end) end
      h.wait(function() return calls == 2 end)
      h.eq(1, reads)
      h.truthy(rawequal(values[1], values[2]))
      local sync = false
      lib.get(function(err, value) h.eq(nil, err); h.truthy(rawequal(values[1], value)); sync = true end)
      h.truthy(sync)
      h.eq(1, reads)
      lib.invalidate()
      load(lib)
      h.eq(2, reads)
    end)
  end },
  { name = 'Library reloads a matching disk cache without querying SQLite', run = function()
    with_library(function(_, sqlite, lib, cache)
      local first = load(lib)
      h.wait(function()
        local ok, raw = pcall(vim.fn.readfile, cache)
        return ok and pcall(vim.json.decode, table.concat(raw, '\n'))
      end)
      package.loaded['ibid.library'] = nil
      local fresh = require('ibid.library')
      sqlite.read = function() error('matching cache must not query SQLite') end
      local called = false
      fresh.get(function(err, value)
        h.eq(nil, err)
        h.eq(first.by_key.doe2020.title, value.by_key.doe2020.title)
        h.eq(first.signature, value.signature)
        called = true
      end)
      h.truthy(called)
    end)
  end },
  { name = 'Database changes invalidate cached library content', run = function()
    with_library(function(_, sqlite, lib)
      local first = load(lib)
      local result = vim.system({ 'sqlite3', sqlite.db_path(),
        "UPDATE itemDataValues SET value = 'An updated study title' WHERE valueID = 1;" }, {text=true}):wait()
      h.eq(0, result.code)
      h.truthy(first.signature ~= sqlite.signature())
      local updated = load(lib)
      h.eq('An updated study title', updated.by_key.doe2020.title)
      h.eq('A careful study', first.by_key.doe2020.title)
    end)
  end },
  { name = 'SQLite signature tracks WAL creation modification and removal', run = function()
    with_library(function(_, sqlite)
      local initial = sqlite.signature()
      local wal = sqlite.db_path() .. '-wal'
      -- Signature checks stat only; no read attempts to replay these sentinel bytes.
      vim.fn.writefile({'first'}, wal)
      local added = sqlite.signature()
      h.truthy(initial ~= added)
      vim.fn.writefile({'a longer sentinel'}, wal)
      h.truthy(added ~= sqlite.signature())
      vim.fn.delete(wal)
      h.eq(initial, sqlite.signature())
    end)
  end },
  { name = 'Legacy library cache is refreshed to include annotation providers', run = function()
    with_library(function(_, sqlite, lib, cache)
      vim.fn.mkdir(vim.fs.dirname(cache), 'p')
      vim.fn.writefile({vim.json.encode({signature=sqlite.signature(),data={items={}}})}, cache)
      local fresh = load(lib)
      h.eq(3, #fresh.items)
      h.eq('Highlighted text', fresh.by_key.doe2020.annotations[1].text)
    end)
  end },
  { name = 'Missing database reports errors through both public load paths', run = function()
    with_library(function(dir, sqlite, lib)
      vim.fn.delete(dir .. '/zotero.sqlite')
      h.eq(nil, sqlite.signature())
      local err
      lib.get(function(e) err = e end)
      h.truthy(err and err:find('no Zotero database', 1, true))
      local done = false
      sqlite.read(function(e) err, done = e, true end)
      h.wait(function() return done end)
      h.truthy(err and err:find('no Zotero database', 1, true))
    end)
  end },
}
