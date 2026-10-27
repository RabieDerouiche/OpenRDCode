#!/bin/sh
# The diagnosis of the pack's scripts against the REAL output of the .NET SDK, where the other suites use the fake
# dotnet: the messages of the host, of the test host, of MSBuild and of package validation that dotnet-problem.sh,
# build-test.sh and dotnet-targets.sh read. Needs the .NET 10 SDK and the .NET 8 SDK (the CI installs both), and the
# NuGet feed of the machine (nuget.org in the CI); no repository and no setting of this machine is changed.
#   - global.json that asks for an SDK this machine does not have: ENVIRONMENT PROBLEM, never a change of global.json
#   - a project that targets a .NET newer than the SDK (NETSDK1045)
#   - tests whose runtime is not installed (a net7.0 or net6.0 test project): ENVIRONMENT PROBLEM
#   - a .NET 8 solution: its build and its xUnit tests, the facts of dotnet-targets.sh (C# 12, the runtimes, the support)
#   - a C# 13 feature in a net8.0 project (CS9202) and an API that netstandard2.0 lacks: the errors shown once each
#   - a library with package validation: a public member removed against the published version (CP0002)
#   - the API tests of the skill api-tests: test-guardian.sh setup --integration, the tests in memory, then
#     env-tests.sh against the API running on this machine, and against one that does not answer
# Usage, from opencode-v2/: sh tools/real-dotnet-test.sh [<shell>] (default sh).
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
command -v dotnet >/dev/null 2>&1 || { echo "real-dotnet-test: dotnet is not on the PATH of this machine"; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/real-dotnet-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tmp"
TMPDIR="$work/tmp"
MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_UI_LANGUAGE=en
export TMPDIR MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO DOTNET_CLI_UI_LANGUAGE
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
# the pauses of the retries of the scripts (transient.sh): none, a check of a failure that passes by itself does not wait
RETRY_PAUSES="0 0"
export RETRY_PAUSES
printf '[init]\n\tdefaultBranch = develop\n' > "$GIT_CONFIG_GLOBAL"
echo "real-dotnet-test: SDKs $(dotnet --list-sdks | awk '{ printf "%s%s", sep, $1; sep = ", " }'); runtimes $(dotnet --list-runtimes | awk '{ printf "%s%s %s", sep, $1, $2; sep = ", " }')"

pass=0
fail=0
check() {
  # check <name> <expected exit: 0|1|any> <grep pattern of the output> [<pattern that must not appear>]
  name=$1 want=$2 pattern=$3 absent=$4
  ok=1
  case "$want" in
    any) ;;
    0) [ "$status" -eq 0 ] || ok=0 ;;
    *) [ "$status" -ne 0 ] || ok=0 ;;
  esac
  printf '%s\n' "$out" | grep -qE -- "$pattern" || ok=0
  [ -n "$absent" ] && printf '%s\n' "$out" | grep -qE -- "$absent" && ok=0
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name (exit $status)"
    printf '%s\n' "$out" | sed 's/^/    /' | tail -n 60
  fi
}
run() {
  script=$1
  shift
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
}
repo() {
  mkdir -p "$work/$1"
  cd "$work/$1" || exit 1
  git init -q .
  printf 'bin/\nobj/\n' > .gitignore
}
commit() { git add -A >/dev/null 2>&1 && git commit -q -m x >/dev/null 2>&1; }
xunit_project() {
  # xunit_project <path> <target framework>: an xUnit test project with one passing test
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>$2</TargetFramework>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.12.0" />
    <PackageReference Include="xunit" Version="2.9.2" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />
  </ItemGroup>
</Project>
EOF
  cat > "$(dirname "$1")/SumTests.cs" <<'EOF'
using Xunit;

public class SumTests
{
    [Fact]
    public void Sum_TwoNumbers_Adds() => Assert.Equal(3, 1 + 2);
}
EOF
}

