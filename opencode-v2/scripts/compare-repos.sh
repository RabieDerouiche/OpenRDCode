#!/bin/sh
# For /compare: what differs between a reference repository (the version that works) and the current one (the
# repository of the session), computed before the agent reads any code. Read-only, no fetch, no build, and never a
# configuration value: configuration files are named, never diffed.
# Prints, in a bounded size:
# - the checkout of each repository (branch, last commit), the reference compared with its production branch;
# - their target frameworks and .NET SDK (global.json);
# - the NuGet packages whose version differs: the direct references (from package-refs.sh, in-house ones first, with
#   the XML documentation of both versions), then the transitive ones resolved by the last restore
#   (obj/project.assets.json), framework packages left out;
# - with an identifier (class, method, route or file name): the files that contain it in each repository, the diff
#   of the files that have the same name on both sides (whitespace ignored), the files without a counterpart, and the
#   history of these files, including the commits of the reference made after the current version was created (a fix
#   there may never have been ported).
# Usage: compare-repos.sh <reference repository path> [<identifier>]
#        compare-repos.sh --raw "<text>"   what I typed after /compare: the path, the identifier, then the symptom
#                                          (ignored here); the path cannot contain spaces in this form

MAX_FILES=25        # files listed per repository for the identifier
TOO_COMMON=60       # more code files than this in a repository: the identifier is too common to pair files
MAX_PAIRS=8         # same-name files compared
MAX_PAIR_LINES=120  # diff lines printed per pair
MAX_DIFF_LINES=400  # diff lines printed in all
MAX_PACKAGES=40     # package lines printed per list

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

if [ "$1" = --raw ]; then
  text=$2
  set -f
  # shellcheck disable=SC2086 # split on purpose: the path, the identifier, then the words of the symptom
  set -- $text
  set +f
