-- Picking items: Telescope when it's installed (card preview, multi-select
-- with <Tab>, item actions on config.keys), vim.ui.select otherwise.

local config = require("ibid.config")
local library = require("ibid.library")

local M = {}

local function label(it)
  return ("%s (%s)  %s"):format(it.authors ~= "" and it.authors or "—", it.year ~= "" and it.year or "n.d.", it.title) .. (it.library_name and ("  [" .. it.library_name .. "]") or "")
end

local function ordered(items, preselected)
  local by_key, result = {}, {}
  for _, item in ipairs(items) do by_key[item.key] = item end
  for _, key in ipairs(preselected or {}) do
    if by_key[key] then result[#result + 1], by_key[key] = by_key[key], nil end
  end
  for _, item in ipairs(items) do if by_key[item.key] then result[#result + 1], by_key[item.key] = item, nil end end
  return result
end
local function fallback(items, opts)
  local cycle = opts.cite_ft and require("ibid.cite.scan").syntax(opts.cite_ft) == "tex" and { cycle = true }
  local function cycle_label()
    return "Cycle LaTeX command (" .. (require("ibid.cite.insert").command(opts.cite_ft) or "custom") .. ")"
  end
  if opts.preselected and #opts.preselected > 0 then
    local selected, selection_order, known = {}, {}, {}
    for _, key in ipairs(opts.preselected) do
      selected[key], known[key] = true, true
      selection_order[#selection_order+1] = key
    end
    local done = { done = true }
    local choices = { done }
    if cycle then choices[#choices + 1] = cycle end
    for _, item in ipairs(items) do choices[#choices + 1] = item end
    local function show()
      vim.ui.select(choices, { prompt = opts.prompt .. " (toggle items, then Done)", format_item = function(it)
        if it.done then return "Done — confirm selected citations" end
        if it.cycle then return cycle_label() end
        return (selected[it.key] and "[x] " or "[ ] ") .. label(it)
      end }, function(it)
        if not it then return end
        if it.done then
          local result = {}
          for _, item in ipairs(items) do if selected[item.key] then result[#result + 1] = item end end
          if #result > 0 then opts.on_select(ordered(result, selection_order)) end
        elseif it.cycle then require("ibid.cite.insert").cycle_command(opts.cite_ft); show()
        else
          selected[it.key] = not selected[it.key]
          if selected[it.key] and not known[it.key] then
            known[it.key] = true; selection_order[#selection_order+1] = it.key
          end
          show()
        end
      end)
    end
    return show()
  end
  local choices = {}
  if cycle then choices[#choices + 1] = cycle end
  vim.list_extend(choices, items)
  local function show()
    vim.ui.select(choices, { prompt = opts.prompt, format_item = function(it) return it.cycle and cycle_label() or label(it) end }, function(it)
      if not it then return end
      if it.cycle then require("ibid.cite.insert").cycle_command(opts.cite_ft); show()
      else opts.on_select({ it }) end
    end)
  end
  show()
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
    return ordered(out, opts.preselected)
  end

  local picker
  picker = pickers.new({}, {
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
      if opts.cite_ft and require("ibid.cite.scan").syntax(opts.cite_ft) == "tex" then
        local key = (config.options.citation or {}).command_key
        if key == nil then key = "<C-t>" end
        if key then map({ "i", "n" }, key, function()
          local command = require("ibid.cite.insert").cycle_command(opts.cite_ft)
          vim.notify("ibid: citation command " .. (command or "custom"))
        end, { desc = "ibid: cycle citation command" }) end
      end
      if opts.preselected and #opts.preselected > 0 then
        local wanted, applied = {}, false
        opts._preselection_ready = false
        for _, key in ipairs(opts.preselected) do wanted[key] = true end
        state.get_current_picker(bufnr):register_completion_callback(function(current)
          if applied then return end
          applied = true
          local count = 0
          for index = 1, current.manager:num_results() do
            local e = current.manager:get_entry(index)
            if e and wanted[e.value.key] then current:add_selection(current:get_row(index)); count = count + 1 end
          end
          opts._preselection_ready = count == #opts.preselected
        end)
      end
      actions.select_default:replace(function()
        if opts._preselection_ready == false then
          return vim.notify("ibid: not all original citation keys are visible; replacement cancelled", vim.log.levels.WARN)
        end
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
  })
  picker:find()
end

-- pick({ prompt, on_select = function(items) }) — items are normalised
-- library items, most recently added first.
function M.pick(opts)
  opts.prompt = opts.prompt or "Zotero"
  library.get(function(err, lib)
    if err then return vim.notify("ibid: " .. err, vim.log.levels.ERROR) end
    local items = vim.tbl_filter(function(it) return it.key ~= nil end, lib.items)
    for _, key in ipairs(opts.preselected or {}) do
      if not lib.by_key or not lib.by_key[key] then
        return vim.notify("ibid: cannot replace citation containing missing Zotero key '" .. key .. "'", vim.log.levels.WARN)
      end
    end
    if #items == 0 then return vim.notify("ibid: the Zotero library is empty", vim.log.levels.WARN) end
    if pcall(require, "telescope") then telescope(items, opts) else fallback(items, opts) end
  end)
end

return M
