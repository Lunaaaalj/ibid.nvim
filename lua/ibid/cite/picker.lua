-- Picking items: Telescope when it's installed (card preview, multi-select
-- with <Tab>, item actions on config.keys), vim.ui.select otherwise.

local config = require("ibid.config")
local library = require("ibid.library")

local M = {}

local function label(it)
  return ("%s (%s)  %s"):format(it.authors ~= "" and it.authors or "—", it.year ~= "" and it.year or "n.d.", it.title) .. (it.library_name and ("  [" .. it.library_name .. "]") or "")
end

local function fallback(items, opts)
  vim.ui.select(items, { prompt = opts.prompt, format_item = label }, function(it)
    if it then opts.on_select({ it }) end
  end)
end

local function telescope(items, opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local state = require("telescope.actions.state")
  local display = require("telescope.pickers.entry_display")

  local displayer = display.create({
    separator = " ",
    items = { { width = 24 }, { width = 4 }, { remaining = true } },
  })
  local function make_display(e)
    local it = e.value
    return displayer({
      { it.authors ~= "" and it.authors or "—", "IbidAuthor" },
      { it.year ~= "" and it.year or "n.d.", "IbidYear" },
      { it.title .. (it.library_name and ("  [" .. it.library_name .. "]") or ""), "IbidTitle" },
    })
  end

  local function selected(bufnr)
    local picker = state.get_current_picker(bufnr)
    local multi = picker:get_multi_selection()
    local out = {}
    for _, e in ipairs(multi) do table.insert(out, e.value) end
    if #out == 0 then
      local e = state.get_selected_entry()
      if e then out = { e.value } end
    end
    return out
  end

  pickers.new({}, {
    prompt_title = opts.prompt,
    finder = finders.new_table({
      results = items,
      entry_maker = function(it)
        return { value = it, display = make_display, ordinal = it.search }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Zotero",
      define_preview = function(self, entry)
        local width = vim.api.nvim_win_get_width(self.state.winid) - 2
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, require("ibid.card").lines(entry.value, width))
        vim.bo[self.state.bufnr].filetype = "markdown"
        vim.wo[self.state.winid].wrap = true
        vim.wo[self.state.winid].conceallevel = 2
      end,
    }),
    attach_mappings = function(bufnr, map)
      actions.select_default:replace(function()
        local its = selected(bufnr)
        actions.close(bufnr)
        if #its > 0 then opts.on_select(its) end
      end)
      local act = require("ibid.actions")
      for name, key in pairs(config.options.keys) do
        if key and act[name] then
          map({ "i", "n" }, key, function()
            local e = state.get_selected_entry()
            if not e then return end
            if name == "open_pdf" or name == "show_in_zotero" then actions.close(bufnr) end
            act[name](e.value)
          end, { desc = "ibid: " .. name:gsub("_", " ") })
        end
      end
      return true
    end,
  }):find()
end

-- pick({ prompt, on_select = function(items) }) — items are normalised
-- library items, most recently added first.
function M.pick(opts)
  opts.prompt = opts.prompt or "Zotero"
  library.get(function(err, lib)
    if err then return vim.notify("ibid: " .. err, vim.log.levels.ERROR) end
    local items = vim.tbl_filter(function(it) return it.key ~= nil end, lib.items)
    if #items == 0 then return vim.notify("ibid: the Zotero library is empty", vim.log.levels.WARN) end
    if pcall(require, "telescope") then telescope(items, opts) else fallback(items, opts) end
  end)
end

return M
