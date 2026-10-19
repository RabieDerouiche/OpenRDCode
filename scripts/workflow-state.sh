#!/bin/sh
# Prints, in one sequential run, the git state used by the workflow commands (/next, /dev, /test, /check, /ship, /sync,
# /ticket, /scans). OpenCode runs the shell injections of a command in parallel: running everything here, after a
# single fetch, avoids stale remote refs and git lock conflicts.
# Read-only, except `git fetch` and a one-time move of the ticket sheets of older versions. The "Code fingerprint" line comes from state-fingerprint.sh (same folder): /check and
# /test write it in the ticket sheet, /ship and /next compare it to know whether that review or test run is still valid.
# Usage: workflow-state.sh [--fetch-all | --no-fetch] [--sheet] [--tickets] [--diff] [--appsec]
#   (default)    fetch only the base branch and the current branch: fast, even with many branches on origin
#   --fetch-all  fetch every branch of origin (/ticket looks for the existing branches of a ticket)
#   --no-fetch   do not fetch
#   --sheet      also print the ticket sheet of the current branch, so that the agent does not read it again
#   --tickets    also print the Jira link and the first sentence of the "Résumé" of the other ticket sheets
#   --diff       also print the commits and the diffs of the branch (committed and uncommitted); a diff longer
#                than MAX_DIFF_LINES is replaced by its file list, to be read file by file
#   --appsec     also print the APPSEC_PROJECT_NAME line of appsec-ci.env (the Fortify SSC application), and only
#                that line: the rest of the file may hold secrets

MAX_DIFF_LINES=1500
MAX_SHEETS=10

# English git messages whatever the language of the machine
LC_ALL=C
export LC_ALL
# File names as they are, without octal quoting of accented letters, so that they can be read (git 2.31 or later;
# older versions ignore these variables)
GIT_CONFIG_COUNT=1
GIT_CONFIG_KEY_0=core.quotePath
GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

fetch=branch
sheet=0
tickets=0
diff=0
appsec=0
for arg in "$@"; do
  case "$arg" in
    --fetch-all) fetch=all ;;
    --no-fetch) fetch=none ;;
    --sheet) sheet=1 ;;
    --tickets) tickets=1 ;;
    --diff) diff=1 ;;
    --appsec) appsec=1 ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository"
  exit 0
fi

here=$(dirname "$0")
root=$(git rev-parse --show-toplevel)
branch=$(git branch --show-current)
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)

# Base branch: origin/develop, otherwise origin/main or origin/master
find_base() {
  base=""
  for candidate in develop main master; do
    if git rev-parse -q --verify "refs/remotes/origin/$candidate" >/dev/null; then
      base="origin/$candidate"
      return
    fi
  done
}
find_base

# The fetch never asks for credentials and gives up after 30 s (fetch.sh): the remote-tracking branches are then those
# of the last fetch, and the line below says so
fetch_failed() {
  if [ "$1" = 124 ]; then
    echo "Fetch: TIMEOUT (GitLab did not answer within 30 s: VPN or network); remote branches as of the last fetch"
  else
    echo "Fetch: FAILED (offline, or GitLab credentials to fix in the Mac Terminal); remote branches as of the last fetch"
  fi
}
if [ "$fetch" = all ] || { [ "$fetch" = branch ] && [ -z "$base" ]; }; then
  sh "$here/fetch.sh" -q --no-tags origin 2>/dev/null || fetch_failed $?
  find_base
