#!/bin/sh
# For /outil liens (the wizard of the related repositories): which repositories of this machine belong to the same
# application as this one, what links them, then the files that declare it:
#   - AGENTS.md « ## Dépôts liés » of this repository: one line per related repository, its name and its role (its path
#     only when it is neither next to this repository nor a reference of this machine);
#   - the same section of the other repository, when the developer asks it (the line that names this one, its role
#     seen from there): written, never committed (its own /push does it);
#   - opencode.json of this machine, « references »: the agents of the pack may read its code (OpenCode reads it at
#     its start: restart it). A comment or the order of opencode.json are kept; a copy is saved first, and the file is
#     checked after the change (put back as it was when it does not read).
# A reference is a git repository of this machine, never the home folder or one of its parents, a hidden folder of it,
# a folder of the system, this repository or a folder inside it: the agents may read it, never write there.
#   scan                      this repository, the related ones declared (found or not, and how), the references of
#                             opencode.json, and the candidates: the git repositories next to it, with what links them
#                             (a package of one used by the other, the Jira keys of their commits, their names, the
#                             URL of the API in the front-end) and the role each could have, both ways
#   references                the references of opencode.json, "<name>\t<path>" (related-repos.sh reads them)
#   apply <name> <path> <role> [--reference] [--reciprocal <its role seen from there>]
#                             declares one related repository; --reference: in opencode.json too
#   remove <name> [--reference]
# Output: "THIS:", "DECLARED:", "REFERENCE:", "CANDIDATE:" and "ROLES:" lines (scan); "AGENTS.md:", "RECIPROCAL:",
# "OPENCODE.JSON:", "RESTART:" (apply); "STOP:" when an argument is not valid (nothing is changed then).
# Usage: related-setup.sh scan | references | apply <name> <path> "<role>" [--reference] [--reciprocal "<role>"]
#        | remove <name> [--reference]

