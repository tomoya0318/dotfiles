#!/bin/bash
# Read JSON from stdin
input=$(cat)

# --- Line 1: Current folder path ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# Replace $HOME with ~
home_escaped=$(echo "$HOME" | sed 's|/|\\/|g')
display_path=$(echo "$cwd" | sed "s|^$HOME|~|")
echo "📁 $display_path"

# --- Line 2: Git repo and branch (only when inside a git repo) ---
if git -C "$cwd" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    repo_name=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
    branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    echo "🐙 $repo_name | 🌿 $branch"
fi

# --- Line 3: Context bar and model ---
model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
used_pct_raw=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

if [ -n "$used_pct_raw" ]; then
    # Round to integer
    used_int=$(printf "%.0f" "$used_pct_raw")

    # Build a 20-character progress bar
    bar_width=20
    filled=$(( used_int * bar_width / 100 ))
    empty=$(( bar_width - filled ))
    bar=""
    for i in $(seq 1 $filled); do bar="${bar}█"; done
    for i in $(seq 1 $empty);  do bar="${bar}░"; done

    echo "🧠 [${bar}] ${used_int}% | 💪 $model"
else
    echo "🧠 [--------------------]  --% | 💪 $model"
fi

# --- Line 4: Rate limits (only when data is available) ---
five_pct=$(echo "$input"  | jq -r '.rate_limits.five_hour.used_percentage  // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at        // empty')
seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage  // empty')
seven_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at       // empty')

if [ -n "$five_pct" ] || [ -n "$seven_pct" ]; then
    line4="💰"

    if [ -n "$five_pct" ]; then
        five_int=$(printf "%.0f" "$five_pct")
        if [ -n "$five_reset" ]; then
            reset_time=$(date -r "$five_reset" "+%H:%M" 2>/dev/null || date -d "@$five_reset" "+%H:%M" 2>/dev/null)
            line4="${line4} 5h ${five_int}% (🔄 ${reset_time})"
        else
            line4="${line4} 5h ${five_int}%"
        fi
    fi

    if [ -n "$seven_pct" ]; then
        seven_int=$(printf "%.0f" "$seven_pct")
        if [ -n "$seven_reset" ]; then
            reset_dt=$(date -r "$seven_reset" "+%m/%d %H:%M" 2>/dev/null || date -d "@$seven_reset" "+%m/%d %H:%M" 2>/dev/null)
            line4="${line4} | 7d ${seven_int}% (🔄 ${reset_dt})"
        else
            line4="${line4} | 7d ${seven_int}%"
        fi
    fi

    echo "$line4"
fi
