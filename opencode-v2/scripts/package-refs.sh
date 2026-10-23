#!/bin/sh
# Lists the NuGet packages that a repository references and tells the in-house ones from the public ones, read-only.
# A package downloaded from nuget.org carries the nuget.org repository signature (.signature.p7s, kept in the package
# cache, also when it comes through an Artifactory proxy); a package built by the company does not. For each in-house
# package: the frameworks it ships, its XML documentation, its dependencies and its source repository, read from its
# .nuspec and its folder names, never from an assembly. Also prints the target frameworks of the projects and whether
# package versions are managed centrally.
# Used by /extract-pattern (source repository) and /apply-pattern (current repository): everything an agent would
# otherwise look for in ~/.nuget, which the agents never list or search themselves.
# --doc <package id>: the XML documentation of one package, in-house or public (Blazorise.DataGrid, MudBlazor…), for
# the framework closest to the projects: the file where the agents look up a member of its API (grep tool on the
# member name) instead of guessing it, probing the assembly or searching the web.
# Usage: package-refs.sh [repository path] | package-refs.sh --doc <package id> [repository path]

LC_ALL=C
export LC_ALL

doc=""
if [ "$1" = --doc ]; then
  doc=$2
  shift 2
  [ -n "$doc" ] || { echo "usage: package-refs.sh --doc <package id> [repository path]"; exit 0; }
fi
repo=$1
# A leading ~ typed by the user arrives quoted, so the shell does not expand it.
# shellcheck disable=SC2088 # a literal ~/ is matched on purpose
case "$repo" in
  "~") repo=$HOME ;;
  "~/"*) repo="$HOME/${repo#"~/"}" ;;
esac
if [ -n "$repo" ] && ! cd "$repo" 2>/dev/null; then
  echo "Packages: folder not found: $repo"
  exit 0
fi
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Packages: not a git repository"
  exit 0
fi
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 0

cache=${NUGET_PACKAGES:-$HOME/.nuget/packages}
cache=${cache%/}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/package-refs.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

git -c core.quotePath=false ls-files -co --exclude-standard |
  grep -E '\.(csproj|fsproj|vbproj|props|targets)$|(^|/)packages\.config$' |
  grep -v -E '(^|/)(bin|obj|node_modules)/' > "$tmp/files"

if [ ! -s "$tmp/files" ]; then
  if git ls-files 'package.json' '*/package.json' 2>/dev/null | grep -v node_modules | grep -q .; then
    echo "Packages: no .NET project file in this repository (front-end dependencies: package.json)"
  else
    echo "Packages: no .NET project file in this repository"
  fi
  exit 0
fi

