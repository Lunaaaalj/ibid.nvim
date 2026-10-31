# Add items by DOI / arXiv / ISBN / URL

Labels: enhancement

`:Ibid add <id>` and the browser's `a` key. The steps:

1. Resolve metadata:
   - **DOI:** `https://doi.org/<doi>` with `Accept: application/x-bibtex`, or CSL-JSON
   - **arXiv:** the export API
   - **ISBN:** OpenLibrary
   - **URL:** let Zotero's own translators handle it via `/connector/saveSnapshot`?
2. **Duplicate check** against the library: DOI, then normalised title + year. If there's a match, show the existing item instead.
3. Pick a target collection: `vim.ui.select` over `library.lib.collections`, with the last choice remembered.
4. Send it to Zotero through the connector. Two candidate endpoints:
   - `POST /connector/import` with the BibTeX body: Zotero runs its BibTeX translator and puts the result in the selected collection.
   - `/connector/saveItems` with Zotero JSON (needs a CSL→Zotero mapping).
5. Wait for the new citation key: poll `library.get()` until the signature changes and the DOI appears, then offer to cite it right away.

Not tested yet: the prototype deliberately didn't POST to `/connector/import` against a real library. Verify the collection-targeting behaviour with a throwaway profile first.

Also: the code action on an "isn't in Zotero" diagnostic → "Search Crossref for this key/title and add".
