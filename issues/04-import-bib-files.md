# Import .bib / RIS files into Zotero

Labels: enhancement

`:Ibid import [file]`: send a `.bib`/`.ris` file (or the current buffer) to Zotero through `/connector/import`.
This is useful for the `.bib` files that pile up from publishers' "export citation" buttons and old projects.

- Before sending, parse the entries with `bib/sync.lua`'s `entries()` and skip ones already in the library (by DOI / title + year). Show a summary like "12 new, 3 already in Zotero".
- After the import, offer to rewrite the source document's keys to the keys Zotero/BBT assigned. Optionally the old keys could go into BBT's `extra` field (`Citation Key: old`) to pin them.
- Afterwards, offer to turn the file into a managed one (`:Ibid sync!`).
