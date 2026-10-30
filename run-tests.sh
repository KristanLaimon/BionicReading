#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ "${1:-}" == "--native" ]]; then
    shift
    exec luajit tests/native.lua "$@"
fi
exec "${LUA:-lua}" tests/run_tests.lua "$@"
