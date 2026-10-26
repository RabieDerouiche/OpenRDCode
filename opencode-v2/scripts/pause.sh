#!/bin/sh
# For /fix: a pause while the CI of the pushed commit still runs; the pilot looks at its pipeline again after it.
# 110 s at most, under the 2 minutes OpenCode gives a command; nothing else runs, nothing is read or written.
# Usage: pause.sh [<seconds>, 60 by default]
seconds=${1:-60}
case "$seconds" in
  ''|*[!0-9]*) seconds=60 ;;
esac
max=${PAUSE_MAX:-110}
[ "$seconds" -le "$max" ] || seconds=$max
sleep "$seconds"
echo "PAUSE: $seconds s"
