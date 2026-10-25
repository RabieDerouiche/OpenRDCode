#!/bin/sh
# For /tests api (its wizard): what the integration tests of the API need, and what would stop the API from starting in
# a test (WebApplicationFactory), read from the code before any test is written, so that the developer decides it in
# the first question instead of finding « BLOQUÉ » at the end. Read-only; names and places only, never a value of a
# configuration file.
#   - the ASP.NET Core projects (Sdk="Microsoft.NET.Sdk.Web"), their target framework, Program (top-level statements,
#     public or not before .NET 10), and the integration test project (Microsoft.AspNetCore.Mvc.Testing) if there is one
#   - the authentication: schemes and policies the endpoints rely on (the test handler takes their names)
#   - each DbContext: how it is registered (its provider), the version of EF Core, and the endpoints that use it
#     directly (no port to fake: the question « Base de données » of the wizard)
#   - the workers (AddHostedService): removed in the factory
#   - the settings read at start (GetConnectionString, GetRequiredSection, ValidateOnStart, ?? throw): given by UseSetting
#   - a configuration provider that calls a remote system at start (Key Vault, App Configuration, Secrets Manager),
#     and whether Program.cs skips it for an environment (a condition on the environment around it)
# Output: "WEB PROJECT:", "INTEGRATION TEST PROJECT:", "PROGRAM:", "AUTHENTICATION:", "DBCONTEXT:", "WORKER:",
# "SETTING AT START:", "REMOTE CONFIGURATION:" lines with file:line, then "BLOCKERS:" (what needs the developer: none,
# or the list), "STOP:" when the repository has no ASP.NET Core project.
# Usage: api-preflight.sh [<folder of the request>]