fi
# Quotes or backticks typed around a word are not part of it
unquote() {
  v=$1
  v=${v#[\"\'\`]}
  v=${v%[\"\'\`]}
  printf '%s' "$v"
}
ref=$(unquote "$1")
term=$(unquote "$2")
# A leading ~ typed by the user arrives quoted, so the shell does not expand it.
# shellcheck disable=SC2088 # a literal ~/ is matched on purpose
case "$ref" in
  "~") ref=$HOME ;;
  "~/"*) ref="$HOME/${ref#"~/"}" ;;
esac

if [ -z "$ref" ]; then
  echo "Reference repository: none given. Usage: /compare <path of the reference repository> <class, method, route or file name> <symptom>"
  exit 0
fi
cur_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$cur_root" ]; then
  echo "Current repository: this session's folder is not a git repository"
  exit 0
fi
if [ ! -d "$ref" ]; then
  echo "Reference repository: folder not found: $ref"
  exit 0
fi
ref_root=$(cd "$ref" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$ref_root" ]; then
  echo "Reference repository: not a git repository: $ref"
  exit 0
fi
if [ "$ref_root" = "$cur_root" ]; then
  echo "Reference repository: same repository as this session ($cur_root): give the path of the other repository"
  exit 0
fi

cache=${NUGET_PACKAGES:-$HOME/.nuget/packages}
cache=${cache%/}
here=$(dirname "$0")

tmp=$(mktemp -d "${TMPDIR:-/tmp}/compare-repos.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# Joins the lines of stdin with ", "
join() {
  awk 'NR > 1 { printf ", " } { printf "%s", $0 } END { if (NR) print "" }'
}

# "branch <name> (<sha>, <date>)[, <n> uncommitted changes]" of the repository in $1
checkout() {
  (
    cd "$1" || exit 0
    branch=$(git symbolic-ref --short -q HEAD) || branch="detached HEAD"
    head=$(git log -1 --format='%h, %cs' 2>/dev/null)
    [ -n "$head" ] || head="no commit yet"
    changes=$(git status --porcelain --untracked-files=no 2>/dev/null | grep -c .)
    line="branch $branch ($head)"
    [ "$changes" -gt 0 ] && line="$line, $changes uncommitted changes"
    printf '%s\n' "$line"
  )
}

# The reference compared with the local copy of its production branch (master, main, otherwise develop)
production() {
  (
    cd "$1" || exit 0
    for candidate in origin/master origin/main origin/develop; do
      git rev-parse -q --verify "$candidate^{commit}" >/dev/null || continue
      counts=$(git rev-list --left-right --count "HEAD...$candidate" 2>/dev/null)
      ahead=${counts%%[!0-9]*}
      behind=${counts##*[!0-9]}
      at=$(git log -1 --format='%h, %cs' "$candidate")
      if [ -z "$counts" ]; then
        echo "  compared with $candidate ($at): no common history"
      elif [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
        echo "  compared with $candidate ($at, local copy, not fetched): same commit"
      else
        echo "  compared with $candidate ($at, local copy, not fetched): $ahead commits ahead, $behind behind: this checkout may not be the version that runs"
      fi
      exit 0
    done
    echo "  no origin/master, origin/main or origin/develop in this clone"
  )
}

# SDK version of global.json at the root of $1
sdk() {
  if [ -f "$1/global.json" ]; then
    v=$(tr -d '\r\n' < "$1/global.json" | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    echo "${v:-global.json without a version}"
  else
    echo "no global.json"
  fi
}

echo "Read-only comparison. Reference = the repository given to /compare (the version that works); current = the repository of this session."
echo "Reference: $ref_root - $(checkout "$ref_root")"
production "$ref_root"
echo "Current: $cur_root - $(checkout "$cur_root")"

# Packages and target frameworks of each repository, from package-refs.sh. Records: "T|<tfm>", "P|<origin>|<id>|<version>",
# "X|<id>|<XML documentation>".
cat > "$tmp/refs.awk" <<'EOF'
/^Target frameworks:/ { sec = "tfm"; next }
/^In-house packages \(no nuget\.org signature\):/ { sec = "in-house"; next }
/^Not in the package cache of this machine/ { sec = "unknown"; next }
/^nuget\.org packages:/ { sec = "public"; next }
/^Package references: none/ { sec = ""; next }
sec == "tfm" && /^- / {
  v = $0
  sub(/^- [^:]*: /, "", v)
  sub(/ \(from .*\)$/, "", v)
  if (v == "not found in the project files") next
  n = split(v, T, ";")
  for (i = 1; i <= n; i++) if (T[i] != "") print "T|" T[i]
  next
}
(sec == "in-house" || sec == "unknown" || sec == "public") && /^- / {
  id = $2
  ver = ($3 == "(no") ? "(no version)" : $3
  print "P|" sec "|" id "|" ver
  last = id
  next
}
sec == "in-house" && /XML documentation: / {
  x = $0
  sub(/^.*XML documentation: /, "", x)
  sub(/ \| depends on: .*$/, "", x)
  print "X|" last "|" x
}
EOF
sh "$here/package-refs.sh" "$ref_root" 2>/dev/null | awk -f "$tmp/refs.awk" > "$tmp/ref.pk"
sh "$here/package-refs.sh" "$cur_root" 2>/dev/null | awk -f "$tmp/refs.awk" > "$tmp/cur.pk"

ref_tfm=$(sed -n 's/^T|//p' "$tmp/ref.pk" | sort -u | join)
cur_tfm=$(sed -n 's/^T|//p' "$tmp/cur.pk" | sort -u | join)
if [ -n "$ref_tfm$cur_tfm" ]; then
  echo "Target frameworks: reference ${ref_tfm:-none found} | current ${cur_tfm:-none found}"
  echo ".NET SDK (global.json): reference $(sdk "$ref_root") | current $(sdk "$cur_root")"
fi

# Direct references whose versions differ, in-house first
cat > "$tmp/direct.awk" <<'EOF'
BEGIN { FS = "|" }
{ side = (FILENAME == ARGV[1]) ? 1 : 2 }
$1 == "P" {
  k = tolower($3)
  if (!(k in name)) { name[k] = $3; order[++n] = k }
  if ($2 == "in-house") inh[k] = 1
  if (side == 1) va[k] = add(va[k], $4); else vb[k] = add(vb[k], $4)
}
$1 == "X" { k = tolower($2); if (side == 1) xa[k] = $3; else xb[k] = $3 }
function add(list, v) { return (index(", " list ", ", ", " v ", ") > 0) ? list : list (list == "" ? "" : ", ") v }
function show(k) {
  label = name[k] (inh[k] ? " (in-house)" : "")
  if (va[k] == "") print "- " label ": only in the current repository (" vb[k] ")"
  else if (vb[k] == "") print "- " label ": only in the reference (" va[k] ")"
  else {
    print "- " label ": " va[k] " -> " vb[k]
    if (inh[k]) print "  XML documentation: reference " (xa[k] == "" ? "none" : xa[k]) " | current " (xb[k] == "" ? "none" : xb[k])
  }
}
END {
  for (i = 1; i <= n; i++) { k = order[i]; if (va[k] != vb[k] && inh[k]) show(k) }
  for (i = 1; i <= n; i++) { k = order[i]; if (va[k] != vb[k] && !inh[k]) show(k) }
}
EOF
if grep -q '^P|' "$tmp/ref.pk" "$tmp/cur.pk"; then
  awk -f "$tmp/direct.awk" "$tmp/ref.pk" "$tmp/cur.pk" > "$tmp/direct"
  total=$(grep -c '^- ' "$tmp/direct")
  if [ "$total" -eq 0 ]; then
    echo "NuGet packages referenced by the projects: same ids and versions in both repositories"
  else
    echo "NuGet packages referenced by the projects, differences only ($total; in-house = without the nuget.org signature):"
    awk -v max="$MAX_PACKAGES" '/^- / { n++ } n <= max' "$tmp/direct"
    [ "$total" -gt "$MAX_PACKAGES" ] && echo "+$((total - MAX_PACKAGES)) more"
  fi
fi

# Transitive packages resolved by the last restore: "<id>|<version>" of the package libraries of every
# obj/project.assets.json of the repository in $1
cat > "$tmp/assets.awk" <<'EOF'
/"libraries"[ \t]*:[ \t]*\{/ { inlib = 1; next }
inlib && /"(projectFileDependencyGroups|packageFolders|project|logs)"[ \t]*:/ { inlib = 0 }
inlib && /^[ \t]*"[^"]+\/[^"]+"[ \t]*:[ \t]*\{[ \t]*$/ {
  cur = $0
  sub(/^[ \t]*"/, "", cur)
  sub(/"[ \t]*:.*$/, "", cur)
  next
}
inlib && cur != "" && /"type"[ \t]*:[ \t]*"package"/ { p = index(cur, "/"); print substr(cur, 1, p - 1) "|" substr(cur, p + 1); cur = ""; next }
inlib && cur != "" && /"type"[ \t]*:/ { cur = "" }
EOF
assets() {
  find "$1" -name node_modules -prune -o -type f -name project.assets.json -path '*/obj/*' -print 2>/dev/null > "$tmp/assets.list"
  [ -s "$tmp/assets.list" ] || return 1
  set --
  while IFS= read -r f; do set -- "$@" "$f"; done < "$tmp/assets.list"
  awk -f "$tmp/assets.awk" "$@" | sort -u
}
ref_assets=1 cur_assets=1
assets "$ref_root" > "$tmp/ref.as" || ref_assets=0
assets "$cur_root" > "$tmp/cur.as" || cur_assets=0
if [ "$ref_assets" -eq 0 ] || [ "$cur_assets" -eq 0 ]; then
  if grep -q '^P|' "$tmp/ref.pk" "$tmp/cur.pk"; then
    missing="the reference"
    [ "$ref_assets" -eq 1 ] && missing="the current repository"
    [ "$ref_assets" -eq 0 ] && [ "$cur_assets" -eq 0 ] && missing="either repository"
    echo "Transitive packages: not compared ($missing was never restored on this machine: no obj/project.assets.json; a \`dotnet restore\` in it, then /compare again, adds them)"
  fi
else
  # Direct references of both sides are already above
  sed -n 's/^P|[^|]*|\([^|]*\)|.*/\1/p' "$tmp/ref.pk" "$tmp/cur.pk" | sort -u > "$tmp/direct.ids"
  cat > "$tmp/transitive.awk" <<'EOF'
BEGIN { FS = "|" }
FILENAME == ARGV[1] { direct[tolower($0)] = 1; next }
{
  side = (FILENAME == ARGV[2]) ? 1 : 2
  k = tolower($1)
  if (k in direct) next
  if (!(k in name)) { name[k] = $1; order[++n] = k }
  if (side == 1) va[k] = add(va[k], $2); else vb[k] = add(vb[k], $2)
}
function add(list, v) { return (index(", " list ", ", ", " v ", ") > 0) ? list : list (list == "" ? "" : ", ") v }
END {
  for (i = 1; i <= n; i++) {
    k = order[i]
    if (va[k] == vb[k]) continue
    if (k ~ /^(system\.|microsoft\.extensions\.|microsoft\.aspnetcore\.|microsoft\.netcore\.|microsoft\.win32\.|runtime\.|netstandard\.library$|microsoft\.csharp$|microsoft\.visualbasic$)/) { framework++; continue }
    print k "|" name[k] "|" va[k] "|" vb[k]
  }
  print "F|" framework + 0
}
EOF
  awk -f "$tmp/transitive.awk" "$tmp/direct.ids" "$tmp/ref.as" "$tmp/cur.as" > "$tmp/transitive"
  framework=$(sed -n 's/^F|//p' "$tmp/transitive")
  grep -v '^F|' "$tmp/transitive" > "$tmp/transitive.rows"
  : > "$tmp/transitive.inhouse"
  : > "$tmp/transitive.other"
  while IFS='|' read -r lid id va vb; do
    [ -n "$lid" ] || continue
    # in-house: in the package cache without the nuget.org signature (same test as package-refs.sh)
    origin=""
    for v in "${vb%%,*}" "${va%%,*}"; do
      [ -n "$v" ] || continue
      d="$cache/$lid/$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')"
      if [ -d "$d" ]; then
        [ -f "$d/.signature.p7s" ] || origin=" (in-house)"
        break
      fi
    done
    if [ -z "$va" ]; then line="- $id$origin: only in the current repository ($vb)"
    elif [ -z "$vb" ]; then line="- $id$origin: only in the reference ($va)"
    else line="- $id$origin: $va -> $vb"
    fi
    if [ -n "$origin" ]; then echo "$line" >> "$tmp/transitive.inhouse"; else echo "$line" >> "$tmp/transitive.other"; fi
  done < "$tmp/transitive.rows"
  total=$(cat "$tmp/transitive.inhouse" "$tmp/transitive.other" | grep -c .)
  if [ "$total" -eq 0 ]; then
    echo "Transitive packages (resolved by the last restore): same versions in both repositories"
  else
    echo "Transitive packages resolved by the last restore (obj/project.assets.json), differences only ($total):"
    cat "$tmp/transitive.inhouse" "$tmp/transitive.other" | head -n "$MAX_PACKAGES"
    [ "$total" -gt "$MAX_PACKAGES" ] && echo "+$((total - MAX_PACKAGES)) more"
  fi
  if [ "${framework:-0}" -gt 0 ]; then
    echo "Left out: $framework framework packages (System.*, Microsoft.Extensions.*, Microsoft.AspNetCore.*, Microsoft.NETCore.*) with other versions: they follow the target framework"
  fi
fi

if [ -z "$term" ]; then
  echo "Identifier: none given (no file search, no diff): locate the feature in both repositories yourself."
  exit 0
fi

# Files of the repository in $1 that contain the identifier or whose path contains it: "<path><TAB><matches>".
# Lock files and minified files left out.
matching() {
  (
    cd "$1" || exit 0
    git grep -c -i -F -e "$term" -- . ':(exclude)*packages.lock.json' ':(exclude)*package-lock.json' \
      ':(exclude)*yarn.lock' ':(exclude)*pnpm-lock.yaml' ':(exclude)*.min.js' ':(exclude)*.min.css' 2>/dev/null |
      awk '{ c = $0; p = $0; sub(/^.*:/, "", c); sub(/:[0-9]+$/, "", p); print p "\t" c }'
    git ls-files 2>/dev/null | grep -i -F -e "$term" | awk '{ print $0 "\tname" }'
  ) | awk -F '\t' '!($1 in seen) { seen[$1] = 1; print }' | sort
}
# Configuration files are named, never diffed: their values stay out of the conversation
split_config() {
  awk -F '\t' -v code="$2" -v conf="$3" '{
    n = split($1, P, "/"); b = tolower(P[n])
    if (b ~ /^appsettings.*\.json$/ || b == "launchsettings.json" || b ~ /\.config$/ || b ~ /^\.env/ || b ~ /^environment.*\.ts$/) print > conf
    else print > code
  }' "$1"
}
if [ "${#term}" -lt 4 ]; then
  echo "Identifier \"$term\": too short to search (no file search, no diff): locate the feature in both repositories with a class, method or route name."
  exit 0
fi
matching "$ref_root" > "$tmp/ref.match"
matching "$cur_root" > "$tmp/cur.match"
: > "$tmp/ref.code"; : > "$tmp/ref.conf"; : > "$tmp/cur.code"; : > "$tmp/cur.conf"
split_config "$tmp/ref.match" "$tmp/ref.code" "$tmp/ref.conf"
split_config "$tmp/cur.match" "$tmp/cur.code" "$tmp/cur.conf"
ref_count=$(grep -c . "$tmp/ref.code")
cur_count=$(grep -c . "$tmp/cur.code")

# "- <path> (<n>)" for the files in $1, at most $2
list_files() {
  awk -F '\t' -v max="$2" 'NR <= max { print "- " $1 ($2 == "name" ? " (name)" : " (" $2 ")") }' "$1"
}
if [ "$ref_count" -gt "$TOO_COMMON" ] || [ "$cur_count" -gt "$TOO_COMMON" ]; then
  echo "Identifier \"$term\": too common ($ref_count code files in the reference, $cur_count in the current repository): no file list, no diff; locate the feature with a class or method name."
  exit 0
fi
echo "Identifier \"$term\" (case-insensitive; number of matches, or \"name\" when only the path contains it):"
for side in ref cur; do
  if [ "$side" = ref ]; then label="reference" count=$ref_count; else label="current repository" count=$cur_count; fi
  if [ "$count" -eq 0 ]; then
    echo "In the $label: no code file"
  else
    echo "In the $label ($count code files):"
    list_files "$tmp/$side.code" "$MAX_FILES"
    [ "$count" -gt "$MAX_FILES" ] && echo "+$((count - MAX_FILES)) more"
  fi
  if [ -s "$tmp/$side.conf" ]; then
    echo "Configuration files of the $label that mention it (read only the section of the feature): $(cut -f1 "$tmp/$side.conf" | join)"
  fi
done

if [ "$ref_count" -eq 0 ] && [ "$cur_count" -eq 0 ]; then
  echo "The identifier is in neither repository: locate the feature with other names."
  exit 0
fi

# Same-name files: a matched file of one side with the file of the same name on the other side (a matched one
# first, otherwise any tracked one), the one whose folders end the same way when several. Prints
# "P<TAB><relevance><TAB>ref<TAB>cur" (both files contain the identifier first, then the most matches) and
# "U<TAB>side<TAB>path" for a matched file without a counterpart.
(cd "$ref_root" && git ls-files) > "$tmp/ref.all" 2>/dev/null
(cd "$cur_root" && git ls-files) > "$tmp/cur.all" 2>/dev/null
cat > "$tmp/pairs.awk" <<'EOF'
BEGIN { FS = "\t" }
FILENAME == ARGV[1] { ma[++na] = $1; ca[$1] = $2 + 0; next }
FILENAME == ARGV[2] { mb[++nb] = $1; cb[$1] = $2 + 0; next }
FILENAME == ARGV[3] { k = base($0); alla[k] = alla[k] "\n" $0; next }
FILENAME == ARGV[4] { k = base($0); allb[k] = allb[k] "\n" $0; next }
function base(p,   n, P) { n = split(p, P, "/"); return P[n] }
function score(p, q,   n, m, P, Q, s) {
  n = split(p, P, "/"); m = split(q, Q, "/"); s = 0
  while (n > 1 && m > 1 && tolower(P[n - 1]) == tolower(Q[m - 1])) { s++; n--; m-- }
  return s
}
function best(p, list,   n, L, i, b, bs, s) {
  n = split(list, L, "\n"); b = ""; bs = -1
  for (i = 1; i <= n; i++) {
    if (L[i] == "") continue
    s = score(p, L[i])
    if (s > bs) { bs = s; b = L[i] }
  }
  return b
}
function pair(p, q,   r) {
  if ((p SUBSEP q) in seen) return
  seen[p SUBSEP q] = 1
  r = ((p in ca) && (q in cb) ? 1000 : 0) + ca[p] + cb[q]
  print "P\t" r "\t" p "\t" q
}
END {
  for (i = 1; i <= na; i++) {
    k = base(ma[i]); lst = ""
    for (j = 1; j <= nb; j++) if (base(mb[j]) == k) lst = lst "\n" mb[j]
    q = (lst != "") ? best(ma[i], lst) : best(ma[i], allb[k])
    if (q == "") print "U\treference\t" ma[i]; else pair(ma[i], q)
  }
  for (j = 1; j <= nb; j++) {
    k = base(mb[j]); lst = ""
    for (i = 1; i <= na; i++) if (base(ma[i]) == k) lst = lst "\n" ma[i]
    p = (lst != "") ? best(mb[j], lst) : best(mb[j], alla[k])
    if (p == "") print "U\tcurrent\t" mb[j]; else pair(p, mb[j])
  }
}
EOF
awk -f "$tmp/pairs.awk" "$tmp/ref.code" "$tmp/cur.code" "$tmp/ref.all" "$tmp/cur.all" > "$tmp/pairs"
tab=$(printf '\t')
grep '^P' "$tmp/pairs" | sort -t "$tab" -k2,2nr > "$tmp/pairs.sorted"

npairs=$(grep -c . "$tmp/pairs.sorted")
if [ "$npairs" -gt 0 ]; then
  echo "Same-name files in both repositories ($npairs; git diff, whitespace ignored; \"-\" = reference, \"+\" = current):"
  printed=0
  shown=0
  : > "$tmp/identical"
  : > "$tmp/different"
  : > "$tmp/skipped"
  while IFS="$tab" read -r _ _ a b; do
    if [ "$shown" -ge "$MAX_PAIRS" ]; then
      echo "$a / $b" >> "$tmp/skipped"
      continue
    fi
    git diff --no-index --no-color --no-ext-diff -w --ignore-cr-at-eol -U3 -- "$ref_root/$a" "$cur_root/$b" > "$tmp/diff" 2>/dev/null
    status=$?
    # git older than 2.16 does not know --ignore-cr-at-eol (exit 129)
    if [ "$status" -gt 1 ]; then
      git diff --no-index --no-color --no-ext-diff -w -U3 -- "$ref_root/$a" "$cur_root/$b" > "$tmp/diff" 2>/dev/null
    fi
    sed -n '/^@@/,$p' "$tmp/diff" > "$tmp/hunks"
    if [ ! -s "$tmp/hunks" ]; then
      echo "$a / $b" >> "$tmp/identical"
      continue
    fi
    removed=$(grep -c '^-' "$tmp/hunks")
    added=$(grep -c '^+' "$tmp/hunks")
    size=$(cat "$ref_root/$a" "$cur_root/$b" | wc -l | tr -d ' ')
    if [ $((removed + added)) -gt $((size * 6 / 10)) ]; then
      echo "$a / $b (-$removed +$added lines out of $size)" >> "$tmp/different"
      continue
    fi
    shown=$((shown + 1))
    echo "=== $a / $b (-$removed +$added)"
    left=$((MAX_DIFF_LINES - printed))
    [ "$left" -gt "$MAX_PAIR_LINES" ] && left=$MAX_PAIR_LINES
    if [ "$left" -le 0 ]; then
      echo "(diff not shown: the report is full; read both files)"
      continue
    fi
    lines=$(wc -l < "$tmp/hunks" | tr -d ' ')
    head -n "$left" "$tmp/hunks" | cut -c1-200
    if [ "$lines" -gt "$left" ]; then
      echo "... $((lines - left)) more diff lines: read both files"
      printed=$((printed + left))
    else
      printed=$((printed + lines))
    fi
  done < "$tmp/pairs.sorted"
  [ -s "$tmp/different" ] && echo "Mostly different, no diff (read the parts you need): $(join < "$tmp/different")"
  [ -s "$tmp/identical" ] && echo "Identical (whitespace ignored): $(join < "$tmp/identical")"
  [ -s "$tmp/skipped" ] && echo "Not compared (more than $MAX_PAIRS diffs): $(join < "$tmp/skipped")"
fi
if grep -q '^U' "$tmp/pairs"; then
  echo "Files without a same-name file in the other repository (read them when the value goes through them):"
  for side in reference current; do
    files=$(awk -F '\t' -v s="$side" '$1 == "U" && $2 == s { print $3 }' "$tmp/pairs" | head -n "$MAX_FILES" | join)
    [ -n "$files" ] && echo "- $side: $files"
  done
fi

# History of the matched code files
history() {
  [ -s "$2" ] || return 0
  (
    list=$2
    cd "$1" || exit 0
    set --
    while IFS="$(printf '\t')" read -r f _; do set -- "$@" "$f"; done < "$list"
    git log -n 5 --format='  %h %cs %s' -- "$@" 2>/dev/null | cut -c1-160
  )
}
echo "History of these files (last 5 commits):"
echo "- reference:"
history "$ref_root" "$tmp/ref.code"
echo "- current:"
history "$cur_root" "$tmp/cur.code"
if [ -s "$tmp/cur.code" ] && [ -s "$tmp/ref.code" ]; then
  first=$(
    cd "$cur_root" || exit 0
    set --
    while IFS="$(printf '\t')" read -r f _; do set -- "$@" "$f"; done < "$tmp/cur.code"
    git log --reverse --format='%cs' -- "$@" 2>/dev/null | head -n 1
  )
  if [ -n "$first" ]; then
    (
      cd "$ref_root" || exit 0
      set --
      while IFS="$(printf '\t')" read -r f _; do set -- "$@" "$f"; done < "$tmp/ref.code"
      git log --since="$first" --format='  %h %cs %s' -- "$@" 2>/dev/null > "$tmp/after"
      n=$(grep -c . "$tmp/after")
      if [ "$n" -eq 0 ]; then
        echo "Commits of the reference on these files since the current version was created ($first): none"
      else
        echo "Commits of the reference on these files since the current version was created ($first): $n (a fix there may never have been ported):"
        head -n 10 "$tmp/after" | cut -c1-160
        [ "$n" -gt 10 ] && echo "  +$((n - 10)) more"
      fi
    )
  fi
fi
exit 0