LC_ALL=C
export LC_ALL
here=$(cd "$(dirname "$0")" && pwd)
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
# the main checkout (a worktree of an OpenCode workspace is elsewhere) and the folder that holds it
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir)
case "$common" in /*) ;; *) common="$root/$common" ;; esac
main=$(cd "$(dirname "$common")" && pwd -P)
parent=$(dirname "$main")
self=$(basename "$main")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/related-setup.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# ---------- opencode.json of this machine (JSON with comments, as OpenCode reads it) ----------
config_file() {
  dir=${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}
  for f in "$dir/opencode.jsonc" "$dir/opencode.json"; do [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }; done
  printf '%s\n' "$dir/opencode.json"
}
# The structure of a JSON-with-comments file, as lines "<kind>\t<start>\t<end>\t<name>" (offsets in bytes, from 1):
# root (the root object), key1 (a key of the root and its value), refs (the object of "references"), key2 (a key of
# references and its value); exit 1 when the braces do not balance
jscan() {
  awk 'BEGIN { RS = "\001" }
    {
      s = $0; n = length(s); depth = 0; i = 1; key = ""; want = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "/" && substr(s, i + 1, 1) == "/") { while (i <= n && substr(s, i, 1) != "\n") i++; continue }
        if (c == "/" && substr(s, i + 1, 1) == "*") { j = index(substr(s, i + 2), "*/"); if (!j) exit 1; i += j + 3; continue }
        if (c == "\"") {
          j = i + 1
          while (j <= n) { d = substr(s, j, 1); if (d == "\\") { j += 2; continue } if (d == "\"") break; j++ }
          str = substr(s, i + 1, j - i - 1)
          # a key: the next character that is not a space is a colon
          k = j + 1; while (k <= n && substr(s, k, 1) ~ /[ \t\r\n]/) k++
          if (substr(s, k, 1) == ":") { key = str; keystart = i; i = k + 1; want = 1; continue }
          if (want) { endvalue(j); want = 0 }
          i = j + 1; continue
        }
        if (c == "{" || c == "[") {
          depth++
          stack[depth] = c; kname[depth] = (want ? key : ""); kstart[depth] = (want ? keystart : i); vstart[depth] = i
          if (depth == 1) root = i
          want = 0
          i++; continue
        }
        if (c == "}" || c == "]") {
          if (depth == 2 && kname[2] != "") print "key1\t" kstart[2] "\t" i "\t" kname[2]
          if (depth == 2 && kname[2] == "references") print "refs\t" vstart[2] "\t" i "\t"
          if (depth == 3 && kname[3] != "" && kname[2] == "references") print "key2\t" kstart[3] "\t" i "\t" kname[3]
          if (depth == 1) print "root\t" root "\t" i "\t"
          depth--
          if (depth < 0) exit 1
          i++; continue
        }
        if (want && c !~ /[ \t\r\n,]/) {
          # a number, true, false or null
          j = i; while (j <= n && substr(s, j, 1) !~ /[,}\] \t\r\n]/) j++
          endvalue(j - 1); want = 0; i = j; continue
        }
        i++
      }
      if (depth != 0) exit 1
    }
    function endvalue(e) {
      if (depth == 1) print "key1\t" keystart "\t" e "\t" key
      if (depth == 2 && kname[2] == "references") print "key2\t" keystart "\t" e "\t" key
    }' "$1"
}
# the references of the file: "<name>\t<path>" (a string value, or the "path" of an object)
references() {
  f=$(config_file)
  [ -f "$f" ] || return 0
  jscan "$f" > "$tmp/scan" || return 0
  grep '^key2	' "$tmp/scan" | while IFS="$(printf '\t')" read -r _ a b n; do
    v=$(awk -v a="$a" -v b="$b" 'BEGIN { RS = "\001" } { print substr($0, a, b - a + 1) }' "$f")
    p=$(printf '%s' "$v" | tr '\n' ' ' | sed -n 's/^"[^"]*"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$p" ] || p=$(printf '%s' "$v" | tr '\n' ' ' | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$p" ] && printf '%s\t%s\n' "$n" "$p"
  done
}
expand() {
  # shellcheck disable=SC2088 # a literal ~ is expanded on purpose
  case "$1" in '~') printf '%s\n' "$HOME" ;; '~/'*) printf '%s\n' "$HOME/${1#'~/'}" ;; /*) printf '%s\n' "$1" ;; *) printf '%s\n' "$parent/$1" ;; esac
}
# ~/repos/x for a folder of the home folder (the form a teammate with the same layout shares)
# shellcheck disable=SC2088 # a literal ~ is written on purpose (opencode.json expands it)
tilde() { case "$1" in "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;; *) printf '%s\n' "$1" ;; esac; }

# ---------- what a repository is ----------
kind() {
  d=$1
  if git -C "$d" ls-files -- '*.csproj' 2>/dev/null | head -n 50 | while IFS= read -r p; do grep -q 'Sdk="Microsoft.NET.Sdk.Web"' "$d/$p" 2>/dev/null && { echo web; break; }; done | grep -q web; then
    echo "API .NET"; return 0
  fi
  pj=$(git -C "$d" ls-files -- 'package.json' '*/package.json' 2>/dev/null | grep -v node_modules | head -n 1)
  if [ -n "$pj" ]; then
    if grep -q '"@angular/core"' "$d/$pj" 2>/dev/null; then echo "front Angular"
    elif grep -q '"react"' "$d/$pj" 2>/dev/null; then echo "front React"
    elif grep -q '"vue"' "$d/$pj" 2>/dev/null; then echo "front Vue"
    else echo "front-end"; fi
    return 0
  fi
  if git -C "$d" ls-files -- '*.csproj' 2>/dev/null | head -n 50 | while IFS= read -r p; do grep -q -E '<PackageId>|<IsPackable>true' "$d/$p" 2>/dev/null && { echo lib; break; }; done | grep -q lib; then
    echo "librairie .NET"; return 0
  fi
  git -C "$d" ls-files -- '*.csproj' 2>/dev/null | grep -q . && { echo "application .NET"; return 0; }
  echo "dépôt"
}
# the package ids a repository publishes, one per line
packages_of() {
  git -C "$1" ls-files -- '*.csproj' 2>/dev/null | head -n 80 | while IFS= read -r p; do
    id=$(sed -n 's:.*<PackageId>\([^<]*\)</PackageId>.*:\1:p' "$1/$p" 2>/dev/null | head -n 1)
    if [ -z "$id" ] && grep -q '<IsPackable>true' "$1/$p" 2>/dev/null; then id=$(basename "$p" .csproj); fi
    [ -n "$id" ] && printf '%s\n' "$id"
  done | sort -u
}
# the packages a repository uses (PackageReference or PackageVersion), one per line
uses_of() {
  git -C "$1" ls-files -- '*.csproj' 'Directory.Packages.props' 2>/dev/null | head -n 120 | while IFS= read -r p; do
    sed -n -E 's:.*<Package(Reference|Version)[^>]*Include="([^"]*)".*:\2:p' "$1/$p" 2>/dev/null
  done | sort -u
}
# the Jira projects of the last commits (FACT-123 -> FACT), one per line
jira_of() {
  git -C "$1" log -200 --pretty=%s 2>/dev/null | grep -o -E '[A-Z][A-Z0-9]{1,9}-[0-9]+' | sed 's/-[0-9]*$//' | sort | uniq -c | awk '$1 >= 2 { print $2 }'
}
# the words of a name that say something (factures in api-factures)
words_of() { printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '\n' | grep -v -E '^(api|apis|front|frontend|back|backend|web|app|apps|ui|service|services|svc|lib|libs|core|common|shared|client|server|net|dotnet|ng|v[0-9]+|[0-9]*)$' | grep -E '..+'; }
# the local URLs of an API (launchSettings.json) and their ports
ports_of() {
  git -C "$1" ls-files -- '*launchSettings.json' 2>/dev/null | while IFS= read -r f; do
    sed -n 's/.*"applicationUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/$f" | tr ';' '\n' | sed -n 's#.*://[^:/]*:\([0-9][0-9]*\).*#\1#p'
  done | sort -u
}
# the URLs and ports a front-end calls (environment*.ts, proxy.conf*.json; never a .env file)
frontcalls_of() {
  git -C "$1" ls-files -- '*environment*.ts' '*proxy.conf*.json' '*proxy.conf*.js' 2>/dev/null | grep -v node_modules | head -n 20 | while IFS= read -r f; do
    grep -o -E 'https?://[A-Za-z0-9.-]+(:[0-9]+)?' "$1/$f" 2>/dev/null
  done | sort -u
}