# ---------- global.json asks for an SDK that is not installed ----------
repo sdk
xunit_project tests/App.Tests/App.Tests.csproj net8.0
printf '{\n  "sdk": { "version": "8.0.999", "rollForward": "disable" }\n}\n' > global.json
commit
run build-test.sh tests/App.Tests/App.Tests.csproj
check "the SDK of global.json is missing: the real message of the host is read" 1 'ENVIRONMENT PROBLEM: global.json asks for the \.NET SDK 8\.0\.999, which is not installed on this machine \(installed: [0-9]'
check "and global.json is never changed" 1 'Never change global.json or its rollForward yourself'
run dotnet-targets.sh
check "dotnet-targets: the SDK of global.json, not installed" 0 '^\.NET SDK: global\.json asks for 8\.0\.999 \(rollForward disable\): NOT INSTALLED'

# ---------- a project that targets a .NET newer than the SDK ----------
repo future
mkdir -p src/Next
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net99.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/Next/Next.csproj
printf 'public class Next { }\n' > src/Next/Next.cs
commit
run build-test.sh --build-only src/Next/Next.csproj
check "a target framework newer than the SDK (NETSDK1045): an environment problem" 1 'ENVIRONMENT PROBLEM: a project targets \.NET 99\.0 newer than the \.NET SDK of this machine'

# ---------- the package feed that does not answer (a port where nothing listens): asked three times, then said ----------
# (in HTTPS: the NuGet of the .NET 10 SDK refuses an HTTP source before any connection, NU1302, below)
repo feed
mkdir -p src/Feed
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n  </PropertyGroup>\n  <ItemGroup>\n    <PackageReference Include="Acme.Pack.NotInAnyCache" Version="1.0.0" />\n  </ItemGroup>\n</Project>\n' > src/Feed/Feed.csproj
printf 'public class Feed { }\n' > src/Feed/Feed.cs
printf '<?xml version="1.0" encoding="utf-8"?>\n<configuration>\n  <packageSources>\n    <clear />\n    <add key="down" value="https://127.0.0.1:9/v3/index.json" />\n  </packageSources>\n</configuration>\n' > nuget.config
commit
run build-test.sh --build-only src/Feed/Feed.csproj
check "the real NU1301 of a feed that does not answer: the same build again (transient.sh)" 1 '^RETRY: the package feed did not answer \(NU1301\): again in 0 s \(attempt 2 of 3\)$'
check "…three attempts, then none left" 1 '^RETRY: none left: the package feed did not answer \(NU1301\), at each of the 3 attempts$'
check "…then the environment problem, as before" 1 'ENVIRONMENT PROBLEM: the package feed \(Artifactory\) refused access or cannot be reached'
# the same feed in HTTP: refused by NuGet before any connection (NU1302), never retried, said as the machine's problem
sed -i 's#https://127.0.0.1:9#http://127.0.0.1:9#' nuget.config
run build-test.sh --build-only src/Feed/Feed.csproj
if printf '%s\n' "$out" | grep -q NU1302; then
  check "a feed in HTTP (NU1302): an environment problem, never retried" 1 '^ENVIRONMENT PROBLEM: a package source of this repository or machine is in HTTP' '^RETRY:'
else
  check "a feed in HTTP on an SDK that still accepts it: the feed that does not answer" 1 'ENVIRONMENT PROBLEM: the package feed'
fi

# ---------- tests whose runtime is not installed ----------
missing=""
for v in 7.0 6.0; do
  dotnet --list-runtimes | grep -q "^Microsoft\.NETCore\.App $v\." || { missing=$v; break; }
done
if [ -n "$missing" ]; then
  repo runtime
  xunit_project tests/Old.Tests/Old.Tests.csproj "net$missing"
  commit
  run build-test.sh tests/Old.Tests/Old.Tests.csproj
  check "tests on a runtime that is not installed: the real message of the test host is read" 1 "ENVIRONMENT PROBLEM: the tests run on Microsoft\.NETCore\.App $missing\.[0-9]+ \(a net${missing%%.*}\.0 project\), which is not installed on this machine"
  check "and the target framework is never changed" 1 'Never change the target framework of a project'
  run dotnet-targets.sh
  check "dotnet-targets: the runtime of the tests, not installed" 0 "^Test runtimes: NOT INSTALLED on this machine: Microsoft\.NETCore\.App $missing for net$missing"
