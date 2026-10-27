#!/bin/sh
# The failures that pass by themselves, for the pack's scripts: a script whose command failed asks this one whether to
# run it again after a pause, instead of stopping a run of /go on a moment of the network or of the machine. A failure
# that would fail again the same way (credentials refused, a package that does not exist, a compilation error, a
# rejected push, a test that fails) is never run again: the line of the script that ran it says what it is, as before.
#   transient.sh retry <kind> <log> <attempt> [<seconds left> [<who>]]
#     dotnet   a dotnet build, or a dotnet test that builds: EVERY error of its output is the package feed that did not
#              answer (NU1301, NU1900 made an error by the project, with the NU1100-NU1103 that follow them), never a
#              401 or 403 nor a local source that does not exist; or a file of the build that another process held a
#              moment (CS2012, MSB3021, MSB3027 « used by another process », « locked by »: Rider building the same
#              project, the application started from a terminal), or a worker of MSBuild that died (MSB4166)
#     npm      an install (npm ci, yarn, pnpm): the registry did not answer (ECONNRESET, ETIMEDOUT, EAI_AGAIN,
#              ENOTFOUND, socket hang up, 429, 500, 502, 503, 504), or a folder of node_modules held a moment (EBUSY,
#              ENOTEMPTY); never with a 401, 403 or 404, an integrity or lockfile error, a full disk
#     network  git fetch or push, curl: no answer in time (the line « no answer from the remote within <n> s » that the
#              caller adds), a connection reset, refused or closed, a name not resolved, HTTP 429 or 5xx, an early EOF;
#              never credentials refused, a repository or a ref that does not exist, a rejected push
#     <log> the output of the command that failed; <attempt> the attempt that just failed (1 for the first); <seconds
#     left> the time the caller still has: a new attempt starts only when its pause and a useful run fit in it; <who>
#     the server that did not answer, for the line (network: GitLab, the environment Recette…).
#     Exit 0 after the pause, with a line « RETRY: <what failed>: again in <n> s (attempt <k> of <max>) »: run the
#     command again. Exit 1: the failure stays as it is; when it was of this kind, a line « RETRY: none left … » says
#     how many attempts it had, and the caller's own line follows (an ENVIRONMENT PROBLEM, a STOP).
#   transient.sh git <git arguments>
#     git, run again when another git process held the index of the repository at that moment (« index.lock: File
#     exists »: Rider or VS Code refresh their status in the background): up to 3 more times, after 1, 2 then 3 s; its
#     output (both streams) and its status. A lock still there after that is named: a git that crashed left it, and the
#     developer deletes it (never this script).
# RETRY_PAUSES: the pauses in seconds, one per new attempt, in place of those of the kind (the tests of the pack: 0).

LC_ALL=C
export LC_ALL

case "$1" in
  git)
    shift
    n=0
    while :; do
      out=$(git "$@" 2>&1)
      rc=$?
      if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "index\.lock'*: File exists"; then
        if [ "$n" -lt 3 ]; then
          n=$((n + 1))
          sleep "$n"
          continue
        fi
        lock=$(printf '%s\n' "$out" | sed -n "s/.*Unable to create '\([^']*index\.lock\)'.*/\1/p" | head -n 1)
        out="$out
NOTE: another git process has held ${lock:-the index.lock of this repository} for more than 6 s: if no git runs (Rider, a terminal), a git that crashed left it, and the developer deletes that file"
      fi
      break
    done
    [ -n "$out" ] && printf '%s\n' "$out"
    exit "$rc" ;;
  retry) shift ;;
  *)
    echo "usage: transient.sh retry dotnet|npm|network <log> <attempt> [<seconds left> [<who>]] | transient.sh git <git arguments>" >&2
    exit 2 ;;
esac

kind=$1 log=$2 attempt=${3:-1} left=${4:-} who=${5:-the server}
[ -f "$log" ] || exit 1
case "$attempt" in ''|*[!0-9]*) attempt=1 ;; esac
case "$left" in *[!0-9-]*) left="" ;; esac

