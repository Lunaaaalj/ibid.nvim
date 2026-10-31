-- Highlight groups. All are `default` links, so a colorscheme or the user's
-- config (setup({ highlights = … }) or plain :hi on ColorScheme) wins.

local config = require("ibid.config")

local M = {}

M.links = {
  IbidAuthor = "Identifier",
  IbidYear = "Number",
  IbidTitle = "Normal",
  IbidKey = "Constant",
  IbidMuted = "Comment",
  IbidAccent = "Function",
}

function M.setup()
  for name, target in pairs(M.links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  for name, spec in pairs(config.options.highlights or {}) do
    vim.api.nvim_set_hl(0, name, spec)
  end
end

return M
