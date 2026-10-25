#!/bin/sh
# The replacement of Blazorise by native Razor, for real, as /go runs a step « (filet d'abord) » on a page: the .NET
# SDKs 10 and 8, the real packages (Blazorise 2.2.2, bUnit, QuickGrid, coverlet) and the pack's scripts, with the code
# of the skill blazorise as it is written (its page on the DataGrid, its test base class, the tests of its page, its
# French pager, its native page, its Bootstrap validation classes). For each target framework:
#   - fortify.sh prereq --tests: no bUnit yet; test-guardian.sh setup --components creates the unit test project with
#     bUnit (the developer agreed), then builds it
#   - before the change (the test-guardian, mission « filet »): deps of the page, its coverage and its net before any
#     test (THIN), the tests of what its users see written on the Blazorise DataGrid, green twice, its net measured by
#     coverlet on the .razor page (OK), test-lint, tests-only, sealed
#   - the developer adds QuickGrid; the coder rewrites the page in native Razor (QuickGrid and the French pager): the
#     sealed tests unchanged, green twice, the net kept, nothing lost
#   - the last step: every Blazorise package, registration, using and link removed, the test base class without it; no
#     Blazorise left, the build and the tests green
# Needs dotnet (the CI installs the SDKs 10 and 8) and the NuGet feed of the machine (nuget.org in the CI); no
# repository and no setting of this machine is changed. Usage, from opencode-v2/: sh tools/blazor-native-test.sh [<shell>]
SHELL_UNDER_TEST=${1:-sh}
pack=$(cd "$(dirname "$0")/.." && pwd)
scripts="$pack/scripts"
command -v dotnet >/dev/null 2>&1 || { echo "blazor-native-test: dotnet is not on the PATH of this machine"; exit 2; }
work=$(mktemp -d "${TMPDIR:-/tmp}/blazor-native-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tmp"
TMPDIR="$work/tmp"
MSBUILDDISABLENODEREUSE=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_UI_LANGUAGE=en
export TMPDIR MSBUILDDISABLENODEREUSE DOTNET_CLI_TELEMETRY_OPTOUT DOTNET_NOLOGO DOTNET_CLI_UI_LANGUAGE
GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$work/gitconfig"
GIT_AUTHOR_NAME=dev GIT_AUTHOR_EMAIL=dev@example.com GIT_COMMITTER_NAME=dev GIT_COMMITTER_EMAIL=dev@example.com
export GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
printf '[init]\n\tdefaultBranch = develop\n' > "$GIT_CONFIG_GLOBAL"
BLAZORISE=2.2.2
echo "blazor-native-test: SDKs $(dotnet --list-sdks | awk '{ printf "%s%s", sep, $1; sep = ", " }')"

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
    printf '%s\n' "$out" | sed 's/^/    /' | tail -n 40
  fi
  return "$((1 - ok))"
}
verdict() {
  # verdict <name> <status of the condition>
  if [ "$2" -eq 0 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $1"; fi
}
run() {
  script=$1
  shift
  out=$("$SHELL_UNDER_TEST" "$scripts/$script" "$@" 2>&1)
  status=$?
}
commit() { git add -A >/dev/null 2>&1 && git commit -q -m "$1" >/dev/null 2>&1; }
note() { echo "NOTE: $*"; }

# The code blocks of the skill, in order: 1 the language of Blazorise, 2 the shared texts of the DataGrid, 3 the orders
# page on the DataGrid, 4 the test base class, 5 the tests of the orders page, 6 the Bootstrap classes of a field,
# 7 the French pager of QuickGrid, 8 the orders page in native Razor
blocks="$work/blocks"
mkdir -p "$blocks"
awk -v dir="$blocks" '
  /^ *```[a-z]+$/ { n++; inblock = 1; file = dir "/" n; next }
  /^ *```$/ && inblock { inblock = 0; close(file); next }
  inblock { sub(/^   /, ""); print > file }' "$pack/skills/blazorise/SKILL.md"
if [ -s "$blocks/8" ] && [ ! -e "$blocks/9" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: the skill blazorise has not its 8 code blocks"; ls "$blocks"; fi

# The rendered markup of the page, after a failure: what the DataGrid or QuickGrid really wrote
markup() {
  [ -s "$1" ] || return 0
  echo "    markup of the page ($2):"
  tr -s ' \t' ' ' < "$1" | sed -e 's/></>\n</g' | grep -v '^[[:space:]]*$' | head -n 40 | sed 's/^/    /'
}
dump_markup() {
  # dump_markup <file>: renders the page once with the data of the tests, and writes its markup (a test of its own,
  # removed right after: it is no test of the page)
  cat > tests/Web.UnitTests/MarkupDump.cs <<'EOF'
using Bunit;
using Microsoft.Extensions.DependencyInjection;
using Web.Components.Pages;
using Web.Data;
using Xunit;

namespace Web.UnitTests;

public class MarkupDump : PageTestContext
{
    [Fact]
    public void Dump()
    {
        var orders = Enumerable.Range(1, 12).Select(i => new Order($"CMD-{i:00}", new DateTime(2026, 1, i), 10.5m * i)).ToList();
        Services.AddSingleton<IOrderSource>(new Fixed(orders));
        var cut = Render<Orders>();
        try { cut.WaitForState(() => cut.FindAll("tbody tr").Count > 0, TimeSpan.FromSeconds(5)); }
        finally { File.WriteAllText(Environment.GetEnvironmentVariable("MARKUP_DUMP")!, cut.Markup); }
    }

    private sealed class Fixed(IReadOnlyList<Order> orders) : IOrderSource
    {
        public IReadOnlyList<Order> All() => orders;
    }
}
EOF
  MARKUP_DUMP=$1 dotnet test tests/Web.UnitTests/Web.UnitTests.csproj --filter FullyQualifiedName~MarkupDump --nologo -v q > "$1.log" 2>&1
  rm -f tests/Web.UnitTests/MarkupDump.cs
}

# The methods coverlet reports for the page (the classes whose file is the .razor page)
razor_methods() {
  report=$(find "$1" -name '*.cobertura.xml' 2>/dev/null | head -n 1)
  [ -n "$report" ] || { echo "no report"; return 0; }
  awk '/<class / { on = ($0 ~ /filename="[^"]*Orders\.razor"/); if (on && match($0, /filename="[^"]*"/)) file = substr($0, RSTART + 10, RLENGTH - 11); next }
       on && /<method / { if (match($0, / name="[^"]*"/)) m[substr($0, RSTART + 7, RLENGTH - 8)] = 1 }
       END { for (k in m) out = out (out == "" ? "" : ", ") k; printf "%s (%s)\n", (out == "" ? "none" : out), (file == "" ? "no class of Orders.razor" : file) }' "$report" |
    sed 's/&lt;/</g; s/&gt;/>/g'
  # no class of the page: what coverlet names instead (a generated file, another path)
  grep -q 'filename="[^"]*Orders\.razor"' "$report" ||
    echo "; the files of the report that name Orders: $(grep -o 'filename="[^"]*Orders[^"]*"' "$report" | sort -u | head -n 5 | tr '\n' ' ')"
}

scenario() {
  tfm=$1 quickgrid=$2
  mkdir -p "$work/$tfm"
  cd "$work/$tfm" || exit 1
  git init -q .
  printf 'bin/\nobj/\n' > .gitignore
  mkdir -p src/Web/Components/Pages src/Web/Data
  cat > src/Web/Web.csproj <<EOF
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>$tfm</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Blazorise.Bootstrap5" Version="$BLAZORISE" />
    <PackageReference Include="Blazorise.Icons.FontAwesome" Version="$BLAZORISE" />
    <PackageReference Include="Blazorise.DataGrid" Version="$BLAZORISE" />
  </ItemGroup>
</Project>
EOF
  cat > src/Web/Program.cs <<'EOF'
using Blazorise;
using Blazorise.Bootstrap5;
using Blazorise.Icons.FontAwesome;
using Web.Components;
using Web.Data;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
builder.Services.AddBlazorise(options => options.Immediate = true).AddBootstrap5Providers().AddFontAwesomeIcons();
builder.Services.AddSingleton<OrdersDb>();
builder.Services.AddScoped<IOrderSource, OrderSource>();
var app = builder.Build();
app.UseStaticFiles();
app.UseAntiforgery();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
app.Run();
EOF
  cat > src/Web/Components/_Imports.razor <<'EOF'
@using Microsoft.AspNetCore.Components.Routing
@using Microsoft.AspNetCore.Components.Web
@using static Microsoft.AspNetCore.Components.Web.RenderMode
@using Web.Components
@using Web.Data
@using Blazorise
@using Blazorise.DataGrid
EOF
  cat > src/Web/Components/App.razor <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8" />
    <base href="/" />
    <link rel="stylesheet" href="css/bootstrap.min.css" />
    <link href="_content/Blazorise/blazorise.css" rel="stylesheet" />
    <link href="_content/Blazorise.Bootstrap5/blazorise.bootstrap5.css" rel="stylesheet" />
    <HeadOutlet @rendermode="InteractiveServer" />
</head>
<body>
    <Routes @rendermode="InteractiveServer" />
    <script src="_framework/blazor.web.js"></script>
</body>
</html>
EOF
  cat > src/Web/Components/Routes.razor <<'EOF'
<Router AppAssembly="typeof(Program).Assembly">
    <Found Context="routeData">
        <RouteView RouteData="routeData" />
    </Found>
</Router>
EOF
  cat > src/Web/Data/Orders.cs <<'EOF'
namespace Web.Data;

public record Order(string Number, DateTime Date, decimal Total);

public interface IOrderSource
{
    IReadOnlyList<Order> All();
}

public class OrderSource(OrdersDb db) : IOrderSource
{
    public IReadOnlyList<Order> All() => db.Orders;
}

public class OrdersDb
{
    public List<Order> Orders { get; } = new();
}
EOF
  # the code of the skill: the language of Blazorise, its texts, the orders page on the DataGrid, the Bootstrap
  # classes of a field
  cp "$blocks/1" src/Web/Components/BlazoriseLanguage.razor
  cp "$blocks/2" src/Web/Components/GridTexts.cs
  cp "$blocks/3" src/Web/Components/Pages/Orders.razor
  cp "$blocks/6" src/Web/Components/BootstrapFieldCssClassProvider.cs
  commit "feat: the orders page on the Blazorise DataGrid"
  page=src/Web/Components/Pages/Orders.razor
  t=tests/Web.UnitTests/Web.UnitTests.csproj

  run build-test.sh --build-only src/Web/Web.csproj
  check "$tfm: the code of the skill builds against Blazorise $BLAZORISE" 0 '^BUILD: OK' || return 0
  run fortify.sh prereq --tests
  check "$tfm: prereq: no test project, no bUnit" 0 '^PREREQ: COMPONENT TESTS: none'
  # the developer agreed: the unit test project, with bUnit
  run test-guardian.sh setup --components xunit "$page"
  check "$tfm: setup --components: the unit test project created with bUnit, built" 0 "^SETUP: $t created \\(xunit, $tfm\\), it references src/Web/Web\\.csproj; packages: .*bunit [0-9]+\\.[0-9.]+.*; build OK$" || return 0
  note "$tfm: $(printf '%s\n' "$out" | sed -n 's/.*packages: \(.*\); build OK$/\1/p')"
  commit "test: add the unit test project, with bUnit"
  run fortify.sh prereq --tests
  check "$tfm: prereq: the unit test project has bUnit now" 0 "^PREREQ: COMPONENT TESTS: bUnit in $t\$"

  # ---- before the change: the safety net of the page (the test-guardian, mission « filet ») ----
  run test-guardian.sh deps "$page"
  check "$tfm: deps of the page: the source of its orders" 0 '^DEPENDS: IOrderSource -> src/Web/Data/Orders\.cs$'
  run test-guardian.sh coverage F1-before "$t" "$page"
  check "$tfm: coverage of the page before its tests: none yet" 0 "no test in $t yet"
  run test-guardian.sh net F1-before "$page:BuildRenderTree" "$page:OnInitialized"
  check "$tfm: the net of the page before its tests: THIN" 0 '^SAFETY NET: THIN \(no test runs these 2 methods yet'
  cp "$blocks/4" tests/Web.UnitTests/PageTestContext.cs
  cp "$blocks/5" tests/Web.UnitTests/OrdersPageTests.cs
  run test-guardian.sh green "$t" "FullyQualifiedName~OrdersPageTests"
  if ! check "$tfm: the tests of what the users see, on the Blazorise DataGrid: green twice" 0 '^GREEN: 4 tests pass, twice$'; then
    dump_markup "$work/$tfm-datagrid.html"
    markup "$work/$tfm-datagrid.html" "Blazorise DataGrid"
    tail -n 15 "$work/$tfm-datagrid.html.log" | sed 's/^/    /'
    return 0
  fi
  run test-guardian.sh coverage F1-net "$t" "$page"
  check "$tfm: coverlet measures the .razor page" 0 '^src/Web/Components/Pages/Orders\.razor lines [1-9][0-9]*/[0-9]+ '
  note "$tfm, the page on the DataGrid, with its tests: $(printf '%s\n' "$out" | grep '^src/Web/Components/Pages/Orders.razor')"
  folder=$("$SHELL_UNDER_TEST" "$scripts/test-guardian.sh" folder | sed -n 's/^FOLDER: //p')
  note "$tfm: coverlet reports for Orders.razor the methods $(razor_methods "$folder/results-F1-net" | tr "\n" " ")"
  run test-guardian.sh net F1-net "$page:BuildRenderTree" "$page:OnInitialized"
  check "$tfm: the net of the page with its tests: OK" 0 '^SAFETY NET: OK '
  note "$tfm: $(printf '%s\n' "$out" | grep -E '^(NET|SAFETY NET):' | tr '\n' ' ')"
  run test-lint.sh tests/Web.UnitTests/OrdersPageTests.cs tests/Web.UnitTests/PageTestContext.cs
  check "$tfm: test-lint on the tests of the page" 0 '^TEST LINT: OK'
  run test-guardian.sh tests-only
  check "$tfm: only the test project changed" 0 '^TESTS-ONLY: OK'
  run test-guardian.sh seal F1 tests/Web.UnitTests/OrdersPageTests.cs
  check "$tfm: the tests of the page sealed" 0 '^SEALED: 1 test files'
  commit "test: the safety net of the orders page"

  # ---- the developer's decision: QuickGrid, of the version of the target framework ----
  sed -i "s#    <PackageReference Include=\"Blazorise.DataGrid\" Version=\"$BLAZORISE\" />#&\n    <PackageReference Include=\"Microsoft.AspNetCore.Components.QuickGrid\" Version=\"$quickgrid\" />#" src/Web/Web.csproj
  commit "chore: add QuickGrid"

  # ---- the coder: the page in native Razor (the French pager and the page of the skill) ----
  cp "$blocks/7" src/Web/Components/FrenchPager.razor
  cp "$blocks/8" "$page"
  run test-guardian.sh sealed F1
  check "$tfm: the sealed tests, unchanged" 0 '^SEAL: OK'
  run test-guardian.sh green "$t" "FullyQualifiedName~OrdersPageTests"
  if ! check "$tfm: the same tests on the native page (QuickGrid $quickgrid): green twice" 0 '^GREEN: 4 tests pass, twice$'; then
    dump_markup "$work/$tfm-quickgrid.html"
    markup "$work/$tfm-quickgrid.html" "QuickGrid"
    tail -n 15 "$work/$tfm-quickgrid.html.log" | sed 's/^/    /'
    return 0
  fi
  run test-guardian.sh coverage F1-after "$t" "$page" src/Web/Components/FrenchPager.razor
  note "$tfm, the native page, with the same tests: $(printf '%s\n' "$out" | grep -E '^src/Web/Components/(Pages/Orders|FrenchPager)\.razor' | tr '\n' ' ')"
  run test-guardian.sh compare F1-before F1-after
  check "$tfm: no coverage lost (compare)" 0 '^COVERAGE: no file lost coverage$'
  run test-guardian.sh net F1-after "$page:BuildRenderTree" "$page:OnInitialized"
  check "$tfm: the net of the native page: kept" 0 '^SAFETY NET: OK '
  run test-guardian.sh sealed F1
  check "$tfm: sealed before the commit" 0 '^SEAL: OK'
  commit "refactor: the orders page in native Razor (QuickGrid)"

  # ---- the last step: Blazorise leaves ----
  sed -i '/Include="Blazorise\./d' src/Web/Web.csproj
  sed -i '/^using Blazorise/d; /AddBlazorise/d' src/Web/Program.cs
  sed -i '/@using Blazorise/d' src/Web/Components/_Imports.razor
  sed -i '/_content\/Blazorise/d' src/Web/Components/App.razor
  rm -f src/Web/Components/GridTexts.cs src/Web/Components/BlazoriseLanguage.razor
  sed -i '/^using Blazorise/d; /Blazorise/d; /AddBlazorise/d; /IComponentActivator/,/^        }$/d' tests/Web.UnitTests/PageTestContext.cs
  sed -i '/^using Microsoft.AspNetCore.Components;$/d; /^using Microsoft.Extensions.DependencyInjection;$/d; /^using Microsoft.Extensions.DependencyInjection.Extensions;$/d' tests/Web.UnitTests/PageTestContext.cs
  left=$(git grep -n -i blazorise -- . ':!*.md' 2>/dev/null)
  [ -z "$left" ]
  verdict "$tfm: no Blazorise left in the code${left:+ ($(printf '%s' "$left" | head -n 3 | tr '\n' ' '))}" $?
  run build-test.sh "$t"
  check "$tfm: without Blazorise, the build and every test green" 0 '^TESTS: OK' 'FAILED TESTS'
  run test-guardian.sh sealed F1
  check "$tfm: the tests of the page still as sealed" 0 '^SEAL: OK'
  commit "chore: remove Blazorise"
}

scenario net10.0 10.0.0
if dotnet --list-sdks | grep -q '^8\.'; then
  scenario net8.0 8.0.19
else
  note "no .NET 8 SDK here: the net8.0 story is not tried"
fi

echo "blazor-native-test ($SHELL_UNDER_TEST): $pass passed, $fail failed"
[ "$fail" -eq 0 ]
