local h = require("tests.helpers")
local cases = {}
local function item(key, opts)
  return vim.tbl_extend("force", {key=key,zkey=key,lib=1,title="Title "..key,authors="Author",author_list="Author, A",year="2020",date="2020",type="book",tags={},collections={},attachments={},people={{last="Author",first="A"}},search=key,added="2020-01-01"},opts or {})
end
local function fixture()
  return {items={
    item("alpha",{collections={2},tags={"methods"},added="2022-01-01"}),
    item("beta",{collections={1},tags={"review"},added="2023-01-01"}),
    item("gamma",{collections={3},tags={"methods"},added="2021-01-01"}),
  },collections={[1]={id=1,name="Research"},[2]={id=2,name="Child",parent=1},[3]={id=3,name="Unrelated"}},groups={}}
end
local function test(name, run)
  cases[#cases+1]={name="browser: "..name,run=function()
    local lib=require("ibid.library")
    local original={get=lib.get,invalidate=lib.invalidate,lib=lib.lib,input=vim.ui.input,notify=vim.notify,browser=package.loaded["ibid.browser"]}
    local win=vim.api.nvim_get_current_win()
    local buf=vim.api.nvim_create_buf(false,true)
    local old_buf=vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(win,buf)
    vim.bo[buf].filetype="markdown"
    vim.api.nvim_buf_set_lines(buf,0,-1,false,{"Text"})
    package.loaded["ibid.browser"]=nil
    local browser=require("ibid.browser")
    local ctx={browser=browser,lib=fixture(),doc=buf,win=win,notices={}}
    lib.get=function(cb) cb(nil,ctx.lib) end
    lib.invalidate=function() ctx.invalidated=true end
    lib.lib=ctx.lib
    vim.notify=function(msg) ctx.notices[#ctx.notices+1]=msg end
    function ctx.open(opts) return browser.open(opts) end
    function ctx.key(s,key)
      vim.api.nvim_set_current_win(s.list_win)
      local mapping=vim.fn.maparg(key,"n",false,true)
      h.truthy(type(mapping.callback)=="function","missing mapping "..key)
      mapping.callback()
    end
    local ok,err=xpcall(function() run(ctx,lib) end,debug.traceback)
    browser.close()
    lib.get,lib.invalidate,lib.lib=original.get,original.invalidate,original.lib
    vim.ui.input,vim.notify=original.input,original.notify
    package.loaded["ibid.browser"]=original.browser
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_set_current_win(win);vim.api.nvim_win_set_buf(win,old_buf) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf,{force=true}) end
    if not ok then error(err) end
  end}
end

