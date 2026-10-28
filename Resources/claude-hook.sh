#!/bin/sh
# Claude Code hook for Harbor. Usage: claude-hook.sh working|finished|failed|waiting|session-end
# Records what Claude is doing in the Harbor session it runs in. Outside Harbor it does nothing,
# and it always exits 0 so it can never get in Claude's way.

case "$HARBOR_SESSION_ID" in
    "" | *[!0-9A-F-]*) exit 0 ;;
esac

event="$1"
input=$(cat)
case "$event" in
    working | finished | failed | waiting) ;;
    session-end)
        case "$input" in
            *'"reason":"clear"'* | *'"reason":"resume"'* | *'"reason": "clear"'* | *'"reason": "resume"'*) event=idle ;;
            *) event=ended ;;
        esac
        ;;
    *) exit 0 ;;
esac

dir="$HOME/Library/Application Support/Harbor/claude"
mkdir -p "$dir" 2>/dev/null || exit 0
tmp="$dir/.$HARBOR_SESSION_ID.$$"
printf '{"event":"%s"}\n' "$event" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dir/$HARBOR_SESSION_ID.json" 2>/dev/null
exit 0
