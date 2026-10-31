# PDF annotations and literature notes

Labels: enhancement

**Annotations:** read `itemAnnotations`, which has the highlight text, comment, colour, `pageLabel` and `position` JSON. Use them in two ways:
- list them in the card and browser, where `<CR>` opens the PDF at that page;
- jump straight to the page in pdfview through an `open_pdf(path, item, { page = n })` hook. The host config already has a page-aware viewer.

**Literature notes:** `:Ibid note` opens (or creates) `<notes_dir>/<key>.md` (or `.typ`) from a template.
The template has front matter (key, title, authors, year, DOI, `zotero://` link), the abstract, and the annotations grouped by colour, with page references.
Re-running it appends new annotations instead of overwriting the note.

**Backlinks:** for the item under the cursor, ripgrep the configured roots for the key and show the hits in a quickfix list or Telescope.
