# Manage Better BibTeX auto-exports

Labels: enhancement

Some projects want a whole collection rather than only the cited entries, e.g. a shared `.bib` for a thesis group.
BBT's JSON-RPC exposes `autoexport.add(collection, translator, path)` (verified: it answers "required argument collection/translator/path missing").

- `:Ibid autoexport`: pick a collection and a path, then register it with BBT.
- `sync.target()` should recognise BBT-auto-exported files and report "auto-exported by Better BibTeX". It should neither refuse them nor overwrite them.
- Health: list the auto-exports that point inside the current project.