elif [ "$fetch" = branch ]; then
  # The base branch, and the remote copy of the current branch if it exists: a pattern that matches nothing is not
  # an error, so a branch never pushed does not make the fetch fail
  remote_name=$branch
  case "$upstream" in origin/*) remote_name=${upstream#origin/} ;; esac
  set -- "+refs/heads/${base#origin/}:refs/remotes/$base"
  [ -n "$remote_name" ] && set -- "$@" "+refs/heads/$remote_name*:refs/remotes/origin/$remote_name*"
  sh "$here/fetch.sh" -q --no-tags origin "$@" 2>/dev/null || fetch_failed $?
fi

key=$(printf '%s' "$branch" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -1)
sheets="$root/.git/opencode-tickets"
# Older versions of the pack kept the sheets in .git/opencode/tickets, but OpenCode 1.19 caches its project id in a
# FILE named .git/opencode: move them once, then free that path for OpenCode
if [ -d "$root/.git/opencode/tickets" ] && [ ! -e "$sheets" ]; then
  mv "$root/.git/opencode/tickets" "$sheets" && rmdir "$root/.git/opencode" 2>/dev/null
fi
remote_url=$(git remote get-url origin 2>/dev/null | sed -E 's#://[^@/]+@#://#')

# Remote copy of the branch: its upstream, otherwise origin/<branch> when it exists (pushed from another computer)
remote_copy=$upstream
if [ -z "$remote_copy" ] && [ -n "$branch" ] && git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
  remote_copy="origin/$branch"
fi

echo "Now: $(date '+%Y-%m-%d %H:%M')"
echo "Repository root: $root"
echo "Remote URL (credentials masked): ${remote_url:-none}"
echo "Current branch: ${branch:-(detached HEAD)}"
echo "Jira key from branch: ${key:-none}"
echo "Base branch: ${base:-NONE (no origin/develop, origin/main or origin/master)}"
echo "HEAD: $(git rev-parse --short HEAD 2>/dev/null)"
echo "Code fingerprint: $(sh "$here/state-fingerprint.sh")"
if [ "$appsec" -eq 1 ]; then
  ssc=$(git grep -h '^APPSEC_PROJECT_NAME=' -- '*appsec-ci.env' 2>/dev/null | head -1)
  echo "Fortify SSC application line (appsec-ci.env): ${ssc:-none}"
fi
if [ -n "$remote_copy" ]; then
  counts=$(git rev-list --left-right --count "$remote_copy...HEAD" 2>/dev/null)
  behind=$(printf '%s' "$counts" | cut -f1)
  ahead=$(printf '%s' "$counts" | cut -f2)
  status=""
  [ "${ahead:-0}" -gt 0 ] && status="ahead $ahead"
  [ "${behind:-0}" -gt 0 ] && status="${status:+$status, }behind $behind"
  echo "Branch vs its remote copy ($remote_copy): ${status:-up to date}"
  if [ -n "$upstream" ]; then
    echo "Upstream: $upstream"
  else
    echo "Upstream: $remote_copy (exists on origin, not set as upstream here)"
  fi
  pushed=$(git log -1 --format='%H %cI' "$remote_copy")
  echo "Pushed commit (upstream): ${pushed%% *}"
  echo "Pushed commit date: ${pushed#* }"
  if [ "${ahead:-0}" -gt 0 ]; then
    echo "Local commits not pushed:"
    git log --oneline "$remote_copy..HEAD"
  fi
else
  echo "Branch vs its remote copy: none"
  echo "Upstream: none (branch never pushed)"
fi
if [ -n "$base" ]; then
  echo "Commits behind / ahead of $base: $(git rev-list --left-right --count "$base...HEAD" | tr '\t' ' ')"
fi
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo "Merge in progress: yes"
  echo "Conflicted files (still unresolved):"
  git diff --name-only --diff-filter=U
else
  echo "Merge in progress: no"
fi
echo "Uncommitted changes summary: $(git diff HEAD --shortstat)"
echo "Staged changes summary: $(git diff --staged --shortstat)"
echo "Uncommitted files (staged and unstaged):"
git diff HEAD --name-status
echo "Untracked files:"
git ls-files --others --exclude-standard
if [ -n "$base" ]; then
  echo "Files changed on the branch (vs $base):"
  git diff --name-status "$base...HEAD"
fi
echo "Existing ticket sheets:"
ls "$sheets" 2>/dev/null
if [ -d "$sheets" ]; then
  # One line per sheet, most recent first
  set --
  # shellcheck disable=SC2010,SC2045 # ls -t orders the sheets by date; their names are Jira keys
  for file in $(ls -t "$sheets" 2>/dev/null | grep '\.md$' | head -n "$MAX_SHEETS"); do
    set -- "$@" "$sheets/$file"
  done
  if [ $# -gt 0 ]; then
    echo "Ticket sheets summary (key | title | branch | branch exists | plan done/total | last Suivi line):"
    { echo "#local branches"; git for-each-ref --format='%(refname:short)' refs/heads/; } | awk -v detail="$tickets" '
      FNR == NR { if (FNR > 1) lb[$0] = 1; next }
      FNR == 1 {
        flush(); file = FILENAME; title = $0; sub(/^# /, "", title)
        br = ""; jira = ""; res = ""; inres = 0; done = 0; todo = 0; last = ""; next
      }
      /^- Branche/ && br == "" { br = $0; sub(/^- Branche *: */, "", br) }
      /^- Jira/ && jira == "" { jira = $0; sub(/^- Jira *: */, "", jira) }
      /^## R[^ ]*sum/ { inres = 1; next }
      inres && NF { if (res == "") res = $0; inres = 0 }
      /^- \[x\]/ { done++ }
      /^- \[ \]/ { todo++ }
      /^- [0-9][0-9][0-9][0-9]-/ { last = $0 }
      END { flush() }
      function flush(   k) {
        if (file == "") return
        k = file; sub(/^.*\//, "", k); sub(/\.md$/, "", k)
        print "- " k " | " title " | " (br == "" ? "?" : br) " | " ((br in lb) ? "yes" : "no") " | " done "/" (done + todo) " | " last
        if (detail == 1) {
          sub(/\. .*$/, ".", res)
          if (length(res) > 200) { res = substr(res, 1, 200); sub(/ [^ ]*$/, "", res); res = res "..." }
          print "    Jira: " (jira == "" ? "?" : jira) " | " res
        }
      }' - "$@"
  fi
fi
if [ -n "$key" ] && [ -f "$sheets/$key.md" ]; then
  echo "Current ticket sheet: $sheets/$key.md"
  echo "Ticket title line: $(head -1 "$sheets/$key.md")"
  echo "Ticket Jira line: $(grep -m1 '^- Jira' "$sheets/$key.md")"
  if [ "$sheet" -eq 1 ]; then
    echo
    echo "=== Ticket sheet $key.md, current content (do not read it again; edit it with exact lines from here)"
    cat "$sheets/$key.md"
    echo "=== End of the ticket sheet"
  fi
elif [ -n "$key" ]; then
  echo "Current ticket sheet: none for $key"
fi

if [ "$diff" -eq 1 ] && [ -n "$base" ]; then
  tmp=$(mktemp "${TMPDIR:-/tmp}/workflow-state.XXXXXX") || exit 0
  trap 'rm -f "$tmp"' EXIT
  # Prints a diff, or only its file list when it is too long to be reviewed in one read
  print_diff() {
    git diff "$@" > "$tmp"
    lines=$(wc -l < "$tmp" | tr -d ' ')
    if [ "$lines" -gt "$MAX_DIFF_LINES" ]; then
      echo "DIFF TOO LARGE ($lines lines): review it file by file with git diff $* -- <path>"
      git diff --stat "$@"
    else
      cat "$tmp"
    fi
  }
  echo
  echo "=== Commits since $base"
  git log --oneline "$base..HEAD"
  echo
  echo "=== Committed diff against $base"
  print_diff "$base...HEAD"
  echo
  echo "=== Uncommitted diff (staged and unstaged)"
  print_diff HEAD
fi
