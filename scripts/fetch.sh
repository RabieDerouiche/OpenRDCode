#!/bin/sh
# Bounded, non-interactive `git fetch` for the pack's scripts: it never waits for a password or a passphrase, and
# gives up after FETCH_TIMEOUT seconds (GitLab unreachable, VPN down), so that a command never waits minutes before
# the model even starts. Output of git goes to stderr only. Exit status: the one of git fetch, 124 after the timeout
# (like coreutils timeout), or 77 when GitLab refused the credentials or got none: this machine has no GitLab
# credentials that git can use on its own, and nobody can type them in an agent's command (COMMANDES.md, section
# "Identifiants GitLab").
# Usage: fetch.sh <git fetch arguments>

FETCH_TIMEOUT=${FETCH_TIMEOUT:-30}

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
git fetch "$@" </dev/null >/dev/null 2>"$errors" &
pid=$!
# The watchdog writes nowhere: a sleeping process must not keep the output of the caller open
( sleep "$FETCH_TIMEOUT"; kill_tree "$pid" ) </dev/null >/dev/null 2>&1 &
watchdog=$!
wait "$pid" 2>/dev/null
status=$?
if kill -0 "$watchdog" 2>/dev/null; then
  kill_tree "$watchdog"
else
  status=124
fi
if [ "$errors" != /dev/null ]; then
  cat "$errors" >&2
  if [ "$status" != 0 ] && [ "$status" != 124 ] &&
    grep -qiE 'could not read (username|password)|terminal prompts disabled|authentication failed|access denied|returned error: 40[13]|permission denied \(publickey|host key verification failed' "$errors"; then
    status=77
  fi
  rm -f "$errors"
fi
case "$status" in
  124) echo "fetch: no answer from the remote after ${FETCH_TIMEOUT} s" >&2 ;;
  77) echo "fetch: authentication failed (no GitLab credentials that git can use on its own on this machine)" >&2 ;;
esac
exit "$status"
