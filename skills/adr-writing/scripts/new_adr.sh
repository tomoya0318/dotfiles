#!/bin/sh

set -eu
LC_ALL=C
export LC_ALL

usage() {
  cat <<'EOF'
Usage:
  new_adr.sh --project-root PATH --title TITLE --slug SLUG [options]

Create the next numbered ADR in <project-root>/ai-guide/adr.

Options:
  --project-root PATH   Confirmed project root. Required.
  --title TITLE         ADR title in one line. Required.
  --slug SLUG           Lowercase ASCII filename slug. Required.
  --status STATUS       Initial status: 提案 or 採用. Defaults to 提案.
  --related-adr TEXT    Related ADR links. Defaults to なし.
  --date YYYY-MM-DD     Valid calendar date. Defaults to today.
  --help                Show this help.
EOF
}

die() {
  printf '%s\n' "Error: $*" >&2
  exit 2
}

require_value() {
  option=$1
  if [ "$#" -lt 2 ] || [ -z "$2" ]; then
    die "$option requires a value."
  fi
}

require_one_line() {
  value=$1
  label=$2
  newline='
'
  case $value in
    '' | *"$newline"*) die "$label must be a non-empty single line." ;;
  esac
}

validate_date() {
  value=$1

  case $value in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "--date must be a valid calendar date in YYYY-MM-DD format." ;;
  esac

  normalized=
  if normalized=$(date -j -f '%Y-%m-%d' "$value" '+%Y-%m-%d' 2>/dev/null); then
    :
  elif normalized=$(date -d "$value" '+%Y-%m-%d' 2>/dev/null); then
    :
  else
    die "--date must be a valid calendar date in YYYY-MM-DD format."
  fi

  [ "$normalized" = "$value" ] ||
    die "--date must be a valid calendar date in YYYY-MM-DD format."
}

project_root=
title=
slug=
status=提案
related_adr=なし
adr_date=$(date '+%Y-%m-%d')

while [ "$#" -gt 0 ]; do
  case $1 in
    --project-root)
      require_value "$@"
      project_root=$2
      shift 2
      ;;
    --title)
      require_value "$@"
      title=$2
      shift 2
      ;;
    --slug)
      require_value "$@"
      slug=$2
      shift 2
      ;;
    --status)
      require_value "$@"
      status=$2
      shift 2
      ;;
    --related-adr)
      require_value "$@"
      related_adr=$2
      shift 2
      ;;
    --date)
      require_value "$@"
      adr_date=$2
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_one_line "$project_root" "--project-root"
require_one_line "$title" "--title"
require_one_line "$slug" "--slug"
require_one_line "$status" "--status"
require_one_line "$related_adr" "--related-adr"
require_one_line "$adr_date" "--date"

case $slug in
  *[!a-z0-9-]* | -* | *- | *--*)
    die "--slug must use lowercase ASCII letters, digits, and single hyphens."
    ;;
esac

case $status in
  提案 | 採用) ;;
  *)
    die "--status must be 提案 or 採用 when creating a new ADR."
    ;;
esac

validate_date "$adr_date"

if ! project_root=$(CDPATH= cd "$project_root" && pwd -P); then
  die "Project root does not exist or is not a directory."
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
template=$script_dir/../assets/adr-template.md
[ -r "$template" ] || die "Template is not readable: $template"

adr_dir=$project_root/ai-guide/adr
mkdir -p "$adr_dir"

lock_dir=$adr_dir/.new-adr.lock
lock_acquired=0
temp_file=

cleanup() {
  if [ -n "$temp_file" ]; then
    rm -f "$temp_file"
  fi
  if [ "$lock_acquired" -eq 1 ] && [ -d "$lock_dir" ]; then
    rmdir "$lock_dir" 2>/dev/null || :
  fi
}

trap cleanup 0
trap 'exit 1' 1 2 15

lock_attempt=0
until mkdir "$lock_dir" 2>/dev/null; do
  lock_attempt=$((lock_attempt + 1))
  if [ "$lock_attempt" -ge 100 ]; then
    die "Could not acquire the ADR creation lock: $lock_dir"
  fi
  sleep 0.1
done
lock_acquired=1

max=0
for path in "$adr_dir"/[0-9][0-9][0-9][0-9]-*.md; do
  [ -f "$path" ] || continue
  filename=${path##*/}
  prefix=${filename%%-*}
  number=$(printf '%s\n' "$prefix" | awk '{ print $1 + 0 }')
  [ "$number" -le "$max" ] || max=$number
done

number=$((max + 1))
while [ "$number" -le 9999 ]; do
  padded_number=$(printf '%04d' "$number")
  target=$adr_dir/$padded_number-$slug.md
  temp_file=$(mktemp "$adr_dir/.new-adr.XXXXXX") ||
    die "Could not create a temporary ADR file in $adr_dir."

  {
    printf '# ADR-%s: %s\n\n' "$padded_number" "$title"
    printf '%s\n' "- 状態：$status"
    printf '%s\n' "- 日付：$adr_date"
    printf '%s\n\n' "- 関連 ADR：$related_adr"
    cat "$template"
  } > "$temp_file" || die "Could not write the temporary ADR file."

  chmod 0644 "$temp_file" || die "Could not set ADR file permissions."

  if ln "$temp_file" "$target" 2>/dev/null; then
    rm -f "$temp_file"
    temp_file=
    printf '%s\n' "$target"
    exit 0
  fi

  rm -f "$temp_file"
  temp_file=
  if [ -e "$target" ] || [ -L "$target" ]; then
    number=$((number + 1))
    continue
  fi

  die "Could not publish the ADR file: $target"
done

die "No ADR number is available below 10000."
