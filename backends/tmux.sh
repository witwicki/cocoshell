# ~/.claude/ccs/driver-tmux.sh — tmux backend for ccs-run (reference implementation).
# Handle = a tmux pane id (%<n>). Uses/creates a dedicated session ($CCS_SESSION or "ccs").
#
# Contract: be_create (print handle), be_alive <h>, be_send <h> <line>, be_observe <h>.
# NOTE: smoke-tested end-to-end against tmux 3.4 (create / send / capture / exit-code
# all OK). zellij remains the default/primary backend.

_SESS="${CCS_SESSION:-ccs}"

be_create() {   # ensure the session, open a `ccs` window running bash, print its pane id
  tmux has-session -t "$_SESS" 2>/dev/null || tmux new-session -d -s "$_SESS" 2>/dev/null
  tmux new-window -d -P -F '#{pane_id}' -n ccs -t "$_SESS:" bash 2>/dev/null
}

be_alive() {    # exit 0 if $1 names a live pane
  [ -n "$1" ] && tmux display-message -p -t "$1" '#{pane_id}' >/dev/null 2>&1
}

be_send() {     # type a line ($2, literal) + Enter into pane $1
  tmux send-keys -t "$1" -l -- "$2" 2>/dev/null &&
  tmux send-keys -t "$1" Enter 2>/dev/null
}

be_observe() {  # (phase 2) stream the pane's output to stdout via a reader
  tmux pipe-pane -t "$1" -O 'cat'
}
