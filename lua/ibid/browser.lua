-- Native list/detail library browser. Rich note/annotation cards are provided
-- separately; this view consumes card.lines and lint.check without copying them.
local M = {}
local tabs = { "Library", "Collections", "Tags", "Recent", "Lint" }
local remembered = { tab = 1, filter = "", cursors = {}, scopes = {} }
local current

local function valid_win(win) return win and vim.api.nvim_win_is_valid(win) end
local function valid_origin(s)
  return valid_win(s.ctx.win) and vim.api.nvim_buf_is_valid(s.ctx.buf)
    and vim.api.nvim_win_get_buf(s.ctx.win) == s.ctx.buf
end
local function set_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "(no items)" })
  vim.bo[buf].modifiable = false
end
local function row_key(s) return tostring(s.tab) .. ":" .. tostring(s.scope or "") end
local function save_cursor(s)
  if valid_win(s.list_win) then s.cursors[row_key(s)] = vim.api.nvim_win_get_cursor(s.list_win)[1] end
end
local function selected(s)
  if not valid_win(s.list_win) then return end
  return s.rows[vim.api.nvim_win_get_cursor(s.list_win)[1]]
end
local function matches(s, text)
  return vim.fn.tolower(text or ""):find(vim.fn.tolower(s.filter), 1, true) ~= nil
end
local function item_label(item)
  return ("%s  %s (%s)  %s"):format(item.key or "(no key)", item.authors or "", item.year or "", item.title or "")
end

