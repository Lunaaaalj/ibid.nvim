# Library lint: find broken metadata before it reaches a bibliography

Labels: enhancement

Bad metadata in Zotero turns into bad citation keys and wrong bibliographies. Examples from a real library:

- `:pactointernacionalderechoscivilespoliticos` and `:berger2002`: the key starts with `:` because the item has no author, or the author's first and last names are swapped (first name "Casella", last name "George").
- `2024:whatdatasovereigntyibm`: the website is the author, so the key format only produced a year.

Checks, shown as a Lint tab in the browser (#01) and as `:Ibid lint` (quickfix-style list, `<CR>` → show in Zotero to fix):

- no creators · no date/year · key starts with a non-letter · key longer than N characters
- likely swapped names: first name looks like a surname (all-caps, or matches another item's surname) and the last name is a common first name
- missing DOI on `journalArticle`/`conferencePaper` (offer a Crossref lookup by title, #03)
- duplicates: same DOI, or same normalised title + year
- PDF attachment whose file is missing on disk

Fixes happen in Zotero, because ibid never writes to the database. The lint just links straight to each item.
