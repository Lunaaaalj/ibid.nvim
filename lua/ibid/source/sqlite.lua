-- Reads the whole library out of zotero.sqlite in one `sqlite3` call.
--
-- Zotero keeps the database locked and in WAL mode while it runs, so the
-- file is never opened in place: zotero.sqlite and its -wal are copied to a
-- per-process cache dir and the copy is queried. (`?immutable=1` would avoid
-- the copy but ignores the WAL, i.e. anything Zotero hasn't checkpointed
-- yet.) Nothing here ever writes to Zotero's files.

local config = require("ibid.config")

local M = {}

local uv = vim.uv

local dir = ("%s/ibid/db-%d"):format(vim.fn.stdpath("cache"), uv.os_getpid())

-- One JSON document for everything. Every subquery is wrapped in json():
-- SQLite's JSON subtype doesn't survive a subquery, and without it nested
-- arrays come back as escaped strings.
M.query = [[
with f as (
  select d.itemID, fl.fieldName k, v.value v
  from itemData d join fields fl using (fieldID) join itemDataValues v using (valueID)
)
select json_object(
  'items', json((
    select json_group_array(json_object(
      'id', i.itemID, 'zkey', i.key, 'lib', i.libraryID, 'type', t.typeName,
      'added', i.dateAdded, 'modified', i.dateModified,
      'fields', json((select json_group_object(f.k, f.v) from f where f.itemID = i.itemID)),
      'creators', json((
        select json_group_array(json_array(last, first, role)) from (
          select c.lastName last, c.firstName first, ct.creatorType role
          from itemCreators ic join creators c using (creatorID) join creatorTypes ct using (creatorTypeID)
          where ic.itemID = i.itemID order by ic.orderIndex))),
      'tags', json((
        select json_group_array(tg.name) from itemTags it join tags tg using (tagID)
        where it.itemID = i.itemID)),
      'collections', json((
        select json_group_array(ci.collectionID) from collectionItems ci where ci.itemID = i.itemID)),
      'attachments', json((
        select json_group_array(json_object(
          'zkey', a.key, 'type', ia.contentType, 'path', ia.path, 'mode', ia.linkMode,
          'title', (select f.v from f where f.itemID = ia.itemID and f.k = 'title')))
        from itemAttachments ia join items a on a.itemID = ia.itemID
        where ia.parentItemID = i.itemID and ia.itemID not in (select itemID from deletedItems)))
    ))
    from items i join itemTypes t using (itemTypeID)
    where t.typeName not in ('attachment', 'note', 'annotation')
      and i.itemID not in (select itemID from deletedItems)
  )),
  'collections', json((
    select json_group_array(json_object(
      'id', collectionID, 'name', collectionName, 'parent', parentCollectionID,
      'zkey', key, 'lib', libraryID))
    from collections)),
  'groups', json((
    select json_group_array(json_object('lib', libraryID, 'id', groupID, 'name', name))
    from groups))
);
]]

function M.db_path() return config.data_dir() .. "/zotero.sqlite" end

-- "size:mtime" of the database and its WAL: changes whenever Zotero writes.
function M.signature()
  local db = uv.fs_stat(M.db_path())
  if not db then return nil end
  local wal = uv.fs_stat(M.db_path() .. "-wal")
  local function part(s) return s and ("%d:%d.%d"):format(s.size, s.mtime.sec, s.mtime.nsec) or "-" end
  return part(db) .. "|" .. part(wal)
end

local function copy(src, dst, cb)
  uv.fs_copyfile(src, dst, nil, function(err) cb(err) end)
end

-- read(cb): cb(err, data) with data = { items, collections, groups } (raw
-- rows; library.lua normalises them). cb runs on the main loop.
function M.read(cb)
  local done = vim.schedule_wrap(cb)
  if vim.fn.executable("sqlite3") == 0 then return done("sqlite3 not found") end
  local src = M.db_path()
  if not uv.fs_stat(src) then return done("no Zotero database at " .. src) end
  vim.fn.mkdir(dir, "p")
  local db = dir .. "/zotero.sqlite"
  -- a stale WAL from an earlier copy would be replayed onto the new one
  os.remove(db .. "-wal")
  os.remove(db .. "-shm")
  copy(src, db, function(err)
    if err then return done("copying the database: " .. err) end
    local wal = uv.fs_stat(src .. "-wal")
    local function query()
      vim.system({ "sqlite3", "-batch", "-noheader", "-list", db, M.query }, { text = true }, function(res)
        if res.code ~= 0 then return done("sqlite3: " .. vim.trim(res.stderr or "")) end
        local ok, data = pcall(vim.json.decode, res.stdout, { luanil = { object = true, array = true } })
        if not ok or type(data) ~= "table" then return done("could not parse the library") end
        done(nil, data)
      end)
    end
    if wal and wal.size > 0 then
      copy(src .. "-wal", db .. "-wal", function() query() end)
    else
      query()
    end
  end)
end

-- Remove this process's copy (VimLeavePre).
function M.cleanup() vim.fn.delete(dir, "rf") end

return M
