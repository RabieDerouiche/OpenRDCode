#!/bin/sh
# Bounded, non-interactive `git fetch` for the pack's scripts: it never waits for a password or a passphrase, and
# gives up after FETCH_TIMEOUT seconds (GitLab unreachable, VPN down), so that a command never waits minutes before
# the model even starts. Output of git goes to stderr only. Exit status: the one of git fetch, or 124 after the
# timeout (like coreutils timeout).
# Usage: fetch.sh <git fetch arguments>

FETCH_TIMEOUT=${FETCH_TIMEOUT:-30}

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

git fetch "$@" </dev/null >/dev/null &
pid=$!
# The watchdog writes nowhere: a sleeping process must not keep the output of the caller open
( sleep "$FETCH_TIMEOUT"; kill_tree "$pid" ) </dev/null >/dev/null 2>&1 &
watchdog=$!
wait "$pid" 2>/dev/null
status=$?
if kill -0 "$watchdog" 2>/dev/null; then
  kill_tree "$watchdog"
else
  echo "fetch: no answer from the remote after ${FETCH_TIMEOUT} s" >&2
  status=124
fi
exit "$status"
