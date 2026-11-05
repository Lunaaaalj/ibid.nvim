local h = require("tests.helpers")
local cases = {}

local function test(name, run)
  cases[#cases + 1] = { name = "wave2 integration: " .. name, run = function()
    local config, library, ibid = require("ibid.config"), require("ibid.library"), require("ibid")
    local saved = { options = config.options, get = library.get, lib = library.lib,
      input = vim.ui.input, notify = vim.notify, hidden = vim.o.hidden }
    local win, previous = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    local item = { key = "alpha", zkey = "ITEM1", lib = 1, title = "Alpha", authors = "Author",
      author_list = "Author", year = "2020", type = "book", tags = {}, collections = {},
      attachments = {}, annotations = {}, people = { { last = "Author" } }, search = "alpha" }
    local lib = { items = { item }, by_key = { alpha = item }, collections = {}, groups = {} }
    local context = { buf = buf, win = win, ibid = ibid, config = config, notices = {} }
    local ok, err = xpcall(function()
      vim.o.hidden = true
      vim.api.nvim_win_set_buf(win, buf)
      vim.api.nvim_buf_set_name(buf, h.tempdir() .. "/document.md")
      vim.bo[buf].filetype = "markdown"
      library.get = function(cb) cb(nil, lib) end
      library.lib = lib
      vim.notify = function(msg) context.notices[#context.notices + 1] = msg end
      config.setup({})
      function context.text(text, ft, col)
        vim.api.nvim_set_current_win(win)
        vim.api.nvim_win_set_buf(win, buf)
        vim.bo[buf].filetype = ft or "markdown"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
        vim.api.nvim_win_set_cursor(win, { 1, col or 0 })
      end
      run(context)
    end, debug.traceback)
    require("ibid.browser").close()
    ibid.setup(saved.options)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      vim.api.nvim_win_set_buf(win, previous)
    end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    config.options, library.get, library.lib = saved.options, saved.get, saved.lib
    vim.ui.input, vim.notify, vim.o.hidden = saved.input, saved.notify, saved.hidden
    if not ok then error(err) end
  end }
end

test("public cite replaces the complete range with command and locator", function(c)
  local text = [[prefix \cite{alpha} suffix]]
  c.text(text, "tex", text:find("alpha", 1, true) - 1)
  c.ibid.cite({ keys = { "beta" }, replace = true, command = "parencite", locator = "p. 8" })
  h.eq({ [[prefix \parencite[p. 8]{beta} suffix]] }, vim.api.nvim_buf_get_lines(c.buf, 0, -1, false))
  c.text("No citation here")
  c.ibid.cite({ keys = { "beta" }, replace = true })
  h.eq({ "No citation here" }, vim.api.nvim_buf_get_lines(c.buf, 0, -1, false))
end)

test("public citation cancellation and a changed document make no edit", function(c)
  c.text("Text")
  local callback
  vim.ui.input = function(_, cb) callback = cb end
  c.ibid.cite({ keys = { "alpha" }, locator = true })
  callback(nil)
  h.eq({ "Text" }, vim.api.nvim_buf_get_lines(c.buf, 0, -1, false))
  c.ibid.cite({ keys = { "alpha" }, locator = true })
  vim.api.nvim_buf_set_lines(c.buf, 0, -1, false, { "Changed while choosing" })
  callback("p. 3")
  h.eq({ "Changed while choosing" }, vim.api.nvim_buf_get_lines(c.buf, 0, -1, false))
end)

test("browser uses the shared locator pipeline after restoring document focus", function(c)
  c.text("Text")
  c.config.setup({ citation = { locator = true } })
  vim.ui.input = function(_, cb)
    h.eq(c.win, vim.api.nvim_get_current_win())
    cb("p. 3")
  end
  local session = c.ibid.browse()
  session.switch_tab(1)
  vim.api.nvim_set_current_win(session.list_win)
  vim.fn.maparg("i", "n", false, true).callback()
  h.eq(false, session.alive)
  h.eq({ "T[@alpha, p. 3]ext" }, vim.api.nvim_buf_get_lines(c.buf, 0, -1, false))
end)

test("insert mapping follows filetypes and setup preserves user overrides", function(c)
  c.text("Text")
  c.ibid.setup({ insert_mapping = "<C-g>c" })
  h.eq("ibid: cite", vim.fn.maparg("<C-g>c", "i", false, true).desc)
  vim.bo[c.buf].filetype = "lua"
  h.eq({}, vim.fn.maparg("<C-g>c", "i", false, true))
  vim.bo[c.buf].filetype = "markdown"
  h.eq("ibid: cite", vim.fn.maparg("<C-g>c", "i", false, true).desc)
  vim.keymap.set("i", "<C-g>c", function() end, { buffer = c.buf, desc = "user override" })
  c.ibid.setup({ insert_mapping = false })
  h.eq("user override", vim.fn.maparg("<C-g>c", "i", false, true).desc)
end)

test("note command opens a generated note for the citation under the cursor", function(c)
  c.text("[@alpha]", "markdown", 3)
  local dir = h.tempdir()
  c.config.setup({ notes_dir = dir })
  local loaded = vim.g.loaded_ibid
  vim.g.loaded_ibid = nil
  vim.cmd.runtime("plugin/ibid.lua")
  local ok, err = pcall(function()
    vim.cmd("Ibid note")
    h.eq(dir .. "/alpha.md", vim.api.nvim_buf_get_name(0))
    h.truthy(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find('key: "alpha"', 1, true))
    local note_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(c.win, c.buf)
    vim.api.nvim_buf_delete(note_buf, { force = true })
  end)
  vim.api.nvim_del_user_command("Ibid")
  vim.g.loaded_ibid = loaded
  if not ok then error(err) end
end)

return cases
