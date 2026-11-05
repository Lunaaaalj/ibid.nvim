local h = require("tests.helpers")
local notes = require("ibid.notes")
local function item()
  return { key = 'doe2020', zkey = 'ITEM0001', lib = 1, title = 'A "quoted" title',
    author_list = 'Doe, Jane', year = '2020', doi = '10.1/test', abstract = 'Abstract text.',
    annotations = { {id='AAA',text='Highlight',comment='Comment',color='#ffd400',page_label='iv',page=4,attachment_zkey='PDF00001'} } }
end
local function text(path) return table.concat(vim.fn.readfile(path), '\n') end
return {
  { name = 'notes render escaped metadata and append only unseen annotation identities', run = function()
    local dir = h.tempdir()
    local it = item()
    local path, err = notes.update(it, {dir=dir})
    h.eq(nil, err)
    local original = text(path)
    h.truthy(original:find('title: "A \\"quoted\\" title"',1,true))
    h.truthy(original:find('Page iv',1,true))
    h.truthy(original:find('Abstract text.',1,true))
    vim.fn.writefile({'', 'My own writing.'}, path, 'a')
    it.annotations[2] = {id='BBB',text='A new annotation',color='#00ff00',page=8}
    notes.update(it, {dir=dir})
    local updated = text(path)
    h.truthy(updated:find('My own writing.',1,true))
    h.truthy(updated:find('A new annotation',1,true))
    h.eq(1, select(2, updated:gsub('Highlight','')))
    local stat = vim.uv.fs_stat(path)
    notes.update(it,{dir=dir})
    h.eq(updated,text(path))
    h.eq(stat.mtime,vim.uv.fs_stat(path).mtime)
  end },
  { name = 'notes preserve unsaved buffer writing and encode traversal keys', run = function()
    local dir = h.tempdir()
    local it = item(); it.key = '../escape'
    local path = assert(notes.update(it,{dir=dir}))
    h.eq(dir .. '/%2E%2E%2Fescape.md',path)
    local buf = vim.fn.bufadd(path); vim.fn.bufload(buf)
    local ok, err = xpcall(function()
      vim.api.nvim_buf_set_lines(buf,-1,-1,false,{'Unsaved writing'})
      it.annotations[2] = {id='CCC',text='Extra',color='blue'}
      notes.update(it,{dir=dir})
      local joined = table.concat(vim.api.nvim_buf_get_lines(buf,0,-1,false),'\n')
      h.truthy(joined:find('Unsaved writing',1,true))
      h.truthy(joined:find('Extra',1,true))
      h.truthy(not text(path):find('Extra',1,true))
    end,debug.traceback)
    vim.api.nvim_buf_delete(buf,{force=true})
    if not ok then error(err) end
  end },
  { name = 'notes Typst text is literal and nonregular paths are refused', run = function()
    local dir = h.tempdir(); local it = item()
    it.title = '#panic("bad")'; it.abstract = '#panic("abstract")'
    local path = assert(notes.update(it,{dir=dir,format='typst'}))
    h.truthy(text(path):find('#text("#panic(\\"bad\\")")',1,true))
    local reserved = item(); reserved.key='CON'
    h.truthy(assert(notes.update(reserved,{dir=dir})):find('/%43ON.md',1,true))
    local link = dir .. '/other.md'
    assert(vim.uv.fs_symlink(path,link))
    it.key='other'
    local p, err = notes.update(it,{dir=dir})
    h.eq(nil,p); h.truthy(err:find('non%-regular'))
    h.eq(nil, notes.update(item(),{dir=dir,format='bad'}))
  end },
  { name = 'page-aware PDF action chooses annotation attachment and keeps old hooks compatible', run = function()
    local library = require('ibid.library'); local actions = require('ibid.actions'); local config = require('ibid.config')
    local saved = {pdf=library.pdf,hook=config.options.open_pdf}
    local it = item(); local opts = {page=4,attachment_zkey='PDF2'}
    local ok, err = xpcall(function()
      library.pdf = function(actual, attachment) h.eq(it,actual); h.eq('PDF2',attachment); return '/fixture.pdf' end
      config.options.open_pdf = function(path, actual, got) h.eq('/fixture.pdf',path); h.eq(it,actual); h.eq(opts,got) end
      actions.open_pdf(it,opts)
      config.options.open_pdf = function(path, actual) h.eq('/fixture.pdf',path); h.eq(it,actual) end
      actions.open_pdf(it,opts)
    end, debug.traceback)
    library.pdf,config.options.open_pdf = saved.pdf,saved.hook
    if not ok then error(err) end
  end },
  { name = 'child note conversion uses optional pandoc and falls back safely', run = function()
    local original_system, original_executable = vim.system, vim.fn.executable
    local ok, err = xpcall(function()
      vim.fn.executable = function(bin) if bin=='pandoc' then return 1 end; return original_executable(bin) end
      vim.system = function(cmd, opts, cb)
        h.eq({'pandoc','--from=html','--to=gfm'},cmd); h.eq('<p>Text</p>',opts.stdin)
        cb({code=0,stdout='**Text**\n'})
      end
      local done, result
      notes.child_text({html='<p>Text</p>'},function(_,v) result=v;done=true end)
      h.wait(function() return done end); h.eq('**Text**',result)
      vim.fn.executable = function(bin) if bin=='pandoc' then return 0 end; return original_executable(bin) end
      notes.child_text({html='<p>A &amp; B</p><script>bad()</script>'},function(_,v) result=v end)
      h.eq('A & B',result)
    end,debug.traceback)
    vim.system,vim.fn.executable=original_system,original_executable
    if not ok then error(err) end
  end },
}
