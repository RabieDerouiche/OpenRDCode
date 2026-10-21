#!/bin/sh
# Starts OpenCode v2 for the pack, next to OpenCode 1.19 and without touching it: its own configuration
# (~/oc2/config) and data (~/oc2/data), a password asked without showing it on screen (never in the command line,
# so never in the shell history), and the log in ~/oc2/serve.log. Stop it with Ctrl+C in the same terminal.
# Usage: sh start-v2.sh [port, default 4097] [address to listen on: 0.0.0.0 (default) or 127.0.0.1 behind an SSH tunnel]

port=${1:-4097}
host=${2:-0.0.0.0}
bin="$HOME/oc2/cli/node_modules/.bin/opencode2"

case "$port" in
  ''|*[!0-9]*) echo "STOP: the port must be a number, for example 4097"; exit 1 ;;
esac
case "$host" in
  0.0.0.0|127.0.0.1) ;;
  *) echo "STOP: the address to listen on is 0.0.0.0 or 127.0.0.1"; exit 1 ;;
esac
[ -x "$bin" ] || { echo "STOP: OpenCode v2 is not installed in ~/oc2/cli (MIGRATION.md, step 4)"; exit 1; }
[ -f "$HOME/oc2/config/opencode/opencode.json" ] || { echo "STOP: no configuration for OpenCode v2 yet (MIGRATION.md, step 5)"; exit 1; }

if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  printf 'Password of OpenCode v2 (typed, not shown): '
  stty -echo 2>/dev/null
  read -r OPENCODE_SERVER_PASSWORD
  stty echo 2>/dev/null
  echo
fi
[ -n "$OPENCODE_SERVER_PASSWORD" ] || { echo "STOP: an empty password would let anyone who reaches the port use OpenCode"; exit 1; }
export OPENCODE_SERVER_PASSWORD

XDG_CONFIG_HOME="$HOME/oc2/config"
XDG_DATA_HOME="$HOME/oc2/data"
export XDG_CONFIG_HOME XDG_DATA_HOME
mkdir -p "$XDG_DATA_HOME"
echo "$("$bin" --version 2>/dev/null | head -n 1) starts on port $port; the log goes to ~/oc2/serve.log. Ctrl+C stops it."
exec "$bin" serve --hostname "$host" --port "$port" --print-logs 2>> "$HOME/oc2/serve.log"
