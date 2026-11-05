local h = require("tests.helpers")
local detect = require("ibid.bib.detect")
local cases = {}
local function check(name, ft, lines, names, translator, setup)
  cases[#cases + 1] = { name = "detect " .. name, run = function()
    require("ibid.config").setup({})
    local dir = h.tempdir()
    local buf = vim.api.nvim_create_buf(false, true)
    local ok, err = xpcall(function()
      vim.api.nvim_buf_set_name(buf, dir .. "/document." .. ft)
      vim.bo[buf].filetype = ft
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      if setup then setup(buf, dir) end
      local expected = vim.tbl_map(function(n) return { path = dir .. "/" .. n, translator = translator or "Better BibLaTeX" } end, names)
      h.eq(expected, detect.bibs(buf))
    end, debug.traceback)
    vim.api.nvim_buf_delete(buf, { force = true })
    require("ibid.config").setup({})
    assert(ok, err)
  end }
end
check("biblatex options and deduplication", "tex", { [[\addbibresource[location=local]{refs.bib}]], [[\addbibresource{refs.bib}]], [[% \addbibresource{ignored.bib}]] }, { "refs.bib" })
check("bibtex list adds extension", "tex", { [[\bibliography{a, b.bib}]] }, { "a.bib", "b.bib" }, "Better BibTeX")
check("pandoc YAML scalar", "markdown", { "---", "bibliography: refs.bib", "---" }, { "refs.bib" })
check("pandoc YAML inline list", "quarto", { "---", "bibliography: ['a.bib', b.bib]", "---" }, { "a.bib", "b.bib" })
check("pandoc YAML block list", "rmd", { "---", "bibliography:", "  - a.bib", "  - b.bib", "---" }, { "a.bib", "b.bib" })
check("quarto project fallback", "quarto", { "Chapter" }, { "project.bib" }, nil, function(_, dir)
  vim.fn.writefile({ "bibliography: project.bib" }, dir .. "/_quarto.yml")
end)
check("Typst scalar", "typst", { '#bibliography("refs.bib")' }, { "refs.bib" })
check("Typst tuple", "typst", { '#bibliography(("a.bib", "b.bib"))' }, { "a.bib", "b.bib" })
check("buffer fallback", "markdown", { "Text" }, { "local.bib" }, nil, function(buf) vim.b[buf].ibid_bib = "local.bib" end)
check("configured fallback", "markdown", { "Text" }, { "config.bib" }, nil, function(buf)
  vim.b[buf].ibid_bib = "buffer.bib"
  require("ibid.config").setup({ bib = { fallback = function() return "config.bib" end } })
end)
return cases
