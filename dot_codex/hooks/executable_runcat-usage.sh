#!/bin/sh
# Write Codex native usage data to a RunCat Neo Custom Metrics JSON file.
# This hook is best-effort: it always returns success so Codex is never blocked.

input=$(cat)
out=${RUNCAT_OUT_FILE:-"$HOME/.codex/runcat-usage.json"}
out_dir=$(dirname "$out")
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
if [ -n "$transcript" ] && [ -r "$transcript" ]; then
    # Codex transcripts are JSONL. Select the newest native token_count event.
    token_count=$(jq -cs '[.[] | .payload // empty | select(.type == "token_count")] | last // {}' "$transcript" 2>/dev/null)
else
    token_count='{}'
fi

mkdir -p "$out_dir" 2>/dev/null || {
    printf '{}\n'
    exit 0
}

tmp=$(mktemp "$out_dir/.runcat-usage.XXXXXX" 2>/dev/null) || {
    printf '{}\n'
    exit 0
}

if jq -n --argjson token "$token_count" '
    def percent_metric($title; $value; $reset):
        if ($value | type) != "number" then empty
        else (if $value < 0 then 0 elif $value > 100 then 100 else $value end) as $clamped
        | {
            title: $title,
            formattedValue: "\($clamped | round)%\(if $reset == null then "" else " \($reset)" end)",
            normalizedValue: (($clamped / 100) * 10000 | round / 10000)
          }
        end;
    def window_title($minutes):
        if ($minutes | type) != "number" then null
        elif ($minutes % 1440) == 0 then "\($minutes / 1440)d"
        elif ($minutes % 60) == 0 then "\($minutes / 60)h"
        else "\($minutes)m"
        end;
    def reset_title($resets_at):
        if ($resets_at | type) == "number"
        then "↻ \(($resets_at + (9 * 60 * 60)) | strftime("%m/%d %H:%M"))"
        else null
        end;

    ["primary", "secondary"]
    | map(($token.rate_limits[.] // {}) as $limit
          | window_title($limit.window_minutes) as $title
          | reset_title($limit.resets_at) as $reset
          | if $title == null then empty
            else percent_metric($title; $limit.used_percent; $reset)
            end)
    | unique_by(.title) as $limits
    | {
        title: "Codex",
        symbol: "camera.aperture",
        metrics: $limits,
        lastUpdatedDate: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
      }
    | if ($limits | length) > 0 then .metricsBarValue = $limits[0].formattedValue else . end
' >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$out" 2>/dev/null || rm -f "$tmp"
else
    rm -f "$tmp"
fi

# A Stop hook expects JSON on stdout; an empty object means continue normally.
printf '{}\n'
