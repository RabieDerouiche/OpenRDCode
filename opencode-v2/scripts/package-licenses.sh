#!/bin/sh
# Flags the NuGet packages whose license makes them paid or copyleft: commercial license, maintenance fee, AGPL.
# A package can be free up to a version and paid from the next one, so the rules below are per version.
# Read-only (temporary files only). Output in English: the agents translate.
#
# Run on demand only (/licences, or the question of /check when the branch changes a project file).
# Usage:
#   package-licenses.sh                  every package of the repository with a license issue: direct references
#                                        (project files, Directory.Packages.props, packages.config), then transitive
#                                        ones from obj/project.assets.json (state of the last restore)
#   package-licenses.sh --diff [<base>]  packages added or changed since the merge base with <base> (default:
#                                        origin/develop, otherwise origin/main or origin/master), working tree included;
#                                        "branche" or "branch" instead of --diff also works
#   package-licenses.sh [--check] <PackageId> [<version>]
#                                        the rule for one package, before adding or upgrading it
#
# Rules, one per line: package ids (exact, or "Prefix.*") | first version concerned (0 = every version) |
# scope (any, or direct: only a direct reference is concerned) | kind | terms | free option.
# Checked in October 2026 against the publishers' announcements: update them when a well-known package changes.

RULES_DATE="2026-10"

usage() {
  echo "Usage: package-licenses.sh [--diff [<base>] | branche | [--check] <PackageId> [<version>]]"
}

# One argument with spaces comes from the /licences command ('$ARGUMENTS'): split it into words
if [ $# -eq 1 ]; then
  case "$1" in
    *" "*)
      set -f
      # shellcheck disable=SC2086 # word splitting wanted
      set -- $1
      set +f ;;
  esac
fi

mode="scan"
case "$1" in
  "") ;;
  --diff|branche|branch) mode="diff"; base=$2 ;;
  --check) mode="check"; check_id=$2; check_version=$3 ;;
  -*) usage; exit 0 ;;
  *) mode="check"; check_id=$1; check_version=$2 ;;
esac
if [ "$mode" = "check" ] && [ -z "$check_id" ]; then
  usage
  exit 0
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/package-licenses.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

cat > "$tmp/rules" <<'EOF'
MediatR|13.0|any|COMMERCIAL|RPL-1.5 or Lucky Penny commercial license since 13.0 (July 2025); free Community edition only under 5M USD yearly revenue, with a license key|the in-house mediator or plain services; 12.5.0 is the last Apache-2.0 version
AutoMapper|15.0|any|COMMERCIAL|RPL-1.5 or Lucky Penny commercial license since 15.0 (July 2025); free Community edition only under 5M USD yearly revenue, with a license key|Mapperly (Apache-2.0), Mapster (MIT) or manual mapping; staying on 14.x is not an option: CVE-2026-32933 (high) is fixed only in 15.1.1 and 16.1.1
FluentAssertions|8.0|any|COMMERCIAL|Xceed commercial license since 8.0 (January 2025); free only for non-commercial use|stay on 7.x (Apache-2.0), or AwesomeAssertions (Apache-2.0 fork of 7.x, same API) or Shouldly (BSD-3)
MassTransit,MassTransit.*|9.0|any|COMMERCIAL|Commercial license (Massient) since 9.0 (2026)|stay on 8.x (Apache-2.0, security fixes announced until the end of 2026), then Rebus (MIT) or Wolverine (MIT)
Polly,Polly.*|9.0|direct|MAINTENANCE FEE|Open Source Maintenance Fee announced for the first major version released after 2026-11-16 (expected 9.0): 20 USD per month per organization earning 20k USD or more from a product that references Polly directly|stay on 8.x, or Microsoft.Extensions.Http.Resilience / Microsoft.Extensions.Resilience (not subject to the fee)
NPOI|2.8|any|MAINTENANCE FEE|EULA on the NuGet binaries since 2.8.0: maintenance fee for organizations with 10k USD yearly revenue or more (the source stays Apache-2.0)|stay on 2.7.x, or ClosedXML (MIT) or MiniExcel (Apache-2.0)
EPPlus|5.0|any|COMMERCIAL|PolyForm Noncommercial or commercial license since 5.0: any use in a company needs a paid license|ClosedXML (MIT) or MiniExcel (Apache-2.0)
QuestPDF|2022.12|any|COMMERCIAL|QuestPDF Community License only under 1M USD yearly revenue (never for listed companies or the public sector), otherwise a paid license|PdfSharp/MigraDoc (MIT)
SixLabors.ImageSharp|3.0|direct|COMMERCIAL|Six Labors Split License since 3.0: paid license for a direct reference by a company with 1M USD yearly revenue or more (free when only transitive)|stay on 2.1.x (Apache-2.0), or SkiaSharp (MIT) or Magick.NET (Apache-2.0)
SixLabors.ImageSharp.Web|3.0|direct|COMMERCIAL|Six Labors Split License since 3.0, same terms as ImageSharp|stay on 2.0.x (Apache-2.0)
SixLabors.ImageSharp.Drawing|2.0|direct|COMMERCIAL|Six Labors Split License, same terms as ImageSharp|SkiaSharp (MIT)
SixLabors.Fonts|2.0|direct|COMMERCIAL|Six Labors Split License since 2.0, same terms as ImageSharp|SkiaSharp (MIT)
Blazorise,Blazorise.*|0.9.4|any|COMMERCIAL|Commercial since 0.9.4 (July 2021); since 2023-07-15 every company needs a paid license per front-end developer whatever its size, contractors included for client work; the free Community license is only for eligible individual developers|native Razor (QuickGrid of Microsoft, MIT, and the forms of ASP.NET Core: the skill blazorise replaces it page by page, under bUnit tests), MudBlazor (MIT) or Radzen.Blazor (MIT); 0.9.3 is the last MIT version (outdated)
Duende.IdentityServer,Duende.IdentityServer.*|0|any|COMMERCIAL|Duende commercial license for production; free Community edition only under 1M USD yearly revenue, with a license key|OpenIddict (Apache-2.0), Keycloak or the company identity provider
itext,itext.*,itext7,itext7.*|0|any|AGPL|AGPL-3.0 or commercial license: in a closed-source application, AGPL means buying a license|PdfSharp/MigraDoc (MIT), or QuestPDF if eligible
iTextSharp|5.0|any|AGPL|AGPL-3.0 or commercial license since 5.0|iTextSharp.LGPLv2.Core (LGPL) or PdfSharp/MigraDoc (MIT)
EOF

