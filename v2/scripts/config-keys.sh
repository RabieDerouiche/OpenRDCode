#!/bin/sh
# For /doc: every configuration key of the repository, never a value (read-only). Sources: appsettings*.json and
# launchSettings.json (keys flattened like .NET configuration, "Section:Key", the items of an array as "[]"), web.config
# and app.config (appSettings keys, connection string names, applicationSettings names), .env.example files and the
# front-end environment*.ts files. For each key: its type (string, url, connection string, number, boolean, array of
# ...), "secret?" when its name or its type looks like a secret, and its state in each file of its folder: set,
# empty, or placeholder (a value replaced at deployment, like #{Name}, __Name__ or ${Name}). Test projects are left
# out. The values never leave this script: the documentation names keys, never what they contain.
# Usage: config-keys.sh

MAX_PER_GROUP=300

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Configuration keys: not a git repository"
  exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/config-keys.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# Configuration files that exist, without build outputs, dependencies and test projects; the base file first in
# each folder
git ls-files -co --exclude-standard | grep -v -E '(^|/)(bin|obj|node_modules|dist)/' |
  grep -v -i -E '(^|/)[^/]*tests?[^/]*/' |
  grep -i -E '(^|/)(appsettings[^/]*\.json|launchSettings\.json|(web|app)(\.[^/]*)?\.config|\.env\.(example|sample|template|dist)|environment[^/]*\.ts)$' |
  while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done |
  awk '{
    n = split($0, part, "/"); name = part[n]; dir = substr($0, 1, length($0) - length(name))
    low = tolower(name)
    rank = (low == "appsettings.json" || low == "web.config" || low == "app.config" || low == "environment.ts") ? 0 : 1
    print dir "\t" rank "\t" low "\t" $0
  }' | sort | cut -f4 > "$tmp/files"

echo "## Configuration keys (values never shown; state per file: set, empty, or placeholder = replaced at deployment)"
if [ ! -s "$tmp/files" ]; then
  echo "- no configuration file (appsettings, launchSettings, web.config, app.config, .env.example, environment.ts)"
  exit 0
fi

