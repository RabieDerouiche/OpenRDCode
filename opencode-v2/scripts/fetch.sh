#!/bin/sh
# Bounded, non-interactive `git fetch` for the pack's scripts: it never waits for a password or a passphrase, and
# gives up after FETCH_TIMEOUT seconds (GitLab unreachable, VPN down), so that a command never waits minutes before
# the model even starts. Output of git goes to stderr only. Exit status: the one of git fetch, 124 after the timeout
# (like coreutils timeout), or 77 when GitLab refused the credentials or got none: this machine has no GitLab
# credentials that git can use on its own, and nobody can type them in an agent's command (COMMANDES.md, section
# "Identifiants GitLab").
# Two worktrees of one repository share their remote-tracking branches: a fetch that meets the lock of a ref another
# worktree is updating at that moment ("cannot lock ref … is at … but expected …", "Unable to create … .lock") is run
# again, up to 3 times (6 worktrees fetching at the same moment while 30 branches move: every raw git fetch failed,
# none of these).
# A fetch that fails on a moment of the network (a reset connection, a name not resolved, HTTP 5xx, no answer in time:
# transient.sh) is run again after 3 s, then 10 s, within FETCH_BUDGET seconds for all its attempts: a fetch that got
# no answer at all is run again only when a whole attempt still fits (never with the 45 s of workflow-state.sh, whose
# command goes on without it). Its "RETRY:" lines go to stderr with the errors of git.
# Usage: fetch.sh <git fetch arguments>

FETCH_TIMEOUT=${FETCH_TIMEOUT:-30}
FETCH_BUDGET=${FETCH_BUDGET:-75}
here=$(cd "$(dirname "$0")" && pwd)
start=$(date +%s)

# English git messages, so that an authentication failure is recognized whatever the language of the machine
LC_ALL=C
export LC_ALL
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT
# ssh never asks either (an ssh agent still works), unless an ssh command is already configured
if [ -z "${GIT_SSH_COMMAND:-}" ] && [ -z "${GIT_SSH:-}" ] && [ -z "$(git config --get core.sshCommand 2>/dev/null)" ]; then
  GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15"
  export GIT_SSH_COMMAND
fi

# A process and its descendants (git starts git-remote-https or ssh, which would otherwise keep running, and keep the
# output of the caller open, after git is stopped)
kill_tree() {
  for child in $(pgrep -P "$1" 2>/dev/null); do
    kill_tree "$child"
  done
  kill "$1" 2>/dev/null
}

# The errors of git, kept to recognize an authentication failure, then passed on to stderr
errors=$(mktemp "${TMPDIR:-/tmp}/fetch.XXXXXX" 2>/dev/null) || errors=/dev/null
attempt=1 net=1
while :; do
  # each attempt within what is left of the budget
  limit=$((start + FETCH_BUDGET - $(date +%s)))
  [ "$limit" -gt "$FETCH_TIMEOUT" ] && limit=$FETCH_TIMEOUT
  [ "$limit" -ge 5 ] || limit=5
  git fetch "$@" </dev/null >/dev/null 2>"$errors" &
  pid=$!
  # The watchdog writes nowhere: a sleeping process must not keep the output of the caller open
  ( sleep "$limit"; kill_tree "$pid" ) </dev/null >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" 2>/dev/null
  status=$?
  if kill -0 "$watchdog" 2>/dev/null; then
    kill_tree "$watchdog"
  else
    status=124
    [ "$errors" != /dev/null ] && echo "no answer from the remote within $limit s" >> "$errors"
  fi
  # a ref locked by the fetch of another worktree at the same moment: once more, after a short pause
  if [ "$status" != 0 ] && [ "$status" != 124 ] && [ "$errors" != /dev/null ] && [ "$attempt" -lt 4 ] &&
    grep -qiE 'cannot lock ref|unable to create .*\.lock|unable to update local ref|is at [0-9a-f]+ but expected' "$errors"; then
    attempt=$((attempt + 1))
    # 1 s, then 2, then 3: the fetches of several worktrees drift apart instead of meeting again
    sleep $((attempt - 1))
    continue
  fi
  # a moment of the network: again after a pause, while the budget allows a useful attempt
  if [ "$status" != 0 ] && [ "$errors" != /dev/null ] &&
    sh "$here/transient.sh" retry network "$errors" "$net" "$((start + FETCH_BUDGET - $(date +%s)))" GitLab >&2; then
    net=$((net + 1))
    continue
  fi
  break
done
if [ "$errors" != /dev/null ]; then
  cat "$errors" >&2
  if [ "$status" != 0 ] && [ "$status" != 124 ] &&
    grep -qiE 'could not read (username|password)|terminal prompts disabled|authentication failed|access denied|returned error: 40[13]|permission denied \(publickey|host key verification failed' "$errors"; then
    status=77
  fi
  rm -f "$errors"
fi
case "$status" in
  124) echo "fetch: no answer from the remote ($net attempt(s), ${FETCH_TIMEOUT} s each at most)" >&2 ;;
  77) echo "fetch: authentication failed (no GitLab credentials that git can use on its own on this machine)" >&2 ;;
esac
exit "$status"
