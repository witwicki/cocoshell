# ~/.claude/ccs/driver-zellij.sh — zellij backend for ccs-run.
# Handle = a zellij pane id (terminal_<n>). Session defaults to the current one.
#
# Contract: be_create (print handle), be_alive <h>, be_send <h> <line>, be_observe <h>.

_SESS="${CCS_SESSION:-${ZELLIJ_SESSION_NAME:-ccs}}"

be_create() {   # create a visible `ccs` pane running bash; print its handle
  zellij --session "$_SESS" run -n ccs -- bash 2>/dev/null | grep -oE 'terminal_[0-9]+' | head -1
}

be_alive() {    # exit 0 if $1 names a live pane
  [ -n "$1" ] && zellij --session "$_SESS" action dump-screen -p "$1" --path /dev/null >/dev/null 2>&1
}

be_send() {     # type a line ($2) + Enter into pane $1
  zellij --session "$_SESS" action write-chars -p "$1" "$2" >/dev/null 2>&1 &&
  zellij --session "$_SESS" action write -p "$1" 13 >/dev/null 2>&1
}

be_observe() {  # (phase 2) stream the pane's render updates to stdout
  zellij --session "$_SESS" subscribe -p "$1"
}
