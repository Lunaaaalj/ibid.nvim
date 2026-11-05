local h = require('tests.helpers')
local config = require('ibid.config')
local cases = {}
local function test(name, fn)
  cases[#cases + 1] = { name = 'citation UX: ' .. name, run = function()
    local options, original_insert = config.options, package.loaded['ibid.cite.insert']
    local original_input, original_notify = vim.ui.input, vim.notify
    package.loaded['ibid.cite.insert'] = nil
    config.setup({})
    local ok, err = xpcall(function() fn(require('ibid.cite.insert')) end, debug.traceback)
    config.options, package.loaded['ibid.cite.insert'] = options, original_insert
    vim.ui.input, vim.notify = original_input, original_notify
    if not ok then error(err) end
  end }
end
local function document(ft, lines, fn)
  local previous = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = ft
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ok, err = xpcall(function() fn(buf) end, debug.traceback)
  if vim.api.nvim_buf_is_valid(previous) then vim.api.nvim_set_current_buf(previous) end
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
  if not ok then error(err) end
end

test('cycles commands per filetype and explicit commands override remembered choice', function(insert)
  h.eq('\\parencite{%s}', insert.cycle_command('tex'))
  h.eq('\\parencite{a,b}', insert.text({'a','b'}, 'tex', ''))
  h.eq('\\cite{a}', insert.text({'a'}, 'plaintex', ''))
  h.eq('\\textcite{a}', insert.text({'a'}, 'tex', '', {command='textcite'}))
  config.options.formats.tex = {'\\autocite{%s}', '\\citeauthor{%s}', sep=','}
  -- New format lists retain a valid remembered position.
  h.eq('\\citeauthor{a}', insert.text({'a'}, 'tex', ''))
end)

test('formats locators in each syntax including literal percent', function(insert)
  h.eq('\\cite[p.~12]{a,b}', insert.text({'a','b'}, 'tex', '', {locator='p.~12'}))
  h.eq('\\cite[50%]{a}', insert.text({'a'}, 'tex', '', {locator='50%'}))
  h.eq('[@a; @b, p. 12]', insert.text({'a','b'}, 'markdown', '', {locator='p. 12'}))
  h.eq('@a[p. 12]', insert.text({'a'}, 'typst', '', {locator='p. 12'}))
end)

test('locator cancellation leaves bytes unchanged and capture rejects delayed edits', function(insert)
  document('markdown', {'Text'}, function(buf)
    vim.api.nvim_win_set_cursor(0, {1,3})
    local ctx = insert.capture()
    vim.ui.input = function(_, cb) cb(nil) end
    insert.choose({'a'}, ctx, {locator=true})
    h.eq({'Text'}, vim.api.nvim_buf_get_lines(buf,0,-1,false))
    local callback
    vim.ui.input = function(_, cb) callback=cb end
    insert.choose({'a'}, ctx, {locator=true})
    vim.api.nvim_buf_set_lines(buf,0,-1,false,{'Changed'})
    local notified = false
    vim.notify = function() notified=true end
    callback('p. 3')
    h.truthy(notified)
    h.eq({'Changed'}, vim.api.nvim_buf_get_lines(buf,0,-1,false))
  end)
end)

test('replaces full multiline LaTeX citation preserving surrounding unicode', function(insert)
  document('tex', {'é before \\cite[old]{a,',' b} after'}, function(buf)
    vim.api.nvim_win_set_cursor(0,{2,1})
    local ctx=insert.capture()
    ctx.range=require('ibid.cite.range').at(buf,1,1)
    h.eq({'a','b'},ctx.range.keys)
    insert.choose({'c'},ctx,{command='parencite',locator='p.~9'})
    h.eq({'é before \\parencite[p.~9]{c} after'},vim.api.nvim_buf_get_lines(buf,0,-1,false))
  end)
end)

test('replaces grouped pandoc and complete Typst locator without deleting punctuation', function(insert)
  for _, item in ipairs({
    {'markdown','é [@a; @b, p. 2].','é [@c].',5},
    {'typst','é @a[p. 2].','é @c.',5},
    {'markdown','é @a.','é [@c].',4},
    {'typst','#cite( <a> )!','@c!',9},
    {'typst','#cite(label("a"))!','@c!',13},
  }) do
    document(item[1],{item[2]},function(buf)
      vim.api.nvim_win_set_cursor(0,{1,item[4]})
      local ctx=insert.capture()
      ctx.range=require('ibid.cite.range').at(buf,0,item[4])
      h.truthy(ctx.range)
      insert.choose({'c'},ctx)
      h.eq({item[3]},vim.api.nvim_buf_get_lines(buf,0,-1,false))
    end)
  end
end)

test('refuses commented code and unsupported multicite replacement',function()
  for _, item in ipairs({{'tex','% \\cite{a}',8},{'tex','\\cites{a}{b}',8},{'markdown','`@a`',2},{'markdown','user@example.org',6},{'typst','<a> @a',5},{'typst','"@a"',2},{'typst','"#cite(<a>)"',8}}) do
    document(item[1],{item[2]},function(buf) h.eq(nil,require('ibid.cite.range').at(buf,0,item[3])) end)
  end
end)

test('does not edit when the captured window changed buffers',function(insert)
  document('markdown',{'Text'},function(buf)
    local ctx=insert.capture()
    local other=vim.api.nvim_create_buf(false,true)
    vim.api.nvim_set_current_buf(other)
    insert.choose({'a'},ctx)
    h.eq({'Text'},vim.api.nvim_buf_get_lines(buf,0,-1,false))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_delete(other,{force=true})
  end)
end)

