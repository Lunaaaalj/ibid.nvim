# Cited keys across multi-file documents (Typst, Quarto, pandoc)

Labels: enhancement

`scan.project_keys()` only follows LaTeX projects (through VimTeX's `sources`). Elsewhere, only the current buffer is scanned, so syncing from a chapter file prunes entries that other chapters cite.

- **Typst:** follow `#include "x.typ"` (and `#import` of local files) from the file that has `#bibliography`. Diagnostics in an included file should resolve `@label`s defined in the rest of the document.
- **Quarto projects:** a book's chapters come from `_quarto.yml`'s `book.chapters`. Scan them all when the bibliography comes from `_quarto.yml`.
- **Without VimTeX:** follow `\input`/`\include` from `% !TEX root` / the main file.

Until this lands, `bib.prune = false` is the safe setting for multi-file documents.
