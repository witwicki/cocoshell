# ~/.claude/ccs/pane-init.sh
# Sourced in the visible `ccs` pane's interactive shell before each command.
# Defines __ccs_exec, which the dispatcher invokes per command.
#
# Each command runs in a FRESH `bash -c` that mirrors the host agent's command wrapper:
#   - re-sources the latest shell snapshot  -> fresh env per command, and
#   - restores/saves cwd via a file         -> cwd persists across commands; env does not.
#
# Output streams live to the pane (for the human) AND is tee'd to jobs/<tok>.out
# (clean capture for the agent). An EXIT trap writes the exit code + resulting cwd,
# so both are captured correctly even when the command itself calls `exit`.
__ccs_exec() {
  local tok="$1"
  local ccsd="$HOME/.claude/ccs"
  local cmdfile="$ccsd/jobs/$tok.cmd"
  local cwdfile="$ccsd/cwd"
  local outfile="$ccsd/jobs/$tok.out"
  local rcfile="$ccsd/jobs/$tok.rc"
  local snap
  snap="$(ls -t "$HOME/.claude/shell-snapshots/snapshot-bash-"*.sh 2>/dev/null | head -1)"
  printf '\033[1;32m$\033[0m %s\n' "$(cat "$cmdfile" 2>/dev/null)"   # show the real command in the pane
  bash -c '
    snap=$1; cwdfile=$2; cmdfile=$3; outfile=$4; rcfile=$5
    fifo="$outfile.fifo"
    [ -n "$snap" ] && source "$snap" >/dev/null 2>&1
    cd "$(cat "$cwdfile" 2>/dev/null)" 2>/dev/null || cd "$HOME"
    rm -f "$fifo"; mkfifo "$fifo"
    exec 4>&1                       # save the pane stdout on fd4
    tee "$outfile" < "$fifo" >&4 &  # clean copy -> file; live copy -> pane
    __tee=$!
    __finish() {
      local rc=$?
      exec 1>&4 2>&4                # detach shell from fifo (closes the only writer)
      wait "$__tee" 2>/dev/null     # let tee flush the file
      rm -f "$fifo"
      pwd > "$cwdfile"             # persist cwd, even if the command called exit
      printf "%s" "$rc" > "$rcfile"
    }
    trap __finish EXIT
    exec > "$fifo" 2>&1            # everything from here streams to pane + file
    source "$cmdfile"
  ' _ "$snap" "$cwdfile" "$cmdfile" "$outfile" "$rcfile"
  printf '\033[3;38;5;176m…executed by %s\033[0m\n' "${CCS_AGENT:-claude}"   # human-facing; completion via the .rc file
}