# ---------- a folder that may be a reference ----------
# Why a folder may not be read by the agents, or nothing
unsafe() {
  t=$1
  [ -d "$t" ] || { echo "it is not a folder of this machine"; return; }
  t=$(cd "$t" && pwd -P)
  h=$(cd "$HOME" && pwd -P)
  case "$h/" in "$t"/*) echo "it is the home folder or one of its parents"; return ;; esac
  [ "$t" = "$h" ] && { echo "it is the home folder"; return; }
  case "$t" in "$h"/.*) echo "it is a hidden folder of the home folder (credentials live there)"; return ;; esac
  case "$t" in /|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*|/etc|/etc/*|/var|/var/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|/boot|/boot/*|/root|/root/*|/private/etc|/private/etc/*|/System|/System/*|/Library|/Library/*)
    echo "it is a folder of the system"; return ;;
  esac
  case "$t/" in "$main"/*) echo "it is this repository, or a folder inside it"; return ;; esac
  case "$main/" in "$t"/*) echo "it holds this repository"; return ;; esac
  top=$(git -C "$t" rev-parse --show-toplevel 2>/dev/null) || { echo "it is not a git repository"; return; }
  top=$(cd "$top" && pwd -P)
  [ "$top" = "$t" ] || { echo "it is a folder inside the repository $top: name its root"; return; }
}

case "$1" in
  references)
    references
    exit 0 ;;
  scan)
    this_kind=$(kind "$main")
    echo "THIS: $self — $main — $this_kind"
    references > "$tmp/refs"
    sh "$here/related-repos.sh" | sed 's/^RELATED: /DECLARED: /' | grep -v '^DECLARED: none'
    while IFS="$(printf '\t')" read -r n p; do
      [ -n "$n" ] && echo "REFERENCE: $n — $(expand "$p") (opencode.json of this machine)"
    done < "$tmp/refs"
    # the git repositories next to this one (and the references), with what links them
    packages_of "$main" > "$tmp/mine.packages"
    uses_of "$main" > "$tmp/mine.uses"
    jira_of "$main" > "$tmp/mine.jira"
    words_of "$self" > "$tmp/mine.words"
    ports_of "$main" > "$tmp/mine.ports"
    frontcalls_of "$main" > "$tmp/mine.calls"
    {
      for d in "$parent"/*/; do d=${d%/}; [ -e "$d/.git" ] && printf '%s\n' "$d"; done
      cut -f2 "$tmp/refs" | while IFS= read -r p; do [ -n "$p" ] && expand "$p"; done
    } | while IFS= read -r d; do
      [ -d "$d" ] || continue
      d=$(cd "$d" && pwd -P)
      [ "$d" = "$main" ] && continue
      git -C "$d" rev-parse --git-dir > /dev/null 2>&1 || continue
      printf '%s\n' "$d"
    done | sort -u | head -n 40 > "$tmp/candidates"
    declared=$(awk '/^## Dépôts liés/ { on = 1; next } /^## / { on = 0 } on && /^- / { l = $0; gsub(/`/, "", l); sub(/^- */, "", l); sub(/[ \t:(].*/, "", l); print l }' AGENTS.md 2>/dev/null)
    while IFS= read -r d; do
      n=$(basename "$d")
      k=$(kind "$d")
      ev=""
      pk=$(packages_of "$d")
      for id in $pk; do grep -qx -F "$id" "$tmp/mine.uses" && ev="$ev; this repository uses its package $id"; done
      uses_of "$d" > "$tmp/its.uses"
      while IFS= read -r id; do [ -n "$id" ] && grep -qx -F "$id" "$tmp/its.uses" && ev="$ev; it uses the package $id of this repository"; done < "$tmp/mine.packages"
      jira_of "$d" | while IFS= read -r j; do grep -qx -F "$j" "$tmp/mine.jira" && printf '%s\n' "$j"; done > "$tmp/common.jira"
      [ -s "$tmp/common.jira" ] && ev="$ev; the same Jira projects in their commits ($(tr '\n' ' ' < "$tmp/common.jira" | sed 's/ $//'))"
      words_of "$n" | while IFS= read -r w; do grep -qx -F "$w" "$tmp/mine.words" && printf '%s\n' "$w"; done > "$tmp/common.words"
      [ -s "$tmp/common.words" ] && ev="$ev; a common name ($(tr '\n' ' ' < "$tmp/common.words" | sed 's/ $//'))"
      # a front-end that calls the local port of this API, or this front-end that calls its port
      for port in $(ports_of "$main"); do frontcalls_of "$d" | grep -q ":$port\$" && ev="$ev; its front-end calls the local port $port of this API"; done
      for port in $(ports_of "$d"); do grep -q ":$port\$" "$tmp/mine.calls" && ev="$ev; this front-end calls its local port $port"; done
      is_declared=no
      printf '%s\n' "$declared" | grep -qx -F "$n" && is_declared=yes
      is_ref=no
      cut -f1 "$tmp/refs" | grep -qx -F "$n" && is_ref=yes
      score=$(printf '%s' "$ev" | tr -cd ';' | wc -c | tr -d ' ')
      printf '%s\tCANDIDATE: %s — %s — %s — evidence: %s — declared: %s — reference: %s\n' "$score" "$n" "$(tilde "$d")" "$k" "${ev#; }" "$is_declared" "$is_ref" |
        sed 's/evidence:  —/evidence: none —/'
    done < "$tmp/candidates" | sort -t "$(printf '\t')" -k1,1nr | cut -f2- | head -n 12
    echo "ROLES (seen from $self, then from the other one): an API and its front-end: « le front <framework> qui appelle cette API » / « l'API .NET que ce front appelle »; a library and its consumer: « la librairie <package> que ce dépôt utilise » / « un dépôt qui utilise cette librairie (paquet <package>) »; two APIs: « une autre API de la même application (<what it does>) »"
    exit 0 ;;
  apply|remove)
    action=$1
    name=$2
    [ -n "$name" ] || { echo "STOP: related-setup.sh $action <name> …"; exit 1; }
    case "$name" in *[!A-Za-z0-9._-]*|.*|"") echo "STOP: the name of a repository is letters, digits, . _ or - ($name)"; exit 1 ;; esac
    shift 2 ;;
  *)
    echo "STOP: related-setup.sh scan | references | apply <name> <path> \"<role>\" [--reference] [--reciprocal \"<role>\"] | remove <name> [--reference]"
    exit 1 ;;
