#!/usr/bin/env bash
set -euo pipefail
repo="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
temporary="$(mktemp -d)"
trap 'rm -rf -- "$temporary"' EXIT
fixture="$temporary/repo"
mkdir -p "$fixture"
for name in build.sh main.lua _meta.lua manifest.json README.md LICENSE; do
    cp "$repo/$name" "$fixture/$name"
done
cp -R "$repo/src" "$fixture/src"
mkdir -p "$fixture/tests" "$fixture/src/__pycache__"
printf 'not plugin data\n' > "$fixture/tests/private.txt"
printf 'not plugin data\n' > "$fixture/src/__pycache__/cache.pyc"

bash "$fixture/build.sh" --output "$temporary/output" >/dev/null
archive="$temporary/output/bionicreading.koplugin.zip"
unzip -t "$archive" >/dev/null
unzip -Z -1 "$archive" | sed '/\/$/d' | LC_ALL=C sort > "$temporary/actual"
cat > "$temporary/expected" <<'EOF'
bionicreading.koplugin/LICENSE
bionicreading.koplugin/README.md
bionicreading.koplugin/_meta.lua
bionicreading.koplugin/main.lua
bionicreading.koplugin/manifest.json
bionicreading.koplugin/src/AUTHORS
bionicreading.koplugin/src/bionicrenderer.lua
bionicreading.koplugin/src/bionicreading.lua
EOF
LC_ALL=C sort -o "$temporary/expected" "$temporary/expected"
diff -u "$temporary/expected" "$temporary/actual"
echo "PASS: ZIP contains the canonical plugin tree and no development files"

unzip -q "$archive" -d "$temporary/unpacked"
"${LUA:-lua}" - "$temporary/unpacked/bionicreading.koplugin" <<'LUA'
local root = arg[1]
package.path = root .. "/?.lua;" .. package.path
package.preload.dispatcher = function() return {} end
package.preload["ui/uimanager"] = function() return {} end
package.preload["ui/widget/container/widgetcontainer"] = function()
    return { extend = function(_, class) return class end }
end
package.preload["ffi/blitbuffer"] = function() return {} end
package.preload.gettext = function() return function(text) return text end end
local plugin = dofile(root .. "/main.lua")
assert(plugin.name == "bionicreading")
assert(type(plugin.onToggleBionicReading) == "function")
LUA
echo "PASS: packaged KOReader entry point loads the implementation from src"

if bash "$fixture/build.sh" --version 999.0.0 --output "$temporary/rejected" >"$temporary/error" 2>&1; then
    echo "FAIL: mismatched tag was accepted" >&2
    exit 1
fi
grep -F 'does not match metadata version' "$temporary/error" >/dev/null
[[ ! -e "$temporary/rejected" ]]
echo "PASS: mismatched tag is rejected before creating an archive"

sed 's/"version": "[^"]*"/"version": "999.0.0"/' "$fixture/manifest.json" > "$temporary/changed.json"
mv "$temporary/changed.json" "$fixture/manifest.json"
if bash "$fixture/build.sh" --output "$temporary/rejected" >"$temporary/error" 2>&1; then
    echo "FAIL: inconsistent metadata was accepted" >&2
    exit 1
fi
grep -F 'disagree on version' "$temporary/error" >/dev/null
echo "PASS: inconsistent manifest and _meta.lua versions are rejected"

sed '/^[[:space:]]*version[[:space:]]*=/d' "$fixture/_meta.lua" > "$temporary/changed.lua"
mv "$temporary/changed.lua" "$fixture/_meta.lua"
if bash "$fixture/build.sh" --output "$temporary/rejected" >"$temporary/error" 2>&1; then
    echo "FAIL: missing metadata version was accepted" >&2
    exit 1
fi
grep -F 'Missing or duplicate _meta.lua field: version' "$temporary/error" >/dev/null
echo "PASS: missing metadata fields fail the build"