# Parser of MSBuild files and packages.config, record = text between two "<".
# Prints "R|<id>|<version>|<file of the reference>|<file of the version>" for each direct reference, then "F|<files>".
cat > "$tmp/parse.awk" <<'EOF'
BEGIN { RS = "<"; nfiles = 0; cnt = 0 }
FNR == 1 {
  pending = ""; incomment = 0; nfiles++
  file = FILENAME
  if (strip != "" && index(file, strip) == 1) file = substr(file, length(strip) + 1)
}
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
  # Central versions (PackageVersion, PackageReference Update): the last one wins
  for (i = 1; i <= cnt; i++) {
    if (kindof[i] == "V" && verof[i] != "") { lid = tolower(idof[i]); cv[lid] = verof[i]; cf[lid] = fileof[i] }
  }
  for (i = 1; i <= cnt; i++) {
    if (kindof[i] != "R") continue
    v = verof[i]; vf = fileof[i]; lid = tolower(idof[i])
    if (v == "" && (lid in cv)) { v = cv[lid]; vf = cf[lid] }
    print "R|" idof[i] "|" resolve(v) "|" fileof[i] "|" vf
  }
  print "F|" nfiles
}
EOF

# Report. Input lines: R (direct reference), B (direct reference at the base), T (transitive), F (files), C (check).
cat > "$tmp/report.awk" <<'EOF'
BEGIN {
  FS = "[|]"
  while ((getline line < rules) > 0) {
    if (line == "" || substr(line, 1, 1) == "#") continue
    split(line, f, "[|]")
    nr++
    rpat[nr] = tolower(f[1]); rfrom[nr] = f[2]; rscope[nr] = f[3]; rkind[nr] = f[4]; rterms[nr] = f[5]; ralt[nr] = f[6]
  }
  close(rules)
}
$1 == "F" { nfiles += $2; next }
$1 == "R" {
  key = tolower($2) "|" $3
  if (!(key in seen)) { nref++; seen[key] = nref; rid[nref] = $2; rver[nref] = $3; rfile[nref] = $4; rvfile[nref] = $5 }
  else { i = seen[key]; if (index(", " rfile[i] ", ", ", " $4 ", ") == 0) rfile[i] = rfile[i] ", " $4 }
  if ($3 ~ /^[0-9][0-9A-Za-z.+-]*$/) direct[tolower($2) "|" $3] = 1
  else fuzzy[tolower($2)] = 1
  ndirect++
  next
}
$1 == "B" {
  bkey[tolower($2) "|" $3] = 1
  lid = tolower($2)
  if (!(lid in bver)) bver[lid] = $3
  else if (index(", " bver[lid] ", ", ", " $3 ", ") == 0) bver[lid] = bver[lid] ", " $3
  next
}
$1 == "T" {
  key = tolower($2) "|" $3
  if (!(key in tseen)) { tseen[key] = 1; nt++; tid[nt] = $2; tver[nt] = $3; tfile[nt] = $4 }
  next
}
$1 == "C" { cid = $2; cver = $3; next }
function rule_for(id,   i, k, n, p, lid, P) {
  lid = tolower(id)
  for (i = 1; i <= nr; i++) {
    n = split(rpat[i], P, ",")
    for (k = 1; k <= n; k++) {
      p = P[k]
      if (substr(p, length(p) - 1) == ".*") { if (index(lid, substr(p, 1, length(p) - 1)) == 1) return i }
      else if (lid == p) return i
    }
  }
  return 0
}
function normver(v,   lo, c, p) {
  gsub(/ /, "", v)
  if (v == "" || substr(v, 1, 2) == "$(") return ""
  c = substr(v, 1, 1)
  if (c == "[" || c == "(") {
    lo = substr(v, 2)
    p = index(lo, ","); if (!p) p = index(lo, "]"); if (!p) p = index(lo, ")")
    if (p) lo = substr(lo, 1, p - 1)
    if (lo == "") return ""
    v = lo
  }
  if (index(v, "*")) { sub(/\.?\*.*$/, "", v); if (v == "") return "*" }
  return v
}
function vcmp(a, b,   i, na, nb, x, y, A, B) {
  sub(/[-+].*$/, "", a); sub(/[-+].*$/, "", b)
  na = split(a, A, "."); nb = split(b, B, ".")
  for (i = 1; i <= 4; i++) {
    x = (i <= na) ? A[i] + 0 : 0
    y = (i <= nb) ? B[i] + 0 : 0
    if (x < y) return -1
    if (x > y) return 1
  }
  return 0
}
function verdict(r, ver,   v) {
  if (rfrom[r] == "0") return "ISSUE"
  v = normver(ver)
  if (v == "" || v == "*") return "UNKNOWN"
  return (vcmp(v, rfrom[r]) >= 0) ? "ISSUE" : "FREE"
}
function kindfrom(r) {
  return (rfrom[r] == "0") ? rkind[r] " (every version)" : rkind[r] " from " rfrom[r]
}
function describe(r, v) {
  if (v == "ISSUE") return kindfrom(r) ". " rterms[r] ". Free option: " ralt[r] "."
  if (v == "UNKNOWN") return "version unknown or floating, " kindfrom(r) ": check the version restored. " rterms[r] ". Free option: " ralt[r] "."
  return "free version; " kindfrom(r) ": do not upgrade without approval."
}
function files(list,   n, L, s) {
  n = split(list, L, ", ")
  s = L[1]
  if (n > 1) s = s ", " L[2]
  if (n > 2) s = s " +" (n - 2) " more"
  return s
}
function shown(v) { return (v == "") ? "(no version)" : v }
function where(i) {
  return files(rfile[i]) ((rvfile[i] != "" && index(", " rfile[i] ", ", ", " rvfile[i] ", ") == 0) ? "; version in " rvfile[i] : "")
}
END {
  if (mode == "check") {
    r = rule_for(cid)
    if (!r) { print cid (cver != "" ? " " cver : "") ": no known license issue in the list of this script (rules of " rdate "); still check the license of that exact version on nuget.org or in Artifactory before adding it."; exit }
    if (cver == "") { print cid ": " kindfrom(r) (rfrom[r] == "0" ? "" : ", earlier versions are free") ". " rterms[r] ". Free option: " ralt[r] "."; exit }
    print cid " " cver ": " describe(r, verdict(r, cver))
    exit
  }
  if (mode == "diff") {
    out = 0
    for (i = 1; i <= nref; i++) {
      lid = tolower(rid[i])
      if ((lid "|" rver[i]) in bkey) continue
      r = rule_for(rid[i])
      text = r ? describe(r, verdict(r, rver[i])) : "no known license issue"
      if (lid in bver) head = "~ " rid[i] " " bver[lid] " -> " shown(rver[i])
      else head = "+ " rid[i] " " shown(rver[i])
      if (!out) print "Package changes since " base " (direct references, working tree included):"
      print "- " head " [" where(i) "]: " text
      out++
    }
    if (!out) print "Package changes since " base ": none."
    exit
  }
  # scan
  n1 = n2 = n3 = n4 = 0
  for (i = 1; i <= nref; i++) {
    r = rule_for(rid[i]); if (!r) continue
    v = verdict(r, rver[i])
    line = "- " rid[i] " " shown(rver[i]) " [" where(i) "]: " describe(r, v)
    if (v == "ISSUE") L1[++n1] = line
    else if (v == "UNKNOWN") L2[++n2] = line
    else L3[++n3] = line
  }
  for (i = 1; i <= nt; i++) {
    if ((tolower(tid[i]) "|" tver[i]) in direct || (tolower(tid[i]) in fuzzy)) continue
    r = rule_for(tid[i]); if (!r || rscope[r] == "direct") continue
    if (verdict(r, tver[i]) != "ISSUE") continue
    L4[++n4] = "- (transitive) " tid[i] " " tver[i] " [" tfile[i] "]: " describe(r, "ISSUE") " Find the reference that brings it: dotnet nuget why <solution or project> " tid[i]
  }
  if (ndirect + 0 == 0 && nt + 0 == 0) { print "Package licenses (NuGet): no package reference in this repository."; exit }
  checked = "Checked: " (ndirect + 0) " direct references in " (nfiles + 0) " file(s); transitive: " (nassets > 0 ? nassets " obj/project.assets.json (state of the last restore)" : "not checked (no obj/project.assets.json: build once)") "."
  if (n1 + n2 + n3 + n4 == 0) {
    print "Package licenses (NuGet, rules of " rdate "): no known commercial, fee-based or AGPL package. " checked
    exit
  }
  print "Package licenses (NuGet, rules of " rdate "):"
  for (i = 1; i <= n1; i++) print L1[i]
  for (i = 1; i <= n2; i++) print L2[i]
  for (i = 1; i <= n4; i++) print L4[i]
  for (i = 1; i <= n3; i++) print L3[i]
  print checked
}
EOF

