# Claude: summaries, and source-aware rigor review

Labels: enhancement, ai

Use the same transport as the host config's writing companion and upstream.nvim: headless `claude -p --output-format json`, an empty cwd, and the Claude Code login.

- **Summarise an item.** Use the abstract, plus Zotero's indexed full text when it exists (`fulltext.sqlite` / `storage/<key>/.zotero-ft-cache`). Cache the summary per item and `dateModified`, and show it in the card.
- **Hook for source-aware review.** Expose `require("ibid").context(keys)` → `{ key = { title, authors, year, abstract, excerpt? } }`, so other tools can give the model what a citation actually says.
  The motivating consumer is the config's `writing/rigor.lua`, whose prompt currently has to say "citations count as support, the model can't read sources". With this hook it could flag claims that the cited abstract doesn't support.
  The glue belongs in the host config; ibid only provides the data.
- **"Find support"** for a selected claim: rank library items by relevance (abstracts in the prompt; embeddings only if the library gets big) and offer to cite the top hits.
