#!/usr/bin/env bash
set -euo pipefail
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

fail() {
    echo "Build failed: $*" >&2
    exit 1
}

output_dir="$script_dir/dist"
expected_version=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|--output)
            [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"
            if [[ "$1" == --version ]]; then expected_version="$2"; else output_dir="$2"; fi
            shift 2
            ;;
        --help)
            echo "Usage: ./build.sh [--version VERSION] [--output DIRECTORY]"
            exit 0
            ;;
        *) fail "Unknown argument: $1" ;;
    esac
done
command -v zip >/dev/null 2>&1 || fail "The standard zip command is required"
command -v unzip >/dev/null 2>&1 || fail "The standard unzip command is required for ZIP verification"

# This repository has a single-package manifest. Read its literal fields with
# standard sed; no Python, Lua, jq, or package installation is needed to build.
manifest="$script_dir/manifest.json"
metadata="$script_dir/_meta.lua"
[[ -f "$manifest" && -f "$metadata" ]] || fail "Missing plugin metadata"
package_manifest="$(sed -n '/"packages"[[:space:]]*:/,$p' "$manifest")"
repo_manifest="$(sed '/"packages"[[:space:]]*:/,$d' "$manifest")"

json_value() {
    local value
    value="$(printf '%s\n' "$2" | sed -nE "s/^[[:space:]]*\"$1\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p")"
    [[ -n "$value" && "$value" != *$'\n'* ]] || fail "Missing or duplicate manifest field: $1"
    printf '%s\n' "$value"
}

meta_value() {
    local value
    value="$(sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*(_\([[:space:]]*)?\"([^\"]*)\".*/\2/p" "$metadata")"
    [[ -n "$value" && "$value" != *$'\n'* ]] || fail "Missing or duplicate _meta.lua field: $1"
    printf '%s\n' "$value"
}

for field in id version description author; do
    metadata_field="$(meta_value "$field")"
    manifest_field="$(json_value "$field" "$package_manifest")"
    [[ "$metadata_field" == "$manifest_field" ]] || fail "_meta.lua and manifest.json disagree on $field"
done
metadata_name="$(meta_value fullname)"
manifest_name="$(json_value name "$package_manifest")"
[[ "$metadata_name" == "$manifest_name" ]] || fail "Plugin display names disagree"
for value in "$(meta_value id)" "$(meta_value name)" \
    "$(json_value id "$repo_manifest")" "$(json_value plugin_module "$package_manifest")"; do
    [[ "$value" == bionicreading ]] || fail "Package and module IDs must be bionicreading"
done
asset_name=bionicreading.koplugin.zip
manifest_asset="$(json_value source_asset "$package_manifest")"
[[ "$manifest_asset" == "$asset_name" ]] || fail "source_asset must be $asset_name"
version="$(meta_value version)"
if [[ -n "$expected_version" && "$version" != "$expected_version" ]]; then
    fail "Tag version $expected_version does not match metadata version $version"
fi

[[ -f "$script_dir/src/bionicreading.lua" && ! -L "$script_dir/src" ]] \
    || fail "Missing plugin implementation or symlinked src directory"
mkdir -p "$output_dir"
output_dir="$(CDPATH= cd -- "$output_dir" && pwd)"
staging="$(mktemp -d)"
trap 'rm -rf -- "$staging"' EXIT
plugin_dir="$staging/bionicreading.koplugin"
mkdir -p "$plugin_dir/src"
for name in main.lua _meta.lua manifest.json README.md LICENSE; do
    [[ -f "$script_dir/$name" && ! -L "$script_dir/$name" ]] || fail "Missing or symlinked file: $name"
    cp "$script_dir/$name" "$plugin_dir/$name"
done
[[ -f "$script_dir/src/AUTHORS" && ! -L "$script_dir/src/AUTHORS" ]] || fail "Missing or symlinked src/AUTHORS"
cp "$script_dir/src/AUTHORS" "$plugin_dir/src/AUTHORS"
while IFS= read -r -d '' file; do
    [[ ! -L "$file" ]] || fail "Symlinked source file: $file"
    relative="${file#"$script_dir/"}"
    mkdir -p "$plugin_dir/$(dirname -- "$relative")"
    cp "$file" "$plugin_dir/$relative"
done < <(find "$script_dir/src" -name '*.lua' \( -type f -o -type l \) -print0)

# Package a fresh staging tree, so previous builds and development files cannot
# leak into the ZIP. -X omits host-specific extra attributes.
(
    cd -- "$staging"
    zip -q -r -X "$asset_name" bionicreading.koplugin
    zip -T "$asset_name" >/dev/null
)
mv -f -- "$staging/$asset_name" "$output_dir/$asset_name"
echo "$output_dir/$asset_name"
