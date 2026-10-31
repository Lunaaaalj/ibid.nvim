# Library browser float

Labels: enhancement

A full-screen float in the style of upstream.nvim: a list on the left and the item card on the right.

- **Tabs:** Library · Collections (as a tree) · Tags · Recent · Lint (see #02). `<Tab>`/`<S-Tab>` and `1`–`5` switch tabs.
- **List:** one item per line, so `j`/`k`/`G` work natively. The float's cursorline is the selection, and its filetype is `ibid`, so hosts can exempt it from cursorline management.
- **Detail pane:** the existing `card.lua`, plus child notes (Zotero's note HTML converted to markdown with pandoc when it's installed), the annotation count, and **which open documents / project files cite the item** (ripgrep over a configured root).
- **Keys:** `i` cite into the previous window · `o` PDF · `gz` show in Zotero · `gx` DOI/URL · `y`/`Y`/`R` yank key/BibTeX/reference · `/` filter · `r` reload · `?` help.
- **State:** the last tab, filter and cursor survive closing the float.

The data is already there: `library.lua` holds collections, with `parent` for the tree, plus tags and attachments.
