-- Findings are advisory. Metadata corrections always happen in Zotero.
local identity = require("ibid.identity")
local M = {}
local common_first = {}
for word in ("james john robert michael william david richard joseph thomas charles george mary patricia jennifer linda elizabeth barbara susan jessica sarah karen anna maria jose juan luis carlos"):gmatch("%S+") do
  common_first[word] = true
end

local function id(item)
  return tostring(item.lib or "") .. ":" .. (item.zkey or item.key or "")
end

-- check(lib, {max_key_length?}) -> { {code, message, item, key, severity, related?} }
-- Stable ordering allows the same findings to drive a browser or quickfix.
function M.check(lib, opts)
  opts = opts or require("ibid.config").options.lint or {}
  local limit = tonumber(opts.max_key_length) or 100
  local items = vim.list_extend({}, lib.items or {})
  table.sort(items, function(a, b)
    local ak, bk = a.key or "", b.key or ""
    if ak ~= bk then return ak < bk end
    return id(a) < id(b)
  end)
  local surnames, dois, titles = {}, {}, {}
  local function group(index, key, item)
    if not key then return end
    index[key] = index[key] or {}
    table.insert(index[key], item)
  end
  for _, item in ipairs(items) do
    for _, person in ipairs(item.people or {}) do
      if person.last and person.last ~= "" then surnames[vim.fn.tolower(person.last)] = true end
    end
    group(dois, identity.doi(item.doi), item)
    group(titles, identity.title_year(item), item)
  end
  local out = {}
  local function add(item, code, message, related)
    out[#out + 1] = { code = code, message = message, item = item,
      key = item.key, severity = "warning", related = related }
  end
  for _, item in ipairs(items) do
    if #(item.people or {}) == 0 then add(item, "missing-creators", "No creators") end
    if not tostring(item.year or ""):match("%d%d%d%d") then add(item, "missing-year", "No date/year") end
    local key = item.key or ""
    if not key:match("^[A-Za-z]") then add(item, "invalid-key", "Citation key must start with a letter") end
    if #key > limit then add(item, "long-key", ("Citation key exceeds %d characters"):format(limit)) end
    for _, person in ipairs(item.people or {}) do
      local first, last = person.first or "", person.last or ""
      local surname_like = (first:match("%u") and first == first:upper()) or surnames[vim.fn.tolower(first)]
      if first ~= "" and common_first[vim.fn.tolower(last)] and surname_like then
        add(item, "swapped-names", ("Possible swapped creator names: first '%s', last '%s' (surname-like first name and common given name in last field)"):format(first, last))
      end
    end
    if (item.type == "journalArticle" or item.type == "conferencePaper") and not identity.doi(item.doi) then
      add(item, "missing-doi", "Missing DOI")
    end
    local duplicate = {}
    local seen = {}
    for _, bucket in ipairs({ dois[identity.doi(item.doi)] or {}, titles[identity.title_year(item)] or {} }) do
      for _, other in ipairs(bucket) do
        if other ~= item and not seen[other] then duplicate[#duplicate + 1], seen[other] = other, true end
      end
    end
    table.sort(duplicate, function(a, b) return id(a) < id(b) end)
    if #duplicate > 0 then
      local labels = vim.tbl_map(function(other) return other.key or other.zkey or "unkeyed item" end, duplicate)
      add(item, "duplicate", "Possible duplicate: " .. table.concat(labels, ", ") .. " (same DOI or normalized title and year)", duplicate)
    end
    for _, attachment in ipairs(item.attachments or {}) do
      -- nil paths are unresolved/unsupported, not evidence of a missing file.
      if attachment.type == "application/pdf" and attachment.path and not vim.uv.fs_stat(attachment.path) then
        add(item, "missing-pdf", "PDF attachment missing on disk: " .. attachment.path)
      end
    end
  end
  return out
end

function M.open_selected()
  local qf = vim.fn.getqflist({ context = 0, idx = 0 })
  local context = qf.context
  if type(context) ~= "table" or context.ibid ~= "lint" then return false end
  -- j/k moves the quickfix cursor without changing the list's current idx.
  local index = vim.bo.buftype == "quickfix" and vim.api.nvim_win_get_cursor(0)[1] or qf.idx
  local item = context.items and context.items[index]
  if item then require("ibid.actions").show_in_zotero(item) end
  return true
end

function M.open()
  require("ibid.library").get(function(err, lib)
    if err then return vim.notify("ibid: " .. err, vim.log.levels.ERROR) end
    local findings = M.check(lib)
    local entries, items = {}, {}
    for _, finding in ipairs(findings) do
      entries[#entries + 1] = { text = (finding.key or finding.item.zkey or "unkeyed") .. ": " .. finding.message,
        type = "W", valid = 1 }
      items[#items + 1] = finding.item
    end
    vim.fn.setqflist({}, " ", { title = "ibid: library lint", items = entries,
      context = { ibid = "lint", items = items } })
    if #entries == 0 then return vim.notify("ibid: no library lint findings") end
    vim.cmd("copen")
    vim.keymap.set("n", "<CR>", function()
      if not M.open_selected() then vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false) end
    end, { buffer = vim.api.nvim_get_current_buf(), desc = "ibid: show lint item in Zotero" })
  end)
end

return M
