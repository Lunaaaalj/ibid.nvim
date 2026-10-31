# Portability: Linux/Windows, linked attachments, group libraries

Labels: enhancement

- **Profile and data dir lookup:** `config.data_dir()` only knows macOS's profile path and `~/.zotero/zotero` (Linux). Add `~/.var/app/org.zotero.Zotero` (Flatpak) and `%APPDATA%\Zotero` (Windows).
- **Linked attachments with `attachments:` paths** are relative to `extensions.zotero.baseAttachmentPath`. Read that pref, so ZotFile-style setups find their PDFs.
- **Group libraries:** `select_url` already handles groups. Check that group items have BBT keys and show the library name in the picker.
- **`vim.ui.open`** of `zotero://` URLs on Linux (needs the desktop handler); document the fallback.
