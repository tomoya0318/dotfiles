#!/bin/bash
# Write Claude rate limit usage to a RunCat Neo Custom Metrics JSON file.
# statusline.sh only runs in the interactive CLI; the Claude desktop app runs
# claude in stream-json mode without a status line, so this hook fetches the
# same numbers from the OAuth usage endpoint instead.
# Best-effort: always exits 0 so Claude Code is never blocked.

cat >/dev/null

out="${RUNCAT_OUT_FILE:-$HOME/.claude/runcat-usage.json}"
out_dir=$(dirname "$out")
min_interval=30

# statusline.sh writes the same file; skip when it was refreshed very recently.
if [ -f "$out" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$out" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$min_interval" ] && exit 0
fi

token="${CLAUDE_CODE_OAUTH_TOKEN:-}"
if [ -z "$token" ]; then
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
        | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
fi
[ -n "$token" ] || exit 0

# Pass the token through curl's config on stdin so it never appears in argv.
usage=$(printf 'header = "Authorization: Bearer %s"\n' "$token" \
    | curl -sf --max-time 5 -K - \
        -H "anthropic-beta: oauth-2025-04-20" \
        https://api.anthropic.com/api/oauth/usage 2>/dev/null) || exit 0

mkdir -p "$out_dir" 2>/dev/null || exit 0
tmp=$(mktemp "$out_dir/.runcat-usage.XXXXXX" 2>/dev/null) || exit 0

if printf '%s' "$usage" | jq '
    def reset_title:
        if (.resets_at | type) == "string"
        then " ↻ \((.resets_at | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) + (9 * 60 * 60) | strftime("%m/%d %H:%M"))"
        else ""
        end;
    def metric($title):
        if (.utilization | type) == "number"
        then {title: $title, formattedValue: "\(.utilization | round)%\(reset_title)", normalizedValue: ([.utilization / 100, 0] | max | [., 1] | min)}
        else empty
        end;
    [(.five_hour // {} | metric("5h")), (.seven_day // {} | metric("7d"))] as $metrics
    | if ($metrics | length) == 0 then error("no usage") else . end
    | {
        title: "Claude Code",
        symbol: "staroflife",
        metricsBarValue: ($metrics[0].formattedValue | split(" ")[0]),
        metrics: $metrics,
        lastUpdatedDate: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
      }
' >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$out" 2>/dev/null || rm -f "$tmp"
else
    rm -f "$tmp"
fi

exit 0
