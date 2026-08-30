#!/usr/bin/env bash
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../run-codex-tab/scripts" && pwd)/spawn-codex-tab.sh" "$@"
