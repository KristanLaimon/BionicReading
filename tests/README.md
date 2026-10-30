# Tests

`PanelsPlusTestFramework/init.lua` contains the framework extracted from Panels Plus.
Its MIT notice is retained, with its license in `PanelsPlusTestFramework/license.md`. Tests follow the same
philosophy: plain Lua `describe`/`it`, explicit assertions and small mocks, no
Busted, LuaRocks, or network setup.

Run `./run-tests.sh` or `LUA=luajit ./run-tests.sh` from the repository root.
Pass a spec path to run that spec alone.

Plugin source is under `src/`. The root `main.lua` delegates to its namespaced
implementation so the packaged KOReader entry point remains valid.

The unit suite checks native reader identity, checksum and statistics session
preservation, public action registration, per-book settings, instance hook
cleanup, page/scroll integration, text-book-only availability, Unicode emphasis,
clipped text, empty pages, traversal termination, and dot placement.

`./run-tests.sh --native` uses LuaJIT and the installed KOReader libraries
(`KOREADER_DIR`, default `/usr/lib/koreader`). It checks actual rendered pixels,
on/off reversibility, unchanged HTML and EPUB bytes, pagination, reading position,
dictionary text, page and scroll drawing, and two-column layouts. Its statistics
regression runs KOReader's real `onPageUpdate`, `onCloseDocument`, schema and
SQLite insertion methods against an isolated database: page turns across mode
toggles must retain one book record and persist 27 seconds on two pages.
Unrelated statistics UI services are mocked. No real-time waiting is needed.

Native fixtures and databases are isolated in a temporary directory; PNGs and
the database remain there for inspection. `fixtures/book.epub` is a generated
sample containing only test prose, with no external book content.

These are host regression tests. Device responsiveness, all scripts/fonts and
every other plugin combination still require interactive testing on the target
reader. Visual emphasis preserves layout and uses a one-pixel weight increase;
it does not replace the native font with a separate bold font.
