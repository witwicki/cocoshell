#!/usr/bin/env bash
# cocoshell installer (Claude Code adapter).
# Symlinks the core + backends into ~/.claude/ccs and registers the PreToolUse hook.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCS_DIR="${CCS_HOME:-$HOME/.claude/ccs}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

echo "cocoshell: installing into $CCS_DIR"

# --- dependencies ---
missing=""
for d in bash jq flock; do command -v "$d" >/dev/null 2>&1 || missing="$missing $d"; done
command -v zellij >/dev/null 2>&1 || command -v tmux >/dev/null 2>&1 || missing="$missing zellij-or-tmux"
[ -z "$missing" ] || { echo "cocoshell: missing dependencies:$missing" >&2; exit 1; }

mkdir -p "$CCS_DIR/jobs"

# --- symlink runtime files (flat names) -> repo sources (edits stay live) ---
ln -sf "$REPO/core/ccs-run"                 "$CCS_DIR/ccs-run"
ln -sf "$REPO/core/pane-init.sh"            "$CCS_DIR/pane-init.sh"
ln -sf "$REPO/backends/zellij.sh"           "$CCS_DIR/driver-zellij.sh"
ln -sf "$REPO/backends/tmux.sh"             "$CCS_DIR/driver-tmux.sh"
ln -sf "$REPO/adapters/claude-code/hook.sh" "$CCS_DIR/hook.sh"
chmod +x "$REPO/core/ccs-run" "$REPO/adapters/claude-code/hook.sh"

# --- register the PreToolUse hook in settings.json (idempotent) ---
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
hook="$CCS_DIR/hook.sh"
tmp="$(mktemp)"
jq --arg cmd "$hook" '
  .hooks //= {} |
  .hooks.PreToolUse //= [] |
  if any(.hooks.PreToolUse[]?; (.hooks[]?|.command) == $cmd)
  then .
  else .hooks.PreToolUse += [{matcher:"Bash", hooks:[{type:"command", command:$cmd}]}]
  end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "cocoshell: installed."
echo "  Claude Code Bash commands now run in a visible 'ccs' pane in your current session."
echo "  disable: touch $CCS_DIR/DISABLED   (delete to re-enable)"
