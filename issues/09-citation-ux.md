# Citation UX: command variants, insert-mode picker, locators

Labels: enhancement

- **Choose the LaTeX command at insert time.** A second key in the picker (or `formats.tex` as a list) cycles `\cite` / `\parencite` / `\textcite` / `\autocite` / `\citeauthor`. The last choice is remembered per filetype.
- **Insert-mode trigger.** A mapping such as `<C-g>c` opens the picker from insert mode. `insert.capture()` already supports resuming insert mode afterwards.
- **Locators.** After picking, optionally prompt for a page or locator: `\cite[p.~12]{k}`, `[@k, p. 12]`, `@k[p. 12]`.
- **Change the citation under the cursor.** Re-open the picker with the current keys pre-selected, and replace the whole citation.
- **cmp source:** limit the results while the typed word is empty, if the library is large (thousands of items).
