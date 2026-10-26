#!/bin/sh
# For /fix: a pause while the CI of the pushed commit still runs; the pilot looks at its pipeline again after it.
# 290 s at most, under the 6 minutes the pack plugin gives this command (OpenCode alone stops a command after 2
# minutes: then keep PAUSE_MAX at 110); nothing else runs, nothing is read or written. A long pause is fewer turns of
# the model while the CI runs: each look at the pipeline is a request with the whole context of the run.
# Usage: pause.sh [<seconds>, 60 by default]
seconds=${1:-60}
case "$seconds" in
  ''|*[!0-9]*) seconds=60 ;;
esac
max=${PAUSE_MAX:-290}
[ "$seconds" -le "$max" ] || seconds=$max
sleep "$seconds"
echo "PAUSE: $seconds s"
