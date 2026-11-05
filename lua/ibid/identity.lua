-- Read-only identity helpers shared by lint and future ingestion workflows.
local M = {}

function M.doi(value)
  if type(value) ~= "string" then return nil end
  local doi = vim.trim(value):lower()
  doi = doi:gsub("^https?://doi%.org/", ""):gsub("^https?://dx%.doi%.org/", ""):gsub("^https?://www%.doi%.org/", ""):gsub("^doi:%s*", "")
  if doi == "" then return nil end
  return doi
end

function M.title_year(item)
  local title = vim.fn.tolower(vim.trim(item.title or "")):gsub("[%s%p]", "")
  local year = tostring(item.year or ""):match("^%d%d%d%d$")
  if title == "" or not year then return nil end
  return title .. "\0" .. year
end

function M.matches(a, b)
  local ad, bd = M.doi(a.doi), M.doi(b.doi)
  if ad and bd and ad == bd then return true end
  local at, bt = M.title_year(a), M.title_year(b)
  return at ~= nil and at == bt
end

return M
