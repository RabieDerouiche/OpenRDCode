#!/bin/sh
# The .NET versions of the repository and of this machine, from its tracked project files (read-only, a few
# milliseconds; dotnet is asked only for its lists of SDKs and runtimes):
#   Target frameworks: each target framework and its projects (the TargetFramework(s) of each project, or of the
#                      nearest Directory.Build.props)
#   C#:                the C# version the code may use (LangVersion, otherwise the default of each target framework):
#                      the agents never write a feature of a newer version
#   .NET SDK:          the SDK global.json asks for (and its rollForward), and whether this machine has one that fits
#   Test runtimes:     the runtimes the test projects run on (Microsoft.NETCore.App, and Microsoft.AspNetCore.App for
#                      the tests of a web project), and whether this machine has them
#   Support:           a target framework at or past its end of support (net8.0 and net9.0 end on 2026-11-10)
# Called by detect-project-type.sh. Usage: dotnet-targets.sh [repository path]

[ -n "$1" ] && { cd "$1" 2>/dev/null || exit 0; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0
projects=$(git ls-files '*.csproj' '*.fsproj' '*.vbproj' 2>/dev/null)
[ -n "$projects" ] || exit 0

# the TargetFramework(s) of a project: its own, otherwise the nearest Directory.Build.props above it
tfms_of() {
  t=$(sed -n 's:.*<TargetFrameworks\{0,1\}>\([^<]*\)</TargetFrameworks\{0,1\}>.*:\1:p' "$1" | head -n 1)
  d=$(dirname "$1")
  while [ -z "$t" ]; do
    [ -f "$d/Directory.Build.props" ] &&
      t=$(sed -n 's:.*<TargetFrameworks\{0,1\}>\([^<]*\)</TargetFrameworks\{0,1\}>.*:\1:p' "$d/Directory.Build.props" | head -n 1)
    [ "$d" = . ] && break
    d=$(dirname "$d")
  done
  # a legacy project: <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
  [ -z "$t" ] && t=$(sed -n 's:.*<TargetFrameworkVersion>v\([0-9]\)\.\([0-9]*\)[^<]*</TargetFrameworkVersion>.*:net\1\2:p' "$1" | head -n 1)
  printf '%s\n' "$t" | tr ';' '\n' | tr -d ' \r' | grep .
}
# a property of a project or of the Directory.Build.props above it (the first found)
prop_of() {
  v=$(sed -n "s:.*<$2>\\([^<]*\\)</$2>.*:\\1:p" "$1" | head -n 1)
  d=$(dirname "$1")
  while [ -z "$v" ]; do
    [ -f "$d/Directory.Build.props" ] && v=$(sed -n "s:.*<$2>\\([^<]*\\)</$2>.*:\\1:p" "$d/Directory.Build.props" | head -n 1)
    [ "$d" = . ] && break
    d=$(dirname "$d")
  done
  printf '%s\n' "$v"
}
# the test projects (the same rule as test-guardian.sh)
is_test() {
  grep -qi 'Microsoft.NET.Test.Sdk\|MSTest.Sdk\|xunit.v3\|Include="MSTest"\|Include="TUnit\|<IsTestProject>[[:space:]]*true' "$1" 2>/dev/null ||
    printf '%s\n' "$1" | grep -qE '\.(Unit|Integration)?Tests?\.csproj$'
}

pairs=""
for p in $projects; do
  for t in $(tfms_of "$p"); do pairs="$pairs$t $p
"; done
done
[ -n "$pairs" ] || exit 0

# Target frameworks: net8.0 (src/Api, src/Core, tests/Api.Tests), netstandard2.0 (src/Contracts)
printf '%s' "$pairs" | awk '
  { split($2, parts, "/"); n = split($2, a, "/"); dir = (n > 1) ? substr($2, 1, length($2) - length(a[n]) - 1) : a[n]
    if (!($1 in seen)) { order[++k] = $1; seen[$1] = 1 }
    count[$1]++; if (count[$1] <= 3) names[$1] = names[$1] (count[$1] > 1 ? ", " : "") dir }
  END { printf "Target frameworks: "
        for (i = 1; i <= k; i++) { t = order[i]; more = count[t] > 3 ? ", +" (count[t] - 3) : ""
          printf "%s%s (%s%s)", (i > 1 ? ", " : ""), t, names[t], more }
        print "" }'

# C#: LangVersion, otherwise the default of each target framework
lang=""
for f in $(git ls-files 'Directory.Build.props' '*/Directory.Build.props' $projects); do
  v=$(sed -n 's:.*<LangVersion>\([^<]*\)</LangVersion>.*:\1:p' "$f" | head -n 1)
  [ -n "$v" ] && { lang="$v (LangVersion in $f)"; break; }
done
if [ -n "$lang" ]; then
  echo "C#: $lang: never a feature of a newer C# version"
else
  printf '%s' "$pairs" | awk '
    function cs(t) {
      if (t ~ /^net1[0-9]\.0/) return 14 + (substr(t, 4, 2) - 10)
      if (t ~ /^net9\.0/) return 13; if (t ~ /^net8\.0/) return 12; if (t ~ /^net7\.0/) return 11
      if (t ~ /^net6\.0/) return 10; if (t ~ /^net5\.0/) return 9; if (t ~ /^netcoreapp3/) return 8
      if (t ~ /^netstandard2\.1/) return 8; if (t ~ /^netstandard/) return "7.3"; if (t ~ /^net4/) return "7.3"
      return "" }
    { v = cs($1); if (v != "" && !($1 in seen)) { seen[$1] = 1; out = out (out == "" ? "" : ", ") v " for " $1 } }
    END { if (out != "") print "C#: " out " (the defaults: no LangVersion): never a feature of a newer C# version; a project with several targets compiles for each" }'
fi

# The SDKs and runtimes of this machine (dotnet --list-sdks and --list-runtimes do not depend on global.json)
sdks="" runtimes=""
if command -v dotnet >/dev/null 2>&1; then
  sdks=$(dotnet --list-sdks 2>/dev/null | awk '/^[0-9]/ { print $1 }')
  runtimes=$(dotnet --list-runtimes 2>/dev/null | awk '/^Microsoft\./ { print $1, $2 }')
fi

# .NET SDK: global.json and its rollForward (patch when it gives a version and no rollForward)
if [ -f global.json ]; then
  want=$(tr -d '\r' < global.json | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  roll=$(tr -d '\r' < global.json | sed -n 's/.*"rollForward"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  if [ -n "$want" ]; then
    [ -n "$roll" ] || roll="patch"
    if ! command -v dotnet >/dev/null 2>&1; then
      echo ".NET SDK: global.json asks for $want (rollForward $roll); dotnet is not on the PATH"
    else
      fit=$(printf '%s\n' "$sdks" | awk -v want="$want" -v roll="$roll" '
        function num(v, part,   a) { sub(/-.*/, "", v); split(v, a, "."); return a[part] + 0 }
        BEGIN { M = num(want, 1); m = num(want, 2); b = int(num(want, 3) / 100); p = num(want, 3) % 100; r = tolower(roll) }
        { M2 = num($1, 1); m2 = num($1, 2); b2 = int(num($1, 3) / 100); p2 = num($1, 3) % 100; ok = 0
          if (r == "disable") ok = ($1 == want)
          else if (r == "patch" || r == "latestpatch") ok = (M2 == M && m2 == m && b2 == b && p2 >= p)
          else if (r == "feature" || r == "latestfeature") ok = (M2 == M && m2 == m && (b2 * 100 + p2) >= (b * 100 + p))
          else if (r == "minor" || r == "latestminor") ok = (M2 == M && (m2 * 10000 + b2 * 100 + p2) >= (m * 10000 + b * 100 + p))
          else ok = (M2 * 1000000 + m2 * 10000 + b2 * 100 + p2) >= (M * 1000000 + m * 10000 + b * 100 + p)
          if (ok) last = $1 }
        END { print last }')
      if [ -n "$fit" ]; then
        echo ".NET SDK: global.json asks for $want (rollForward $roll): $fit is installed"
      else
        echo ".NET SDK: global.json asks for $want (rollForward $roll): NOT INSTALLED on this machine (installed: $(printf '%s\n' "$sdks" | tr '\n' ' ' | sed 's/ $//' | sed 's/ /, /g')): every build stops with an ENVIRONMENT PROBLEM until it is installed"
      fi
    fi
  elif [ -n "$sdks" ]; then
    echo ".NET SDK: global.json gives no SDK version: the newest installed, $(printf '%s\n' "$sdks" | tail -n 1)"
  fi
elif [ -n "$sdks" ]; then
  echo ".NET SDK: no global.json: the newest installed, $(printf '%s\n' "$sdks" | tail -n 1)"
fi

# Test runtimes: what each test project runs on, and whether this machine has it (same major.minor, or any higher
# major when the project rolls forward to it)
if [ -n "$runtimes" ]; then
  needs=""
  for p in $projects; do
    is_test "$p" || continue
    web=0
    grep -qi 'Microsoft.AspNetCore.Mvc.Testing\|FrameworkReference Include="Microsoft.AspNetCore.App"\|Sdk="Microsoft.NET.Sdk.Web"' "$p" && web=1
    rf=$(prop_of "$p" RollForward)
    for t in $(tfms_of "$p"); do
      case "$t" in net[0-9]*.[0-9]*) ;; *) continue ;; esac
      v=${t#net}; v=${v%%-*}
      needs="${needs}Microsoft.NETCore.App $v $t $rf
"
      [ "$web" -eq 1 ] && needs="${needs}Microsoft.AspNetCore.App $v $t $rf
"
    done
  done
  if [ -n "$needs" ]; then
    printf '%s' "$needs" | sort -u | HAVE="$runtimes" awk '
      BEGIN { n = split(ENVIRON["HAVE"], lines, "\n"); for (i = 1; i <= n; i++) { split(lines[i], f, " "); split(f[2], v, "."); got[f[1], v[1] "." v[2]] = 1; majors[f[1]] = majors[f[1]] " " v[1] } }
      { split($2, w, "."); key = w[1] "." w[2]; ok = ((($1, key) in got))
        if (!ok && $4 ~ /[Mm]ajor/) { m = split(majors[$1], ms, " "); for (i = 1; i <= m; i++) if (ms[i] + 0 > w[1] + 0) ok = 1 }
        if (ok) { if (!($3 in g)) order[++k] = $3; g[$3] = g[$3] (g[$3] == "" ? "" : ", ") $1 }
        else bad = bad (bad == "" ? "" : ", ") $1 " " key " for " $3 }
      END {
        if (bad != "") print "Test runtimes: NOT INSTALLED on this machine: " bad ": these tests stop with an ENVIRONMENT PROBLEM until the runtime is installed"
        else { out = ""; for (i = 1; i <= k; i++) out = out (i > 1 ? "; " : "") order[i] ": " g[order[i]]
               if (out != "") print "Test runtimes: installed (" out ")" } }'
  fi
fi

# Support: the end of support of each modern target framework that is not current (.NET 10 is supported until
# 2028-11-10; .NET 8 and 9 end on 2026-11-10)
printf '%s' "$pairs" | awk '{ print $1 }' | sort -u | awk -v today="$(date +%Y-%m-%d)" '
  function end(t) {
    if (t ~ /^net9\.0/ || t ~ /^net8\.0/) return "2026-11-10"; if (t ~ /^net7\.0/) return "2024-05-14"
    if (t ~ /^net6\.0/) return "2024-11-12"; if (t ~ /^net5\.0/) return "2022-05-10"; if (t ~ /^netcoreapp3\.1/) return "2022-12-13"
    if (t ~ /^netcoreapp/) return "2022-12-13"; return "" }
  { e = end($1); if (e == "") next
    if (e < today) past = past (past == "" ? "" : ", ") $1 " (ended on " e ")"
    else soon = soon (soon == "" ? "" : ", ") $1 " (ends on " e ")" }
  END {
    if (past != "") print "Support: " past ": no more security fixes; .NET 10 (LTS) is supported until 2028-11-10. Moving to it is a ticket of its own, never part of another change"
    if (soon != "") print "Support: " soon "; .NET 10 (LTS) is supported until 2028-11-10. Moving to it is a ticket of its own, never part of another change" }'
exit 0
