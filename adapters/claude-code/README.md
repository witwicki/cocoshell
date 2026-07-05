# Claude Code adapter

Routes Claude Code's Bash tool commands through cocoshell via a **`PreToolUse` hook**.

## What it does

`hook.sh` receives each Bash tool call as JSON on stdin. For a foreground Bash command it:

1. writes the command text to `~/.claude/ccs/jobs/<token>.cmd`, and
2. returns `hookSpecificOutput.updatedInput.command = "~/.claude/ccs/ccs-run --job <token>"`,

so Claude Code runs `ccs-run` instead — which injects the real command into the visible pane and
returns its output + exit code. Claude sees an identical interface (command in → output + exit
code out), so it doesn't need to know the hook exists.

It is **fail-open** (any problem → the original command runs untouched), skips `run_in_background`
jobs, and never re-routes `ccs-run` itself.

## Registration

`install.sh` adds this to `~/.claude/settings.json`:

```json
{ "hooks": { "PreToolUse": [
  { "matcher": "Bash", "hooks": [ { "type": "command", "command": "<HOME>/.claude/ccs/hook.sh" } ] }
] } }
```

Hook input-rewriting (`updatedInput`) requires **Claude Code ≥ 2.1.195**.

## Known couplings to generalize

- The runtime dir is currently `~/.claude/ccs` (shared by core + this adapter). Making it
  configurable (e.g. `CCS_HOME`) would fully decouple the core from Claude.
- `pane-init.sh` re-sources Claude Code's shell snapshot to mirror its per-command environment;
  that step no-ops on systems without one.
