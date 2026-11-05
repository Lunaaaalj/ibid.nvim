local h = require("tests.helpers")
local entries = require("ibid.bib.sync").entries
return {
  { name = "entries ignore directives and preserve nested braces", run = function()
    local a = '@article{alpha,\n title = {{Nested} Title},\n note = {a, b}\n}'
    local b = '@book(beta, title = "Other")'
    local parsed, order = entries('% Header\n@string{journal = "J"}\n@comment{unused}\n@preamble{"p"}\n' .. a .. '\n\n' .. b .. '\n')
    h.eq({ alpha = a, beta = b }, parsed)
    h.eq({ "alpha", "beta" }, order)
  end },
  { name = "entries empty input", run = function()
    h.eq({}, entries(nil))
    h.eq({}, entries(""))
  end },
}
