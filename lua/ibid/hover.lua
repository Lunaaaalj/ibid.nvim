-- hover.nvim provider: the Zotero card for the citation key under the
-- cursor. Priority 1001, just above LSP, but only enabled on a key that is
-- in the library, so K everywhere else is untouched.
--
--   require("hover").config({ providers = { "ibid.hover", … } })

local config = require("ibid.config")
local library = require("ibid.library")
local scan = require("ibid.cite.scan")

local function item_here(bufnr)
  if not vim.tbl_contains(config.options.filetypes, vim.bo[bufnr].filetype) then return nil end
  if not library.current() then return nil end
  local key = scan.key_at(bufnr)
  return key and library.item(key)
end

return {
  name = "Zotero",
  priority = 1001,
  enabled = function(bufnr) return item_here(bufnr) ~= nil end,
  execute = function(params, done)
    local it = item_here(params.bufnr)
    if not it then return done() end
    done({ lines = require("ibid.card").lines(it, math.max(40, math.min(80, vim.o.columns - 12))),
      filetype = "markdown" })
  end,
}
