#!/bin/sh
# For /doc: the HTTP endpoints of the repository, computed from its C# code (read-only).
# - Controllers (attribute routing): class route + action route, [controller], [action] and [area] replaced, a route
#   starting with "/" or "~/" kept as it is, routes and [Authorize] inherited from base classes in the repository,
#   [Route] without verb = any verb, no route at all = conventional routing.
# - Minimal APIs: MapGet, MapPost, MapPut, MapPatch, MapDelete, MapMethods, with the prefixes of their MapGroup, also
#   when the group is passed to an extension method (this IEndpointRouteBuilder / RouteGroupBuilder / WebApplication);
#   MapHub, MapHealthChecks and MapGrpcService.
# For each endpoint: verb, route, action or handler with its line, authorization, parameters (services and
# cancellation tokens left out), response type and statuses, XML documentation summary or WithSummary. What cannot be
# computed (a route held in a constant, a group passed as an argument, an attribute outside a controller) is listed
# at the end with its file and line. Test projects are left out. At most MAX_ROWS endpoints are printed: for a larger
# repository, run it again for one folder at a time.
# Usage: api-routes.sh [folder]

MAX_ROWS=300

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "HTTP endpoints: not a git repository"
  exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 0
folder=${1#./}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/api-routes.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

git ls-files -co --exclude-standard -- '*.cs' | grep -v -E '(^|/)(bin|obj)/' | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' |
  while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done > "$tmp/all"
# the extension methods are looked for everywhere, the endpoints only in the folder asked
if [ -n "$folder" ]; then
  awk -v p="$folder" 'index($0, p) == 1' "$tmp/all" > "$tmp/cs"
else
  cp "$tmp/all" "$tmp/cs"
fi

# Extension methods that map endpoints on a route builder: their calls carry the prefix of the group they extend
exts=""
if [ -s "$tmp/all" ]; then
  exts=$(tr '\n' '\0' < "$tmp/all" |
    xargs -0 grep -h -o -E 'static[^(=;]*[[:space:]][A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([[:space:]]*this[[:space:]]+(IEndpointRouteBuilder|RouteGroupBuilder|WebApplication|IApplicationBuilder)[[:space:]]' 2>/dev/null |
    sed -E 's/[[:space:]]*\([[:space:]]*this[[:space:]].*//; s/.*[[:space:]]//' | grep -v -E '^Map(Get|Post|Put|Patch|Delete|Methods|Group)$' | sort -u | tr '\n' '|' | sed 's/|$//')
fi

pattern='\[(Http(Get|Post|Put|Patch|Delete|Head|Options)|Route|RoutePrefix|AcceptVerbs|ApiController|Controller\])|Controller([^A-Za-z0-9_]|$)|\.Map(Get|Post|Put|Patch|Delete|Methods|Group|Controllers|ControllerRoute|AreaControllerRoute|DefaultControllerRoute|Route|HttpRoute|Hub|HealthChecks|GrpcService)[[:space:]]*[(<]|this[[:space:]]+(IEndpointRouteBuilder|RouteGroupBuilder|WebApplication|IApplicationBuilder)[[:space:]]'
[ -n "$exts" ] && pattern="$pattern|\\.($exts)[[:space:]]*\\("
: > "$tmp/files"
[ -s "$tmp/cs" ] && tr '\n' '\0' < "$tmp/cs" | xargs -0 grep -l -E "$pattern" 2>/dev/null | sort > "$tmp/files"

if [ ! -s "$tmp/files" ]; then
  echo "## HTTP endpoints (computed from the code${folder:+, folder $folder})"
  echo "- no controller and no minimal API in the C# code"
  exit 0
fi

cat > "$tmp/routes.awk" <<'EOF'
# ---------- text helpers ----------
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function squeeze(s) { gsub(/[ \t]+/, " ", s); return trim(s) }
function cell(s) { s = squeeze(s); gsub(/\|/, "\\|", s); if (length(s) > 160) s = substr(s, 1, 157) "..."; return s == "" ? "-" : s }
function newlit(text) { nl++; lit[nl] = text; return "\"#" nl "#\"" }
function restore(s,   out, n) {
  out = ""
  while (match(s, /"#[0-9]+#"/)) {
    n = substr(s, RSTART + 2, RLENGTH - 4)
    out = out substr(s, 1, RSTART - 1) "\"" lit[n] "\""
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}
# The value of a string literal argument, or <expression> when it is not a literal
function litval(arg) {
  arg = trim(arg)
  sub(/^template[ \t]*:[ \t]*/, "", arg)
  if (arg ~ /^"#[0-9]+#"$/) return lit[substr(arg, 3, length(arg) - 4)]
  return arg == "" ? "" : "<" restore(arg) ">"
}
# Splits s at the commas outside (), [], {} (and <> when angle is 1)
function split_args(s, arr, angle,   n, i, c, d, start) {
  n = 0; d = 0; start = 1
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(" || c == "[" || c == "{" || (angle && c == "<")) d++
    else if (c == ")" || c == "]" || c == "}" || (angle && c == ">")) d--
    else if (c == "," && d == 0) { arr[++n] = trim(substr(s, start, i - start)); start = i + 1 }
  }
  if (trim(substr(s, start)) != "" || n > 0) arr[++n] = trim(substr(s, start))
  return n
}
# s starts (after spaces) with the opening character: the text up to its matching closing character, both included
function take_balanced(s, op, cl,   i, c, d, first) {
  d = 0; first = 0; tb_ok = 1
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == op) { d++; first = 1 }
    else if (c == cl) { d--; if (first && d == 0) return substr(s, 1, i) }
  }
  tb_ok = 0
  return s
}
function inner(s, op, cl,   t) {
  t = take_balanced(substr(s, index(s, op)), op, cl)
  return substr(t, 2, length(t) - 2)
}
function first_arg(args,   a, n) { n = split_args(args, a, 1); return n > 0 ? a[1] : "" }

# ---------- C# lines: comments removed, every string literal replaced by "#n#" (its text in lit[n]) ----------
function sanitize(s,   out, i, n, c, j, k, pre, content, d2) {
  if (!inblock && !inverb && !inraw && s !~ /["'\/@$]/) return s
  out = ""; i = 1; n = length(s)
  while (i <= n) {
    if (inblock) { j = index(substr(s, i), "*/"); if (j == 0) return out; i += j + 1; inblock = 0; continue }
    if (inraw) {
      j = index(substr(s, i), "\"\"\"")
      if (j == 0) return out
      i += j + 2
      while (substr(s, i, 1) == "\"") i++
      inraw = 0; out = out newlit(""); continue
    }
    if (inverb) {
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\"") { if (substr(s, i + 1, 1) == "\"") { verbtext = verbtext c; i += 2; continue }; break }
        verbtext = verbtext c; i++
      }
      if (i > n) { verbtext = verbtext " "; return out }
      i++; inverb = 0; out = out newlit(verbtext); continue
    }
    c = substr(s, i, 1)
    if (c == "/" && substr(s, i + 1, 1) == "/") return out
    if (c == "/" && substr(s, i + 1, 1) == "*") { inblock = 1; i += 2; continue }
    if (c == "'") {
      j = i + 1
      if (substr(s, j, 1) == "\\") j += 2; else j++
      while (j <= n && substr(s, j, 1) != "'") j++
      out = out "' '"; i = j + 1; continue
    }
    if (c == "\"" || c == "@" || c == "$") {
      j = i; pre = ""
      while (j <= n && (substr(s, j, 1) == "@" || substr(s, j, 1) == "$")) { pre = pre substr(s, j, 1); j++ }
      if (substr(s, j, 1) != "\"") { out = out c; i++; continue }
      if (substr(s, j, 3) == "\"\"\"") {
        k = index(substr(s, j + 3), "\"\"\"")
        if (k == 0) { inraw = 1; return out }
        out = out newlit(substr(s, j + 3, k - 1))
        i = j + 3 + k + 2
        while (substr(s, i, 1) == "\"") i++
        continue
      }
      if (index(pre, "@")) {
        k = j + 1; content = ""
        while (k <= n) {
          c = substr(s, k, 1)
          if (c == "\"") { if (substr(s, k + 1, 1) == "\"") { content = content c; k += 2; continue }; break }
          content = content c; k++
        }
        if (k > n) { inverb = 1; verbtext = content " "; return out }
        out = out newlit(content); i = k + 1; continue
      }
      k = j + 1
      while (k <= n) {
        c = substr(s, k, 1)
        if (c == "\\") { k += 2; continue }
        if (index(pre, "$") && c == "{") {
          if (substr(s, k + 1, 1) == "{") { k += 2; continue }
          d2 = 1; k++
          while (k <= n && d2 > 0) {
            c = substr(s, k, 1)
            if (c == "{") d2++
            else if (c == "}") d2--
            else if (c == "\"") { k++; while (k <= n && substr(s, k, 1) != "\"") { if (substr(s, k, 1) == "\\") k++; k++ } }
            k++
          }
          continue
        }
        if (c == "\"") break
        k++
      }
      out = out newlit(substr(s, j + 1, k - j - 1)); i = k + 1; continue
    }
    out = out c; i++
  }
  return out
}

# ---------- attributes ----------
# Appends the attributes at the start of t to attrs (one element per attribute, separated by \036); returns the rest
function take_attributes(t,   block, body, n, a, i) {
  while (substr(t, 1, 1) == "[") {
    block = take_balanced(t, "[", "]")
    if (!tb_ok) { attropen = t; return "" }
    body = substr(block, 2, length(block) - 2)
    if (attrline == 0) attrline = FNR
    n = split_args(body, a, 1)
    for (i = 1; i <= n; i++) attrs = attrs (attrs == "" ? "" : "\036") a[i]
    t = trim(substr(t, length(block) + 1))
  }
  return t
}
function attr_name(el,   nm) {
  nm = el
  sub(/[ \t]*[(<].*$/, "", nm)
  sub(/^.*\./, "", nm)
  sub(/Attribute$/, "", nm)
  return nm
}
function attr_args(el,   rest) {
  rest = el
  sub(/^[A-Za-z_][A-Za-z0-9_.]*[ \t]*/, "", rest)
  if (substr(rest, 1, 1) == "<") rest = substr(rest, length(take_balanced(rest, "<", ">")) + 1)
  rest = trim(rest)
  if (substr(rest, 1, 1) != "(") return ""
  return inner(rest, "(", ")")
}
function attr_generic(el,   rest) {
  rest = el
  sub(/^[A-Za-z_][A-Za-z0-9_.]*[ \t]*/, "", rest)
  if (substr(rest, 1, 1) != "<") return ""
  return inner(rest, "<", ">")
}
function describe_auth(args,   n, a, i, x, out) {
  if (trim(args) == "") return "authenticated"
  n = split_args(args, a, 1)
  out = ""
  for (i = 1; i <= n; i++) {
    x = a[i]
    if (x ~ /^Policy[ \t]*=/) { sub(/^Policy[ \t]*=[ \t]*/, "", x); x = "policy " litval(x) }
    else if (x ~ /^Roles[ \t]*=/) { sub(/^Roles[ \t]*=[ \t]*/, "", x); x = "roles " litval(x) }
    else if (x ~ /^AuthenticationSchemes[ \t]*=/) { sub(/^AuthenticationSchemes[ \t]*=[ \t]*/, "", x); x = "schemes " litval(x) }
    else x = "policy " litval(x)
    out = out (out == "" ? "" : ", ") x
  }
  return out
}
function add_auth(list, x) {
  if (x == "") return list
  if (list == "" || list == "-") return x
  if (index(" + " list " + ", " + " x " + ")) return list
  return list " + " x
}
function status_of(x,   low) {
  x = trim(x)
  sub(/^\(int\)[ \t]*/, "", x)
  if (x ~ /^[0-9][0-9][0-9]$/) return x
  if (match(x, /Status[0-9][0-9][0-9]/)) return substr(x, RSTART + 6, 3)
  low = tolower(x)
  sub(/^.*\./, "", low)
  if (low == "ok") return "200"
  if (low == "created") return "201"
  if (low == "accepted") return "202"
  if (low == "nocontent") return "204"
  if (low == "badrequest") return "400"
  if (low == "unauthorized") return "401"
  if (low == "forbidden") return "403"
  if (low == "notfound") return "404"
  if (low == "conflict") return "409"
  if (low == "unprocessableentity") return "422"
  return ""
}
# ProducesResponseType(typeof(T), 200) / ProducesResponseType<T>(200) / ProducesResponseType(404): "200 T" or "404"
function produces(el,   args, a, n, i, type, st) {
  args = attr_args(el)
  type = attr_generic(el)
  n = split_args(args, a, 1)
  st = ""
  for (i = 1; i <= n; i++) {
    if (a[i] ~ /^typeof[ \t]*\(/) type = inner(a[i], "(", ")")
    else if (a[i] ~ /^(type|Type)[ \t]*[:=][ \t]*typeof/) type = inner(a[i], "(", ")")
    else if (st == "") st = status_of(a[i])
  }
  if (st == "") st = (type != "") ? "200" : ""
  return trim(st " " type)
}

# ---------- types and parameters ----------
function unwrap(t,   again, n, a, i, x) {
  t = squeeze(t)
  do {
    again = 0
    if (t ~ /^(Task|ValueTask|ActionResult|Ok|Created|CreatedAtRoute|CreatedAtAction|Accepted)<.*>$/) { t = trim(inner(t, "<", ">")); again = 1 }
    else if (t ~ /^Results<.*>$/) {
      n = split_args(inner(t, "<", ">"), a, 1)
      x = ""
      for (i = 1; i <= n; i++) if (a[i] ~ /^(Ok|Created|CreatedAtRoute|Accepted)<.*>$/) { x = a[i]; break }
      t = x; again = (x != "")
    }
  } while (again)
  if (t ~ /^(Task|ValueTask|void|IActionResult|ActionResult|IResult|IHttpActionResult|HttpResponseMessage|Results<.*>|Ok|NoContent|NotFound|BadRequest)$/) t = ""
  return t
}
function is_service(p,   x) {
  x = p
  if (x ~ /\[FromServices\]/) return 1
  gsub(/\[[^]]*\][ \t]*/, "", x)
  x = trim(x)
  sub(/^(this|params|ref|out|in)[ \t]+/, "", x)
  if (x ~ /^(CancellationToken|HttpContext|HttpRequest|HttpResponse|ClaimsPrincipal|ILogger|IMediator|ISender|IPublisher|IMapper|IConfiguration)([ \t<?]|$)/) return 1
  if (x ~ /^I[A-Z][A-Za-z0-9_]*(<[^>]*>)?\??[ \t]/) return 1
  if (x ~ /^[A-Za-z0-9_.]*DbContext[ \t]/) return 1
  return 0
}
function params_of(list,   n, a, i, out) {
  n = split_args(list, a, 1)
  out = ""
  for (i = 1; i <= n; i++) if (a[i] != "" && !is_service(a[i])) out = out (out == "" ? "" : ", ") restore(a[i])
  return out
}

# ---------- routes ----------
function join_route(prefix, route) {
  if (route == "") return prefix == "" ? "/" : prefix
  if (substr(route, 1, 2) == "~/") route = substr(route, 2)
  sub(/\/+$/, "", prefix)
  sub(/^\/+/, "", route)
  if (prefix == "" || prefix == "/") return "/" route
  return prefix "/" route
}
function norm_route(r) {
  gsub(/\/\/+/, "/", r)
  if (substr(r, 1, 1) != "/" && substr(r, 1, 1) != "<") r = "/" r
  if (length(r) > 1) sub(/\/$/, "", r)
  return r
}
function replace_token(r, token, value,   low, i, out) {
  out = ""
  while ((i = index(tolower(r), "[" token "]")) > 0) {
    out = out substr(r, 1, i - 1) value
    r = substr(r, i + length(token) + 2)
  }
  return out r
}

# ---------- classes and actions ----------
function start_class(t,   nm, rest, base, attr, n, el, i, a) {
  match(t, /class[ \t]+[A-Za-z_][A-Za-z0-9_]*/)
  nm = substr(t, RSTART, RLENGTH)
  sub(/^class[ \t]+/, "", nm)
  rest = substr(t, RSTART + RLENGTH)
  if (match(rest, /^[ \t]*</)) rest = substr(rest, RSTART + length(take_balanced(substr(rest, RSTART), "<", ">")))
  rest = trim(rest)
  if (substr(rest, 1, 1) == "(") rest = substr(rest, length(take_balanced(rest, "(", ")")) + 1)
  base = ""
  if (match(rest, /^[ \t]*:[ \t]*[A-Za-z_][A-Za-z0-9_.]*/)) { base = substr(rest, RSTART, RLENGTH); sub(/^[ \t]*:[ \t]*/, "", base); sub(/^.*\./, "", base) }
  ncls++
  cname[ncls] = nm
  cmember[ncls] = line_depth + 1
  copened[ncls] = 0
  if (!(nm in cfile)) {
    nclasses++; corder[nclasses] = nm
    cfile[nm] = file; cline[nm] = FNR; cbase[nm] = base
    cabstract[nm] = (t ~ /(^|[ \t])abstract[ \t]/) ? 1 : 0
    cdoc[nm] = summary(doc)
  } else if (cbase[nm] == "" && base != "") cbase[nm] = base
  n = split(attrs, el, "\036")
  for (i = 1; i <= n; i++) {
    a = attr_name(el[i])
    if (a == "Route" || a == "RoutePrefix") croutes[nm] = croutes[nm] "\036" litval(first_arg(attr_args(el[i])))
    else if (a == "ApiController" || a == "Controller") capi[nm] = 1
    else if (a == "NonController") cnon[nm] = 1
    else if (a == "Authorize") cauth[nm] = add_auth(cauth[nm], describe_auth(attr_args(el[i])))
    else if (a == "AllowAnonymous") canon[nm] = 1
    else if (a == "Area") carea[nm] = litval(first_arg(attr_args(el[i])))
    else if (a == "ApiVersion") cver[nm] = cver[nm] (cver[nm] == "" ? "" : ", ") "v" litval(first_arg(attr_args(el[i])))
  }
  attrs = ""; attrline = 0; doc = ""
  if (opens > 0 && depth_after == line_depth) ncls--
}
function is_method_decl(t,   pre) {
  pre = substr(t, 1, index(t, "(") - 1)
  if (pre ~ /=|(^|[ \t])(class|delegate|event|operator|static|abstract|implicit|explicit)[ \t]/) return 0
  if (pre !~ /^public([ \t]+(async|virtual|override|new|sealed|unsafe|extern|partial))*[ \t]+[^ \t].*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*(<.*>)?[ \t]*$/) return 0
  return 1
}
function finish_signature(   pre, nm, ret, cls, n, el, i, a, args, verbs, k) {
  sigopen = 0
  cls = cname[ncls]
  pre = trim(substr(sig, 1, index(sig, "(") - 1))
  if (pre ~ />$/) { attrs = ""; attrline = 0; doc = ""; return }
  match(pre, /[A-Za-z_][A-Za-z0-9_]*$/)
  nm = substr(pre, RSTART, RLENGTH)
  ret = substr(pre, 1, RSTART - 1)
  sub(/^public[ \t]+/, "", ret)
  while (ret ~ /^(async|virtual|override|new|sealed|unsafe|extern|partial)[ \t]/) sub(/^[a-z]+[ \t]+/, "", ret)
  if (nm == cls || nm ~ /^(Dispose|OnActionExecuting|OnActionExecuted|OnActionExecutionAsync)$/) { attrs = ""; attrline = 0; doc = ""; return }
  na++
  aclass[na] = cls; afile[na] = file; aline[na] = sigline; aname[na] = nm
  aret[na] = unwrap(restore(ret))
  aparams[na] = params_of(inner(sig, "(", ")"))
  adoc[na] = summary(doc)
  n = split(attrs, el, "\036")
  for (i = 1; i <= n; i++) {
    a = attr_name(el[i])
    args = attr_args(el[i])
    if (a ~ /^Http(Get|Post|Put|Patch|Delete|Head|Options)$/) {
      verbs = toupper(substr(a, 5))
      if (trim(args) != "" && trim(first_arg(args)) !~ /^[A-Za-z]+[ \t]*=/) ahttp[na] = ahttp[na] "\036" verbs "\035" litval(first_arg(args)) "\035" 1
      else ahttp[na] = ahttp[na] "\036" verbs "\035\035" 0
    } else if (a == "AcceptVerbs") {
      verbs = ""; k = ""
      split_verbs(args)
      if (av_route != "") ahttp[na] = ahttp[na] "\036" av_verbs "\035" av_route "\035" 1
      else ahttp[na] = ahttp[na] "\036" av_verbs "\035\035" 0
    } else if (a == "Route") aroute[na] = aroute[na] "\036" litval(first_arg(args))
    else if (a == "Authorize") aauth[na] = add_auth(aauth[na], describe_auth(args))
    else if (a == "AllowAnonymous") aanon[na] = 1
    else if (a == "NonAction") anon_action[na] = 1
    else if (a == "ProducesResponseType") aprod[na] = aprod[na] (aprod[na] == "" ? "" : ", ") produces(el[i])
    else if (a == "MapToApiVersion") aver[na] = aver[na] (aver[na] == "" ? "" : ", ") "v" litval(first_arg(args))
  }
  attrs = ""; attrline = 0; doc = ""
}
function split_verbs(args,   n, a, i, x) {
  av_verbs = ""; av_route = ""
  n = split_args(args, a, 1)
  for (i = 1; i <= n; i++) {
    x = a[i]
    if (x ~ /^Route[ \t]*=/) { sub(/^Route[ \t]*=[ \t]*/, "", x); av_route = litval(x) }
    else if (x ~ /^"#[0-9]+#"$/) av_verbs = av_verbs (av_verbs == "" ? "" : ",") toupper(litval(x))
  }
  if (av_verbs == "") av_verbs = "ANY"
}
function summary(d,   s, tag, val) {
  if (d == "") return ""
  s = d
  gsub(/\/\/\//, " ", s)
  if (index(s, "<summary>")) { s = substr(s, index(s, "<summary>") + 9); if (index(s, "</summary>")) s = substr(s, 1, index(s, "</summary>") - 1) }
  else return ""
  while (match(s, /<(see|seealso|paramref|typeparamref)[^>]*>/)) {
    tag = substr(s, RSTART, RLENGTH)
    val = ""
    if (match(tag, /(cref|name|langword)="[^"]*"/)) { val = substr(tag, RSTART, RLENGTH); sub(/^[a-z]+="/, "", val); sub(/"$/, "", val); sub(/^[A-Z]:/, "", val); sub(/^.*\./, "", val) }
    match(s, /<(see|seealso|paramref|typeparamref)[^>]*>/)
    s = substr(s, 1, RSTART - 1) val substr(s, RSTART + RLENGTH)
  }
  gsub(/<[^>]*>/, " ", s)
  return squeeze(s)
}

# ---------- minimal APIs ----------
function stmt_end(s,   i, c, d) {
  d = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(" || c == "[" || c == "{") d++
    else if (c == ")" || c == "]" || c == "}") { d--; if (d < 0) return i }
    else if (c == ";" && d == 0) return i
  }
  return 0
}
function receiver_prefix(recv) {
  if ((file SUBSEP recv) in vprefix) { gauth = vauth[file, recv]; return vprefix[file, recv] }
  gauth = ""
  if (extname != "" && recv == extparam) return "\001" extname "\001"
  return ""
}
function handle_statement(s,   target, e, p, recv, rest, nm, gen, args, ep, n, a, called, x) {
  p = stmt_end(s)
  if (p > 0) s = substr(s, 1, p - 1)
  s = trim(s)
  target = ""
  if (match(s, /^[A-Za-z_][A-Za-z0-9_.<>?]*[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=>]/)) {
    target = substr(s, 1, RLENGTH - 1)
    sub(/[ \t]*=$/, "", target)
    sub(/^.*[ \t]/, "", target)
    e = substr(s, RLENGTH)
  } else if (match(s, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=[^=>]/)) {
    target = substr(s, 1, RLENGTH - 1)
    sub(/[ \t]*=$/, "", target)
    e = substr(s, RLENGTH)
  } else {
    e = s
    sub(/^(return|await)[ \t]+/, "", e)
    if (e ~ /^(public|private|internal|protected|static|void)[ \t]/ && index(e, "=>")) e = substr(e, index(e, "=>") + 2)
  }
  e = trim(e)
  if (!match(e, /^(this\.)?[A-Za-z_][A-Za-z0-9_]*/)) return
  recv = substr(e, RSTART, RLENGTH)
  sub(/^this\./, "", recv)
  rest = substr(e, RSTART + RLENGTH)
  prefix = receiver_prefix(recv)
  ep = 0
  while (match(rest, /^[ \t]*[?!]?\.[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) {
    nm = substr(rest, RSTART, RLENGTH)
    sub(/^[ \t]*[?!]?\.[ \t]*/, "", nm)
    rest = substr(rest, RSTART + RLENGTH)
    gen = ""
    if (match(rest, /^[ \t]*</)) { rest = trim(rest); gen = take_balanced(rest, "<", ">"); rest = substr(rest, length(gen) + 1); gen = substr(gen, 2, length(gen) - 2) }
    called = 0
    if (match(rest, /^[ \t]*\(/)) { rest = trim(rest); args = take_balanced(rest, "(", ")"); rest = substr(rest, length(args) + 1); args = substr(args, 2, length(args) - 2); called = 1 }
    if (!called) continue
    if (index(args, "MapGroup(")) note("route group passed as an argument (" restore(args) "): the endpoints mapped with it start with its prefix")
    if (nm == "MapGroup") { prefix = join_route(prefix, litval(first_arg(args))); ep = 0; continue }
    if (nm ~ /^Map(Get|Post|Put|Patch|Delete|Methods)$/) { ep = add_endpoint(nm, args, ""); continue }
    if (nm == "MapHub") { ep = add_endpoint("HUB", args, gen); continue }
    if (nm == "MapHealthChecks") { ep = add_endpoint("MapGet", args, "health checks"); continue }
    if (nm == "MapGrpcService") { ep = add_endpoint("GRPC", "", gen); continue }
    if (nm == "MapControllers" || nm == "MapDefaultControllerRoute") { ctl_stmt = 1; continue }
    if (nm ~ /^(MapControllerRoute|MapRoute|MapHttpRoute|MapAreaControllerRoute)$/) { note("conventional route " template_arg(args) " (" nm "): the actions without route attributes use it"); ctl_stmt = 1; continue }
    if (nm == "RequireAuthorization") {
      if (ep) mauth[ep] = add_auth(mauth[ep] == "-" ? "" : mauth[ep], auth_args(args))
      else if (ctl_stmt) note("MapControllers().RequireAuthorization(" restore(args) "): every controller action requires it, except [AllowAnonymous]")
      else gauth = add_auth(gauth, auth_args(args))
      continue
    }
    if (nm == "AllowAnonymous") { if (ep) mauth[ep] = "anonymous"; else gauth = "anonymous"; continue }
    if (ep && (nm == "WithSummary" || nm == "WithDescription")) { if (msum[ep] == "") msum[ep] = litval(first_arg(args)); continue }
    if (ep && nm == "WithName" && msum[ep] == "") { mname[ep] = litval(first_arg(args)); continue }
    if (ep && nm == "Produces") {
      x = (first_arg(args) == "" ? "200" : status_of(first_arg(args)))
      if (x ~ /^2/ && mret[ep] == "" && gen != "") mret[ep] = gen
      if (x != "") mstat[ep] = mstat[ep] (mstat[ep] == "" ? "" : ", ") x
      continue
    }
    if (ep && nm == "Accepts") { mreq[ep] = gen; continue }
    if (!ep && exts != "" && nm ~ ("^(" exts ")$")) { caller[nm] = prefix; callerauth[nm] = gauth; continue }
  }
  ctl_stmt = 0
  if (target != "" && !ep) { vprefix[file, target] = prefix; vauth[file, target] = gauth }
}
function template_arg(args,   n, a, i, x) {
  n = split_args(args, a, 1)
  for (i = 1; i <= n; i++) {
    x = a[i]
    if (x ~ /^(pattern|url|routeTemplate|template)[ \t]*:/) { sub(/^[A-Za-z]+[ \t]*:[ \t]*/, "", x); return litval(x) }
  }
  for (i = 1; i <= n; i++) if (a[i] !~ /^[A-Za-z]+[ \t]*:/ && i > 1) return litval(a[i])
  return "?"
}
function auth_args(args,   n, a, i, out) {
  if (trim(args) == "") return "authenticated"
  n = split_args(args, a, 1)
  out = ""
  for (i = 1; i <= n; i++) out = out (out == "" ? "" : ", ") (a[i] ~ /^"#[0-9]+#"$/ ? "policy " litval(a[i]) : restore(a[i]))
  return out
}
function add_endpoint(kind, args, extra,   n, a, route, verbs, h, handler, x) {
  n = split_args(args, a, 1)
  m++
  mfile[m] = file; mline[m] = stmtline; mauth[m] = (gauth == "" ? "-" : gauth); msum[m] = ""; mret[m] = ""; mstat[m] = ""; mreq[m] = ""
  mext[m] = (index(prefix, "\001") ? substr(prefix, 2, index(substr(prefix, 2), "\001") - 1) : "")
  if (kind == "GRPC") { mverb[m] = "gRPC"; mroute[m] = "-"; mhandler[m] = extra; mparams[m] = ""; return m }
  route = n > 0 ? litval(a[1]) : ""
  mroute[m] = join_route(prefix, route)
  if (kind == "HUB") { mverb[m] = "SignalR hub"; mhandler[m] = extra; mparams[m] = ""; return m }
  if (extra == "health checks") { mverb[m] = "GET"; mhandler[m] = "health checks"; mparams[m] = ""; return m }
  verbs = toupper(substr(kind, 4))
  h = (n > 1) ? a[2] : ""
  if (kind == "MapMethods") {
    verbs = ""
    x = a[2]
    while (match(x, /"#[0-9]+#"/)) { verbs = verbs (verbs == "" ? "" : ",") toupper(litval(substr(x, RSTART, RLENGTH))); x = substr(x, RSTART + RLENGTH) }
    h = (n > 2) ? a[3] : ""
  }
  mverb[m] = verbs
  h = trim(h)
  handler = "lambda"
  if (h ~ /^[A-Za-z_][A-Za-z0-9_.]*$/) handler = h
  else if (match(h, /new[ \t]+[A-Z][A-Za-z0-9_]*(Command|Query|Request)[ \t]*[({]/)) { x = substr(h, RSTART + 4, RLENGTH - 5); gsub(/[ \t({]/, "", x); handler = "lambda, sends " x }
  else if (h == "") handler = "-"
  mhandler[m] = handler
  mparams[m] = ""
  if (match(h, /^(async[ \t]+)?(static[ \t]+)?\(/)) mparams[m] = params_of(inner(h, "(", ")"))
  return m
}
function note(text) { nnotes++; notes[nnotes] = file ":" (stmtline ? stmtline : FNR) ": " text }
function row(text) { if (rows < MAXROWS) { print text; rows++ } else hidden++ }
function header(text) { if (rows < MAXROWS) { print ""; print text; print "|---|---|---|---|---|---|---|" } }

# ---------- line processing ----------
function process(t,   rest) {
  t = trim(t)
  if (sigopen) {
    sig = sig " " t; siglines++
    if (balanced(sig)) finish_signature()
    else if (siglines > 40) { sigopen = 0; attrs = ""; attrline = 0; doc = ""; lost(file ":" sigline, "action signature not understood") }
    return
  }
  if (stmtopen) {
    stmt = stmt " " t; stmtlines++
    if (stmt_end(stmt)) { handle_statement(stmt); stmtopen = 0; if (ext_expr) { extname = ""; extparam = ""; ext_expr = 0 } }
    else if (stmtlines > 300) { stmtopen = 0; lost(file ":" stmtline, "endpoint statement not understood") }
    return
  }
  if (attropen != "") { t = trim(attropen " " t); attropen = "" }
  if (substr(t, 1, 1) == "[" && decl_level()) {
    t = take_attributes(t)
    if (attropen != "") return
    t = trim(t)
    if (t == "") return
  }
  if (t == "") return
  if (decl_level() && t ~ /(^|[ \t])class[ \t]+[A-Za-z_]/ && t !~ /^(return|var|new|using)[ \t]/) { start_class(t); return }
  if (match(t, /static[ \t].*\([ \t]*this[ \t]+(IEndpointRouteBuilder|RouteGroupBuilder|WebApplication|IApplicationBuilder)[ \t]+[A-Za-z_][A-Za-z0-9_]*/)) {
    rest = substr(t, RSTART, RLENGTH)
    extparam = rest; sub(/^.*[ \t]/, "", extparam)
    extname = rest; sub(/[ \t]*\([ \t]*this[ \t].*$/, "", extname); sub(/^.*[ \t]/, "", extname)
    extdepth = line_depth; extopened = 0
    attrs = ""; attrline = 0; doc = ""
    rest = substr(t, RSTART + RLENGTH)
    if (index(rest, "=>") && substr(rest, index(rest, "=>")) ~ stmtre) {
      stmt = substr(rest, index(rest, "=>") + 2); stmtline = FNR; stmtlines = 1
      if (stmt_end(stmt)) { handle_statement(stmt); extname = ""; extparam = "" } else { stmtopen = 1; ext_expr = 1 }
    }
    return
  }
  if (ncls > 0 && line_depth == cmember[ncls] && t ~ /^public[ \t]/ && index(t, "(") > 0 && is_method_decl(t)) {
    sig = t; sigline = FNR; siglines = 1
    if (balanced(sig)) finish_signature(); else sigopen = 1
    return
  }
  if (t ~ stmtre) {
    stmt = t; stmtline = FNR; stmtlines = 1
    if (stmt_end(stmt)) handle_statement(stmt); else stmtopen = 1
    return
  }
  if (decl_level()) {
    if (attrs ~ /(^|\036)[ \t]*(Http(Get|Post|Put|Patch|Delete)|Route)([ \t(]|\036|$)/ && t ~ /\(/) lost(file ":" attrline, "routing attribute on a member that is not a public instance method: not an endpoint")
    attrs = ""; attrline = 0; doc = ""
  }
}
function lost(where, text) { nlost++; lostl[nlost] = where ": " text }
function decl_level() { return ncls == 0 || line_depth <= cmember[ncls] }
function balanced(s,   i, c, d, seen) {
  d = 0; seen = 0
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "(") { d++; seen = 1 }
    else if (c == ")") { d--; if (seen && d == 0) return 1 }
  }
  return 0
}

BEGIN {
  stmtre = "\\.(Map(Get|Post|Put|Patch|Delete|Methods|Group|Controllers|ControllerRoute|AreaControllerRoute|DefaultControllerRoute|Route|HttpRoute|Hub|HealthChecks|GrpcService)" (exts != "" ? "|" exts : "") ")[ \t]*[(<]"
}
FNR == 1 {
  file = FILENAME
  depth = 0; inblock = 0; inverb = 0; inraw = 0; ncls = 0; attrs = ""; attrline = 0; attropen = ""; doc = ""
  sigopen = 0; stmtopen = 0; extname = ""; extparam = ""; ctl_stmt = 0; ext_expr = 0
  sub(/^\357\273\277/, "")
}
{
  raw = $0
  if (!inblock && !inverb && !inraw && raw ~ /^[ \t]*\/\/\//) { doc = doc " " raw; next }
  code = sanitize(raw)
  x = code; opens = gsub(/[{]/, "", x)
  x = code; closes = gsub(/[}]/, "", x)
  line_depth = depth
  depth_after = depth + opens - closes
  process(code)
  depth = depth_after
  while (ncls > 0) {
    if (!copened[ncls] && depth >= cmember[ncls]) copened[ncls] = 1
    if (copened[ncls] && depth < cmember[ncls]) ncls--
    else break
  }
  if (extname != "") {
    if (!extopened && depth > extdepth) extopened = 1
    if (extopened && depth <= extdepth) { extname = ""; extparam = "" }
  }
}

# ---------- output ----------
function chain_routes(c,   out, guard) {
  out = ""; guard = 0
  while (c != "" && guard++ < 20) { out = out croutes[c]; c = cbase[c]; if (!(c in cfile)) break }
  return out
}
function chain_auth(c,   out, guard) {
  out = ""; guard = 0
  while (c != "" && guard++ < 20) { if (cauth[c] != "") out = add_auth(out, cauth[c]); if (!(c in cfile)) break; c = cbase[c] }
  return out
}
function chain_flag(arr, c,   guard) {
  guard = 0
  while (c != "" && guard++ < 20) { if (arr[c]) return 1; if (!(c in cfile)) return 0; c = cbase[c] }
  return 0
}
function chain_area(c,   guard) {
  guard = 0
  while (c != "" && guard++ < 20) { if (carea[c] != "") return carea[c]; if (!(c in cfile)) return ""; c = cbase[c] }
  return ""
}
function is_controller(c,   b, guard) {
  if (cabstract[c] || cnon[c]) return 0
  if (c ~ /Controller$/ || chain_flag(capi, c)) return 1
  b = cbase[c]; guard = 0
  while (b != "" && guard++ < 20) {
    if (b ~ /^(ControllerBase|Controller|ApiController|ODataController|EndpointBase|EndpointBaseAsync|EndpointBaseSync)$/) return 1
    if (!(b in cfile)) return 0
    if (capi[b]) return 1
    b = cbase[b]
  }
  return 0
}
function resolve(r,   i, j, nm, p, guard) {
  guard = 0
  while ((i = index(r, "\001")) > 0 && guard++ < 10) {
    j = index(substr(r, i + 1), "\001")
    nm = substr(r, i + 1, j - 1)
    p = (nm in caller) ? caller[nm] : "<prefix?>"
    if (!(nm in caller)) unresolved[nm] = 1
    r = substr(r, 1, i - 1) p substr(r, i + j + 1)
  }
  return norm_route(r)
}
END {
  total = 0
  for (k = 1; k <= na; k++) if (!anon_action[k] && is_controller(aclass[k])) total++
  print "## HTTP endpoints (computed from the code" (folder != "" ? ", folder " folder : "") ": " total " controller actions, " (m + 0) " minimal API endpoints)"
  print "Routes are exact for literal routes; <...> is an expression to look up in the code. Authorization \"-\": none on the endpoint (see the notes for a global policy)."
  for (ci = 1; ci <= nclasses; ci++) {
    c = corder[ci]
    if (!is_controller(c)) {
      for (k = 1; k <= na; k++) if (aclass[k] == c && (ahttp[k] != "" || aroute[k] != "")) { lost(afile[k] ":" aline[k], "class " c " has routing attributes but is not recognized as a controller (name, [ApiController] or base class)"); break }
      continue
    }
    croute = chain_routes(c)
    cauthz = chain_auth(c)
    canonym = chain_flag(canon, c)
    area = chain_area(c)
    short = c
    sub(/Controller$/, "", short)
    shown = 0
    for (k = 1; k <= na; k++) {
      if (aclass[k] != c || anon_action[k]) continue
      if (!shown) {
        cr = croute; gsub(/\036/, " ", cr)
        header("### Controller " c " (" cfile[c] ":" cline[c] ")" (trim(cr) != "" ? " - route " squeeze(cr) : " - no class route") (cauthz != "" ? " - " cauthz : "") (canonym ? " - anonymous" : "") (cver[c] != "" ? " - API versions " cver[c] : "") (cdoc[c] != "" ? " - " cdoc[c] : "") "\n| Verb | Route | Action (line) | Authorization | Parameters | Returns | Summary |")
        shown = 1
      }
      action = aname[k]
      sub(/Async$/, "", action)
      # selectors: Http* with a route, [Route] (verbs of the Http* without route, or any), Http* alone, nothing
      nsel = 0
      plain = ""
      nh = split(ahttp[k], hs, "\036")
      for (h = 2; h <= nh; h++) {
        split(hs[h], parts, "\035")
        if (parts[3] == 1) { nsel++; sv[nsel] = parts[1]; st[nsel] = parts[2]; sh[nsel] = 1 }
        else plain = plain (plain == "" ? "" : ",") parts[1]
      }
      nr = split(aroute[k], rs, "\036")
      for (h = 2; h <= nr; h++) { nsel++; sv[nsel] = (plain == "" ? "ANY" : plain); st[nsel] = rs[h]; sh[nsel] = 1 }
      if (nr < 2 && plain != "") { nsel++; sv[nsel] = plain; st[nsel] = ""; sh[nsel] = 0 }
      if (nsel == 0) { nsel++; sv[nsel] = "ANY"; st[nsel] = ""; sh[nsel] = 0 }
      authz = (aanon[k] || canonym) ? "anonymous" : add_auth(cauthz, aauth[k])
      ret = aret[k]
      if (aprod[k] != "") {
        if (ret == "") { split(aprod[k], pl, ", "); for (h = 1; h in pl; h++) if (pl[h] ~ /^2[0-9][0-9] /) { ret = substr(pl[h], 5); break } }
        st_list = ""
        np = split(aprod[k], pl, ", ")
        for (h = 1; h <= np; h++) { s3 = pl[h]; sub(/ .*/, "", s3); if (s3 != "") st_list = st_list (st_list == "" ? "" : ", ") s3 }
        ret = trim(ret (st_list != "" ? " (" st_list ")" : ""))
      }
      nc = split(croute, crs, "\036")
      for (s = 1; s <= nsel; s++) {
        t = st[s]
        if (substr(t, 1, 1) == "/" || substr(t, 1, 2) == "~/") { nroutes = 1; rr[1] = (substr(t, 1, 1) == "~") ? substr(t, 2) : t }
        else if (nc >= 2) { nroutes = 0; for (h = 2; h <= nc; h++) { nroutes++; rr[nroutes] = join_route(crs[h], t) } }
        else if (sh[s]) { nroutes = 1; rr[1] = t }
        else { nroutes = 1; rr[1] = "(conventional routing)" }
        for (h = 1; h <= nroutes; h++) {
          r = rr[h]
          if (r != "(conventional routing)") {
            r = replace_token(r, "controller", short)
            r = replace_token(r, "action", action)
            r = replace_token(r, "area", area)
            r = norm_route(r)
          }
          if (index(r, "<")) lost(afile[k] ":" aline[k], "route of " aname[k] " uses an expression: " r)
          if (aver[k] != "") r = r " (" aver[k] ")"
          row("| " sv[s] " | " cell(r) " | " cell(aname[k] " (" aline[k] ")") " | " cell(authz) " | " cell(aparams[k]) " | " cell(ret) " | " cell(adoc[k]) " |")
        }
      }
    }
  }
  lastfile = ""
  for (k = 1; k <= m; k++) {
    if (mfile[k] != lastfile) {
      header("### Minimal APIs (" mfile[k] ")\n| Verb | Route | Handler (line) | Authorization | Parameters | Returns | Summary |")
      lastfile = mfile[k]
    }
    r = (mroute[k] == "-") ? "-" : resolve(mroute[k])
    a2 = mauth[k]
    if (mext[k] != "" && callerauth[mext[k]] != "") a2 = add_auth(callerauth[mext[k]], a2 == "-" ? "" : a2)
    if (index(mroute[k], "<") && mroute[k] != "-") lost(mfile[k] ":" mline[k], "route uses an expression: " r)
    params = mparams[k] != "" ? mparams[k] : (mreq[k] != "" ? mreq[k] " (body)" : "")
    sm = msum[k] != "" ? msum[k] : (mname[k] != "" ? "name " mname[k] : "")
    ret = trim(mret[k] (mstat[k] != "" ? " (" mstat[k] ")" : ""))
    row("| " mverb[k] " | " cell(r) " | " cell(mhandler[k] " (" mline[k] ")") " | " cell(a2) " | " cell(params) " | " cell(ret) " | " cell(sm) " |")
  }
  if (hidden > 0) { print ""; print "- +" hidden " endpoints not shown: run `sh ~/.config/opencode/scripts/api-routes.sh <folder>` for one project folder at a time" }
  for (nm in unresolved) note_end[++nend] = "<prefix?>: " nm " is never called on a literal route group here; its caller sets the prefix of these routes"
  if (nnotes + nend > 0) {
    print ""
    print "### Notes"
    for (k = 1; k <= nnotes && k <= 40; k++) print "- " notes[k]
    if (nnotes > 40) print "- +" (nnotes - 40) " more notes"
    for (k = 1; k <= nend && k <= 20; k++) print "- " note_end[k]
  }
  if (nlost > 0) {
    print ""
    print "### Not computed (read these lines)"
    for (k = 1; k <= nlost && k <= 40; k++) print "- " lostl[k]
    if (nlost > 40) print "- +" (nlost - 40) " more lines"
  }
}
EOF

tr '\n' '\0' < "$tmp/files" | xargs -0 awk -v exts="$exts" -v folder="$folder" -v MAXROWS="$MAX_ROWS" -f "$tmp/routes.awk"
exit 0
