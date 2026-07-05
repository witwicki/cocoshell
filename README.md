# cocoshell

**A collaborative command shell for agents** — watch and share the shell an agent runs commands in.

`cocoshell` (internally `ccs`: **co**llaborative **co**mmand **sh**ell) routes an agent's shell
commands into a *visible terminal pane* you can watch live — and even type into. Instead of an
agent running commands in an invisible subprocess, they execute in a real shell in your terminal
multiplexer, streamed as they happen, with output and exit codes captured back to the agent
unchanged. **Claude Code is the first integration; the core is agent-agnostic.**

## Why

Agents usually run shell commands in an invisible, non-interactive subprocess. cocoshell makes
that execution **visible and shared**: you see each command and its output land in a pane in real
time, the shell has a real tty (so interactive prompts work and you can answer them), and cwd
persists across commands — while the agent still gets clean output and exit codes exactly as
before. It's transparent: the agent doesn't need to know.

## How it works

```
agent ──(adapter)──▶ ccs-run ──(backend)──▶ visible pane
                        │                        │
                        └──◀── files: output, exit code, cwd ──┘
```

- **Adapter** (per agent) routes the agent's command into `ccs-run`. For Claude Code this is a
  `PreToolUse` hook that rewrites the Bash command — see `adapters/claude-code/`.
- **`ccs-run`** (core) injects the command into a visible pane, waits, and returns the captured
  output + exit code. Concurrent commands are serialized with `flock`.
- **`pane-init.sh`** (core) runs each command in the pane in a fresh `bash -c`, streaming output
  live (via `tee`) while capturing a clean copy to a file; an `EXIT` trap records the exit code
  and cwd. Completion is detected by polling that file — no terminal scraping.
- **Backend** (per multiplexer) provides "create a pane / is it alive / type into it". Ships with
  `zellij` (default) and `tmux`.

Everything the agent relies on — output, exit code, cwd, completion — is file-based and
backend/agent-neutral. Swapping the terminal or the agent touches only a thin driver.

## Install (Claude Code + zellij)

Requires `bash`, `jq`, `flock` (util-linux), and `zellij` (or `tmux`).

```sh
git clone https://github.com/witwicki/cocoshell ~/src/cocoshell
~/src/cocoshell/setup.sh        # interactive: checks deps + version, picks the session, installs
```

`setup.sh` walks you through dependency and Claude Code version checks, confirms the zellij session
that will host the pane, and then installs. For a non-interactive install, run `install.sh` directly.

Both symlink the core + backends into `~/.claude/ccs/` (so edits stay live) and register the
`PreToolUse` hook in `~/.claude/settings.json`. Claude Code's Bash commands then run in a pane
named `ccs` in your current session.

**Disable anytime:** `touch ~/.claude/ccs/DISABLED` (delete to re-enable). It's also fail-open:
any problem falls back to running the command normally.

## Configuration (env vars)

| var | default | meaning |
|-----|---------|---------|
| `CCS_BACKEND` | `zellij` | terminal backend (`zellij`, `tmux`) |
| `CCS_SESSION` | current session | which multiplexer session hosts the pane |
| `CCS_TIMEOUT` | `600` | seconds to wait for a command |
| `CCS_POLL` | `0.01` | completion poll interval (seconds) |
| `CCS_AGENT` | `claude` | label shown after each command in the pane |

## Gotchas

- **stdin is a real tty** in the pane, so interactive commands (`ssh`, `sudo`, bare `read`) prompt
  *in the pane* and block until answered — great for human-in-the-loop, but prefer non-interactive
  flags for automation.
- **Commands serialize** (one pane = one shell); don't rely on an agent's parallel calls running
  concurrently.
- Overhead is ~50–90 ms/command (fixed, not proportional to output size).

## Extending

- **Backend:** add `backends/<name>.sh` defining `be_create` / `be_alive` / `be_send`
  (+ `be_observe`), then set `CCS_BACKEND=<name>`.
- **Agent:** add `adapters/<agent>/` with whatever routes that agent's commands through `ccs-run`.
  The core doesn't change.

## License

MIT © Stefan Witwicki