LC_ALL=C
export LC_ALL
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "STOP: not a git repository"; exit 1; }
cd "$root" || exit 1
folder=${1#./}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/api-preflight.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT

# the production C# files (test projects left out), and the web projects
git ls-files -- '*.cs' | grep -v -E '(^|/)(bin|obj)/' | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' > "$tmp/cs"
git ls-files -- '*.csproj' | while IFS= read -r p; do
  grep -q 'Sdk="Microsoft.NET.Sdk.Web"' "$p" 2>/dev/null && printf '%s\n' "$p"
done > "$tmp/webs"
if [ ! -s "$tmp/webs" ]; then
  echo "STOP: no ASP.NET Core project (Sdk=\"Microsoft.NET.Sdk.Web\") in this repository: /tests api tests the endpoints of one"
  exit 1
fi
blockers=""
add_blocker() { blockers="$blockers
- $1"; }

while IFS= read -r p; do
  d=$(dirname "$p")
  tfm=$(sed -n 's:.*<TargetFrameworks\{0,1\}>\([^<;]*\).*:\1:p' "$p" | head -n 1)
  [ -n "$tfm" ] || tfm=$(grep -h -o '<TargetFrameworks\{0,1\}>[^<;]*' Directory.Build.props 2>/dev/null | head -n 1 | sed 's/.*>//')
  major=$(printf '%s' "$tfm" | sed -n 's/^net\([0-9][0-9]*\)\..*/\1/p')
  echo "WEB PROJECT: $p (${tfm:-target framework not found})"
  pf="$d/Program.cs"
  if [ -f "$pf" ]; then
    if git grep -q -E 'public[[:space:]]+(partial[[:space:]]+)?class[[:space:]]+Program([^A-Za-z0-9_]|$)' -- "$d" 2>/dev/null; then
      echo "PROGRAM: $pf: public Program class (WebApplicationFactory<Program> sees it)"
    elif grep -q -E 'class[[:space:]]+Program([^A-Za-z0-9_]|$)' "$pf"; then
      echo "PROGRAM: $pf: a Program class that is not public: WebApplicationFactory<Program> needs it public (a change of production code: test-guardian.sh setup --integration does it only for top-level statements)"
      add_blocker "Program non public dans $pf (classe Program explicite)"
    elif [ "${major:-10}" -ge 10 ]; then
      echo "PROGRAM: $pf: top-level statements, public by itself on .NET 10"
    else
      echo "PROGRAM: $pf: top-level statements on .NET ${major:-?}: test-guardian.sh setup --integration adds public partial class Program { } at its end (its setup commit)"
    fi
  else
    echo "PROGRAM: no Program.cs in $d (a Startup class, or another entry point): WebApplicationFactory<Startup> or the entry point the tests can name"
  fi
done < "$tmp/webs"

# the integration test project
it=""
for t in $(git ls-files -- '*.csproj'); do
  grep -qi 'Microsoft.AspNetCore.Mvc.Testing' "$t" 2>/dev/null && { it=$t; break; }
done
if [ -n "$it" ]; then
  echo "INTEGRATION TEST PROJECT: $it (Microsoft.AspNetCore.Mvc.Testing)"
  if grep -qi 'Microsoft.EntityFrameworkCore.Sqlite' "$it"; then echo "INTEGRATION TEST PROJECT: SQLite already there (Microsoft.EntityFrameworkCore.Sqlite)"; fi
else
  echo "INTEGRATION TEST PROJECT: none (the wizard asks to create it: test-guardian.sh setup --integration)"
fi

# grep_cs <ERE>: file:line:text of the production files that match
grep_cs() { xargs grep -n -E "$1" < "$tmp/cs" 2>/dev/null; }

# authentication
grep_cs 'Add(JwtBearer|MicrosoftIdentityWebApi(Authentication)?|OpenIdConnect|Negotiate|Certificate|Cookie)([^A-Za-z0-9_]|$)|AddAuthentication\(|AddScheme<' |
  head -n 8 | while IFS= read -r l; do
    f=$(printf '%s' "$l" | cut -d: -f1,2)
    what=$(printf '%s' "$l" | grep -o -E 'Add(JwtBearer|MicrosoftIdentityWebApi(Authentication)?|OpenIdConnect|Negotiate|Certificate|Cookie)|AddAuthentication\([^)]*\)|AddScheme<[^>]*>(\("[^"]*")?' | paste -sd '+' - | sed 's/+/ + /g')
    echo "AUTHENTICATION: $what ($f)"
  done
grep_cs 'AuthenticationSchemes[[:space:]]*=[[:space:]]*"[^"]+"' | head -n 4 | while IFS= read -r l; do
  echo "AUTHENTICATION: scheme $(printf '%s' "$l" | grep -o -E 'AuthenticationSchemes[[:space:]]*=[[:space:]]*"[^"]+"' | head -n 1 | sed 's/.*"\([^"]*\)"/\1/') named by an endpoint ($(printf '%s' "$l" | cut -d: -f1,2)): the test handler is registered under it too"
done
grep_cs 'AddPolicy\("[^"]+"' | head -n 6 | while IFS= read -r l; do
  echo "AUTHENTICATION: policy $(printf '%s' "$l" | grep -o -E 'AddPolicy\("[^"]+"' | head -n 1 | sed 's/AddPolicy("//; s/"$//') ($(printf '%s' "$l" | cut -d: -f1,2))"
done

# the DbContexts, their registration and the endpoints that use them directly
efv=$(git ls-files -- '*.csproj' 'Directory.Packages.props' 'Directory.Build.props' | xargs grep -h -o -E '"Microsoft\.EntityFrameworkCore(\.[A-Za-z]+)?"[[:space:]]+Version="[0-9][^"]*"' 2>/dev/null |
  sed 's/.*Version="\([^"]*\)".*/\1/' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
contexts=$(grep_cs 'class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*(\([^)]*\))?[[:space:]]*:[[:space:]]*(Identity|ApiAuthorization)?DbContext([^A-Za-z0-9_]|$)' |
  sed -E 's/.*class[[:space:]]+([A-Za-z0-9_]+).*/\1/' | sort -u)
endpoints=$(xargs grep -l -E '(:[[:space:]]*(Controller|ControllerBase)([^A-Za-z0-9_]|$)|\.Map(Get|Post|Put|Patch|Delete|Methods|Group)\(|: *IEndpoint)' < "$tmp/cs" 2>/dev/null)
[ -n "$folder" ] && endpoints=$(printf '%s\n' "$endpoints" | awk -v p="$folder" 'index($0, p) == 1')
for c in $contexts; do
  reg=$(grep_cs "AddDbContext(Pool|Factory)?<$c>" | head -n 1)
  provider=$(printf '%s' "$reg" | grep -o -E 'Use(SqlServer|Npgsql|MySql|MySQL|Oracle|Sqlite|InMemoryDatabase|Cosmos)' | head -n 1)
  if [ -z "$provider" ] && [ -n "$reg" ]; then
    # the provider on the next lines of the registration
    f=$(printf '%s' "$reg" | cut -d: -f1) n=$(printf '%s' "$reg" | cut -d: -f2)
    provider=$(sed -n "$n,$((n + 6))p" "$f" | grep -o -E 'Use(SqlServer|Npgsql|MySql|MySQL|Oracle|Sqlite|InMemoryDatabase|Cosmos)' | head -n 1)
  fi
  # an endpoint file that names the context outside its registration (a constructor, a parameter of a handler)
  users=$(printf '%s\n' "$endpoints" | while IFS= read -r e; do
    [ -n "$e" ] && grep -E "(^|[^A-Za-z0-9_])$c([^A-Za-z0-9_]|$)" "$e" | grep -q -v -E 'AddDbContext|DbContextOptions<|DbContextFactory<|IDbContextFactory<' && printf '%s\n' "$e"
  done | head -n 6 | tr '\n' ' ' | sed 's/ $//')
  echo "DBCONTEXT: $c — ${reg:+registered at $(printf '%s' "$reg" | cut -d: -f1,2)}${provider:+, ${provider#Use}}${efv:+, EF Core $efv}; used directly by the endpoints: ${users:-none (behind ports: the fakes replace them)}"
  if [ -n "$users" ]; then
    add_blocker "DbContext $c utilisé directement par $users (base : SQLite en mémoire, ou ces endpoints laissés de côté)"
  fi
done

# the workers
grep_cs 'AddHostedService<[A-Za-z0-9_.]+>' | head -n 8 | while IFS= read -r l; do
  echo "WORKER: $(printf '%s' "$l" | grep -o -E 'AddHostedService<[A-Za-z0-9_.]+>' | head -n 1 | sed 's/AddHostedService<//; s/>//') ($(printf '%s' "$l" | cut -d: -f1,2)): removed in the factory by its type"
done

# the settings read at start, by their names
grep_cs 'GetConnectionString\("[^"]+"\)|GetRequiredSection\("[^"]+"\)|ValidateOnStart\(\)|Configuration\["[^"]+"\][[:space:]]*\?\?[[:space:]]*throw' |
  head -n 10 | while IFS= read -r l; do
    key=$(printf '%s' "$l" | grep -o -E 'GetConnectionString\("[^"]+"\)|GetRequiredSection\("[^"]+"\)|ValidateOnStart\(\)|Configuration\["[^"]+"\]' | head -n 1)
    case "$key" in
      GetConnectionString*) key="ConnectionStrings:$(printf '%s' "$key" | sed 's/.*("\([^"]*\)").*/\1/')" ;;
      GetRequiredSection*) key="$(printf '%s' "$key" | sed 's/.*("\([^"]*\)").*/\1/') (required section)" ;;
      ValidateOnStart*) key="options validated at start (their keys need valid values)" ;;
      *) key=$(printf '%s' "$key" | sed 's/.*\["\([^"]*\)"\].*/\1/') ;;
    esac
    echo "SETTING AT START: $key ($(printf '%s' "$l" | cut -d: -f1,2)): a value given by UseSetting in the factory"
  done

# a remote configuration provider at start, and whether a condition on the environment surrounds it
grep_cs 'Add(AzureKeyVault|AzureAppConfiguration|SecretsManager|SystemsManager|Consul|VaultConfiguration)([^A-Za-z0-9_]|$)' | head -n 4 | while IFS= read -r l; do
  f=$(printf '%s' "$l" | cut -d: -f1) n=$(printf '%s' "$l" | cut -d: -f2)
  what=$(printf '%s' "$l" | grep -o -E 'Add(AzureKeyVault|AzureAppConfiguration|SecretsManager|SystemsManager|Consul|VaultConfiguration)' | head -n 1)
  # the condition on the environment that governs it: the line right after such an if without a brace, or its block
  cond=$(awk -v n="$n" '
      function count(s, c,   t) { t = s; return gsub(c, "", t) }
      NR < n {
        line = $0; sub(/\/\/.*/, "", line)
        if (line ~ /^[ \t]*$/) next
        single = ""
        if (line ~ /if[ \t]*\(.*(Environment|IsDevelopment|IsProduction|IsStaging|IsEnvironment)/) {
          if (line ~ /\{/) { stack[++top] = depth + 0; text[top] = line } else { single = line; pending = line }
        } else if (pending != "" && line ~ /^[ \t]*\{/) { stack[++top] = depth + 0; text[top] = pending; pending = "" }
        else pending = ""
        depth += count(line, "\\{") - count(line, "\\}")
        while (top > 0 && depth <= stack[top]) top--
        last = single
        next
      }
      NR == n { t = last != "" ? last : (top > 0 ? text[top] : ""); gsub(/^[ \t]+|[ \t]+$/, "", t); print t; exit }' "$f")
  case "$cond" in
    "")
      echo "REMOTE CONFIGURATION: $what ($f:$n), at every start: in memory, the API calls it and cannot start without it"
      printf '%s\n' "$what ($f:$n)" >> "$tmp/remote" ;;
    *'!'*IsDevelopment*|*IsDevelopment*'== false'*)
      echo "REMOTE CONFIGURATION: $what ($f:$n), skipped only in Development ($cond): the factory runs the API in the environment Development (UseEnvironment(\"Development\")), never Testing" ;;
    *'!'*IsProduction*|*'!'*IsStaging*|*IsProduction*'== false'*)
      echo "REMOTE CONFIGURATION: $what ($f:$n), run in every environment but one ($cond): the environment Testing calls it too"
      printf '%s\n' "$what ($f:$n)" >> "$tmp/remote" ;;
    *IsDevelopment*|*IsProduction*|*IsStaging*)
      echo "REMOTE CONFIGURATION: $what ($f:$n), inside a condition on the environment ($cond): the environment Testing skips it" ;;
    *)
      echo "REMOTE CONFIGURATION: $what ($f:$n), inside a condition on the environment ($cond): the test-guardian checks it against the environment of its factory (Testing)" ;;
  esac
done
[ -s "$tmp/remote" ] && while IFS= read -r r; do add_blocker "$r appelé à chaque démarrage : une condition sur l'environnement dans Program.cs (changement du code de production, /go sans ticket), sinon ces tests sont BLOQUÉS"; done < "$tmp/remote"

if [ -n "$blockers" ]; then
  echo "BLOCKERS (the developer decides them in the first question):$blockers"
else
  echo "BLOCKERS: none (the API can start in memory with the fakes, the test authentication, the settings and the workers handled by the factory)"
fi
exit 0
