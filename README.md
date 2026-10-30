# BionicReading for KOReader

Bionic reading and guided dots inside KOReader's native text reader. A fork of
Gervie Macahia's Focus Reading patch, maintained by KristanLaimon. Both authors
are credited in the plugin metadata and [AUTHORS](src/AUTHORS); the original
commit history is preserved.

## Install and use

1. If you used the old patch, follow the migration steps below first.
2. Put this repository in `koreader/plugins/bionicreading.koplugin/` and restart
   KOReader. This development checkout's existing `.koplugin` directory also works;
   install only one copy.
3. Open a text book and choose **Typography → Bionic reading**. Toggle **Bionic
   reading**, **Guided dots**, or both. Each book remembers its own settings.
4. Gesture and hotkey actions are available as **Toggle bionic reading** and
   **Toggle guided dots**.

Available for reflowable books handled by KOReader's text engine, including
EPUB, HTML, TXT, FB2, and supported MOBI documents. PDF, DjVu, images, and comics
do not expose this menu. Page and scroll modes use the same native reader.

## Reading statistics and book identity

The old patch rewrote the EPUB/HTML file and called `reloadDocument()` on every
toggle. KOReader identifies statistics by book metadata and a file checksum;
rewriting a book can change that identity, especially with hash-based sidecars.

This plugin draws emphasis on the native page after text rendering and before
highlights and other decorations. It never rewrites or reloads the book, changes
pagination, navigates to another position, or opens another reader. Your native
statistics session, checksum, bookmarks, dictionary selection, and progress stay
with the same book. KOReader's normal statistics settings still determine which
reading durations count.

Emphasis adds a pixel of weight to the first part of each word using the actual
character boxes. The original rule is retained: one and three-character words
emphasize one character; other words emphasize half, rounded up. Unicode
characters are counted rather than UTF-8 bytes. Guided dots are drawn in existing
gaps between words, without adding text or changing line breaks. Their appearance
can differ from the original patch's inserted bold tags and dot characters.

## Migrate from the old patch

1. While the old patch is still installed, open each book where it was enabled
   and switch **both** Bionic Reading and Guided Dots off. The old patch restores
   its `.intellireading.orig` backup when both modes are disabled.
2. Disable/remove `2-focus-reading.lua` from your KOReader patches directory,
   then restart KOReader with this plugin installed.
3. Enable the desired modes through the new plugin menu.

Keep any `.intellireading.orig` backups until you have verified your books.
If the patch is already removed, restore a backup over its corresponding book
only while that book is closed and after saving a separate copy of both files.
The plugin does not automatically overwrite books or delete old backups.

Reading time that was never recorded cannot be recovered by this plugin.
Statistics already split between old checksums are not automatically merged.