# Parser of MSBuild files and packages.config (same as package-licenses.sh), record = text between two "<".
# Prints "R|<id>|<version>|<file>" per direct reference, "T|<file>|<target frameworks>" and "C|<files>" (central
# package management).
cat > "$tmp/parse.awk" <<'EOF'
BEGIN { RS = "<"; cnt = 0 }
FNR == 1 { pending = ""; incomment = 0; file = FILENAME }
{
  rec = $0
  gsub(/[\r\n\t]/, " ", rec)
  if (incomment) { if (index(rec, "-->")) incomment = 0; next }
  if (substr(rec, 1, 3) == "!--") { if (!index(rec, "-->")) incomment = 1; next }
  low = tolower(rec)
  name = low
  sub(/[ \/>].*$/, "", name)
  if (name == "packagereference" || name == "globalpackagereference" || name == "packageversion" || name == "package") {
    isupdate = 0
    if (name == "package") ids = attr("id")
    else {
      ids = attr("include")
      if (ids == "") { ids = attr("update"); isupdate = 1 }
    }
    ver = attr("versionoverride")
    if (ver == "") ver = attr("version")
    kind = (name == "packageversion" || isupdate) ? "V" : "R"
    if (low ~ /\/ *> *$/) emit(kind, ids, ver)
    else { pending = ids; pkind = kind; pver = ver; pclose = "/" name }
    next
  }
  if (pending != "") {
    if (name == "version" || name == "versionoverride") {
      v = rec; sub(/^[^>]*>/, "", v); gsub(/^ +| +$/, "", v)
      if (v != "") pver = v
      next
    }
    if (substr(low, 1, length(pclose)) == pclose) { emit(pkind, pending, pver); pending = ""; next }
  }
  if (name == "targetframework" || name == "targetframeworks" || name == "targetframeworkversion") {
    v = rec; sub(/^[^>]*>/, "", v); gsub(/^ +| +$/, "", v)
    if (v != "") {
      if (!(file in tfm)) { nt++; tfile[nt] = file; tfm[file] = v }
      else if (index(";" tfm[file] ";", ";" v ";") == 0) tfm[file] = tfm[file] ";" v
    }
  }
  if (name == "managepackageversionscentrally") {
    v = low; sub(/^[^>]*>/, "", v); gsub(/^ +| +$/, "", v)
    if (v == "true") cpm = cpm (cpm == "" ? "" : ", ") file
  }
  # Property without attributes, <Name>value</Name>: used to resolve Version="$(Name)"
  if (low ~ /^[a-z_][a-z0-9_.-]*>/) {
    pn = low; sub(/>.*$/, "", pn)
    pv = rec; sub(/^[^>]*>/, "", pv); gsub(/^ +| +$/, "", pv)
    if (pv != "") prop[pn] = pv
  }
}
function attr(a,   s, q, v) {
  if (!match(low, "[ ]" a "[ ]*=[ ]*[\"']")) return ""
  q = substr(rec, RSTART + RLENGTH - 1, 1)
  s = substr(rec, RSTART + RLENGTH)
  v = substr(s, 1, index(s, q) - 1)
  gsub(/^ +| +$/, "", v)
  return v
}
function emit(kind, ids, ver,   n, i, L) {
  n = split(ids, L, ";")
  for (i = 1; i <= n; i++) {
    gsub(/^ +| +$/, "", L[i])
    if (L[i] == "" || L[i] ~ /^[@$%]/) continue
    cnt++
    kindof[cnt] = kind; idof[cnt] = L[i]; verof[cnt] = ver; fileof[cnt] = file
  }
}
function resolve(v,   pn, guard) {
  guard = 0
  while (v ~ /^\$\([A-Za-z_][A-Za-z0-9_.-]*\)$/ && guard < 5) {
    guard++
    pn = tolower(substr(v, 3, length(v) - 3))
    if (!(pn in prop)) break
    v = prop[pn]
  }
  return v
}
END {
  for (i = 1; i <= cnt; i++) {
    if (kindof[i] == "V" && verof[i] != "") cv[tolower(idof[i])] = verof[i]
  }
  for (i = 1; i <= cnt; i++) {
    if (kindof[i] != "R") continue
    v = verof[i]; lid = tolower(idof[i])
    if (v == "" && (lid in cv)) v = cv[lid]
    print "R|" idof[i] "|" resolve(v) "|" fileof[i]
  }
  for (i = 1; i <= nt; i++) {
    n = split(tfm[tfile[i]], L, ";"); out = ""
    for (k = 1; k <= n; k++) if (L[k] != "") out = out (out == "" ? "" : ";") resolve(L[k])
    print "T|" tfile[i] "|" out
  }
  if (cpm != "") print "C|" cpm
}
EOF

