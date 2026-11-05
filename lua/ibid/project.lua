-- Shared source discovery. Reads loaded buffers before disk, and never crawls
-- recursively: reverse root lookup examines source files in ancestor directories.
local M = {}

function M.path(dir, name)
  name = vim.trim(name):gsub('^["\']', ''):gsub('["\']$', '')
  local profile = require('ibid.profile')
  name = profile.normalize(name)
  if not profile.is_absolute(name) then name = dir .. '/' .. name end
  name = vim.fs.normalize(name)
  return vim.uv.fs_realpath(name) or name
end

function M.lines(path)
  local buf = vim.fn.bufnr(path)
  if buf > 0 and vim.api.nvim_buf_is_loaded(buf) then return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
  local ok, lines = pcall(vim.fn.readfile, path)
  if ok then return lines end
end

local function text(path, syntax)
  local lines = M.lines(path)
  if not lines then return nil end
  return table.concat(require('ibid.cite.scan').clean_lines(lines, syntax), '\n')
end

local function links(path, syntax)
  local s = text(path, syntax)
  if not s then return nil, 'cannot read project source: ' .. path end
  local names, unresolved = {}, false
  if syntax == 'tex' then
    for name in s:gmatch('\\input%s*{([^}]+)}') do names[#names + 1] = name end
    for name in s:gmatch('\\include%s*{([^}]+)}') do names[#names + 1] = name end
    for name in s:gmatch('\\input%s+([^%s{}]+)') do names[#names + 1] = name end
  else
    for kind, pos in s:gmatch('#(i%a+)()') do
      if (kind == 'include' or kind == 'import') and not s:sub(pos, pos):match('%s') then unresolved = true end
    end
    for kind, pos in s:gmatch('#(i%a+)%s+()') do
      local arg = s:sub(pos)
      if kind == 'include' or kind == 'import' then
        local name = arg:match('^"([^"]+)"')
        if name then
          if name:sub(1, 1) ~= '@' then names[#names + 1] = name end
        else unresolved = true end
      end
    end
  end
  local out = {}
  for _, name in ipairs(names) do
    if syntax == 'tex' and not name:match('%.tex$') then name = name .. '.tex' end
    out[#out + 1] = M.path(vim.fs.dirname(path), name)
  end
  return out, unresolved and ('dynamic project include in ' .. path) or nil
end

local function graph(root, syntax, extra)
  local paths, seen, errors = {}, {}, {}
  local function visit(path)
    if seen[path] then return end
    seen[path] = true
    paths[#paths + 1] = path
    local children, err = links(path, syntax)
    if err then errors[#errors + 1] = err end
    for _, child in ipairs(children or {}) do visit(child) end
  end
  visit(root)
  for _, path in ipairs(extra or {}) do visit(path) end
  return { root = root, paths = paths, seen = seen, syntax = syntax, errors = errors }
end

local function has_bib(path, syntax)
  local s = text(path, syntax) or ''
  return syntax == 'typst' and s:find('#bibliography%s*%(') or syntax == 'tex' and
    (s:find('\\addbibresource') or s:find('\\bibliography'))
end

-- This intentionally supports literal Quarto chapter lists, including nested
-- parts. Unsupported expressions are reported rather than silently pruning.
local function quarto(path, current)
  local lines = M.lines(path) or {}
  local chapters, active, base, errors, declared = {}, false, nil, {}, false
  for _, line in ipairs(lines) do
    local indent, value = line:match('^(%s*)chapters:%s*(.-)%s*$')
    if indent then
      declared = true
      if not active then active, base = true, #indent end
      if value ~= '' then
        if value:match('^%[.*%]$') then
          for name in value:sub(2, -2):gmatch('[^,]+') do chapters[#chapters + 1] = vim.trim(name) end
        else errors[#errors + 1] = 'unsupported Quarto chapters expression in ' .. path end
      end
    elseif active then
      local ws, rest = line:match('^(%s*)(.-)%s*$')
      if rest ~= '' and rest:sub(1, 1) ~= '#' and #ws <= base then active = false
      elseif rest:match('^%-') then
        local name = rest:match('^%-%s*(.-)%s*$')
        if name:match('^part:') then
          local part = name:match('^part:%s*(.-)%s*$')
          if part:match('%.qmd["\']?$') then chapters[#chapters + 1] = part end
        elseif not name:match('^chapters:') then chapters[#chapters + 1] = name end
      end
    end
  end
  if not declared then return nil end
  if #chapters == 0 and #errors == 0 then errors[#errors + 1] = 'Quarto book has no literal chapters: ' .. path end
  local result = { root = current, config = path, syntax = 'pandoc', paths = {}, seen = {}, errors = errors }
  for _, name in ipairs(chapters) do
    name = name:gsub('%s+#.*$', '')
    if name:find('[&*!{}]') or name == '' then errors[#errors + 1] = 'unsupported Quarto chapter: ' .. name
    else
      local source = M.path(vim.fs.dirname(path), name)
      if not result.seen[source] then
        result.paths[#result.paths + 1], result.seen[source] = source, true
        if not M.lines(source) then errors[#errors + 1] = 'cannot read project source: ' .. source end
      end
    end
  end
  if not result.seen[current] then
    errors[#errors + 1] = 'current document is not listed in Quarto book chapters: ' .. current
    result.paths[#result.paths + 1], result.seen[current] = current, true
  end
  return result
end

function M.discover(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local syntax = require('ibid.cite.scan').syntax(vim.bo[buf].filetype)
  local current = M.path(vim.fn.getcwd(), vim.api.nvim_buf_get_name(buf))
  if syntax == 'pandoc' then
    local lines = M.lines(current) or {}
    if lines[1] == '---' then
      for i = 2, #lines do
        if lines[i] == '---' or lines[i] == '...' then break end
        if lines[i]:match('^bibliography:') then
          return {root=current, paths={current}, syntax=syntax, errors={}}
        end
      end
    end
    local config = vim.fs.find('_quarto.yml', { upward = true, path = vim.fs.dirname(current), stop = vim.uv.os_homedir() })[1]
    local project = config and quarto(config, current)
    return project or { root = current, paths = {current}, syntax = syntax, errors = {}, config = config }
  end
  if syntax ~= 'tex' and syntax ~= 'typst' then return {root=current, paths={current}, syntax=syntax, errors={}} end
  if vim.b[buf].ibid_root then return graph(M.path(vim.fs.dirname(current), vim.b[buf].ibid_root), syntax, {current}) end
  local vt = syntax == 'tex' and vim.b[buf].vimtex
  if type(vt) == 'table' and (vt.tex or (vt.root and type(vt.sources) == 'table')) then
    local extra = {current}
    for _, source in ipairs(type(vt.sources) == 'table' and vt.sources or {}) do extra[#extra + 1] = M.path(vt.root or vim.fs.dirname(vt.tex or current), source) end
    return graph(M.path(vim.fs.dirname(current), vt.tex or current), syntax, extra)
  end
  if syntax == 'tex' then
    for _, line in ipairs(M.lines(current) or {}) do
      local root = line:match('^%s*%%%s*!%s*[Tt][Ee][Xx]%s+root%s*=%s*(.-)%s*$')
      if root then return graph(M.path(vim.fs.dirname(current), root), syntax, {current}) end
    end
  end
  -- Root lookup is bounded to this directory and four ancestors, stopping at
  -- the repository boundary or home. Only candidate roots that include current
  -- participate, so neighbouring documents do not leak citations into this one.
  local candidates, tried, dir = {}, {}, vim.fs.dirname(current)
  for _ = 1, 5 do
    local paths = vim.fn.glob(dir .. '/*.' .. (syntax == 'tex' and 'tex' or 'typ'), false, true)
    for _, loaded in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(loaded)
      if vim.api.nvim_buf_is_loaded(loaded) and vim.fs.dirname(name) == dir then paths[#paths + 1] = name end
    end
    for _, path in ipairs(paths) do
      path = M.path(dir, path)
      if not tried[path] and has_bib(path, syntax) then
        tried[path] = true
        local candidate = graph(path, syntax)
        if candidate.seen[current] then candidates[#candidates + 1] = candidate end
      end
    end
    if vim.uv.fs_stat(dir .. '/.git') or dir == vim.uv.os_homedir() or vim.fs.dirname(dir) == dir then break end
    dir = vim.fs.dirname(dir)
  end
  if #candidates == 1 then return candidates[1] end
  local result = graph(current, syntax)
  if #candidates > 1 then result.errors[#result.errors + 1] = 'ambiguous project root; set b:ibid_root to the main document' end
  return result
end

return M