esac

# ---------- writing ----------
# set_line <AGENTS.md file> <name> <line, empty to remove>: the line of <name> in « ## Dépôts liés » replaced (or added,
# or removed); the section created after « ## Project overview » (or before « ## Environnements » or « ## Build & test »,
# or at the end) when it is missing
set_line() {
  awk -v name="$2" -v line="$3" '
    function heading(l) { return l ~ /^## +D[ée]p[ôo]ts li[ée]s/ || l ~ /^## +D\303\251p\303\264ts li\303\251s/ }
    { lines[NR] = $0; if (heading($0)) has = 1 }
    END {
      for (n = 1; n <= NR; n++) {
        l = lines[n]
        if (l ~ /^## /) {
          if (insec && !done && line != "") { print line; done = 1; if (lines[n - 1] !~ /^[ \t]*$/) {} }
          if (!has && !done && line != "" && (l ~ /^## +(Environnements|Environments|Build)/ || after)) { print "## Dépôts liés"; print line; print ""; done = 1 }
          insec = heading(l); after = 0
          if (!has && l ~ /^## +Project overview/) after = 1
          print l; continue
        }
        if (insec && l ~ /^- /) {
          q = l; gsub(/`/, "", q); sub(/^- */, "", q); sub(/[ \t:(].*/, "", q)
          if (q == name) { if (!done && line != "") { print line; done = 1 } else if (line == "") { removed = 1 } ; continue }
        }
        if (insec && l ~ /^[ \t]*$/ && !done && line != "") {
          # the end of the section: the new line before its blank lines
          rest = 0; for (m = n; m <= NR && lines[m] ~ /^[ \t]*$/; m++) rest++
          if (m > NR || lines[m] ~ /^## /) { print line; done = 1 }
        }
        print l
      }
      if (!done && line != "") { if (!has) { print ""; print "## Dépôts liés" } print line }
    }' "$1" > "$tmp/agents.md" && cat "$tmp/agents.md" > "$1"
}
# The reference <name> -> <path> added to opencode.json (or its path changed), or removed (path empty); the file saved
# first and checked after
set_reference() {
  f=$(config_file)
  if [ ! -f "$f" ]; then
    [ -n "$2" ] || return 0
    echo "OPENCODE.JSON: $f does not exist: OpenCode has no configuration there (COMMANDES.md, « Lire un autre dépôt »); nothing written"
    return 1
  fi
  jscan "$f" > "$tmp/scan" || { echo "OPENCODE.JSON: $f does not read as JSON (a brace or a quote missing): nothing written; fix it first"; return 1; }
  cp "$f" "$f.before-outil-liens" || return 1
  desc=$(printf '%s' "$3" | sed 's/\\/\\\\/g; s/"/\\"/g')
  entry="\"$1\": { \"path\": \"$(tilde "$2")\", \"description\": \"$desc\" }"
  existing=$(awk -F '\t' -v n="$1" '$1 == "key2" && $4 == n { print $2 "\t" $3 }' "$tmp/scan" | head -n 1)
  refs=$(awk -F '\t' '$1 == "refs" { print $2 "\t" $3 }' "$tmp/scan" | head -n 1)
  rootpos=$(awk -F '\t' '$1 == "root" { print $2 }' "$tmp/scan" | head -n 1)
  [ -n "$rootpos" ] || { echo "OPENCODE.JSON: $f has no root object: nothing written"; return 1; }
  # (the entry through the environment: awk -v would read its backslashes as escapes)
  RELATED_ENTRY=$entry awk -v remove="$([ -n "$2" ] && echo 0 || echo 1)" -v existing="$existing" -v refs="$refs" -v rootpos="$rootpos" '
    BEGIN { RS = "\001"; entry = ENVIRON["RELATED_ENTRY"] }
    {
      s = $0
      if (existing != "") {
        split(existing, e, "\t"); a = e[1]; b = e[2]
        if (remove) {
          # the entry and the comma after it (or before it, for the last one)
          tail = substr(s, b + 1); sub(/^[ \t]*,/, "", tail)
          head = substr(s, 1, a - 1)
          if (tail ~ /^[ \t\r\n]*\}/) sub(/,[ \t\r\n]*$/, "", head)
          # no line left empty where the entry was
          sub(/[ \t]+$/, "", head)
          if (head ~ /\n$/ && tail ~ /^\r?\n/) sub(/^\r?\n/, "", tail)
          printf "%s%s", head, tail
        } else printf "%s%s%s", substr(s, 1, a - 1), entry, substr(s, b + 1)
      } else if (remove) {
        printf "%s", s
      } else if (refs != "") {
        split(refs, r, "\t"); op = r[1]; cl = r[2]
        inner = substr(s, op + 1, cl - op - 1)
        sep = (inner ~ /"/) ? "," : ""
        printf "%s\n    %s%s%s", substr(s, 1, op), entry, sep, substr(s, op + 1)
      } else {
        rest = substr(s, rootpos + 1)
        sep = (rest ~ /^[ \t\r\n]*\}/) ? "\n" : ","
        printf "%s\n  \"references\": {\n    %s\n  }%s%s", substr(s, 1, rootpos), entry, sep, rest
      }
    }' "$f" > "$tmp/opencode.json" || { echo "OPENCODE.JSON: the change of $f failed: nothing written"; return 1; }
  # the result must read, keep every section it had, and hold the reference as asked (or not hold it any more)
  if ! jscan "$tmp/opencode.json" > "$tmp/scan2" || ! grep -q '^root	' "$tmp/scan2"; then
    echo "OPENCODE.JSON: the change would break $f: nothing written (the copy $f.before-outil-liens is the file as it was)"
    return 1
  fi
  for k in $(awk -F '\t' '$1 == "key1" { print $4 }' "$tmp/scan"); do
    awk -F '\t' -v k="$k" '$1 == "key1" && $4 == k { found = 1 } END { exit !found }' "$tmp/scan2" ||
      { echo "OPENCODE.JSON: the change would lose the section $k of $f: nothing written"; return 1; }
  done
  before=$(grep -c '^key2	' "$tmp/scan") after=$(grep -c '^key2	' "$tmp/scan2")
  if [ -n "$2" ]; then
    awk -F '\t' -v n="$1" '$1 == "key2" && $4 == n { found = 1 } END { exit !found }' "$tmp/scan2" &&
      [ "$after" -ge "$before" ] || { echo "OPENCODE.JSON: the reference $1 is not where OpenCode reads it after the change: nothing written"; return 1; }
  elif [ -n "$existing" ]; then
    ! awk -F '\t' -v n="$1" '$1 == "key2" && $4 == n { found = 1 } END { exit !found }' "$tmp/scan2" &&
      [ "$after" -eq $((before - 1)) ] || { echo "OPENCODE.JSON: the reference $1 would not be removed cleanly: nothing written"; return 1; }
  else
    echo "OPENCODE.JSON: no reference $1 in $f: nothing to remove"
    return 1
  fi
  cat "$tmp/opencode.json" > "$f"
  return 0
}

if [ "$action" = remove ]; then
  ref=0
  [ "$1" = --reference ] && ref=1
  [ -f AGENTS.md ] && set_line AGENTS.md "$name" ""
  echo "AGENTS.md: $name removed from « ## Dépôts liés »"
  if [ "$ref" -eq 1 ]; then
    set_reference "$name" "" "" && echo "OPENCODE.JSON: reference $name removed ($(config_file); copy before the change: $(config_file).before-outil-liens)" && echo "RESTART: restart OpenCode: it reads its references at its start"
  fi
  exit 0
fi

# ---------- apply ----------
path=$1 role=$2
shift 2 2>/dev/null || { echo "STOP: related-setup.sh apply <name> <path> \"<role>\" [--reference] [--reciprocal \"<role>\"]"; exit 1; }
ref=0 recip=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reference) ref=1; shift ;;
    --reciprocal) [ -n "$2" ] || { echo "STOP: --reciprocal needs the role of this repository seen from the other one"; exit 1; }; recip=$2; shift 2 ;;
    *) echo "STOP: unknown option $1"; exit 1 ;;
  esac
done
[ -n "$role" ] || { echo "STOP: the role of $name (what it is for this repository)"; exit 1; }
case "$role$recip" in *'`'*|*'
'*) echo "STOP: a backquote or a new line in a role"; exit 1 ;; esac
target=$(expand "$path")
why=$(unsafe "$target")
[ -z "$why" ] || { echo "STOP: $path cannot be a related repository: $why"; exit 1; }
target=$(cd "$target" && pwd -P)
# the line: its path only when it is neither next to this repository nor a reference of this machine
line="- \`$name\` : $role"
if [ "$ref" -eq 0 ] && [ "$(dirname "$target")" != "$parent" ]; then
  line="- \`$name\` (\`$(tilde "$target")\`) : $role"
elif [ "$ref" -eq 0 ] && [ "$(basename "$target")" != "$name" ]; then
  line="- \`$name\` (\`$(tilde "$target")\`) : $role"
fi
if [ ! -f AGENTS.md ]; then
  printf '# %s\n\n## Dépôts liés\n' "$self" > AGENTS.md
  echo "AGENTS.md: created with its « ## Dépôts liés » section (/outil setup completes it)"
fi
set_line AGENTS.md "$name" "$line"
echo "AGENTS.md: $line"
if [ -n "$recip" ]; then
  if [ -f "$target/AGENTS.md" ]; then
    back="- \`$self\` : $recip"
    [ "$(dirname "$target")" = "$parent" ] || back="- \`$self\` (\`$(tilde "$main")\`) : $recip"
    set_line "$target/AGENTS.md" "$self" "$back"
    echo "RECIPROCAL: $target/AGENTS.md: $back (not committed: /push in a session of $name sends it)"
  else
    echo "RECIPROCAL: $target has no AGENTS.md: nothing written there (/outil setup in a session of $name writes it, with its « Dépôts liés »)"
  fi
fi
if [ "$ref" -eq 1 ]; then
  if set_reference "$name" "$target" "$role"; then
    echo "OPENCODE.JSON: reference $name -> $(tilde "$target") in $(config_file) (copy before the change: $(config_file).before-outil-liens)"
    echo "RESTART: restart OpenCode (COMMANDES.md, « Redémarrer OpenCode »): it reads its references at its start; then the agents read the code of $name, never write there"
  fi
fi
sh "$here/related-repos.sh" | grep -F -- "$name" | head -n 1
exit 0