# One line per package and version: "<id>|<version>|<normalized version or empty>|<files>". The normalized version is
# the name of its folder in the package cache (NuGet: 1.0 -> 1.0.0, 1.2.3.0 -> 1.2.3, lower case); empty for a range,
# a floating version or an unresolved property.
cat > "$tmp/group.awk" <<'EOF'
BEGIN { FS = "[|]" }
$1 == "R" {
  k = tolower($2) "|" $3
  if (!(k in seen)) { seen[k] = ++n; id[n] = $2; ver[n] = $3; files[n] = $4 }
  else { i = seen[k]; if (index(", " files[i] ", ", ", " $4 ", ") == 0) files[i] = files[i] ", " $4 }
}
function norm(v,   p, pre, c, i, A, out) {
  gsub(/ /, "", v)
  if (v ~ /^\[[^],]+\]$/) v = substr(v, 2, length(v) - 2)
  if (v !~ /^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/) return ""
  sub(/\+.*$/, "", v)
  pre = ""
  p = index(v, "-")
  if (p) { pre = tolower(substr(v, p)); v = substr(v, 1, p - 1) }
  c = split(v, A, ".")
  if (c > 4) return ""
  for (i = 1; i <= 4; i++) A[i] = (i <= c) ? A[i] + 0 : 0
  out = A[1] "." A[2] "." A[3]
  if (A[4] != 0) out = out "." A[4]
  return out pre
}
function shortlist(list,   c, L, s) {
  c = split(list, L, ", ")
  s = L[1]
  if (c > 1) s = s ", " L[2]
  if (c > 2) s = s " +" (c - 2) " more"
  return s
}
END { for (i = 1; i <= n; i++) print id[i] "|" ver[i] "|" norm(ver[i]) "|" shortlist(files[i]) }
EOF

# What the .nuspec of an in-house package says: "D|<description>", "U|<repository>", "P|<dependencies>"
cat > "$tmp/nuspec.awk" <<'EOF'
BEGIN { RS = "<" }
{
  rec = $0
  gsub(/[\r\n\t]/, " ", rec)
  low = tolower(rec)
  name = low
  sub(/[ \/>].*$/, "", name)
  if (name == "description" && desc == "") { v = rec; sub(/^[^>]*>/, "", v); gsub(/  +/, " ", v); gsub(/^ +| +$/, "", v); desc = v }
  else if (name == "repository") { u = attr("url"); if (u != "") repo = u }
  else if (name == "projecturl" && purl == "") { v = rec; sub(/^[^>]*>/, "", v); gsub(/^ +| +$/, "", v); purl = v }
  else if (name == "dependency") {
    d = attr("id")
    if (d != "") { k = tolower(d); if (!(k in seen)) { seen[k] = 1; nd++; dep[nd] = d " " attr("version") } }
  }
}
function attr(a,   s, q, v) {
  if (!match(low, "[ ]" a "[ ]*=[ ]*[\"']")) return ""
  q = substr(rec, RSTART + RLENGTH - 1, 1)
  s = substr(rec, RSTART + RLENGTH)
  v = substr(s, 1, index(s, q) - 1)
  gsub(/^ +| +$/, "", v)
  return v
}
END {
  if (length(desc) > 160) desc = substr(desc, 1, 157) "..."
  u = (repo != "") ? repo : purl
  # never print credentials that a URL could carry
  sub(/:\/\/[^\/@]*@/, "://", u)
  out = ""
  for (i = 1; i <= nd && i <= 8; i++) out = out (i > 1 ? ", " : "") dep[i]
  if (nd > 8) out = out ", +" (nd - 8) " more"
  print "D|" desc
  print "U|" u
  print "P|" out
}
EOF

set --
while IFS= read -r f; do
  [ -f "$f" ] && set -- "$@" "$f"
