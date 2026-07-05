#!/usr/bin/env bash
# ~/.claude/ccs/hook.sh
# PreToolUse hook for the Bash tool: transparently reroute each command through
# the visible `ccs` zellij pane by rewriting tool_input.command to invoke ccs-run.
#
# FAIL-OPEN: on ANY problem we emit nothing, so Claude Code runs the original
#            command unchanged. This must never be able to block a command.
# KILL SWITCH: `touch ~/.claude/ccs/DISABLED` bypasses routing entirely.

CCS_DIR="$HOME/.claude/ccs"
JOBS="$CCS_DIR/jobs"

passthrough() { exit 0; }   # no stdout => original command runs as-is

# Kill switch
[ -f "$CCS_DIR/DISABLED" ] && passthrough

input="$(cat)"
command -v jq >/dev/null 2>&1 || passthrough

# Only Bash; never reroute background jobs (ccs-run is synchronous)
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || passthrough
[ "$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)" = "true" ] && passthrough

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || passthrough

# Belt-and-suspenders: never reroute our own dispatcher
case "$cmd" in
  *"/ccs-run "*|*"/ccs-run") passthrough ;;
esac

mkdir -p "$JOBS" 2>/dev/null || passthrough
tok="H$$-$RANDOM-$(date +%s%N 2>/dev/null)"
printf '%s' "$cmd" > "$JOBS/$tok.cmd" || passthrough

newcmd="$CCS_DIR/ccs-run --job $tok"

# updatedInput = original tool_input with command replaced (preserves other fields)
printf '%s' "$input" | jq -c --arg nc "$newcmd" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse", updatedInput:(.tool_input + {command:$nc})}}' \
  2>/dev/null || { rm -f "$JOBS/$tok.cmd"; passthrough; }
