-- :Ibid [cite]                     pick items and insert a citation
-- :Ibid cayw                       cite through Better BibTeX's picker
-- :Ibid sync[!]                    write the cited entries to the .bib (! = re-export all, take over a hand-written .bib)
-- :Ibid info|pdf|zotero|url        the item under the cursor (else a picker)
-- :Ibid key|bibtex|reference       yank it
-- :Ibid reload                     re-read the library
-- Nothing else runs at startup; autocmds come from setup().

if vim.g.loaded_ibid then return end
vim.g.loaded_ibid = true

local subs = {
  cite = function(ibid) ibid.cite() end,
  cayw = function(ibid) ibid.cayw() end,
  sync = function(ibid, bang) ibid.sync({ force = bang, adopt = bang }) end,
  info = function(ibid) ibid.info() end,
  pdf = function(ibid) ibid.open_pdf() end,
  zotero = function(ibid) ibid.show_in_zotero() end,
  url = function(ibid) ibid.open_url() end,
  key = function(ibid) ibid.yank_key() end,
  bibtex = function(ibid) ibid.yank_bibtex() end,
  reference = function(ibid) ibid.yank_reference() end,
  reload = function(ibid) ibid.reload() end,
  lint = function(ibid) ibid.lint() end,
}

vim.api.nvim_create_user_command("Ibid", function(cmd)
  local sub = cmd.fargs[1] or "cite"
  if not subs[sub] then return vim.notify("ibid: unknown argument '" .. sub .. "'", vim.log.levels.ERROR) end
  subs[sub](require("ibid"), cmd.bang)
end, {
  nargs = "?",
  bang = true,
  desc = "Zotero: cite, sync the .bib, item actions",
  complete = function(lead)
    local names = vim.tbl_keys(subs)
    table.sort(names)
    return vim.tbl_filter(function(n) return n:find(lead, 1, true) == 1 end, names)
  end,
})