else
  echo "NOTE: the .NET 7 and 6 runtimes are both installed here: the missing runtime is not tried"
fi

# ---------- a .NET 8 solution, with the .NET 8 SDK ----------
repo net8
xunit_project tests/App.Tests/App.Tests.csproj net8.0
mkdir -p src/App
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n    <Nullable>enable</Nullable>\n  </PropertyGroup>\n</Project>\n' > src/App/App.csproj
printf 'namespace App;\npublic static class Invoice\n{\n    public static decimal Total(decimal a, decimal b) => a + b;\n}\n' > src/App/Invoice.cs
v8=$(dotnet --list-sdks | awk '/^8\./ { v = $1 } END { print v }')
if [ -n "$v8" ]; then
  printf '{\n  "sdk": { "version": "8.0.100", "rollForward": "latestFeature" }\n}\n' > global.json
fi
dotnet new sln -n App > /dev/null 2>&1
dotnet sln App.sln add src/App/App.csproj tests/App.Tests/App.Tests.csproj > /dev/null 2>&1 || dotnet sln add src/App/App.csproj tests/App.Tests/App.Tests.csproj > /dev/null 2>&1
commit
run build-test.sh
check ".NET 8: build and tests" 0 '^TESTS: OK' 'ENVIRONMENT PROBLEM'
run dotnet-targets.sh
check "dotnet-targets: C# 12 for net8.0" 0 '^C#: 12 for net8\.0'
check "dotnet-targets: the runtime of the tests, installed" 0 '^Test runtimes: installed \(net8\.0: Microsoft\.NETCore\.App\)'
check "dotnet-targets: the end of support of .NET 8" 0 '^Support: net8\.0 \((ends|ended) on 2026-11-10\)'
[ -n "$v8" ] && check "dotnet-targets: the SDK of global.json fits ($v8)" 0 "^\\.NET SDK: global\\.json asks for 8\\.0\\.100 \\(rollForward latestFeature\\): 8\\.0\\.[0-9]+ is installed"
[ -z "$v8" ] && echo "NOTE: no .NET 8 SDK here: the net8.0 projects are built by the newest SDK"

# ---------- a C# 13 feature in a net8.0 project built by the .NET 10 SDK (no global.json): the error the coder meets ----------
repo csharp
mkdir -p src/App
printf '<Project Sdk="Microsoft.NET.Sdk">\n  <PropertyGroup>\n    <TargetFramework>net8.0</TargetFramework>\n  </PropertyGroup>\n</Project>\n' > src/App/App.csproj
printf 'namespace App;\npublic static class Escape\n{\n    public const string Reset = "\\e[0m";\n}\n' > src/App/Escape.cs
commit
run build-test.sh --build-only src/App/App.csproj
check "a C# 13 feature in a net8.0 project: CS9202, shown" 1 'error CS9202: .*C# 12\.0.*language version 13'
check "and the build fails" 1 '^BUILD: FAILED'

# ---------- a multi-target library and its package ----------
repo lib
mkdir -p src/Lib feed
cat > src/Lib/Lib.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>netstandard2.0;net8.0</TargetFrameworks>
    <PackageId>Company.Lib</PackageId>
    <Version>1.0.0</Version>
    <IsPackable>true</IsPackable>
  </PropertyGroup>
