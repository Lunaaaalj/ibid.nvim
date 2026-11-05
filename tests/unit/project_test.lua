local h = require('tests.helpers')
local project = require('ibid.project')
local scan = require('ibid.cite.scan')
local detect = require('ibid.bib.detect')
local cases = {}
local function test(name, fn)
  cases[#cases + 1] = { name = 'project: ' .. name, run = function()
    local dir, buffers = h.tempdir(), {}
    local function write(path, lines)
      vim.fn.mkdir(vim.fs.dirname(dir .. '/' .. path), 'p')
      vim.fn.writefile(lines, dir .. '/' .. path)
    end
    local function buf(path, ft, lines)
      local b = vim.api.nvim_create_buf(false, true)
      buffers[#buffers + 1] = b
      vim.api.nvim_buf_set_name(b, dir .. '/' .. path)
      vim.bo[b].filetype = ft
      vim.api.nvim_buf_set_lines(b, 0, -1, false, lines or vim.fn.readfile(dir .. '/' .. path))
      return b
    end
    local ok, err = xpcall(function() fn(dir, write, buf) end, debug.traceback)
    for _, b in ipairs(buffers) do if vim.api.nvim_buf_is_valid(b) then vim.api.nvim_buf_delete(b, {force=true}) end end
    if not ok then error(err) end
  end }
end

test('Typst chapter finds root siblings labels and unsaved text', function(dir, write, buf)
  write('main.typ', {'#include "chapters/a.typ" #import "chapters/b.typ": *', '#bibliography("refs.bib")', '@root'})
  write('chapters/a.typ', {'@a @heading @bibkey #cite( <spaced>)'})
  write('chapters/b.typ', {'<heading> @old'})
  local b = buf('chapters/a.typ', 'typst')
  buf('chapters/b.typ', 'typst', {'<heading> @unsaved #let example = "<bibkey>"'})
  h.eq(dir .. '/main.typ', project.discover(b).root)
  local keys, err = scan.project_keys(b)
  h.eq(nil, err)
  h.eq({'a','bibkey','root','spaced','unsaved'}, keys)
  h.eq({'a','bibkey','spaced'}, vim.tbl_map(function(f) return f.key end, scan.project_scan(b)))
  h.eq(dir .. '/refs.bib', detect.bibs(b)[1].path)
end)

test('Typst cycles terminate and ignore package imports', function(_, write, buf)
  write('main.typ', {'#include "a.typ"', '#bibliography("refs.bib")'})
  write('a.typ', {'#include "main.typ"', '#import "@preview/test:0.1.0": *', '@one'})
  local keys, err = scan.project_keys(buf('a.typ','typst'))
  h.eq(nil, err)
  h.eq({'one'}, keys)
end)

test('missing and dynamic includes make discovery incomplete', function(_, write, buf)
  write('main.typ', {'#include "missing.typ"', '#include variable', '#bibliography("refs.bib")'})
  local keys, err = scan.project_keys(buf('main.typ','typst'))
  h.eq({}, keys)
  h.truthy(err:find('missing.typ',1,true))
  h.truthy(err:find('dynamic project include',1,true))
end)

test('ambiguous roots require explicit override', function(dir, write, buf)
  write('one.typ', {'#include "a.typ"','#bibliography("one.bib")'})
  write('two.typ', {'#include "a.typ"','#bibliography("two.bib")'})
  write('a.typ', {'@a'})
  local b = buf('a.typ','typst')
  local _, err = scan.project_keys(b)
  h.truthy(err:find('ambiguous',1,true))
  vim.b[b].ibid_root = 'two.typ'
  h.eq(dir .. '/two.bib', detect.bibs(b)[1].path)
  h.eq(nil, select(2,scan.project_keys(b)))
end)

test('LaTeX magic root and input/include preserve sibling citations', function(dir, write, buf)
  write('main.tex', {'\\input{a}', '\\include{b}', '\\addbibresource{refs.bib}', '\\cite{root}'})
  write('a.tex', {'% !TEX root = main.tex', '\\cite{a}'})
  write('b.tex', {'\\input{a}', '\\cite{b}'})
  local b = buf('a.tex','tex')
  h.eq({'a','b','root'}, scan.project_keys(b))
  h.eq(dir .. '/refs.bib',detect.bibs(b)[1].path)
end)

test('LaTeX reverse root and VimTeX source lists', function(dir, write, buf)
  write('main.tex', {'\\input{a}', '\\bibliography{refs}'})
  write('a.tex', {'\\cite{a}'})
  write('extra.tex', {'\\cite{extra}'})
  local b = buf('a.tex','tex')
  h.eq(dir .. '/main.tex',project.discover(b).root)
  vim.b[b].vimtex = {tex=dir .. '/main.tex',root=dir,sources={'a.tex','extra.tex'}}
  h.eq({'a','extra'},scan.project_keys(b))
end)

test('Quarto nested book parts and chapter buffers', function(dir, write, buf)
  write('_quarto.yml', {'project:', '  type: book', 'bibliography: refs.bib', 'book:', '  chapters:', '    - index.qmd', '    - part: "Methods"', '      chapters:', '        - chapters/a.qmd', '        - chapters/b.qmd', '    - end.qmd'})
  write('index.qmd', {'@intro'})
  write('end.qmd', {'@end'})
  write('chapters/a.qmd', {'@a'})
  write('chapters/b.qmd', {'@b'})
  local b = buf('chapters/a.qmd','quarto')
  h.eq({'a','b','end','intro'},scan.project_keys(b))
  h.eq(dir .. '/refs.bib',detect.bibs(b)[1].path)
end)

test('Quarto missing chapters and unsupported expressions block pruning', function(_, write, buf)
  write('_quarto.yml', {'bibliography: refs.bib','book:', '  chapters:', '    - a.qmd', '    - missing.qmd'})
  write('a.qmd', {'@a'})
  local b = buf('a.qmd','quarto')
  h.truthy(select(2,scan.project_keys(b)):find('missing.qmd',1,true))
  write('_quarto.yml', {'bibliography: refs.bib','book:', '  chapters: !expr chapters'})
  h.truthy(select(2,scan.project_keys(b)):find('unsupported',1,true))
end)

test('local frontmatter bibliography keeps Quarto chapter scope local', function(dir, write, buf)
  write('_quarto.yml', {'bibliography: project.bib', 'book:', '  chapters: [a.qmd, b.qmd]'})
  write('a.qmd', {'---', 'bibliography: local.bib', '---', '@local'})
  write('b.qmd', {'@sibling'})
  local b = buf('a.qmd','quarto')
  h.eq({'local'}, scan.project_keys(b))
  h.eq(dir .. '/local.bib', detect.bibs(b)[1].path)
end)

test('unsupported Typst include delimiters block sync discovery', function(_, write, buf)
  write('main.typ', {'#include("a.typ")', '#import(variable): *', '#bibliography("refs.bib")'})
  local _, err = scan.project_keys(buf('main.typ','typst'))
  h.truthy(err and err:find('dynamic project include',1,true))
end)

test('Quarto unlisted current document and empty lists fail safely', function(_, write, buf)
  write('_quarto.yml', {'bibliography: refs.bib', 'book:', '  chapters: [other.qmd]'})
  write('other.qmd', {'@other'})
  write('a.qmd', {'@a'})
  local b = buf('a.qmd','quarto')
  h.truthy(select(2,scan.project_keys(b)):find('not listed',1,true))
  write('_quarto.yml', {'bibliography: refs.bib', 'book:', '  chapters: []'})
  h.truthy(select(2,scan.project_keys(b)):find('no literal chapters',1,true))
end)

test('included Typst diagnostics resolve labels in sibling files', function(_, write, buf)
  write('main.typ', {'#include "a.typ" #include "b.typ"', '#bibliography("refs.bib")'})
  write('a.typ', {'@heading @missing'})
  write('b.typ', {'<heading>'})
  local b = buf('a.typ','typst')
  local lib, diagnostics = require('ibid.library'), require('ibid.diagnostics')
  local get = lib.get
  lib.get = function(cb) cb(nil,{by_key={}}) end
  local ok, err = xpcall(function()
    diagnostics.refresh(b)
    local results = vim.diagnostic.get(b,{namespace=diagnostics.ns})
    h.eq(1,#results)
    h.truthy(results[1].message:find('missing',1,true))
  end,debug.traceback)
  lib.get = get
  vim.diagnostic.reset(diagnostics.ns,b)
  if not ok then error(err) end
end)

test('sync from chapter preserves sibling keys and refuses incomplete graphs', function(dir, write, buf)
  local sync = require('ibid.bib.sync')
  local library = require('ibid.library')
  local get, notify = library.get, vim.notify
  local entry = function(k) return '@book{' .. k .. ', title = {' .. k .. '}}' end
  local contents = sync.header .. '\n\n' .. entry('a') .. '\n\n' .. entry('b') .. '\n'
  write('main.typ', {'#include "a.typ" #include "b.typ"','#bibliography("refs.bib")'})
  write('a.typ', {'@a'})
  write('b.typ', {'@b'})
  write('refs.bib',vim.split(contents,'\n',{plain=true}))
  -- Make the seed exactly match sync serialization, without writefile's extra newline.
  local fd = assert(io.open(dir .. '/refs.bib','w')); fd:write(contents); fd:close()
  local b = buf('a.typ','typst')
  library.get = function(cb) cb(nil,{by_key={a={modified='2000-01-01 00:00:00'},b={modified='2000-01-01 00:00:00'}}}) end
  vim.notify = function() end
  local ok, err = xpcall(function()
    local done, failure, result = false
    sync.sync(b,{quiet=true},function(e,s) done,failure,result=true,e,s end)
    h.truthy(done); h.eq(nil,failure); h.eq(2,result.entries); h.eq(false,result.changed)
    write('main.typ',{'#include "a.typ" #include "missing.typ"','#bibliography("refs.bib")'})
    sync.sync(b,{quiet=true},function(e) failure=e end)
    h.truthy(failure:find('incomplete project',1,true))
    h.eq(contents,table.concat(vim.fn.readfile(dir .. '/refs.bib','b'),'\n'))
  end,debug.traceback)
  library.get,vim.notify=get,notify
  if not ok then error(err) end
end)
return cases
