local h = require("tests.helpers")
local lint = require("ibid.lint")
local identity = require("ibid.identity")
local function item(key, opts)
  return vim.tbl_extend("force", { key = key, zkey = key, lib = 1, title = key, year = "2020",
    people = { {first="Jane",last="Doe"} }, attachments = {}, type = "book" }, opts or {})
end
local function codes(findings)
  return vim.tbl_map(function(f) return f.code end, findings)
end
return {
  { name = "identity normalizes DOI prefixes case and title punctuation", run = function()
    h.eq("10.123/a", identity.doi(" DOI: 10.123/A "))
    h.eq("10.123/a", identity.doi("https://dx.doi.org/10.123/A"))
    h.eq("10.123/a", identity.doi("https://doi.org/10.123/A"))
    h.eq("10.123/a", identity.doi(" HTTPS://WWW.DOI.ORG/10.123/A "))
    h.eq(nil, identity.doi("  "))
    h.truthy(identity.matches({doi="10.123/a"}, {doi="https://doi.org/10.123/A"}))
    h.truthy(identity.matches({title="A Test: Book",year="2020"}, {title="a test book",year="2020"}))
    h.eq(false, identity.matches({title="A",year="2020"}, {title="A",year="2021"}))
    h.eq(false, identity.matches({title="",year=""}, {title="",year=""}))
    h.eq(false, identity.matches({title="A"}, {title="A"}))
  end },
  { name = "lint checks missing metadata invalid long keys and absent DOI", run = function()
    local it = item(":invalid", { people={},year="",type="journalArticle" })
    h.eq({"missing-creators","missing-year","invalid-key","long-key","missing-doi"},
      codes(lint.check({items={it}}, {max_key_length=3})))
    h.eq({}, lint.check({items={item("valid")}}))
  end },
  { name = "lint exposes explained swapped-name heuristics without modifying items", run = function()
    local bad = item("swapped", {people={{first="CASELLA",last="George"}}})
    local other = item("other", {people={{first="Jane",last="Casella"}}})
    local match = item("matched", {people={{first="Casella",last="George"}}})
    local before = vim.deepcopy({bad,other,match})
    local found = lint.check({items={bad,other,match}})
    h.eq({"swapped-names","swapped-names"}, codes(found))
    h.truthy(found[1].message:find("Possible swapped",1,true))
    h.truthy(found[1].message:find("surname-like",1,true))
    h.eq(before,{bad,other,match})
  end },
  { name = "lint duplicate groups are deterministic and do not match missing identities", run = function()
    local a = item("a",{doi="10.1/example",title="A test",year="2024"})
    local b = item("b",{doi="https://doi.org/10.1/EXAMPLE",title="A test!",year="2024"})
    local c = item("c",{title="A test",year="2024"})
    local found = lint.check({items={c,b,a}})
    h.eq({"duplicate","duplicate","duplicate"}, codes(found))
    h.eq({"a","b","c"},vim.tbl_map(function(f) return f.key end,found))
    h.eq({b,c},found[1].related)
    h.eq(found,lint.check({items={a,b,c}}))
    local empty1,empty2=item("empty1",{title="",year=""}),item("empty2",{title="",year=""})
    h.eq({"missing-year","missing-year"},codes(lint.check({items={empty1,empty2}})))
  end },
  { name = "lint flags only resolved PDF paths missing on disk", run = function()
    local dir = h.tempdir()
    local present = dir .. "/exists.pdf"
    vim.fn.writefile({"pdf"},present)
    local it = item("pdf",{attachments={
      {type="application/pdf",path=present}, {type="application/pdf",path=dir .. "/absent.pdf"},
      {type="application/pdf"}, {type="text/html",path=dir .. "/page.html"},
    }})
    local found = lint.check({items={it}})
    h.eq({"missing-pdf"},codes(found))
    h.truthy(found[1].message:find("absent.pdf",1,true))
  end },
  { name = "lint quickfix opens the selected Zotero item and rejects replaced lists", run = function()
    local library = require("ibid.library")
    local actions = require("ibid.actions")
    local old_get,old_open,old_feedkeys = library.get,actions.show_in_zotero,vim.api.nvim_feedkeys
    local original = vim.api.nvim_get_current_win()
    local first,second=item("a",{year=""}),item("b",{year=""})
    local opened
    local ok,err=xpcall(function()
      library.get=function(cb) cb(nil,{items={second,first}}) end
      actions.show_in_zotero=function(it) opened=it end
      lint.open()
      local qf=vim.fn.getqflist({items=0,context=0})
      h.eq(2,#qf.items)
      h.eq("lint",qf.context.ibid)
      h.eq(1,vim.fn.getqflist({idx=0}).idx)
      vim.api.nvim_win_set_cursor(0,{2,0})
      local mapping=vim.fn.maparg("<CR>","n",false,true)
      h.eq("function",type(mapping.callback))
      mapping.callback()
      h.eq(second,opened)
      vim.fn.setqflist({}," ",{title="unrelated",items={{text="unrelated"}}})
      h.eq(false,lint.open_selected())
      local fallback
      vim.api.nvim_feedkeys=function(keys,mode,escape) fallback={keys,mode,escape} end
      mapping.callback()
      h.eq({vim.keycode("<CR>"),"n",false},fallback)
      h.eq(second,opened)
    end,debug.traceback)
    library.get,actions.show_in_zotero,vim.api.nvim_feedkeys=old_get,old_open,old_feedkeys
    vim.cmd("cclose")
    if vim.api.nvim_win_is_valid(original) then vim.api.nvim_set_current_win(original) end
    if not ok then error(err,0) end
  end },
}