local function collection_rows(lib)
  local children, out, visited = {}, {}, {}
  for id, col in pairs(lib.collections or {}) do
    local parent = col.parent
    if not parent or not lib.collections[parent] then parent = 0 end
    children[parent] = children[parent] or {}
    children[parent][#children[parent] + 1] = { id = id, col = col }
  end
  for _, list in pairs(children) do
    table.sort(list, function(a, b)
      if a.col.name ~= b.col.name then return (a.col.name or "") < (b.col.name or "") end
      return tostring(a.id) < tostring(b.id)
    end)
  end
  local function visit(entry, depth)
    if visited[entry.id] then return end
    visited[entry.id] = true
    out[#out + 1] = { kind = "collection", id = entry.id, label = string.rep("  ", depth) .. (entry.col.name or "(unnamed)") }
    for _, child in ipairs(children[entry.id] or {}) do visit(child, depth + 1) end
  end
  for _, entry in ipairs(children[0] or {}) do visit(entry, 0) end
  -- Malformed cyclic collections still remain reachable in the selector.
  local rest = {}
  for id, col in pairs(lib.collections or {}) do rest[#rest + 1] = {id=id,col=col} end
  table.sort(rest, function(a,b) return tostring(a.id) < tostring(b.id) end)
  for _, entry in ipairs(rest) do visit(entry, 0) end
  return out
end
local function in_collection(lib, item, wanted)
  for _, id in ipairs(item.collections or {}) do
    local seen = {}
    while id and not seen[id] do
      if id == wanted then return true end
      seen[id] = true
      id = lib.collections[id] and lib.collections[id].parent
    end
  end
  return false
end

local function detail(s)
  if not s.alive or not s.detail_buf then return end
  local row = selected(s)
  if not row then return set_lines(s.detail_buf, { "No matching items.", "", "Use / to change the filter; ? shows keys." }) end
  if not row.item then return set_lines(s.detail_buf, { row.label, "", "<CR> lists matching items, including child collections.", "<BS> returns to the selector." }) end
  local width = valid_win(s.detail_win) and vim.api.nvim_win_get_width(s.detail_win) - 2 or 40
  local ok, lines = pcall(require("ibid.card").lines, row.item, math.max(10, width))
  if not ok then lines = { row.item.title or "(untitled)", "", "Card unavailable: " .. tostring(lines) } end
  if row.finding then table.insert(lines, 1, "**Lint:** " .. row.finding.message); table.insert(lines, 2, "") end
  set_lines(s.detail_buf, lines)
end
local function render(s)
  if not s.alive or not s.lib or not valid_win(s.list_win) then return end
  local rows = {}
  if s.tab == 2 and not s.scope then
    for _, row in ipairs(collection_rows(s.lib)) do if matches(s, row.label) then rows[#rows + 1] = row end end
  elseif s.tab == 3 and not s.scope then
    local tags = {}
    for _, item in ipairs(s.lib.items) do for _, tag in ipairs(item.tags or {}) do tags[tag] = true end end
    local names = vim.tbl_keys(tags); table.sort(names)
    for _, tag in ipairs(names) do if matches(s, tag) then rows[#rows + 1] = { kind="tag", id=tag, label=tag } end end
  elseif s.tab == 5 then
    for _, finding in ipairs(require("ibid.lint").check(s.lib)) do
      local label = item_label(finding.item) .. " — " .. finding.message
      if matches(s, label) then rows[#rows + 1] = { item=finding.item, finding=finding, label=label } end
    end
  else
    local items = vim.list_extend({}, s.lib.items)
    if s.tab == 4 then table.sort(items, function(a,b) return (a.added or "") > (b.added or "") end) end
    for i, item in ipairs(items) do
      if s.tab == 4 and i > (s.opts.recent_limit or 50) then break end
      local allowed = true
      if s.tab == 2 then allowed = in_collection(s.lib, item, s.scope) end
      if s.tab == 3 then allowed = vim.tbl_contains(item.tags or {}, s.scope) end
      if allowed and matches(s, (item.search or "") .. " " .. item_label(item)) then
        rows[#rows + 1] = { item=item, label=item_label(item) }
      end
    end
  end
  s.rows = rows
  set_lines(s.list_buf, vim.tbl_map(function(row) return row.label end, rows))
  vim.api.nvim_win_set_cursor(s.list_win, {math.min(s.cursors[row_key(s)] or 1, math.max(1,#rows)),0})
  local names = {}
  for i, name in ipairs(tabs) do names[i] = i == s.tab and ("[" .. name .. "]") or name end
  vim.api.nvim_win_set_config(s.list_win, { title = "[" .. tabs[s.tab] .. "] " .. table.concat(names," ") .. (s.filter ~= "" and (" /" .. s.filter) or ""), title_pos="left" })
  detail(s)
end

local function layout(s, create)
  if vim.o.columns < 12 or vim.o.lines < 8 then s.close(); return end
  local available, height = vim.o.columns - 6, math.max(1, vim.o.lines - 6)
  local left = math.max(3, math.floor(available * 0.44))
  local common = { relative="editor", row=1, height=height, style="minimal", border="rounded", zindex=60 }
  local a = vim.tbl_extend("force", common, { col=1, width=left })
  local b = vim.tbl_extend("force", common, { col=left+3, width=available-left, title="Item", title_pos="left" })
  if create then
    s.detail_win = vim.api.nvim_open_win(s.detail_buf, false, b)
    s.list_win = vim.api.nvim_open_win(s.list_buf, true, a)
    vim.wo[s.list_win].cursorline = true
    vim.wo[s.list_win].wrap = false
    vim.wo[s.detail_win].wrap = true
    vim.wo[s.detail_win].conceallevel = 2
  else
    if valid_win(s.list_win) then vim.api.nvim_win_set_config(s.list_win,a) end
    if valid_win(s.detail_win) then vim.api.nvim_win_set_config(s.detail_win,b) end
  end
end

function M.close() if current then current.close() end end
function M.open(opts)
  opts = opts or {}
  if current and current.alive then
    if valid_win(current.list_win) then vim.api.nvim_set_current_win(current.list_win) end
    return current
  end
  local insert = require("ibid.cite.insert")
  local s = { alive=true, opts=opts, ctx=opts.ctx or insert.capture(), tab=remembered.tab,
    filter=remembered.filter, cursors=vim.deepcopy(remembered.cursors), scopes=vim.deepcopy(remembered.scopes), rows={}, request=0 }
  current = s
  s.scope = s.scopes[s.tab]
  function s.close()
    if not s.alive then return end
    local focused = vim.api.nvim_get_current_win()
    local restore = focused == s.list_win or focused == s.detail_win
    save_cursor(s)
    remembered = {tab=s.tab,filter=s.filter,cursors=vim.deepcopy(s.cursors),scopes=vim.deepcopy(s.scopes)}
    s.alive = false
    if current == s then current = nil end
    if s.group then vim.api.nvim_del_augroup_by_id(s.group) end
    for _, win in ipairs({s.list_win or false,s.detail_win or false}) do if valid_win(win) then vim.api.nvim_win_close(win,true) end end
    for _, buf in ipairs({s.list_buf or false,s.detail_buf or false}) do if buf and vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf,{force=true}) end end
    if restore and valid_origin(s) then vim.api.nvim_set_current_win(s.ctx.win) end
  end
  function s.switch_tab(tab)
    if not s.alive then return end
    save_cursor(s)
    s.scopes[s.tab] = s.scope
    s.tab = ((tab-1) % #tabs)+1
    s.scope = s.scopes[s.tab]
    render(s)
  end
  local function activate(cite)
    local row = selected(s)
    if not row then return end
    if not row.item then
      save_cursor(s); s.scope=row.id; s.scopes[s.tab]=row.id; render(s); return
    end
    if not cite and row.finding then require("ibid.actions").show_in_zotero(row.item); return end
    if not row.item.key or row.item.key == "" then return vim.notify("ibid: item has no citation key",vim.log.levels.WARN) end
    s.close()
    if opts.on_select then return opts.on_select({row.item},s.ctx) end
    if insert.choose then insert.choose({row.item.key},s.ctx,opts.citation or {}) else insert.insert({row.item.key},s.ctx) end
  end
  local function request(reload)
    s.request=s.request+1
    local token=s.request
    local library=require("ibid.library")
    if reload then require("ibid.profile").invalidate(); library.invalidate() end
    library.get(function(err,lib)
      if not s.alive or token ~= s.request then return end
      if err then s.close(); return vim.notify("ibid: " .. err,vim.log.levels.ERROR) end
      s.lib=lib
      if not s.list_buf then
        -- A late load must not open over a different document/window.
        if not valid_origin(s) or vim.api.nvim_get_current_win() ~= s.ctx.win then s.close(); return end
        vim.cmd("stopinsert")
        s.list_buf=vim.api.nvim_create_buf(false,true)
        s.detail_buf=vim.api.nvim_create_buf(false,true)
        for _,buf in ipairs({s.list_buf,s.detail_buf}) do vim.bo[buf].bufhidden="wipe"; vim.bo[buf].swapfile=false end
        vim.bo[s.list_buf].filetype="ibid"
        vim.bo[s.detail_buf].filetype="markdown"
        layout(s,true)
        if not s.alive then return end
        s.group=vim.api.nvim_create_augroup("ibid_browser_" .. s.list_buf,{clear=true})
        vim.api.nvim_create_autocmd("CursorMoved",{group=s.group,buffer=s.list_buf,callback=function() save_cursor(s);detail(s) end})
        vim.api.nvim_create_autocmd("VimResized",{group=s.group,callback=function() layout(s,false);render(s) end})
        vim.api.nvim_create_autocmd("WinClosed",{group=s.group,callback=function(ev)
          if tonumber(ev.match)==s.list_win or tonumber(ev.match)==s.detail_win then s.close() end
        end})
        local function map(key,fn)
          for _,buf in ipairs({s.list_buf,s.detail_buf}) do
            vim.keymap.set("n",key,fn,{buffer=buf,nowait=true,silent=true})
          end
        end
        map("q",s.close);map("<Esc>",s.close)
        map("<Tab>",function() s.switch_tab(s.tab+1) end);map("<S-Tab>",function() s.switch_tab(s.tab-1) end)
        for i=1,#tabs do map(tostring(i),function() s.switch_tab(i) end) end
        map("i",function() activate(true) end);map("<CR>",function() activate(false) end)
        map("<BS>",function() save_cursor(s);s.scope=nil;s.scopes[s.tab]=nil;render(s) end)
        map("/",function() vim.ui.input({prompt="Filter library: ",default=s.filter},function(value)
          if not s.alive or value==nil then return end
          save_cursor(s);s.filter=value;s.cursors[row_key(s)]=1;render(s)
        end) end)
        map("r",function() save_cursor(s);request(true) end)
        map("?",function() set_lines(s.detail_buf,{
          "# Library browser", "", "Tab / Shift-Tab or 1–5: change tab", "j / k / G: select row", "Enter: open selector / cite / show lint item", "Backspace: back to collection/tag selector", "i: cite into previous window", "o: open PDF · gz: Zotero · gx: URL", "y: key · Y: BibTeX · R: reference", "/: filter · r: reload · q / Escape: close", "Recent shows the newest " .. tostring(opts.recent_limit or 50) .. " items."}) end)
        for key,action in pairs({o="open_pdf",gz="show_in_zotero",gx="open_url",y="yank_key",Y="yank_bibtex",R="yank_reference"}) do
          map(key,function() local row=selected(s);if row and row.item then require("ibid.actions")[action](row.item) end end)
        end
      end
      render(s)
    end)
  end
  request(false)
  return s
end
return M
