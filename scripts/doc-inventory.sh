#!/bin/sh
# For /doc: the facts of the repository that its documentation needs, found by text search (read-only). Each line
# points to a file and a line: /doc reads them before writing anything. The documentation describes what this
# inventory and the code show, never more. No configuration value is printed.
# Sections: existing documentation (and what changed since /doc last wrote it, uncommitted changes included),
# projects and their references (with a Mermaid graph), entry points, request handlers (CQRS), options bound to
# configuration, integrations, data, background work, authentication, CI, front-end. The HTTP endpoints come from
# api-routes.sh and the configuration keys from config-keys.sh.
# Usage: doc-inventory.sh

MAX=150

LC_ALL=C
export LC_ALL
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.quotePath GIT_CONFIG_VALUE_0=false
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Documentation inventory: not a git repository"
  exit 0
fi
root=$(git rev-parse --show-toplevel)
cd "$root" || exit 0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/doc-inventory.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' INT TERM

# Tracked and untracked (not ignored) files, without build outputs and dependencies
git ls-files -co --exclude-standard | grep -v -E '(^|/)(bin|obj|node_modules|dist|wwwroot/lib)/' > "$tmp/files"
grep -E '\.cs$' "$tmp/files" | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' > "$tmp/cs"
grep -E '\.cs$' "$tmp/files" > "$tmp/cs-all"

# grep over a file list, "file:line: text" (text trimmed, at most MAX lines, then the count of the others)
search() {
  list=$1 pattern=$2
  [ -s "$list" ] || return 0
  tr '\n' '\0' < "$list" | xargs -0 grep -n -E "$pattern" 2>/dev/null |
    sed -E 's/^([^:]*:[0-9]+:)[[:space:]]*/\1 /' | cut -c1-220 > "$tmp/hits"
  count=$(grep -c '' "$tmp/hits")
  head -n "$MAX" "$tmp/hits" | sed 's/^/- /'
  [ "$count" -gt "$MAX" ] && echo "- +$((count - MAX)) more"
  return 0
}

head_sha=$(git rev-parse --short HEAD 2>/dev/null)
echo "Today: $(date '+%Y-%m-%d')"
echo "Repository: $root - branch $(git symbolic-ref --short -q HEAD || echo detached) - HEAD ${head_sha:-none} ($(git log -1 --format=%cs 2>/dev/null))"

echo
echo "## Existing documentation"
grep -i -E '(^|/)(README|CHANGELOG|CONTRIBUTING)[^/]*\.md$|^docs/' "$tmp/files" | head -40 | while IFS= read -r f; do
  marker=$(grep -m1 -o 'généré par /doc depuis [0-9a-f]*' "$f" 2>/dev/null)
  echo "- $f ($(grep -c '' "$f") lines)${marker:+ - $marker}"
done
grep -E '^docs/.*\.md$' "$tmp/files" > "$tmp/docs"
# The oldest commit that a file of docs/ was generated from: what changed since then may be missing somewhere
last=""
found=""
[ -s "$tmp/docs" ] && found=$(tr '\n' '\0' < "$tmp/docs" | xargs -0 grep -h -o 'généré par /doc depuis [0-9a-f]*' 2>/dev/null | sed 's/.* //' | sort -u)
for sha in $found; do
  if git rev-parse -q --verify "$sha^{commit}" >/dev/null; then
    printf '%s %s\n' "$(git log -1 --format=%ct "$sha")" "$sha"
  else
    printf '0 %s\n' "$sha"
  fi
done | sort -n | head -1 | cut -d' ' -f2 > "$tmp/last"
last=$(cat "$tmp/last")
if [ -n "$last" ] && git rev-parse -q --verify "$last^{commit}" >/dev/null; then
  # what the documentation does not describe yet: commits since then and the working tree, docs/ left out
  stat=$(git diff --shortstat "$last" -- . ':(exclude)docs' | sed 's/^[[:space:]]*//')
  echo "Changes since the last /doc ($last), uncommitted changes included: ${stat:-none}"
  git diff --stat=100 "$last" -- . ':(exclude)docs' | sed '$d' | tail -n 40
  git ls-files -o --exclude-standard -- . ':(exclude)docs' | grep -v -E '(^|/)(bin|obj|node_modules|dist)/' | head -20 | sed 's/^/ new, not committed: /'
elif [ -n "$last" ]; then
  echo "Last /doc commit $last: not in this clone (update every section)"
fi