report() {
  awk -v mode="$mode" -v rules="$tmp/rules" -v rdate="$RULES_DATE" -v base="$base" -v nassets="${nassets:-0}" -f "$tmp/report.awk"
}

if [ "$mode" = check ]; then
  printf 'C|%s|%s\n' "$check_id" "$check_version" | report
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Package licenses: not a git repository"
  exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 0

pattern='\.(csproj|fsproj|vbproj|props|targets)$|(^|/)packages\.config$'

# parse <list of files> <prefix of the copies>: direct references of the files of the list
parse() {
  list=$1 prefix=$2
  set --
  while IFS= read -r f; do
    [ -f "$prefix$f" ] && set -- "$@" "$prefix$f"
  done < "$list"
  [ $# -eq 0 ] && return 0
  awk -v strip="$prefix" -f "$tmp/parse.awk" "$@"
}

git ls-files -co --exclude-standard | grep -E "$pattern" > "$tmp/files"

if [ "$mode" = diff ]; then
  if [ -z "$base" ]; then
    for candidate in origin/develop origin/main origin/master; do
      if git rev-parse -q --verify "$candidate" >/dev/null; then base=$candidate; break; fi
    done
  fi
  if [ -z "$base" ] || ! git rev-parse -q --verify "$base" >/dev/null; then
    echo "Package changes: no base branch found (origin/develop, origin/main or origin/master)."
    exit 0
  fi
  mb=$(git merge-base HEAD "$base" 2>/dev/null)
  if [ -z "$mb" ]; then
    echo "Package changes: no common commit with $base."
    exit 0
  fi
  git ls-tree -r --name-only "$mb" | grep -E "$pattern" > "$tmp/basefiles"
  while IFS= read -r f; do
    mkdir -p "$tmp/base/$(dirname "$f")"
    git show "$mb:$f" > "$tmp/base/$f" 2>/dev/null
  done < "$tmp/basefiles"
  {
    parse "$tmp/basefiles" "$tmp/base/" | sed -e '/^F|/d' -e 's/^R|/B|/'
    parse "$tmp/files" ""
  } | report
  exit 0
fi

# scan: direct references, then transitive packages of the last restore
find . \( -name node_modules -o -name .git \) -prune -o -name project.assets.json -print 2>/dev/null | sort > "$tmp/assets"
nassets=$(grep -c . "$tmp/assets")
{
  parse "$tmp/files" ""
  while IFS= read -r a; do
    sed -n 's/^ *"\([A-Za-z0-9_.+-]*\)\/\([0-9][^"]*\)": *{ *$/\1|\2/p' "$a" | sort -u | awk -v a="${a#./}" '{ print "T|" $0 "|" a }'
  done < "$tmp/assets"
} | report
exit 0
