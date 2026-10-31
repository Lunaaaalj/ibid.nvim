-- An item as markdown lines: the picker preview, hover and :Ibid info.

local library = require("ibid.library")

local M = {}

local types = {
  journalArticle = "Article", conferencePaper = "Conference paper", book = "Book",
  bookSection = "Book chapter", thesis = "Thesis", report = "Report", webpage = "Web page",
  blogPost = "Blog post", encyclopediaArticle = "Encyclopedia entry", preprint = "Preprint",
  computerProgram = "Software", magazineArticle = "Magazine article", newspaperArticle = "Newspaper article",
  dataset = "Dataset", manuscript = "Manuscript", presentation = "Presentation",
}

local function wrap(text, width)
  local out, line = {}, ""
  for word in text:gmatch("%S+") do
    if line ~= "" and vim.fn.strdisplaywidth(line .. " " .. word) > width then
      table.insert(out, line)
      line = word
    else
      line = line == "" and word or (line .. " " .. word)
    end
  end
  if line ~= "" then table.insert(out, line) end
  return out
end

-- lines(item, width?) → markdown lines
function M.lines(it, width)
  width = width or 78
  local out = {}
  local function add(s) table.insert(out, s) end
  for _, l in ipairs(wrap("# " .. (it.title ~= "" and it.title or "(untitled)"), width)) do add(l) end
  add("")
  local who = it.author_list ~= "" and it.author_list or "(no authors)"
  for _, l in ipairs(wrap(("**%s** · %s"):format(who, it.date or it.year ~= "" and it.year or "n.d."), width)) do
    add(l)
  end
  local where = { types[it.type] or it.type }
  if it.container and it.container ~= "" then table.insert(where, 1, "*" .. it.container .. "*") end
  add(table.concat(where, " · "))
  add("")
  add("`" .. (it.key or "(no citation key)") .. "`")
  if it.doi then add("DOI: https://doi.org/" .. it.doi) elseif it.url then add("URL: " .. it.url) end
  if #it.tags > 0 then add("Tags: " .. table.concat(it.tags, ", ")) end
  local cols = {}
  for _, id in ipairs(it.collections) do
    local c = library.lib and library.lib.collections[id]
    if c then table.insert(cols, c.name) end
  end
  if #cols > 0 then add("Collections: " .. table.concat(cols, ", ")) end
  local pdf = library.pdf(it)
  if pdf then add("PDF: " .. vim.fs.basename(pdf)) end
  if it.abstract and it.abstract ~= "" then
    add("")
    add("---")
    add("")
    for _, para in ipairs(vim.split(it.abstract, "\n%s*\n")) do
      vim.list_extend(out, wrap(para, width))
      add("")
    end
    if out[#out] == "" then table.remove(out) end
  end
  return out
end

return M