done < "$tmp/files"
[ $# -gt 0 ] && awk -f "$tmp/parse.awk" "$@" > "$tmp/parsed"
[ -f "$tmp/parsed" ] || : > "$tmp/parsed"
awk -f "$tmp/group.awk" "$tmp/parsed" > "$tmp/packages"

# --doc: the XML documentation of one package (the version the repository references, otherwise the highest version
# in the cache), in the lib folder of the framework of the projects, or else the most recent one
if [ -n "$doc" ]; then
  lid=$(printf '%s' "$doc" | tr '[:upper:]' '[:lower:]')
  line=$(awk -F '|' -v id="$lid" 'tolower($1) == id { print; exit }' "$tmp/packages")
  nver=$(printf '%s' "$line" | cut -d'|' -f3)
  how="the version referenced by $(printf '%s' "$line" | cut -d'|' -f4)"
  dir="$cache/$lid"
  if [ -z "$nver" ] || [ ! -d "$dir/$nver" ]; then
    # a dependency of a package: the version the last restore of a project resolved (obj/project.assets.json)
    resolved=""
    if [ -z "$line" ]; then
      resolved=$(git ls-files -o -- '*obj/project.assets.json' 2>/dev/null | head -n 20 |
        while IFS= read -r a; do grep -oi "\"$lid/[^\"]*\": *{" "$a" 2>/dev/null; done |
        sed 's#^"[^/]*/\([^"]*\)".*#\1#' | tr '[:upper:]' '[:lower:]' | sort | uniq -c | sort -rn | awk 'NR == 1 { print $2 }')
    fi
    if [ -n "$resolved" ] && [ -d "$dir/$resolved" ]; then
      nver=$resolved how="a dependency of a package of this repository, the version its last restore resolved"
    else
      # the highest stable version in the cache (a prerelease only when there is no stable one)
      nver=$(for d in "$dir"/*/; do [ -d "$d" ] && { d=${d%/}; echo "${d##*/}"; }; done |
        awk -F '[.-]' '{ printf "%d%09d%09d%09d%09d %s\n", ($0 ~ /-/) ? 0 : 1, $1, $2, $3, $4, $0 }' | sort | tail -n 1 | cut -d' ' -f2)
      if [ -n "$line" ]; then how="its version is not in the cache: the highest one there"; else how="not referenced by a project of this repository: the highest version in the cache"; fi
    fi
  fi
  if [ -z "$nver" ]; then
    echo "XML documentation of $doc: not in the package cache of this machine (never restored here: build the solution once). Its API then comes from its existing calls in this repository only: never guess it, never probe it."
    exit 0
  fi
  frameworks=$(sed -n 's/^T|[^|]*|//p' "$tmp/parsed" | tr ';' '\n' | grep . | sort -u)
  best=$(for d in "$dir/$nver"/lib/*/; do [ -d "$d" ] && { d=${d%/}; echo "${d##*/}"; }; done |
    awk -v want="$(printf '%s' "$frameworks" | tr '\n' ' ')" '
      BEGIN { n = split(want, W, " "); for (i = 1; i <= n; i++) mine[tolower(W[i])] = 1 }
      { f = tolower($0); s = 0
        if (match(f, /^net[0-9]+\.[0-9]+/)) { split(substr(f, 4), v, "."); s = (v[1] >= 5) ? 3000 + v[1] * 10 + v[2] : 0 }
        else if (match(f, /^netcoreapp[0-9]+\.[0-9]+/)) { split(substr(f, 11), v, "."); s = 2000 + v[1] * 10 + v[2] }
        else if (match(f, /^netstandard[0-9]+\.[0-9]+/)) { split(substr(f, 12), v, "."); s = 1000 + v[1] * 10 + v[2] }
        if (f in mine) s += 100000
        if (s > top || best == "") { top = s; best = $0 } }
      END { print best }')
  files=""
  [ -n "$best" ] && for x in "$dir/$nver/lib/$best"/*.xml; do [ -f "$x" ] && files="$files$x
"; done
  if [ -z "$files" ]; then
    echo "XML documentation of $doc $nver: none (the package ships no XML documentation${best:+ in lib/$best}). Its API comes from its existing calls in this repository: never guess it, never probe the assembly; say what is missing."
    exit 0
  fi
  echo "XML documentation of $doc $nver (lib/$best; $how): look up a member with the grep tool on its name in:"
  printf '%s' "$files" | sed 's/^/- /'
  exit 0
fi

: > "$tmp/inhouse"
: > "$tmp/unknown"
: > "$tmp/public"
while IFS='|' read -r id ver nver files; do
  [ -n "$id" ] || continue
  shown=${ver:-"(no version)"}
  lid=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
  dir="$cache/$lid"
  vdir=""
  note=""
  if [ -n "$nver" ] && [ -d "$dir/$nver" ]; then
    vdir="$dir/$nver"
  elif [ -d "$dir" ]; then
    others=""
    for d in "$dir"/*/; do
      [ -d "$d" ] || continue
      d=${d%/}
      others="${others:+$others, }${d##*/}"
      vdir=$d
    done
    [ -n "$vdir" ] && note="version $shown not in the cache, which has $others (details below: ${vdir##*/})"
  fi
  if [ -z "$vdir" ]; then
    echo "- $id $shown [$files]" >> "$tmp/unknown"
    continue
  fi
  if [ -f "$vdir/.signature.p7s" ]; then
    echo "- $id $shown [$files]" >> "$tmp/public"
    continue
  fi
  frameworks=""
  for d in "$vdir"/lib/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    frameworks="${frameworks:+$frameworks, }${d##*/}"
  done
  if [ -z "$frameworks" ]; then
    for d in "$vdir"/ref/*/; do
      [ -d "$d" ] || continue
      d=${d%/}
      frameworks="${frameworks:+$frameworks, }ref/${d##*/}"
    done
  fi
  xml=""
  for x in "$vdir"/lib/*/*.xml; do
    [ -f "$x" ] && xml="${xml:+$xml, }$x"
  done
  desc="" url="" deps=""
  for n in "$vdir"/*.nuspec; do
    [ -f "$n" ] || continue
    awk -f "$tmp/nuspec.awk" "$n" > "$tmp/nuspec.out"
    while IFS= read -r line; do
      case "$line" in
        D\|*) desc=${line#D|} ;;
        U\|*) url=${line#U|} ;;
        P\|*) deps=${line#P|} ;;
      esac
    done < "$tmp/nuspec.out"
    break
  done
  {
    echo "- $id $shown [$files]"
    [ -n "$note" ] && echo "  $note"
    echo "  frameworks: ${frameworks:-none (no lib folder: build or content package)} | XML documentation: ${xml:-none} | depends on: ${deps:-nothing} | repository: ${url:-unknown}"
    [ -n "$desc" ] && echo "  description: $desc"
  } >> "$tmp/inhouse"
done < "$tmp/packages"

echo "Packages of $root (direct references of its project files; origin read from the package cache of this machine, $cache):"
cpm=$(sed -n 's/^C|//p' "$tmp/parsed" | head -1)
if [ -n "$cpm" ]; then
  echo "Central package management: yes ($cpm)"
else
  echo "Central package management: no (versions in the project files)"
fi
# Target framework of each project: its own, otherwise the one of the nearest Directory.Build.props above it
sed -n 's/^T|//p' "$tmp/parsed" > "$tmp/tfms"
grep -E '\.(csproj|fsproj|vbproj)$' "$tmp/files" > "$tmp/projects"
if [ -s "$tmp/projects" ]; then
  echo "Target frameworks:"
  while IFS= read -r project; do
    own=$(awk -F '|' -v p="$project" '$1 == p { print $2; exit }' "$tmp/tfms")
    if [ -n "$own" ]; then
      echo "- $project: $own"
      continue
    fi
    dir=$project
    found=""
    while [ "$dir" != "." ] && [ -n "$dir" ]; do
      case "$dir" in */*) dir=${dir%/*} ;; *) dir="." ;; esac
      props="Directory.Build.props"
      [ "$dir" != "." ] && props="$dir/Directory.Build.props"
      inherited=$(awk -F '|' -v p="$props" '$1 == p { print $2; exit }' "$tmp/tfms")
      if [ -n "$inherited" ]; then found="$inherited (from $props)"; break; fi
    done
    echo "- $project: ${found:-not found in the project files}"
  done < "$tmp/projects"
fi
if [ ! -s "$tmp/packages" ]; then
  echo "Package references: none"
  exit 0
fi
[ -d "$cache" ] || echo "Package cache not found ($cache): nothing was restored on this machine, so the origin of every package is unknown."
if [ -s "$tmp/inhouse" ]; then
  echo "In-house packages (no nuget.org signature):"
  cat "$tmp/inhouse"
else
  echo "In-house packages (no nuget.org signature): none"
fi
if [ -s "$tmp/unknown" ]; then
  echo "Not in the package cache of this machine (never restored here: origin unknown):"
  cat "$tmp/unknown"
fi
if [ -s "$tmp/public" ]; then
  echo "nuget.org packages (the XML documentation of one: package-refs.sh --doc <id>):"
  cat "$tmp/public"
fi
exit 0