echo
echo "## Projects and their references"
: > "$tmp/graph"
grep -E '\.(csproj|vbproj|fsproj)$' "$tmp/files" | while IFS= read -r p; do
  refs=$(grep -o -E 'ProjectReference Include="[^"]+"' "$p" 2>/dev/null | sed -E 's/.*"([^"]+)"/\1/; s#\\#/#g; s#.*/##; s/\.[a-z]+proj$//' | tr '\n' ' ' | sed 's/ $//')
  sdk=$(grep -m1 -o -E 'Sdk="[^"]+"' "$p" | sed -E 's/Sdk="([^"]+)"/\1/')
  name=$(basename "$p" | sed -E 's/\.[a-z]+proj$//')
  echo "- $name ($p${sdk:+, $sdk})${refs:+ -> $refs}"
  # the graph leaves the test projects out
  case "$name" in
    *[Tt]ests | *[Tt]est | *[Ss]pecs | *.[Tt]ests.* | *.[Tt]est.* | *[Tt]est[Ss]upport* | *[Tt]esting) ;;
    *) printf '%s|%s\n' "$name" "$refs" >> "$tmp/graph" ;;
  esac
done
[ -f package.json ] && echo "- front-end package: package.json"
if [ -s "$tmp/graph" ]; then
  echo "Project graph (Mermaid, test projects left out; add the external systems to it):"
  echo '```mermaid'
  echo "graph LR"
  awk -F'|' '
    function id(name,   x) { x = name; gsub(/[^A-Za-z0-9_]/, "_", x); if (x ~ /^[0-9]/) x = "p_" x; return x }
    function node(name) { if (name in declared) return id(name); declared[name] = 1; return id(name) "[\"" name "\"]" }
    {
      n = split($2, ref, " ")
      if (n == 0 && !($1 in seen)) { alone[++na] = $1 }
      seen[$1] = 1
      for (i = 1; i <= n; i++) { print "  " node($1) " --> " node(ref[i]); linked[ref[i]] = 1; linked[$1] = 1 }
    }
    END { for (i = 1; i <= na; i++) if (!(alone[i] in linked)) print "  " node(alone[i]) }
  ' "$tmp/graph"
  echo '```'
fi

echo
echo "## Entry points"
search "$tmp/cs" 'WebApplication\.Create(Slim)?Builder|Host\.Create(Default|Application)Builder|WebHost\.CreateDefaultBuilder|class [A-Za-z0-9_]+ *: *(BackgroundService|IHostedService)'

echo
echo "## Request handlers (CQRS)"
search "$tmp/cs" 'class [A-Za-z0-9_]+ *(<[^>]*>)? *: *[^{]*I(Command|Query|Request|Notification)Handler<'

echo
echo "## Options bound to configuration"
search "$tmp/cs" 'Configure<[^>]+>\(|BindConfiguration\(|AddOptions<[^>]+>\(|GetSection\("|GetValue<[^>]+>\("|GetConnectionString\("|Configuration\["|Environment\.GetEnvironmentVariable\("'


echo
echo "## Integrations"
grep -E '\.(csproj|vbproj|fsproj|props)$' "$tmp/files" > "$tmp/projects"
: > "$tmp/packages"
[ -s "$tmp/projects" ] && tr '\n' '\0' < "$tmp/projects" | xargs -0 grep -h -o -i -E '(PackageReference|PackageVersion) Include="[^"]+"' 2>/dev/null |
  sed -E 's/.*"([^"]+)"/\1/' | sort -u > "$tmp/packages"
pick() { grep -i -E "$1" "$tmp/packages" | tr '\n' ' ' | sed 's/ $//'; }
for line in \
  "AWS (S3 and other services)|^AWSSDK\." \
  "SharePoint / CSOM|SharePoint|^PnP\." \
  "DocuSign|^DocuSign" \
  "Entity Framework Core|^Microsoft\.EntityFrameworkCore\.(SqlServer|Sqlite|InMemory|Cosmos)$|^Npgsql\.EntityFrameworkCore|^Oracle\.EntityFrameworkCore|^Pomelo\.EntityFrameworkCore" \
  "Other database access|^Dapper|^Microsoft\.Data\.SqlClient|^System\.Data\.SqlClient|^Npgsql$|^Oracle\.ManagedDataAccess|^MongoDB\.Driver" \
  "Cache|^StackExchange\.Redis|^Microsoft\.Extensions\.Caching\.(StackExchangeRedis|SqlServer)" \
  "Messaging|^MassTransit|^RabbitMQ\.Client|^Azure\.Messaging|^Confluent\.Kafka|^NServiceBus|^Rebus" \
  "Scheduling|^Hangfire|^Quartz" \
  "HTTP clients and resilience|^Refit|^RestSharp|^Polly|^Microsoft\.Extensions\.Http\.(Resilience|Polly)" \
  "Authentication|^Microsoft\.AspNetCore\.Authentication|^Microsoft\.Identity\.(Web|Client)|^Duende|^IdentityModel" \
  "API description|^Swashbuckle|^NSwag|^Microsoft\.AspNetCore\.OpenApi|^Scalar" \
  "Logging and telemetry|^Serilog|^NLog|^log4net|^OpenTelemetry|^Elastic\.|^Microsoft\.ApplicationInsights" \
  "Feature flags|^Microsoft\.FeatureManagement|^Unleash|^LaunchDarkly|^FeatureToggle" \
  "Health checks|^AspNetCore\.HealthChecks|^Microsoft\.Extensions\.Diagnostics\.HealthChecks" \
  "Validation and mapping|^FluentValidation|^AutoMapper|^Mapster|^Riok\.Mapperly"; do
  label=${line%%|*}
  found=$(pick "${line#*|}")
  [ -n "$found" ] && echo "- $label: $found"
