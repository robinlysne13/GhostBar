#!/bin/zsh
# Claude Code hook → GhostBar. Usage: claude-status.sh working|done|attention|end
# Writes one file per session to ~/.ghostbar/sessions/<session_id>:
#   line 1: state, line 2: project folder

# Only report sessions running inside Cursor (its extension panel or its
# terminal). Claude desktop and other hosts are ignored. Remove this line to
# report every session.
[[ "$__CFBundleIdentifier" == "com.todesktop.230313mzl4w4u92" ]] || exit 0

dir="$HOME/.ghostbar/sessions"
mkdir -p "$dir"
input=$(cat)
session=$(print -r -- "$input" | /usr/bin/jq -r '.session_id // empty')
[[ -z "$session" ]] && exit 0
file="$dir/$session"

case "$1" in
  end)
    rm -f "$file" ;;
  attention)
    # Skip the "you've been idle" reminder; only real prompts need attention.
    type=$(print -r -- "$input" | /usr/bin/jq -r '.notification_type // empty')
    [[ "$type" == "idle_prompt" ]] && exit 0
    cwd=$(print -r -- "$input" | /usr/bin/jq -r '.cwd // empty')
    printf '%s\n%s\n' attention "$cwd" > "$file" ;;
  *)
    cwd=$(print -r -- "$input" | /usr/bin/jq -r '.cwd // empty')
    printf '%s\n%s\n' "$1" "$cwd" > "$file" ;;
esac
exit 0
