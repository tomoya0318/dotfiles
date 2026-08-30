#!/bin/bash
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../run-codex-tab/scripts" && pwd)/resume-codex-tab.sh" "$@"