done
echo "Registrations in code (HTTP clients, health checks, database contexts, caches):"
search "$tmp/cs" 'AddHttpClient(<[^>]+>)?\(|AddHealthChecks\(|\.AddCheck(<[^>]+>)?\(|AddDbContext(Pool|Factory)?<|AddStackExchangeRedisCache|AddAWSService<|AddDefaultAWSOptions|AddFeatureManagement'

echo
echo "## Data"
search "$tmp/cs" 'class [A-Za-z0-9_]+ *: *[A-Za-z]*DbContext\b|DbSet<[^>]+>'
migrations=$(grep -E '/Migrations/[0-9]{14}_[^/]*\.cs$' "$tmp/cs-all" | grep -c -v -E '\.Designer\.cs$')
latest=$(grep -E '/Migrations/[0-9]{14}_[^/]*\.cs$' "$tmp/cs-all" | grep -v -E '\.Designer\.cs$' | sed 's#.*/##' | sort | tail -1)
[ "$migrations" -gt 0 ] && echo "- EF Core migrations: $migrations, latest ${latest:-?}"

echo
echo "## Background work"
search "$tmp/cs" ': *(BackgroundService|IHostedService)\b|RecurringJob\.AddOrUpdate|IJob\b|AddHostedService<|PeriodicTimer'

echo
echo "## Authentication and authorization"
search "$tmp/cs" 'AddAuthentication\(|AddJwtBearer\(|AddMicrosoftIdentityWebApi|AddOpenIdConnect\(|AddCookie\(|AddAuthorization\(|AddPolicy\("'

echo
echo "## CI"
if [ -f .gitlab-ci.yml ]; then
  stages=$(sed -n '/^stages:/,/^[^[:space:]-]/p' .gitlab-ci.yml | grep -E '^[[:space:]]*-' | sed -E 's/^[[:space:]]*-[[:space:]]*//' | tr '\n' ' ')
  echo "- .gitlab-ci.yml stages: ${stages:-not listed}"
  jobs=$(grep -E '^[A-Za-z0-9_.-][A-Za-z0-9_. -]*:' .gitlab-ci.yml | sed 's/:.*//' | grep -v -E '^(stages|variables|default|include|workflow|image|services|before_script|after_script|cache)$' | grep -v '^\.' | tr '\n' ' ')
  echo "- jobs: ${jobs:-none found (included templates?)}"
  grep -n -E '^include:|^[[:space:]]+- (project|local|template|remote):' .gitlab-ci.yml | head -10 | sed 's/^/- include line /'
else
  echo "- no .gitlab-ci.yml"
fi

if grep -q -E '(^|/)package\.json$' "$tmp/files"; then
  echo
  echo "## Front-end"
  grep -E '(^|/)package\.json$' "$tmp/files" | head -5 | while IFS= read -r f; do
    echo "- $f: $(grep -o -E '"(@angular/core|react|vue|svelte|next|nuxt)"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" | tr '\n' ' ')"
  done
  grep -E '\.(ts|tsx|js|jsx)$' "$tmp/files" | grep -v -E '\.(spec|test)\.' > "$tmp/front"
  echo "Routes:"
  search "$tmp/front" "path:[[:space:]]*['\"]|<Route[[:space:]]|createBrowserRouter|loadChildren|loadComponent"
  echo "Calls to back-end APIs:"
  search "$tmp/front" 'http(Client)?\.(get|post|put|patch|delete)(<[^>]*>)?\(|fetch\('
fi
exit 0
