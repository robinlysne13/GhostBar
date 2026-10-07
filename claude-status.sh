#!/bin/zsh
# Claude Code hook → Perch. Usage: claude-status.sh working|done|attention|end
# Writes one file per session to ~/.perch/sessions/<session_id>:
#   line 1: state, line 2: project folder, line 3: pid of the Claude process

# Only report sessions running inside Cursor (its extension panel or its
# terminal). Claude desktop and other hosts are ignored. Remove this line to
# report every session.
[[ "$__CFBundleIdentifier" == "com.todesktop.230313mzl4w4u92" ]] || exit 0

dir="$HOME/.perch/sessions"
mkdir -p "$dir"
input=$(cat)
session=$(print -r -- "$input" | /usr/bin/jq -r '.session_id // empty')
[[ -z "$session" ]] && exit 0
file="$dir/$session"

# The pid of the Claude process that owns this session, so Perch can drop a
# session that quit without running its SessionEnd hook instead of leaving a
# stale icon in the bar. The hook runs under a short-lived shell, so walk up the
# parents until the claude binary itself turns up.
owner_pid() {
  local pid=$PPID cmd
  repeat 5; do
    [[ -z "$pid" || "$pid" -le 1 ]] && return
    cmd=$(/bin/ps -o comm= -p "$pid" 2>/dev/null)
    [[ "$cmd" == *claude* ]] && { print -r -- "$pid"; return }
    pid=$(/bin/ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
}
pid=$(owner_pid)

case "$1" in
  end)
    rm -f "$file" ;;
  attention)
    # Skip the "you've been idle" reminder; only real prompts need attention.
    type=$(print -r -- "$input" | /usr/bin/jq -r '.notification_type // empty')
    [[ "$type" == "idle_prompt" ]] && exit 0
    cwd=$(print -r -- "$input" | /usr/bin/jq -r '.cwd // empty')
    printf '%s\n%s\n%s\n' attention "$cwd" "$pid" > "$file" ;;
  *)
    cwd=$(print -r -- "$input" | /usr/bin/jq -r '.cwd // empty')
    printf '%s\n%s\n%s\n' "$1" "$cwd" "$pid" > "$file" ;;
esac
exit 0
