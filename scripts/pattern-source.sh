#!/bin/sh
# For /extract-pattern: where the implementation is in the source repository, without searching. Read-only, no fetch.
# Prints the checked-out branch compared with the local copy of its base (origin/develop, otherwise origin/main or
# origin/master): the agent reads the files of this checkout, which may not contain the development. Then, for each
# Jira key of the text: its branches, its commits on the local and remote-tracking branches (merge requests
# included), whether they are in the checkout, and the files they changed.
# Usage: pattern-source.sh <repository path> [<text with Jira keys>]

LC_ALL=C
export LC_ALL

repo=$1
[ $# -gt 0 ] && shift
text="$*"
# shellcheck disable=SC2088 # a literal ~/ is matched on purpose
case "$repo" in
  "~") repo=$HOME ;;
  "~/"*) repo="$HOME/${repo#"~/"}" ;;
esac
if [ -n "$repo" ] && ! cd "$repo" 2>/dev/null; then
  echo "Checkout of the source repository: folder not found: $repo"
  exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Checkout of the source repository: not a git repository"
  exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 0

GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

branch=$(git symbolic-ref --short -q HEAD) || branch="detached HEAD"
head=$(git log -1 --format='%h, %cs' 2>/dev/null)
[ -n "$head" ] || head="no commit yet"
changes=$(git status --porcelain --untracked-files=no 2>/dev/null | grep -c .)
line="Checked-out branch of the source repository: $branch ($head)"
[ "$changes" -gt 0 ] && line="$line, with $changes uncommitted changes"
echo "$line"

base=""
for candidate in origin/develop origin/main origin/master; do
  if git rev-parse -q --verify "$candidate^{commit}" >/dev/null; then base=$candidate; break; fi
done
if [ -n "$base" ]; then
  counts=$(git rev-list --left-right --count "HEAD...$base" 2>/dev/null)
  ahead=${counts%%[!0-9]*}
  behind=${counts##*[!0-9]}
  basehead=$(git log -1 --format='%h, %cs' "$base")
  if [ -z "$counts" ]; then
    echo "Compared with $base ($basehead): no common history"
  elif [ "$behind" -eq 0 ] && [ "$ahead" -eq 0 ]; then
    echo "Compared with $base ($basehead, local copy, not fetched): same commit"
  elif [ "$behind" -eq 0 ]; then
    echo "Compared with $base ($basehead, local copy, not fetched): $ahead commits ahead, none behind"
  else
    echo "Compared with $base ($basehead, local copy, not fetched): BEHIND by $behind commits (and $ahead ahead): the files of this checkout may not be the latest version of the implementation"
  fi
else
  echo "Compared with its base: no origin/develop, origin/main or origin/master in this clone"
fi

# Jira keys typed as such (upper case), minus look-alikes common in a description (AES-256, SHA-1, UTF-8, ISO-8601...)
keys=$(printf '%s\n' "$text" | grep -o -E '[A-Z][A-Z0-9_]+-[0-9]+' |
  grep -v -E '^(AES|SHA|UTF|ISO|RFC|TLS|SSL|RSA|HMAC|PKCS|ECDSA|ECDH|CVE|CWE|HTTP|HTTPS|NET|X509|S3|EC2|KMS)-' | sort -u)
[ -z "$keys" ] && exit 0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pattern-source.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

for key in $keys; do
  echo "Development $key:"
  regex="(^|[^A-Za-z0-9])$key([^0-9]|$)"
  git for-each-ref --format='%(refname:short)' refs/heads refs/remotes | grep -i -E "$regex" | head -5 > "$tmp/branches"
  if [ -s "$tmp/branches" ]; then
    echo "- branches: $(tr '\n' ' ' < "$tmp/branches" | sed 's/ $//; s/ /, /g')"
  fi
  git log --branches --remotes -E -i --grep="$regex" --format='%H' 2>/dev/null | head -50 > "$tmp/commits"
  total=$(grep -c . "$tmp/commits")
  if [ "$total" -eq 0 ]; then
    echo "- no commit mentions $key on the local and remote-tracking branches of this clone"
    continue
  fi
  echo "- commits, newest first ($total):"
  head -15 "$tmp/commits" | while IFS= read -r c; do
    git log -1 --format='  %h %cs %s' "$c" | cut -c1-160
  done
  [ "$total" -gt 15 ] && echo "  +$((total - 15)) more"
  inhead=0
  : > "$tmp/changes"
  while IFS= read -r c; do
    git merge-base --is-ancestor "$c" HEAD 2>/dev/null && inhead=$((inhead + 1))
    words=$(git rev-list --parents -n 1 "$c" | wc -w)
    if [ "$words" -gt 2 ]; then
      # merge commit (a merge request): its whole change compared with the branch it was merged into
      git diff --name-status --no-renames "$c^1" "$c" >> "$tmp/changes" 2>/dev/null
    else
      git diff-tree -r --root --no-commit-id --name-status --no-renames "$c" >> "$tmp/changes" 2>/dev/null
    fi
  done < "$tmp/commits"
  if [ "$inhead" -eq "$total" ]; then
    echo "- in the checked-out branch: yes"
  elif [ "$inhead" -eq 0 ]; then
    echo "- in the checked-out branch: NO: the files of this checkout do not contain this development"
  else
    echo "- in the checked-out branch: only $inhead of $total commits: the files of this checkout may not contain all of it"
  fi
  # one line per file (first status seen, newest commit first); lock files left out; files gone from the checkout marked
  awk -F '\t' 'NF >= 2 && !($2 in seen) {
      seen[$2] = 1
      n = split($2, P, "/")
      if (P[n] ~ /^(packages\.lock\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$/) next
      print $1 "\t" $2
    }' "$tmp/changes" | sort -t "$(printf '\t')" -k2 > "$tmp/files"
  count=$(grep -c . "$tmp/files")
  echo "- files changed ($count; A added, M modified, D deleted):"
  head -80 "$tmp/files" | while IFS="$(printf '\t')" read -r status path; do
    if [ -e "$path" ]; then echo "  $status $path"; else echo "  $status $path (not in this checkout)"; fi
  done
  [ "$count" -gt 80 ] && echo "  +$((count - 80)) more"
done
exit 0
