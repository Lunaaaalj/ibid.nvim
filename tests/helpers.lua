local M = {}
local dirs = {}
function M.eq(expected, actual)
  assert(vim.deep_equal(expected, actual), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
function M.truthy(value, msg) assert(value, msg or "expected a truthy value") end
function M.tempdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  dir = vim.uv.fs_realpath(dir) or dir
  dirs[#dirs + 1] = dir
  return dir
end
function M.wait(predicate, timeout)
  assert(vim.wait(timeout or 5000, predicate, 10), "timed out waiting for callback")
end
function M.cleanup()
  for _, dir in ipairs(dirs) do vim.fn.delete(dir, "rf") end
  dirs = {}
end
return M
