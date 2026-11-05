local h = require('tests.helpers')
local backlinks = require('ibid.backlinks')
local function with_stub(fn)
  local system, executable = vim.system, vim.fn.executable
  vim.fn.executable = function(bin) if bin=='rg' then return 1 end; return executable(bin) end
  local ok, err = xpcall(fn,debug.traceback)
  vim.system,vim.fn.executable=system,executable
  if not ok then error(err) end
end
return {
  {name='backlinks use literal shell-safe candidates and filter substrings and code',run=function()
    with_stub(function()
      local dir=h.tempdir();local path=dir..'/a space.md'
      vim.fn.writefile({'[@wanted; @wantedExtra]','`@wanted`','user@wanted.org'},path)
      vim.system=function(cmd,opts,cb)
        h.eq({'rg','--files-with-matches','--null','--fixed-strings','--','wanted',dir..'/'},cmd)
        cb({code=0,stdout=path..'\0'})
      end
      local done, result
      backlinks.find({key='wanted'},{roots={dir}},function(err,hits)h.eq(nil,err);result=hits;done=true end)
      h.wait(function()return done end)
      h.eq(1,#result);h.eq(path,result[1].filename);h.eq(1,result[1].lnum);h.eq(3,result[1].col)
    end)
  end},
  {name='backlinks refresh loaded buffers after deferred search and tolerate deletion',run=function()
    with_stub(function()
      local dir=h.tempdir();local path=dir..'/changed.md';local deleted=dir..'/deleted.md'
      vim.fn.writefile({'[@wanted]'},path);vim.fn.writefile({'[@wanted]'},deleted)
      local dead=vim.fn.bufadd(deleted);vim.fn.bufload(dead);vim.bo[dead].filetype='markdown'
      local completion
      vim.system=function(_,_,cb)completion=cb end
      local done,result
      backlinks.find({key='wanted'},{roots={dir}},function(err,hits)h.eq(nil,err);result=hits;done=true end)
      vim.api.nvim_buf_delete(dead,{force=true})
      local changed=vim.fn.bufadd(path);vim.fn.bufload(changed);vim.bo[changed].filetype='markdown'
      vim.api.nvim_buf_set_lines(changed,0,-1,false,{'No citation in unsaved buffer'})
      completion({code=0,stdout=path..'\0'..deleted..'\0'})
      h.wait(function()return done end)
      vim.api.nvim_buf_delete(changed,{force=true})
      h.eq(1,#result);h.eq(deleted,result[1].filename)
    end)
  end},
  {name='backlinks searches loaded unsaved buffers without rg and reports process failures',run=function()
    with_stub(function()
      local dir=h.tempdir();local buf=vim.api.nvim_create_buf(false,true)
      vim.api.nvim_buf_set_name(buf,dir..'/unsaved.tex');vim.bo[buf].filetype='tex'
      vim.api.nvim_buf_set_lines(buf,0,-1,false,{[[\cite{unsaved}]]})
      local ok,err=xpcall(function()
        vim.system=function()error('no process needed for open buffers')end
        local hits
        backlinks.find({key='unsaved'},{roots={}},function(e,v)h.eq(nil,e);hits=v end)
        h.eq(1,#hits);h.eq(buf,hits[1].bufnr)
        local done, failure
        vim.system=function(_,_,cb)cb({code=2,stderr='permission denied'})end
        backlinks.find({key='unsaved'},{roots={dir}},function(e)failure=e;done=true end)
        h.wait(function()return done end);h.truthy(failure:find('permission denied',1,true))
      end,debug.traceback)
      vim.api.nvim_buf_delete(buf,{force=true})
      if not ok then error(err)end
    end)
  end},
}
