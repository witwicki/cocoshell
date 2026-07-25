# PLANS

Design notes and roadmap for cocoshell. Captures the guiding tension, the shippable default,
and the collaboration features we've scoped but deliberately gated behind opt-ins.

_Last updated: 2026-07._

## The guiding tension: transparency ↔ collaboration

cocoshell pursues two goals that pull against each other:

- **Transparency** — the agent behaves *exactly* as it would without cocoshell; the human
  simply watches. Favors per-command isolation, non-persistent env, and plain bash. This is
  the current default and the robust baseline. The simplest thing is to keep it as-is.
- **Collaboration** — the agent and human share a live workspace: shared shell state, typing
  into the same shell, the agent reading what the human does. Richer, but every step adds
  complexity, coupling, and new failure modes.

**Design principle:** the transparent path stays the robust default; collaboration features
are explicit, opt-in modes that must never degrade or destabilize that default.

## Status quo — the transparent default (ship as-is)

- Each command runs in a **fresh `bash -c`** → non-persistent env, mirroring the agent's own
  execution model (env resets per command; cwd carried via a file).
- **File-based capture** (`.out` / `.rc`), `flock` serialization, fail-open fallback.
- The human **watches** and can answer interactive prompts (the pane's stdin is a real tty).

Nothing in the collaboration track should change this behavior when its flags are unset.

---

## Collaboration track

### C1 — Persistent / shared-state shell  (opt-in: `CCS_PERSIST=1`)

**Goal:** env vars, `cd`, aliases, functions, venvs, shell options set by one command persist
to the next *and* are shared with the human in the pane — a genuinely shared REPL.

**Sketch:**
- Drop the nested `bash -c`; run `{ source "$cmdfile"; }` directly in the pane's long-lived
  shell so side effects persist.
- Capture per-command with `fifo + tee + wait` around just that brace group; take `rc=$?`
  immediately after; write `.rc`; poll as today.
- Retire the `cwd` file and snapshot re-sourcing — state lives in the shell.

**Trade-offs / risks:**
- **`exit` kills the shared pane** (no isolation). Mitigation: shadow `exit`/`logout` with a
  function that `return`s, and/or auto-respawn the pane on death (which loses state).
- **Bleed-through:** a stray `set -e`/`set -x`, changed `IFS`, leftover alias, or `cd` from one
  command silently affects the next. The agent writes commands assuming a clean env, so this
  can cause subtle, hard-to-debug surprises.
- **Two-way sharing:** the human's env changes also affect the agent's commands.

**Open questions:** is a "soft persist" (persist env + cwd, but reset shell options / `IFS`
between commands) a safer default than full persist? How much isolation can we keep while still
sharing the useful state?

**Status:** scoped, not started. Ships behind `CCS_PERSIST`, default off.

### C2 — Reading the human's commands & output  (Phase 2)

**Goal:** the agent can *read* the commands and output the human runs, not just have its own
commands watched — closing the collaboration loop in both directions.

**Mechanism:** a persistent **`be_observe`** stream (already stubbed per backend:
`zellij subscribe`, `tmux pipe-pane`). `subscribe` is validated and reserved for this. The
`$ <command>` / `…executed` lines already double as parseable boundaries.

**Two forks that determine the design:**
1. **Where does the human type?** In the shared `ccs` pane, or in their own separate pane(s)
   the agent subscribes to?
2. **May we instrument the human's shell?** A light `bash-preexec`/`PROMPT_COMMAND` (or fish/zsh
   equivalent) emitting clean start/end markers → reliable parsing. Or must the observer be
   **fully passive**, inferring command/output boundaries from raw render (harder: prompt-detection
   heuristics)?

**Sketch (instrumented path):** a background reader tails `be_observe`, splits on markers into
`(command, output, exit)` records, and exposes them to the agent (a log the agent reads, or a
tool returning "recent human activity").

**Open questions:** how does the agent *consume* this — poll a log, an MCP tool, or injected
context? Consent/privacy boundaries on reading the human's terminal.

**Status:** substrate proven (bidirectional pane + subscribe). Blocked on the two forks above.

### C3 — Alternate pane *host* shell (fish / zsh)

**Goal:** the visible pane runs the human's preferred shell so the prompt and anything the
human types there matches their environment.

**Key distinction:** the *host* shell (the pane's interactive shell / prompt) vs. the *executor*
(the `bash -c` that runs the agent's command). Only the **host** changes; the agent's commands
remain bash (see C4).

**What it entails:** a fish/zsh port of `pane-init.sh` (the `__ccs_exec` protocol, tee/trap,
markers — currently bash), and `be_create` launching `-- fish` / `-- zsh`.

**Status:** low priority; cosmetic for correctness. Composes with C1 (a persistent fish host
would share *fish* state).

### C4 — Agent emitting non-bash (a "fish tool")

**Assessment:** unnatural; not recommended as the primary path.
- The "Bash" tool is built into the harness — no first-class fish tool to enable.
- The model is strongly bash/POSIX-fluent; fish syntax is sparse in training and divergent
  (`set -x` vs `export`, `if…end`, `$status` vs `$?`). Simple commands are fine; bash-isms get
  error-prone and the bash ecosystem advantage is lost.

**Recommended instead:** keep bash as the agent's default; when fish is specifically needed,
have the agent shell out deliberately with `fish -c '…'`. Works today, no tool changes.

---

## Cross-cutting / smaller items

- **Decouple runtime dir from Claude:** introduce `CCS_HOME` (default `~/.claude/ccs`) threaded
  through `ccs-run`, `pane-init.sh`, and the hook, so non-Claude adapters can install elsewhere.
- **Latency (only if it matters):** ~58 ms/command is dominated by ~3 zellij CLI round-trips.
  Could skip the liveness `dump-screen` (inject optimistically, recreate on failure) and fold
  Enter into `write-chars` (trailing newline). Diminishing returns.
- **More backends:** `screen`, raw-PTY + `tail -f`, `ttyd` (web) — each a `backends/<name>.sh`.
- **More adapters:** `adapters/<agent>/` for other agents; the core is already agent-neutral.

## Decision log

- **Non-persistence is the default** to preserve transparency (the agent's own model is
  non-persistent env + per-command isolation). Persistence is C1, opt-in.
- **Completion via `.rc` file polling**, not `subscribe`, for the agent's own (instrumented)
  commands — an exact, race-free signal. `subscribe` is reserved for C2 (un-instrumented human
  activity).
- **`flock` serialization** adopted: the pane is one shell; parallel agent calls queue. (Done.)
- **zellij default backend**, tmux validated as the second — proving the driver abstraction.
