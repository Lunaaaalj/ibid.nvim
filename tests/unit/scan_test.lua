local h = require("tests.helpers")
local scan = require("ibid.cite.scan")
local cases = {}
local function test(name, syntax, lines, keys)
  cases[#cases + 1] = { name = name, run = function()
    local found = scan.scan_lines(lines, syntax)
    h.eq(keys, vim.tbl_map(function(f) return f.key end, found))
    for _, f in ipairs(found) do
      h.eq(f.key, lines[f.lnum + 1]:sub(f.col + 1, f.end_col))
    end
  end }
end
test("LaTeX comments and escaped percent", "tex", { [[\cite{a} % \cite{ignored}]], [[\% \cite{b}]] }, { "a", "b" })
test("LaTeX multiline and multicites", "tex", { [[\cite{a,]], [[ b} \parencites[p. 2]{c}[p. 4]{d}]] }, { "a", "b", "c", "d" })
test("LaTeX excludes macro arguments and nocite wildcard", "tex", { [[\cite{#1} \nocite{*} \cite{real}]] }, { "real" })
test("pandoc code fences inline code and emails", "pandoc", { "~~~lua", "@ignored", "~~~", "`@inline` user@example.org [@a; @b]" }, { "a", "b" })
test("Quarto crossrefs are not citations", "pandoc", { "@fig-one @tbl-two @sec-three @author2020" }, { "author2020" })
test("Typst labels and explicit citation forms", "typst", { '<section> @section @a #cite(<b>) #cite(label("c"))' }, { "a", "b", "c" })
test("Typst comments and code", "typst", { "// @comment", "```", "@fence", "```", "`@inline` @real" }, { "real" })
cases[#cases + 1] = { name = "scanner reports byte offsets after unicode", run = function()
  local line = "é [@alpha]"
  h.eq({ { key = "alpha", lnum = 0, col = 5, end_lnum = 0, end_col = 10 } }, scan.scan_lines({ line }, "pandoc"))
end }
return cases
