#!/bin/bash
# Read JSON from stdin and extract all fields in a single jq call
input=$(cat)
eval "$(echo "$input" | jq -r '
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "used_pct_raw=\(.context_window.used_percentage // "")",
  @sh "five_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "five_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "seven_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "seven_reset=\(.rate_limits.seven_day.resets_at // "")"
')"

# RunCat Neo custom metrics. Keep this best-effort so a metrics write failure
# never breaks Claude Code's status line.
runcat_out="${RUNCAT_OUT_FILE:-$HOME/.claude/runcat-usage.json}"
runcat_dir=$(dirname "$runcat_out")
if mkdir -p "$runcat_dir" 2>/dev/null; then
    runcat_tmp=$(mktemp "$runcat_dir/.runcat-usage.XXXXXX" 2>/dev/null) || runcat_tmp=""
    if [ -n "$runcat_tmp" ]; then
        if echo "$input" | jq '{
            title: "Claude Code",
            symbol: "staroflife",
            metricsBarValue: (if .rate_limits.five_hour.used_percentage != null then "\(.rate_limits.five_hour.used_percentage | round)%" elif .rate_limits.seven_day.used_percentage != null then "\(.rate_limits.seven_day.used_percentage | round)%" else null end),
            metrics: ([
                (if .rate_limits.five_hour.used_percentage != null then {title: "5h", formattedValue: "\(.rate_limits.five_hour.used_percentage | round)%\(if (.rate_limits.five_hour.resets_at | type) == "number" then " ↻ \((.rate_limits.five_hour.resets_at + (9 * 60 * 60)) | strftime("%m/%d %H:%M"))" else "" end)", normalizedValue: ([.rate_limits.five_hour.used_percentage / 100, 0] | max | [., 1] | min)} else empty end),
                (if .rate_limits.seven_day.used_percentage != null then {title: "7d", formattedValue: "\(.rate_limits.seven_day.used_percentage | round)%\(if (.rate_limits.seven_day.resets_at | type) == "number" then " ↻ \((.rate_limits.seven_day.resets_at + (9 * 60 * 60)) | strftime("%m/%d %H:%M"))" else "" end)", normalizedValue: ([.rate_limits.seven_day.used_percentage / 100, 0] | max | [., 1] | min)} else empty end)
            ]),
            lastUpdatedDate: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        } | with_entries(select(.value != null))' >"$runcat_tmp" 2>/dev/null; then
            mv -f "$runcat_tmp" "$runcat_out" 2>/dev/null || rm -f "$runcat_tmp"
        else
            rm -f "$runcat_tmp"
        fi
    fi
fi

# --- Line 1: Current folder path ---
echo "📁 ${cwd/#$HOME/~}"

# --- Line 2: Git repo and branch (only when inside a git repo) ---
if git -C "$cwd" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    repo_name=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
    branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    echo "🐙 $repo_name | 🌿 $branch"

fi

# --- Line 3: Context bar and model ---
if [ -n "$used_pct_raw" ]; then
    used_int=$(printf "%.0f" "$used_pct_raw")
    filled=$(( used_int * 20 / 100 ))
    empty=$(( 20 - filled ))
    # tr は byte 単位の処理で UTF-8 マルチバイト文字 (█ 等) を壊すので
    # bash の loop で組み立てる
    bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "🧠 [${bar}] ${used_int}% | 💪 $model"
else
    echo "🧠 [░░░░░░░░░░░░░░░░░░░░]  --% | 💪 $model"
fi

# --- Line 4: Rate limits (only when data is available) ---
if [ -n "$five_pct" ] || [ -n "$seven_pct" ]; then
    line4="💰"

    # BSD date は `-r EPOCH`、GNU date は `-d "@EPOCH"` で Unix epoch を扱う。
    # PATH 上に GNU coreutils が来ても動くよう両方試す。
    fmt_epoch() {
        date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
    }

    if [ -n "$five_pct" ]; then
        five_int=$(printf "%.0f" "$five_pct")
        if [ -n "$five_reset" ]; then
            line4="${line4} 5h ${five_int}% (🔄 $(fmt_epoch "$five_reset" "%H:%M"))"
        else
            line4="${line4} 5h ${five_int}%"
        fi
    fi

    if [ -n "$seven_pct" ]; then
        seven_int=$(printf "%.0f" "$seven_pct")
        if [ -n "$seven_reset" ]; then
            line4="${line4} | 7d ${seven_int}% (🔄 $(fmt_epoch "$seven_reset" "%m/%d %H:%M"))"
        else
            line4="${line4} | 7d ${seven_int}%"
        fi
    fi

    echo "$line4"
fi
