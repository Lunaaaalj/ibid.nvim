-- rg supplies candidate files; the citation scanner determines actual matches.
local M = {}
local extensions = { tex = "tex", md = "markdown", markdown = "markdown", qmd = "quarto", rmd = "rmd", typ = "typst" }
function M.find(item, opts, cb)
  opts = opts or {}
  local key = item.key
  if not key or key == "" then return cb("item has no citation key") end
  local roots = opts.roots or require("ibid.config").options.backlink_roots or {}
  if type(roots) == "string" then roots = { roots } end
  local function finish(files)
    -- Rebuild at completion: rg is asynchronous and buffers can change meanwhile.
    local loaded = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name ~= "" then loaded[vim.fs.normalize(name)] = buf end
      end
    end
    local paths = {}
    for path in pairs(loaded) do paths[path] = true end
    for _, path in ipairs(files) do paths[vim.fs.normalize(path)] = true end
    local hits = {}
    for _, path in ipairs(vim.fn.sort(vim.tbl_keys(paths))) do
      local buf = loaded[path]
      local ft = buf and vim.bo[buf].filetype or extensions[(path:match('%.([^./]+)$') or ''):lower()]
      local syntax = require("ibid.cite.scan").syntax(ft)
      if syntax then
        local ok, lines = true, nil
        if buf then lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false) else ok, lines = pcall(vim.fn.readfile, path) end
        if ok then
          for _, found in ipairs(require("ibid.cite.scan").scan_lines(lines, syntax)) do
            if found.key == key then hits[#hits + 1] = { filename = path, bufnr = buf, lnum = found.lnum + 1,
              col = found.col + 1, text = lines[found.lnum + 1] } end
          end
        end
      end
    end
    cb(nil, hits)
  end
  if #roots == 0 then return finish({}) end
  if vim.fn.executable("rg") == 0 then return cb("ripgrep (rg) is required to search backlink roots") end
  local cmd = { "rg", "--files-with-matches", "--null", "--fixed-strings", "--", key }
  for _, root in ipairs(roots) do cmd[#cmd + 1] = vim.fn.fnamemodify(root, ":p") end
  return vim.system(cmd, { text = false, timeout = opts.timeout or 5000 }, vim.schedule_wrap(function(res)
    if res.code ~= 0 and res.code ~= 1 then return cb("backlink search failed: " .. vim.trim(res.stderr or "")) end
    finish(vim.split(res.stdout or "", "\0", { plain = true, trimempty = true }))
  end))
end
function M.open(item, opts)
  return M.find(item, opts, function(err, hits)
    if err then return vim.notify("ibid: " .. err, vim.log.levels.ERROR) end
    vim.fn.setqflist({}, " ", { title = "ibid: backlinks for " .. item.key, items = hits })
    if #hits > 0 then vim.cmd("copen") else vim.notify("ibid: no backlinks for " .. item.key) end
  end)
end
return M