# what failed, in a few words, and the pauses of the kind (one per new attempt) and the least time a run needs
what=""
case "$kind" in
  dotnet)
    # every error line, once (MSBuild repeats an error for each project that builds the file)
    errors=$(grep -E '(^|[^A-Za-z])error [A-Z]+[0-9]+:|: error :' "$log" | sed -E 's/ \[[^]]*\]$//' | sort -u)
    [ -n "$errors" ] || exit 1
    feed=$(printf '%s\n' "$errors" | grep -E 'error NU(1301|1900):')
    if [ -n "$feed" ] && ! grep -q -E '40[13]|Unauthorized|Forbidden|local source .*(does not|doesn.t) exist' "$log"; then
      # a restore that failed on the feed also fails to resolve what it could not download
      others=$(printf '%s\n' "$errors" | grep -v -E 'error NU(1301|1900|1100|1101|1102|1103):')
      code=$(printf '%s\n' "$feed" | grep -o -E 'NU(1301|1900)' | head -n 1)
      what="the package feed did not answer ($code)"
      pauses="20 60" need=60
    else
      others=$(printf '%s\n' "$errors" | grep -v -E 'used by another process|is locked by|MSB4166|exited prematurely')
      # a task that failed on a file held by another process: its exception is on the next line
      [ -n "$others" ] && grep -q 'used by another process' "$log" && others=$(printf '%s\n' "$others" | grep -v 'error MSB4018:')
      if printf '%s\n' "$errors" | grep -q -E 'MSB4166|exited prematurely'; then
        what="a worker process of MSBuild stopped (MSB4166)"
      else
        code=$(printf '%s\n' "$errors" | grep -o -E 'error [A-Z]+[0-9]+' | head -n 1 | sed 's/^error //')
        what="a file of the build was held by another process ($code)"
      fi
      pauses="10 30" need=60
    fi
    [ -z "$others" ] || exit 1 ;;
  npm)
    if grep -q -E 'E40[134]|ERR_PNPM_FETCH_40[134]|40[13] (Unauthorized|Forbidden)|404 Not Found|Unable to authenticate|EINTEGRITY|ERESOLVE|ETARGET|No matching version|can only install packages when|lockfile needs to be updated|OUTDATED_LOCKFILE|YN0028|ENOSPC|EACCES|EPERM|Cannot read propert' "$log"; then
      exit 1
    fi
    found=$(grep -o -E 'ECONNRESET|ETIMEDOUT|ESOCKETTIMEDOUT|ERR_SOCKET_TIMEOUT|EAI_AGAIN|ENOTFOUND|ECONNREFUSED|ENETUNREACH|EHOSTUNREACH|EPIPE|socket hang up|code E(429|50[0234])|ERR_PNPM_FETCH_(429|50[0234])|ERR_PNPM_META_FETCH_FAIL|(429|50[0234]) (Too Many Requests|Internal Server Error|Bad Gateway|Service Unavailable|Gateway Time-?out)|EBUSY|ENOTEMPTY' "$log" | head -n 1)
    [ -n "$found" ] || exit 1
    case "$found" in
      EBUSY|ENOTEMPTY) what="a folder of node_modules was held by another process ($found)" ;;
      *) what="the package registry did not answer (${found#code })" ;;
    esac
    pauses="15 45" need=60 ;;
  network)
    if grep -q -i -E 'could not read (username|password)|terminal prompts disabled|authentication failed|access denied|returned error: 40[134]|permission denied \(publickey|host key verification failed|repository .*not found|does not appear to be a git repository|couldn.t find remote ref|\[rejected\]|\[remote rejected\]|non-fast-forward|fetch first|SSL certificate problem|certificate verify failed' "$log"; then
      exit 1
    fi
    found=$(grep -o -i -E 'no answer from the remote within [0-9]+ s|could not resolve host|could not resolve hostname|temporary failure in name resolution|failed to connect|couldn.t connect|connection timed out|operation timed out|timed out after|connection reset|connection refused|connection closed|closed by remote host|early EOF|unexpected disconnect|RPC failed|remote end hung up|empty reply from server|recv failure|transfer closed|network is unreachable|broken pipe|SSL_ERROR_SYSCALL|gnutls_handshake|kex_exchange_identification|(returned error|HTTP|http status): ?(429|5[0-9][0-9])' "$log" | head -n 1)
    [ -n "$found" ] || exit 1
    what="$who did not answer ($found)"
    case "$found" in
      # no answer at all: once more, when a whole attempt still fits
      no\ answer*) pauses="3" need=30 ;;
      *) pauses="3 10" need=15 ;;
    esac ;;
  *) exit 1 ;;
esac

[ -n "${RETRY_PAUSES:-}" ] && pauses=$RETRY_PAUSES
# shellcheck disable=SC2086 # the words of the list
set -- $pauses
max=$(($# + 1))
if [ "$attempt" -ge "$max" ]; then
  echo "RETRY: none left: $what, at each of the $max attempts"
  exit 1
fi
shift $((attempt - 1))
pause=$1
if [ -n "$left" ] && [ "$left" -lt $((pause + need)) ]; then
  echo "RETRY: no time left for another attempt ($left s): $what"
  exit 1
fi
echo "RETRY: $what: again in $pause s (attempt $((attempt + 1)) of $max)"
sleep "$pause"
exit 0