test("native rows update cards, expose actions, and restore focus",function(c)
  local s=c.open()
  h.eq("ibid",vim.bo[s.list_buf].filetype)
  h.eq("markdown",vim.bo[s.detail_buf].filetype)
  h.truthy(vim.wo[s.list_win].cursorline)
  h.eq(3,#s.rows)
  vim.api.nvim_win_set_cursor(s.list_win,{2,0})
  vim.api.nvim_exec_autocmds("CursorMoved",{buffer=s.list_buf})
  h.truthy(table.concat(vim.api.nvim_buf_get_lines(s.detail_buf,0,-1,false),"\n"):find("Title beta",1,true))
  local actions=require("ibid.actions")
  local original=actions.open_pdf
  local picked
  actions.open_pdf=function(it) picked=it.key end
  local ok,err=pcall(function() c.key(s,"o");h.eq("beta",picked) end)
  actions.open_pdf=original
  if not ok then error(err) end
  require("ibid.diagnostics").refresh(s.list_buf)
  h.eq({},vim.diagnostic.get(s.list_buf))
  local list_buf,detail_buf=s.list_buf,s.detail_buf
  c.key(s,"q")
  h.eq(false,s.alive)
  h.eq(c.win,vim.api.nvim_get_current_win())
  h.eq(false,vim.api.nvim_buf_is_valid(list_buf))
  h.eq(false,vim.api.nvim_buf_is_valid(detail_buf))
end)

test("collection tree selects parent descendants and returns to selector",function(c)
  local s=c.open();c.key(s,"2")
  h.eq(2,s.tab)
  h.eq({"Research","  Child","Unrelated"},vim.tbl_map(function(r)return r.label end,s.rows))
  c.key(s,"<CR>")
  h.eq({"alpha","beta"},vim.tbl_map(function(r)return r.item.key end,s.rows))
  c.key(s,"<BS>")
  vim.api.nvim_win_set_cursor(s.list_win,{2,0});c.key(s,"<CR>")
  h.eq({"alpha"},vim.tbl_map(function(r)return r.item.key end,s.rows))
  c.key(s,"<Tab>");h.eq(3,s.tab)
  c.key(s,"<S-Tab>");h.eq(2,s.tab)
  h.eq("alpha",s.rows[1].item.key)
end)

test("tag filter, cancelled prompt, and tab cursor survive reopening",function(c)
  local s=c.open();c.key(s,"3")
  h.eq({"methods","review"},vim.tbl_map(function(r)return r.label end,s.rows))
  c.key(s,"<CR>")
  h.eq({"alpha","gamma"},vim.tbl_map(function(r)return r.item.key end,s.rows))
  vim.ui.input=function(_,cb) cb(nil) end
  c.key(s,"/");h.eq("",s.filter)
  vim.ui.input=function(_,cb) cb("gamma") end
  c.key(s,"/");h.eq(1,#s.rows);h.eq("gamma",s.rows[1].item.key)
  s.close();s=c.open()
  h.eq(3,s.tab);h.eq("methods",s.scope);h.eq("gamma",s.filter)
  h.eq("gamma",s.rows[1].item.key)
end)

test("recent sorts newest and lint Enter selects its item",function(c)
  c.lib.items[1].people={}
  local s=c.open({recent_limit=2});c.key(s,"4")
  h.eq({"beta","alpha"},vim.tbl_map(function(r)return r.item.key end,s.rows))
  c.key(s,"5");h.eq("missing-creators",s.rows[1].finding.code)
  local actions=require("ibid.actions");local original=actions.show_in_zotero;local picked
  actions.show_in_zotero=function(it)picked=it.key end
  local ok,err=pcall(function()c.key(s,"<CR>");h.eq("alpha",picked);h.truthy(s.alive)end)
  actions.show_in_zotero=original
  if not ok then error(err) end
end)

test("cite closes before callback and targets the captured document",function(c)
  local picked,context
  local s=c.open({on_select=function(items,ctx)picked=items[1].key;context=ctx;h.eq(c.win,vim.api.nvim_get_current_win())end})
  vim.api.nvim_win_set_cursor(s.list_win,{2,0});c.key(s,"i")
  h.eq("beta",picked);h.eq(c.doc,context.buf);h.eq(false,s.alive)
  h.eq({"Text"},vim.api.nvim_buf_get_lines(c.doc,0,-1,false))
end)

test("default cite uses shared insertion after closing the float",function(c)
  local s=c.open();c.key(s,"i")
  h.eq({"T[@alpha]ext"},vim.api.nvim_buf_get_lines(c.doc,0,-1,false))
  h.eq(false,s.alive)
end)

test("resize preserves selection and external close cleans both panes",function(c)
  local s=c.open()
  vim.api.nvim_win_set_cursor(s.list_win,{2,0})
  vim.api.nvim_exec_autocmds("CursorMoved",{buffer=s.list_buf})
  vim.api.nvim_exec_autocmds("VimResized",{})
  h.eq(2,vim.api.nvim_win_get_cursor(s.list_win)[1])
  h.truthy(vim.api.nvim_win_get_width(s.detail_win)>0)
  vim.api.nvim_win_close(s.detail_win,true)
  h.eq(false,s.alive)
  h.eq(false,vim.api.nvim_win_is_valid(s.list_win))
  h.eq(c.win,vim.api.nvim_get_current_win())
end)

test("empty library remains navigable and shows help",function(c)
  c.lib.items={};c.lib.collections={}
  local s=c.open()
  h.eq({"(no items)"},vim.api.nvim_buf_get_lines(s.list_buf,0,-1,false))
  c.key(s,"i");h.truthy(s.alive)
  c.key(s,"?");h.eq("# Library browser",vim.api.nvim_buf_get_lines(s.detail_buf,0,1,false)[1])
  c.key(s,"2");h.eq(0,#s.rows)
  vim.api.nvim_set_current_win(s.detail_win)
  vim.fn.maparg("q","n",false,true).callback()
  h.eq(false,s.alive)
end)

test("closed loading session and stale reload callbacks cannot reopen or replace UI",function(c,lib)
  local callbacks={}
  lib.get=function(cb)callbacks[#callbacks+1]=cb end
  local s=c.open();s.close();callbacks[1](nil,c.lib)
  h.eq(nil,s.list_win)
  callbacks={}
  lib.get=function(cb)cb(nil,c.lib)end
  s=c.open()
  lib.get=function(cb)callbacks[#callbacks+1]=cb end
  c.key(s,"r");c.key(s,"r");h.truthy(c.invalidated)
  local latest={items={item("latest")},collections={},groups={}}
  callbacks[2](nil,latest);callbacks[1](nil,c.lib)
  h.eq("latest",s.rows[1].item.key)
  c.key(s,"r");s.close();callbacks[3](nil,c.lib)
  h.eq(false,s.alive)
end)

return cases
