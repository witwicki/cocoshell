#!/usr/bin/env bash
# cocoshell — interactive setup for Claude Code + zellij.
# Checks dependencies and Claude Code version, confirms the zellij session that will
# host the pane, then runs install.sh (symlinks + PreToolUse hook registration).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCS_DIR="${CCS_HOME:-$HOME/.claude/ccs}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

c_g=$'\033[1;32m'; c_y=$'\033[1;33m'; c_r=$'\033[1;31m'; c_b=$'\033[1;34m'; c_0=$'\033[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_0" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_y" "$c_0" "$*"; }
err()  { printf '  %s✗%s %s\n' "$c_r" "$c_0" "$*"; }
ask()  { local q="$1" def="${2:-Y}" ans; read -r -p "$(printf '%s? [%s] ' "$q" "$def")" ans || true
         ans="${ans:-$def}"; [[ "$ans" =~ ^[Yy] ]]; }

printf '%s\n\n' "${c_b}cocoshell setup — Claude Code + zellij${c_0}"

# --- 1. dependencies ---
say "Checking dependencies…"
fail=0
for d in bash jq flock zellij; do
  if command -v "$d" >/dev/null 2>&1; then ok "$d ($(command -v "$d"))"; else err "$d not found"; fail=1; fi
done
if [ "$fail" = 1 ]; then
  say; err "Install the missing tools and re-run. On Debian/Ubuntu:"
  say  "    sudo apt-get install -y jq util-linux      # jq + flock"
  say  "    zellij: https://zellij.dev/documentation/installation"
  exit 1
fi

# --- 2. Claude Code version (hook input rewriting needs >= 2.1.195) ---
say
if command -v claude >/dev/null 2>&1; then
  ver="$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -n "$ver" ] && [ "$(printf '%s\n2.1.195\n' "$ver" | sort -V | head -1)" = "2.1.195" ]; then
    ok "Claude Code $ver (supports hook input rewriting)"
  elif [ -n "$ver" ]; then
    warn "Claude Code $ver — routing needs >= 2.1.195; upgrade for it to activate."
  else
    warn "Could not parse Claude Code version; continuing."
  fi
else
  warn "'claude' not on PATH — installing anyway; the hook activates when you run Claude Code."
fi

# --- 3. zellij session ---
say
say "zellij session that will host the 'ccs' pane:"
if [ -n "${ZELLIJ_SESSION_NAME:-}" ]; then
  ok "inside session '${ZELLIJ_SESSION_NAME}' — commands will appear right here."
  sess="$ZELLIJ_SESSION_NAME"
else
  warn "not currently inside a zellij session."
  say  "  cocoshell shows commands in whatever session you're attached to. Existing sessions:"
  zellij list-sessions 2>/dev/null | sed 's/^/      /' || say "      (none)"
  say  "  Tip: start one and run Claude Code from inside it:  zellij attach --create ccs"
  sess="(your current session at runtime)"
fi

# --- 4. confirm + install ---
say
say "About to:"
say "  • symlink core + backends into $CCS_DIR"
say "  • register a PreToolUse (Bash) hook in $SETTINGS"
ask "Proceed" "Y" || { say "Aborted — nothing changed."; exit 0; }
say
"$REPO/install.sh"

# --- 5. verify ---
say
if jq -e --arg c "$CCS_DIR/hook.sh" '.hooks.PreToolUse[]?.hooks[]?|select(.command==$c)' "$SETTINGS" >/dev/null 2>&1; then
  ok "hook registered in settings.json"
else
  err "hook not found in settings.json — check $SETTINGS"
fi
[ -L "$CCS_DIR/ccs-run" ] && ok "core symlinked into $CCS_DIR" || warn "ccs-run not symlinked"

say
printf '%s Claude Code Bash commands will run in a %sccs%s pane in %s.\n' "${c_g}Done.${c_0}" "$c_b" "$c_0" "$sess"
say "  disable:   touch $CCS_DIR/DISABLED"
say "  re-enable: rm $CCS_DIR/DISABLED"