cat > "$tmp/keys.awk" <<'EOF'
# ---------- recording ----------
# One line per key of a group; its state per file of the group (the best one when an array repeats it: set, then
# placeholder, then empty)
function record(path, type, state, secret,   k) {
  if (path == "") return
  k = G SUBSEP tolower(path)
  if (!(k in types)) {
    count[G]++
    order[G, count[G]] = path
    types[k] = type
  } else if ((types[k] == "null" && type != "null") || (types[k] == "string" && type != "null" && type != "string" && type !~ /^array/)) types[k] = type
  if (secret && type != "boolean" && type != "number" && type != "section") secrets[k] = 1
  if (!((k, L) in fstate) || rank[state] > rank[fstate[k, L]]) fstate[k, L] = state
}
function looks_secret(path,   low, n, seg, last) {
  low = tolower(path)
  if (low ~ /^connectionstrings:/) return 1
  n = split(low, seg, ":")
  last = seg[n]
  sub(/\[\]$/, "", last)
  if (last ~ /(partition|sort|cache|row|routing|primary|foreign|idempotency|lookup|unique|object|s3|bucket|prefix)key$/) return 0
  if (last ~ /password|passwd|pwd|secret|apikey|api_key|accesskey|access_key|privatekey|private_key|credential|connectionstring|signingkey|encryptionkey|passphrase|salt|sastoken|token$|tokens$|sas$|keys?$|certificate$|pfx$/) return 1
  return 0
}
function string_type(s,   low) {
  low = tolower(s)
  if (low ~ /^[a-z][a-z0-9+.-]*:\/\/[^\/@]+:[^\/@]*@/) return "url with credentials"
  if (low ~ /^[a-z][a-z0-9+.-]*:\/\//) return "url"
  if (low ~ /(^|;)[ ]*(server|data source|host|initial catalog|database|user id|uid|accountkey|accountname|endpoint|defaultendpointsprotocol|sharedaccesskey)[ ]*=/) return "connection string"
  if (low ~ /(^|[;,])[ ]*password[ ]*=/) return "connection string"
  return "string"
}
function string_state(s,   low) {
  if (s == "") return "empty"
  low = tolower(s)
  if (s ~ /^#[{][^}]*[}]#?$/ || s ~ /^__[A-Za-z0-9_.-]+__$/ || s ~ /^[$][{(][^})]*[})]$/ || s ~ /^%[A-Za-z0-9_]+%$/ || s ~ /^[{][{][^}]*[}][}]$/ || s ~ /^<[^>]*>$/) return "placeholder"
  if (low ~ /^(changeme|change_me|change-me|todo|tbd|to_be_defined|xxx+|[*][*][*]+|secret|password)$/) return "placeholder"
  return "set"
}

# ---------- JSON (comments and trailing commas accepted, like the .NET configuration) ----------
function joinseg(p, s) { if (s == "[]") return p "[]"; return (p == "") ? s : p ":" s }
function pathof(d, extra,   p, k) {
  p = ""
  for (k = 2; k <= d; k++) p = joinseg(p, segs[k])
  if (extra != "") p = joinseg(p, extra)
  return p
}
function json_open(c,   seg) {
  seg = ""
  if (depth > 0) {
    seg = (typ[depth] == "o") ? key : "[]"
    has[depth] = 1
    if (typ[depth] == "a") aobj[depth] = 1
  }
  depth++
  typ[depth] = (c == "{") ? "o" : "a"
  segs[depth] = seg
  has[depth] = 0; ascalar[depth] = ""; aobj[depth] = 0; aset[depth] = 0
  expect = (c == "{") ? "key" : "value"
}
function json_close(   p) {
  if (depth == 0) return
  if (depth > 1) {
    p = pathof(depth, "")
    if (typ[depth] == "a") {
      if (!aobj[depth]) record(p, (ascalar[depth] == "" ? "array" : "array of " ascalar[depth]), (aset[depth] ? "set" : "empty"), looks_secret(p))
    } else if (!has[depth]) record(p, "section", "empty", 0)
  }
  depth--
  if (depth > 0 && typ[depth] == "o") expect = "after"
}
function json_value(type, state,   p, base) {
  if (depth == 0) return
  has[depth] = 1
  if (typ[depth] == "a") {
    base = (type == "url" || type == "url with credentials" || type == "connection string") ? "string" : type
    if (ascalar[depth] == "" || ascalar[depth] == "null") ascalar[depth] = base
    else if (base != "null" && ascalar[depth] != base) ascalar[depth] = "mixed values"
    if (state != "empty") aset[depth] = 1
    return
  }
  if (expect != "value") return
  p = pathof(depth, key)
  record(p, type, state, looks_secret(p) || type == "connection string" || type == "url with credentials")
  expect = "after"
}
function json_line(line,   i, j, len, c, d, s, lit) {
  len = length(line)
  i = 1
  while (i <= len) {
    c = substr(line, i, 1)
    if (incomment) {
      j = index(substr(line, i), "*/")
      if (j == 0) return
      i += j + 1
      incomment = 0
      continue
    }
    if (c == " " || c == "\t" || c == "\r") { i++; continue }
    if (c == "/") {
      d = substr(line, i + 1, 1)
      if (d == "/") return
      if (d == "*") { incomment = 1; i += 2; continue }
      i++
      continue
    }
    if (c == "\"") {
      j = i + 1
      while (j <= len) {
        d = substr(line, j, 1)
        if (d == "\\") { j += 2; continue }
        if (d == "\"") break
        j++
      }
      s = substr(line, i + 1, j - i - 1)
      i = j + 1
      if (depth > 0 && typ[depth] == "o" && expect == "key") { key = s; expect = "colon" }
      else json_value(string_type(s), string_state(s))
      continue
    }
    if (c == "{" || c == "[") { json_open(c); i++; continue }
    if (c == "}" || c == "]") { json_close(); i++; continue }
    if (c == ":") { if (depth > 0 && typ[depth] == "o") expect = "value"; i++; continue }
    if (c == ",") { if (depth > 0 && typ[depth] == "o") expect = "key"; i++; continue }
    j = i
    while (j <= len && index(" \t\r,:{}[]\"/", substr(line, j, 1)) == 0) j++
    lit = substr(line, i, j - i)
    i = j
    if (lit == "true" || lit == "false") json_value("boolean", "set")
    else if (lit == "null") json_value("null", "empty")
    else if (lit ~ /^-?[0-9]/) json_value("number", "set")
  }
}

# ---------- XML configuration (web.config, app.config and their transforms) ----------
function attr(element, name,   rest) {
  if (!match(element, "[ \t]" name "[ \t]*=[ \t]*\"[^\"]*\"")) return ""
  rest = substr(element, RSTART, RLENGTH)
  sub(/^[^"]*"/, "", rest)
  sub(/"$/, "", rest)
  return rest
}
function has_attr(element, name) { return match(element, "[ \t]" name "[ \t]*=") > 0 }
function in_settings(   i, low) {
  for (i = 1; i <= xdepth; i++) {
    low = tolower(xstack[i])
    if (low == "applicationsettings" || low == "usersettings") return 1
  }
  return 0
}
function xml_element(element,   low, nm, top, k, v, p) {
  low = tolower(element)
  if (low ~ /^<[?!]/) return
  if (low ~ /^<\//) { if (xdepth > 0) xdepth--; return }
  nm = element
  sub(/^</, "", nm)
  sub(/[ \t\/>].*$/, "", nm)
  top = (xdepth > 0) ? xstack[xdepth] : ""
  if (tolower(nm) == "add") {
    if (tolower(top) == "connectionstrings" || has_attr(element, "connectionString")) {
      k = attr(element, "name")
      if (k != "") {
        v = attr(element, "connectionString")
        record("connectionStrings:" k, "connection string", has_attr(element, "connectionString") ? string_state(v) : "set", 1)
      }
    } else if (has_attr(element, "key")) {
      k = attr(element, "key")
      if (k != "") {
        v = attr(element, "value")
        p = (top == "" ? "" : top ":") k
        record(p, string_type(v), has_attr(element, "value") ? string_state(v) : "set", looks_secret(p) || string_type(v) ~ /connection string|credentials/)
      }
    }
  } else if (tolower(nm) == "setting" && in_settings()) {
    k = attr(element, "name")
    if (k != "") { p = "applicationSettings:" k; record(p, "string", "set", looks_secret(p)) }
  }
  if (element !~ /\/[ \t]*>$/) { xdepth++; xstack[xdepth] = nm }
}
function xml_line(line,   start, stop) {
  pending = pending (pending == "" ? "" : " ") line
  while ((start = index(pending, "<")) > 0) {
    pending = substr(pending, start)
    if (substr(pending, 1, 4) == "<!--") {
      stop = index(pending, "-->")
      if (stop == 0) return
      pending = substr(pending, stop + 3)
      continue
    }
    stop = index(pending, ">")
    if (stop == 0) return
    xml_element(substr(pending, 1, stop))
    pending = substr(pending, stop + 1)
  }
  pending = ""
}

# ---------- .env.example ----------
function dotenv_line(line,   k, v) {
  sub(/^[ \t]*export[ \t]+/, "", line)
  if (line !~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=/) return
  k = line
  sub(/^[ \t]*/, "", k)
  sub(/[ \t]*=.*/, "", k)
  v = line
  sub(/^[^=]*=[ \t]*/, "", v)
  sub(/[ \t]+#.*$/, "", v)
  sub(/^["']/, "", v)
  sub(/["'][ \t]*$/, "", v)
  record(k, string_type(v), string_state(v), looks_secret(k) || string_type(v) ~ /connection string|credentials/)
}

# ---------- front-end environment*.ts: "name: value" lines, "name: {" opens a level, "}" closes it ----------
function ts_line(line,   k, v, p, i, q, t, j) {
  if (match(line, /^[ \t]*['"]?[A-Za-z_$][A-Za-z0-9_$]*['"]?[ \t]*:/)) {
    k = substr(line, RSTART, RLENGTH)
    gsub(/[ \t'":]/, "", k)
    v = substr(line, RSTART + RLENGTH)
    sub(/^[ \t]*/, "", v)
    if (v ~ /^[{]/ && v !~ /[}]/) { tsdepth++; tsseg[tsdepth] = k; return }
    p = ""
    for (i = 1; i <= tsdepth; i++) p = p tsseg[i] ":"
    p = p k
    q = substr(v, 1, 1)
    if (q == "'" || q == "\"" || q == "`") {
      t = substr(v, 2)
      j = index(t, q)
      if (j > 0) t = substr(t, 1, j - 1)
      record(p, string_type(t), string_state(t), looks_secret(p) || string_type(t) ~ /connection string|credentials/)
      return
    }
    sub(/[ \t]*\/\/.*$/, "", v)
    sub(/[ \t]*,?[ \t]*$/, "", v)
    if (v == "true" || v == "false") record(p, "boolean", "set", 0)
    else if (v ~ /^-?[0-9]/) record(p, "number", "set", 0)
    else if (v ~ /^\[/) record(p, "array", "set", looks_secret(p))
    else record(p, "expression", "set", looks_secret(p))
    return
  }
  if (tsdepth > 0 && line ~ /^[ \t]*[}]/) tsdepth--
}

# ---------- files ----------
BEGIN { rank["empty"] = 0; rank["placeholder"] = 1; rank["set"] = 2 }
FNR == 1 {
  file = FILENAME
  n = split(file, part, "/")
  name = part[n]
  low = tolower(name)
  dir = substr(file, 1, length(file) - length(name))
  if (dir == "") dir = "./"
  label = ""
  if (low == "launchsettings.json") { kind = "json"; G = dir " launchSettings"; what = "local run profiles"; L = "launchSettings" }
  else if (low ~ /^appsettings/) {
    kind = "json"; G = dir " appsettings"; what = "application settings"
    L = (low == "appsettings.json") ? "base" : substr(name, 13, length(name) - 17)
    label = L
  } else if (low ~ /\.config$/) {
    kind = "xml"; G = dir " " substr(low, 1, 3); what = "XML configuration"
    L = (low == "web.config" || low == "app.config") ? "base" : substr(name, 5, length(name) - 11)
    label = L
  } else if (low ~ /^\.env\./) { kind = "dotenv"; G = dir " " name; what = "environment variables"; L = name }
  else {
    kind = "ts"; G = dir " environment.ts"; what = "front-end environment"
    L = (low == "environment.ts") ? "base" : substr(name, 13, length(name) - 15)
    label = L
  }
  if (!(G in gfiles)) { ng++; gorder[ng] = G; gdir[G] = dir; gwhat[G] = what }
  gfiles[G] = gfiles[G] (gfiles[G] == "" ? "" : ", ") name (label == "" ? "" : " (" label ")")
  nfiles[G]++
  glabel[G, nfiles[G]] = L
  depth = 0; expect = ""; key = ""; incomment = 0; pending = ""; xdepth = 0; tsdepth = 0
  sub(/^\357\273\277/, "")
}
kind == "json" { json_line($0); next }
kind == "xml" { xml_line($0); next }
kind == "dotenv" { dotenv_line($0); next }
kind == "ts" { ts_line($0); next }

END {
  for (g = 1; g <= ng; g++) {
    G = gorder[g]
    print ""
    print "### " gdir[G] " - " gwhat[G] ": " gfiles[G]
    if (count[G] == 0) { print "- no key"; continue }
    shown = (count[G] > MAX) ? MAX : count[G]
    for (i = 1; i <= shown; i++) {
      path = order[G, i]
      k = G SUBSEP tolower(path)
      line = ""
      for (f = 1; f <= nfiles[G]; f++) {
        if ((k, glabel[G, f]) in fstate) line = line (line == "" ? "" : ", ") glabel[G, f] " " fstate[k, glabel[G, f]]
      }
      print "- " path " (" types[k] ((k in secrets) ? ", secret?" : "") "): " line
    }
    if (count[G] > MAX) print "- +" (count[G] - MAX) " more keys"
  }
}
EOF

tr '\n' '\0' < "$tmp/files" | xargs -0 awk -v MAX="$MAX_PER_GROUP" -f "$tmp/keys.awk"
exit 0