test('fallback replacement preserves all preselected keys until explicitly toggled and confirmed',function()
  local library=require('ibid.library')
  local get, select=library.get,vim.ui.select
  local a={key='a',authors='A',year='2020',title='A'}
  local b={key='b',authors='B',year='2021',title='B'}
  local ok,err=xpcall(function()
    library.get=function(cb) cb(nil,{items={a,b},by_key={a=a,b=b}}) end
    local choices, callback, result
    vim.ui.select=function(items,_,cb) choices,callback=items,cb end
    require('ibid.cite.picker').pick({preselected={'a','b'},on_select=function(items) result=items end})
    h.eq(true,choices[1].done)
    callback(choices[1])
    h.eq({a,b},result)
    result=nil
    require('ibid.cite.picker').pick({preselected={'a','b'},on_select=function(items) result=items end})
    callback(choices[2]) -- explicitly deselect a
    callback(choices[1])
    h.eq({b},result)
    result=nil
    require('ibid.cite.picker').pick({preselected={'a'},on_select=function(items) result=items end})
    callback(nil)
    h.eq(nil,result)
  end,debug.traceback)
  library.get,vim.ui.select=get,select
  if not ok then error(err) end
end)

test('empty completion is capped and requests a new complete list once text is typed',function()
  local library=require('ibid.library')
  local get=library.get
  local items={}
  for i=1,60 do items[i]={key='key'..i,authors='A',author_list='A',year='2020',title='Title'} end
  local ok,err=xpcall(function()
    library.get=function(cb) cb(nil,{items=items}) end
    document('markdown',{'@'},function()
      local source=require('ibid.cite.cmp').new()
      local result
      source:complete({context={cursor_before_line='@'}},function(value) result=value end)
      h.eq(50,#result.items); h.eq(true,result.isIncomplete)
      source:complete({context={cursor_before_line='@key'}},function(value) result=value end)
      h.eq(60,#result.items); h.eq(false,result.isIncomplete)
    end)
  end,debug.traceback)
  library.get=get
  if not ok then error(err) end
end)
test('locators survive partial at and bracket contexts; unsupported TeX fails explicitly', function(insert)
  h.eq('a, p. 12', insert.text({'a'}, 'markdown', '@', {locator='p. 12'}))
  h.eq('; @a, p. 12', insert.text({'a'}, 'markdown', '[@old', {locator='p. 12'}))
  h.eq('a[p. 12]', insert.text({'a'}, 'typst', '@', {locator='p. 12'}))
  local text, err = insert.text({'a'}, 'tex', '\\cite{old,', {locator='p. 12'})
  h.eq(nil, text); h.truthy(err)
end)

test('multiline locator is rejected without changing document', function(insert)
  document('markdown', {'Text'}, function(buf)
    local notified = false
    vim.notify = function() notified = true end
    insert.choose({'a'}, insert.capture(), {locator='p. 1\nextra'})
    h.truthy(notified)
    h.eq({'Text'}, vim.api.nvim_buf_get_lines(buf,0,-1,false))
  end)
end)
test('Telescope marks original keys and cycles commands before confirming selection', function(insert)
  local modules = {'ibid.cite.picker','telescope','telescope.pickers','telescope.finders','telescope.config','telescope.previewers','telescope.actions','telescope.actions.state','telescope.pickers.entry_display'}
  local saved, library = {}, require('ibid.library')
  for _, name in ipairs(modules) do saved[name] = package.loaded[name] end
  local original_get = library.get
  local ok, err = xpcall(function()
    local a={key='a',authors='A',year='2020',title='A',search='A'}
    local b={key='b',authors='B',year='2021',title='B',search='B'}
    library.get=function(cb) cb(nil,{items={a,b},by_key={a=a,b=b}}) end
    package.loaded['ibid.cite.picker']=nil
    package.loaded.telescope={}
    package.loaded['telescope.finders']={new_table=function(opts) return opts end}
    package.loaded['telescope.config']={values={generic_sorter=function() return {} end}}
    package.loaded['telescope.previewers']={new_buffer_previewer=function() return {} end}
    package.loaded['telescope.pickers.entry_display']={create=function() return function(parts) return parts end end}
    local confirm, completion, mapped, selected, result = nil,nil,{}, {},nil
    local entries={{value=a},{value=b}}
    local current={manager={num_results=function() return 2 end,get_entry=function(_,i) return entries[i] end},
      register_completion_callback=function(_,cb) completion=cb end,
      get_row=function(_,i) return i-1 end,
      add_selection=function(_,row) selected[#selected+1]=entries[row+1] end,
      get_multi_selection=function() return selected end}
    package.loaded['telescope.actions.state']={get_current_picker=function() return current end,get_selected_entry=function() return entries[1] end}
    package.loaded['telescope.actions']={select_default={replace=function(_,cb) confirm=cb end},close=function() end}
    package.loaded['telescope.pickers']={new=function(_,opts) return {find=function() opts.attach_mappings(99,function(_,key,cb) mapped[key]=cb end) end} end}
    require('ibid.cite.picker').pick({cite_ft='tex',preselected={'a','b'},on_select=function(value) result=value end})
    completion(current)
    h.eq(2,#selected)
    vim.notify=function() end
    mapped['<C-t>']()
    h.eq('\\parencite{%s}',insert.command('tex'))
    confirm()
    h.eq({a,b},result)
  end,debug.traceback)
  library.get=original_get
  for _,name in ipairs(modules) do package.loaded[name]=saved[name] end
  if not ok then error(err) end
end)
return cases
