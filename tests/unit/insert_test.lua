local h = require("tests.helpers")
local insert = require("ibid.cite.insert")
local cases = {}
for _, row in ipairs({
  { "tex full", "tex", "Text ", [[\cite{a,b}]] },
  { "tex empty citation", "tex", [[\cite{]], "a,b" },
  { "tex existing key", "tex", [[\parencite{old]], ",a,b" },
  { "tex trailing comma", "tex", [[\cite{old, ]], "a,b" },
  { "pandoc full", "markdown", "Text ", "[@a; @b]" },
  { "pandoc after at", "quarto", "@", "a; @b" },
  { "pandoc bracket locator", "rmd", "[@old, p. 3", "; @a; @b" },
  { "typst full", "typst", "Text ", "@a @b" },
  { "typst after at", "typst", "@", "a @b" },
}) do
  cases[#cases + 1] = { name = "insert " .. row[1], run = function()
    require("ibid.config").setup({})
    h.eq(row[4], insert.text({ "a", "b" }, row[2], row[3]))
  end }
end
cases[#cases + 1] = { name = "custom citation format function", run = function()
  local config = require("ibid.config")
  config.setup({ formats = { tex = function(keys, ft) return ft .. ":" .. table.concat(keys, "/") end } })
  h.eq("tex:a/b", insert.text({ "a", "b" }, "tex", ""))
  config.setup({})
end }
return cases