</Project>
EOF
cat > src/Lib/Client.cs <<'EOF'
namespace Lib
{
    public class Client
    {
        public void Connect(string host) { }
        public void Disconnect() { }
    }
}
EOF
printf '<?xml version="1.0" encoding="utf-8"?>\n<configuration>\n  <packageSources>\n    <add key="local" value="feed" />\n  </packageSources>\n</configuration>\n' > nuget.config
printf 'bin/\nobj/\nfeed/\n' > .gitignore
commit
# the published version 1.0.0, in the local feed
dotnet pack src/Lib/Lib.csproj -c Release -o feed > "$work/pack1.log" 2>&1 || { tail -n 30 "$work/pack1.log"; echo "FAIL: dotnet pack of version 1.0.0"; fail=$((fail + 1)); }
# an API that netstandard2.0 lacks: the error of that target
printf 'namespace Lib\n{\n    public static class Text\n    {\n        public static bool HasComma(string s) => s.Contains(%s);\n    }\n}\n' "','" > src/Lib/Text.cs
run build-test.sh --build-only src/Lib/Lib.csproj
check "an API that netstandard2.0 lacks: its error, for that target" 1 'error CS1503: .*netstandard2\.0|netstandard2\.0.*error CS1503|error CS1503'
rm src/Lib/Text.cs
# version 2.0.0, validated against 1.0.0, without Disconnect
sed -i 's#<Version>1.0.0</Version>#<Version>2.0.0</Version>\n    <EnablePackageValidation>true</EnablePackageValidation>\n    <PackageValidationBaselineVersion>1.0.0</PackageValidationBaselineVersion>#' src/Lib/Lib.csproj
sed -i '/public void Disconnect() { }/d' src/Lib/Client.cs
run detect-project-type.sh
check "detect-project-type: the library and its package validation" any 'Library: src/Lib/Lib\.csproj packable; version: 2\.0\.0 .*package validation: on, against 1\.0\.0'
run build-test.sh --build-only --pack src/Lib/Lib.csproj
check "--pack: the real package validation finds the removed member (CP0002)" 1 "^BREAKING CHANGE: CP0002: .*Disconnect"
check "--pack: and fails" 1 '^PACK: FAILED \(package validation: [0-9]+ breaking change'
git checkout -q -- src/Lib/Client.cs
run build-test.sh --build-only --pack src/Lib/Lib.csproj
check "--pack: the same API, the package is made" 0 '^PACK: OK \(Company\.Lib\.2\.0\.0\.nupkg'
if [ -z "$(git status --porcelain --untracked-files=all | grep '^??')" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: --pack wrote in the repository"; git status --porcelain --untracked-files=all; fi

# ---------- the API tests of the skill api-tests: the project of /tests api, in memory, then on a running API ----------
# Its code blocks, in order: 1 the factory, 2 the test authentication, 3 the factory of an API with settings at start, a
# worker and a DbContext (tools/oidc-real-test.sh builds it), 4 the environment attribute, 5 the environment client,
# 6 environment tests (/health, /api/orders). The API: .NET 10, top-level statements (Program public by itself).
repo apitests
mkdir -p src/Api blocks
cat > src/Api/Api.csproj <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
EOF
cat > src/Api/Program.cs <<'EOF'
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();
builder.Services.AddAuthorization();
var app = builder.Build();
app.UseAuthorization();
app.MapHealthChecks("/health");
app.MapGet("/api/orders", () => Results.Ok(new[] { new { id = 1, total = 12.5m } }));
app.MapGet("/api/orders/{id:int}", (int id) => id == 1 ? Results.Ok(new { id = 1, total = 12.5m }) : Results.NotFound())
    .RequireAuthorization();
app.Run();
EOF
commit
run test-guardian.sh setup --integration xunit src/Api/Api.csproj
check "setup --integration with the real SDK: the project of the API tests" 0 '^SETUP: tests/Api\.IntegrationTests/Api\.IntegrationTests\.csproj created \(xunit, net10\.0\).*Microsoft\.AspNetCore\.Mvc\.Testing 10\.[0-9.]+.*build OK' 'public partial class Program'
awk -v dir="$PWD/blocks" '
  /^ *```[a-z]+$/ { n++; inblock = 1; file = dir "/" n; next }
  /^ *```$/ && inblock { inblock = 0; close(file); next }
  inblock { sub(/^   /, ""); print > file }' "$pack/skills/api-tests/SKILL.md"
if [ -s blocks/6 ] && [ ! -e blocks/7 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: the skill api-tests has not its 6 code blocks"; ls blocks; fi
t=tests/Api.IntegrationTests
cp blocks/1 "$t/ApiFactory.cs"
cp blocks/2 "$t/TestAuthHandler.cs"
cp blocks/4 "$t/EnvironmentFactAttribute.cs"
cp blocks/5 "$t/EnvironmentClient.cs"
cp blocks/6 "$t/HealthEnvironmentTests.cs"
rm -rf blocks
cat > "$t/OrdersEndpointsTests.cs" <<'EOF'
using System.Net;
using System.Net.Http.Json;
using Xunit;

public class OrdersEndpointsTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory factory;

    public OrdersEndpointsTests(ApiFactory factory) => this.factory = factory;

    [Fact]
    public async Task Get_OrderById_WithoutUser_Returns401()
    {
        var response = await factory.CreateClient().GetAsync("/api/orders/1");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Get_OrderById_Known_Returns200WithItsTotal()
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add(TestAuthHandler.UserHeader, "dev");
        var order = await client.GetFromJsonAsync<OrderDto>("/api/orders/1");
        Assert.Equal(12.5m, order!.Total);
    }

    [Fact]
    public async Task Get_OrderById_Unknown_Returns404()
    {
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add(TestAuthHandler.UserHeader, "dev");
        var response = await client.GetAsync("/api/orders/2");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}

public record OrderDto(int Id, decimal Total);
EOF
commit
run build-test.sh "$t/Api.IntegrationTests.csproj"
check "the API tests in memory: green, the environment tests skipped without an environment" 0 '^TESTS: OK' 'FAILED TESTS'
run test-lint.sh "$t/OrdersEndpointsTests.cs" "$t/HealthEnvironmentTests.cs"
check "test-lint: the API tests of the skill" 0 '^TEST LINT: OK'
# the API running on this machine, as a deployed environment; and one that does not answer
printf '# Api\n\n## Environnements\n- `ci` : http://127.0.0.1:5199 (écriture permise)\n- `down` : http://127.0.0.1:5198\n' > AGENTS.md
commit
# the built API itself (dotnet run would leave its child process running after a kill)
dotnet src/Api/bin/Debug/net10.0/Api.dll --urls http://127.0.0.1:5199 > "$work/api.log" 2>&1 &
api=$!
up=0
for _ in $(seq 1 90); do
  curl -fs http://127.0.0.1:5199/health > /dev/null 2>&1 && { up=1; break; }
  sleep 1
done
if [ "$up" -eq 1 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: the API did not start"; tail -n 20 "$work/api.log" | sed 's/^/    /'; fi
run env-tests.sh ci
# one line per test on VSTest (the TRX report); a template of the SDK on Microsoft.Testing.Platform gives its summary
case "$(sh "$scripts/test-platform.sh" kind "$t/Api.IntegrationTests.csproj" 2>/dev/null)" in
  vstest*) check "env-tests on a running API: its environment tests, one line each" 0 '^  OK  .*HealthEnvironmentTests\.Get_Orders_ReturnsAJsonArray \([0-9.]+ s\)$' '^  (FAILED|SKIPPED)  ' ;;
  *) check "env-tests on a running API: its environment tests" 0 '^TESTS: OK' ;;
esac
check "env-tests on a running API: read only" 0 '^ENVIRONMENT: ci http://127\.0\.0\.1:5199 \(read only\)'
kill "$api" 2>/dev/null
wait "$api" 2>/dev/null
run env-tests.sh down
check "env-tests: the real message of an environment that does not answer" 1 '^ENVIRONMENT PROBLEM: down \(http://127\.0\.0\.1:5198\) cannot be reached from this machine'

echo "real-dotnet-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
