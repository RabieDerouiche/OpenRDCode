#!/bin/sh
# Detects the project type of a git repository from tracked files only (read-only).
# With .NET projects, also their target frameworks, the C# version the code may use, the SDK global.json asks for, the
# runtimes of the tests and their support (dotnet-targets.sh); a packable library, its packages, how they are versioned
# and checked; a front-end package, its framework, package manager, test runner and node (front-info.sh); the related
# repositories of AGENTS.md « Dépôts liés ».
# Usage: detect-project-type.sh [--files] [repository path]
#   --files  also print the repository root, the state of its AGENTS.md, its solution and project files, and the
#            files that define how it is built, checked and contributed to (SDK, code style, CI, local tools,
#            test settings, merge request templates): what /agents-md reads
# Output is injected into OpenCode commands. A "Project type" section in AGENTS.md overrides it.

files=0
repo=""
for arg in "$@"; do
  case "$arg" in
    --files) files=1 ;;
    *) [ -z "$repo" ] && repo=$arg ;;
  esac
done

# Optional argument: path of the repository to analyze (default: current directory). A leading ~ typed by the user is
# expanded here: it arrives quoted, so the shell does not expand it.
# shellcheck disable=SC2088 # a literal ~/ is matched on purpose
case "$repo" in
  "~") repo=$HOME ;;
  "~/"*) repo="$HOME/${repo#"~/"}" ;;
esac
if [ -n "$repo" ]; then
  if ! cd "$repo" 2>/dev/null; then
    echo "Project type (auto-detected): unknown (folder not found: $repo)"
    exit 0
  fi
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Project type (auto-detected): unknown (not a git repository)"
  exit 0
fi

types=""
evidence=""
build=""
test=""

add_type() {
  case " $types " in *" $1 "*) ;; *) types="${types:+$types }$1" ;; esac
}

# ---------- .NET ----------
projects=$(git ls-files '*.csproj' '*.vbproj' 2>/dev/null)
if [ -n "$projects" ]; then
  legacy_projects=$(git grep -l -E '<TargetFrameworkVersion>v[0-9]|<TargetFrameworks?>[^<]*net4[0-9]' -- '*.csproj' '*.vbproj' 2>/dev/null)
  legacy_web=$(git ls-files '*.aspx' '*.asmx' '*.svc' '*Global.asax' 2>/dev/null | head -1)
  web_sdk=$(git grep -l 'Sdk="Microsoft.NET.Sdk.Web"' -- '*.csproj' 2>/dev/null)
  handlers=$(git grep -l -E 'I(Request|Command|Query)Handler<' -- '*.cs' 2>/dev/null | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' | head -3)
  mediatr=$(git grep -l -E 'PackageReference Include="MediatR' -- '*.csproj' 'Directory.Packages.props' 2>/dev/null | head -1)
  packable=$(git grep -l -E '<IsPackable>true|<GeneratePackageOnBuild>true|<PackageId>' -- '*.csproj' 2>/dev/null)
  test_projects=$(git ls-files '*.csproj' 2>/dev/null | grep -i -E 'tests?\.csproj$|\.tests?/' | head -3)
  # Blazor: Razor components (.razor), with or without a .razor.cs code-behind
  razor=$(git ls-files '*.razor' 2>/dev/null | wc -l | tr -d ' ')
  code_behind=$(git ls-files '*.razor.cs' 2>/dev/null | wc -l | tr -d ' ')
  endpoints=$(git grep -l -E '\[ApiController\]|:[[:space:]]*ControllerBase([^[:alnum:]_]|$)|\.Map(Get|Post|Put|Delete|Patch)\(' -- '*.cs' 2>/dev/null | grep -v -i -E '(^|/)[^/]*tests?[^/]*/' | head -1)
  wasm=$(git grep -l 'Sdk="Microsoft.NET.Sdk.BlazorWebAssembly"' -- '*.csproj' 2>/dev/null | head -1)
  abp=$(git grep -l -E 'Include="Volo\.Abp\.' -- '*.csproj' 'Directory.Packages.props' 2>/dev/null | head -1)

  if [ -n "$legacy_projects" ] || [ -n "$legacy_web" ]; then
    add_type legacy
    evidence="$evidence
- legacy .NET Framework: $(echo "$legacy_projects $legacy_web" | tr '\n' ' ' | cut -c1-200)"
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) build="msbuild (Visual Studio Build Tools, .NET Framework)"; test="vstest.console (Visual Studio)" ;;
      *) build="not buildable on this machine (.NET Framework needs Windows)"; test="none on this machine (.NET Framework needs Windows)" ;;
    esac
  fi

  if [ -n "$web_sdk" ] && [ -n "$handlers" ]; then
    add_type cqrs-api
    evidence="$evidence
- CQRS handlers: $(echo "$handlers" | tr '\n' ' ')"
    [ -n "$mediatr" ] && evidence="$evidence
- WARNING: MediatR package still referenced in $mediatr"
  elif [ -n "$web_sdk" ] && { [ "$razor" -eq 0 ] || [ -n "$endpoints" ]; }; then
    add_type api
    evidence="$evidence
- ASP.NET Core web project(s) without CQRS handlers: $(echo "$web_sdk" | tr '\n' ' ' | cut -c1-200)"
  fi

  if [ "$razor" -gt 0 ]; then
    add_type blazor
    ui_libs=$(git grep -h -o -i -E 'Include="(Blazorise|MudBlazor|Radzen\.Blazor|Syncfusion\.Blazor|Telerik\.UI\.for\.Blazor)[^"]*"' -- '*.csproj' 'Directory.Packages.props' 2>/dev/null | sed -E 's/Include="([^".]+).*/\1/' | sort -u | tr '\n' ' ')
    evidence="$evidence
- Blazor components: $razor .razor files, $code_behind with a .razor.cs code-behind${ui_libs:+; component library: $ui_libs}"
  fi

  if [ -n "$abp" ]; then
    evidence="$evidence
- ABP Framework (Volo.Abp packages, e.g. in $abp): follow the conventions of its existing modules (application services, repositories, permissions, DTO mapping)"
  fi

  if [ -z "$web_sdk" ] && [ -z "$wasm" ] && [ -z "$legacy_projects" ] && [ -z "$legacy_web" ]; then
    if [ -n "$packable" ] || ! git grep -q -E '<OutputType>(Exe|WinExe)' -- '*.csproj' 2>/dev/null; then
      add_type library
      evidence="$evidence
- class library without web project${packable:+, packable: $(echo "$packable" | tr '\n' ' ' | cut -c1-200)}"
    fi
  fi

  if [ -z "$types" ]; then
    add_type dotnet-app
    evidence="$evidence
- .NET console / worker application: $(echo "$projects" | tr '\n' ' ' | cut -c1-200)"
  fi

  if [ -z "$build" ]; then
    build="dotnet build"
    if [ -n "$test_projects" ]; then test="dotnet test"; else test="none (no test project found)"; fi
  fi
fi

# ---------- Front-end ----------
packages=$(git ls-files 'package.json' '*/package.json' 2>/dev/null | grep -v node_modules)
if [ -n "$packages" ]; then
  # shellcheck disable=SC2086 # one argument per package.json
  ui=$(git grep -l -E '"(@angular/core|react|vue|svelte|next|nuxt)"[[:space:]]*:' -- $packages 2>/dev/null | head -3)
  if [ -n "$ui" ]; then
    add_type frontend
    evidence="$evidence
- UI framework dependency in: $(echo "$ui" | tr '\n' ' ')"
    runner="npm"
    git ls-files --error-unmatch yarn.lock >/dev/null 2>&1 && runner="yarn"
    git ls-files --error-unmatch pnpm-lock.yaml >/dev/null 2>&1 && runner="pnpm"
    first=$(echo "$ui" | head -1)
    front_dir=$(dirname "$first")
    front_build="sh ~/.config/opencode/scripts/build-test.sh $front_dir (its build script, then its tests once)"
    front_test="none (no test script)"
    git grep -q -E '"test"[[:space:]]*:' -- "$first" 2>/dev/null && front_test="sh ~/.config/opencode/scripts/build-test.sh $front_dir (its test script, once: never $runner test in a watch mode)"
    [ "$front_dir" = . ] && front_build="sh ~/.config/opencode/scripts/build-test.sh (its build script, then its tests once)"
    if [ -n "$build" ]; then
      build="$build | front-end: $front_build"
      test="$test | front-end: $front_test"
    else
      build="$front_build"
      test="$front_test"
    fi
  fi
fi

# ---------- Test stack (frameworks, mocking and assertion libraries actually referenced) ----------
test_stack=""
add_lib() {
  case " $test_stack " in *" $1 "*) ;; *) test_stack="${test_stack:+$test_stack }$1" ;; esac
}
dotnet_refs=$(git grep -h -o -i -E '(PackageReference|PackageVersion) Include="[^"]+"|<package id="[^"]+"' -- '*.csproj' '*.vbproj' 'Directory.Packages.props' '*packages.config' 2>/dev/null | sed -E 's/.*"([^"]+)"/\1/' | tr '[:upper:]' '[:lower:]' | sort -u)
for lib in $dotnet_refs; do
  case "$lib" in
    xunit|xunit.v3) add_lib xunit ;;
    nunit) add_lib nunit ;;
    mstest.testframework|mstest) add_lib mstest ;;
    moq) add_lib moq ;;
    nsubstitute) add_lib nsubstitute ;;
    fakeiteasy) add_lib fakeiteasy ;;
    rhino.mocks) add_lib rhino.mocks ;;
    fluentassertions) add_lib fluentassertions ;;
    shouldly) add_lib shouldly ;;
    autofixture) add_lib autofixture ;;
    awesomeassertions) add_lib awesomeassertions ;;
    testcontainers) add_lib testcontainers ;;
    bogus) add_lib bogus ;;
    microsoft.aspnetcore.mvc.testing) add_lib webapplicationfactory ;;
    bunit) add_lib bunit ;;
  esac
done
if [ -n "$packages" ]; then
  for lib in jest vitest karma jasmine-core mocha @testing-library/react @testing-library/angular @testing-library/vue cypress @playwright/test; do
    # shellcheck disable=SC2086 # one argument per package.json
    git grep -q -F "\"$lib\"" -- $packages 2>/dev/null && add_lib "$lib"
  done
fi

[ -z "$types" ] && types="unknown"
echo "Project type (auto-detected): $types"
echo "Build: ${build:-unknown}"
echo "Test: ${test:-unknown}"
echo "Test stack: ${test_stack:-none detected}"
echo "Evidence:$evidence"

here=$(cd "$(dirname "$0")" && pwd)
# .NET: target frameworks, C#, SDK, test runtimes, support
[ -n "$projects" ] && sh "$here/dotnet-targets.sh"

# A packable library: its packages, how they are versioned, and what checks their public API
if [ -n "$packable" ]; then
  version=""
  for f in $packable $(git ls-files 'Directory.Build.props' '*/Directory.Build.props' 2>/dev/null); do
    v=$(sed -n -E 's:.*<(Version|VersionPrefix|PackageVersion)>([^<$]*)</(Version|VersionPrefix|PackageVersion)>.*:\2 (\1 in '"$f"'):p' "$f" | head -n 1)
    [ -n "$v" ] && { version=$v; break; }
  done
  [ -z "$version" ] && git ls-files --error-unmatch GitVersion.yml >/dev/null 2>&1 && version="from git (GitVersion.yml)"
  [ -z "$version" ] && git ls-files --error-unmatch version.json >/dev/null 2>&1 && version="from git (Nerdbank.GitVersioning, version.json)"
  [ -z "$version" ] && git grep -q -i 'Include="MinVer"' -- '*.csproj' 'Directory.Build.props' 'Directory.Packages.props' 2>/dev/null && version="from the git tags (MinVer)"
  [ -z "$version" ] && version="set by the CI (none in the repository)"
  validation=$(git grep -h -o '<PackageValidationBaselineVersion>[^<]*' -- '*.csproj' 'Directory.Build.props' 2>/dev/null | head -n 1 | sed 's/.*>//')
  if git grep -q -i '<EnablePackageValidation>[[:space:]]*true' -- '*.csproj' 'Directory.Build.props' 2>/dev/null; then
    validation="on${validation:+, against $validation}: dotnet pack fails on a breaking change (build-test.sh --pack)"
  else
    validation="off: a breaking change of the public API is found by reading the diff (api-surface.sh)"
  fi
  public_api=$(git ls-files '*PublicAPI.Shipped.txt' 2>/dev/null | head -n 1)
  echo "Library: $(printf '%s\n' "$packable" | head -n 3 | tr '\n' ' ' | sed 's/ $//')$( [ "$(printf '%s\n' "$packable" | grep -c .)" -gt 3 ] && echo " …") packable; version: $version; package validation: $validation${public_api:+; public API tracked in PublicAPI.Shipped.txt / Unshipped.txt (RS0016: a new public member goes into PublicAPI.Unshipped.txt)}"
fi

# Front-end: its framework, package manager, test runner and node
if [ -n "${ui:-}" ]; then
  for f in $(printf '%s\n' "$ui" | head -n 2); do
    d=$(dirname "$f")
    fi_framework="" fi_pm="" fi_runner="" fi_node="" fi_want="" fi_watch=0
    while IFS= read -r line; do
      case "${line%%=*}" in
        framework) fi_framework=${line#*=} ;; pm) fi_pm=${line#*=} ;; runner) fi_runner=${line#*=} ;;
        node) fi_node=${line#*=} ;; nodewant) fi_want=${line#*=} ;; watch) fi_watch=${line#*=} ;;
      esac
    done <<EOF
$(sh "$here/front-info.sh" "$d")
EOF
    case "$fi_runner" in
      karma-ng) how="Karma through the Angular CLI (ChromeHeadless, --watch=false)" ;;
      vitest-ng) how="Vitest through the Angular CLI (--watch=false)" ;;
      jest-ng) how="Jest through the Angular CLI (--watch=false)" ;;
      ng) how="the Angular CLI (--watch=false)" ;;
      cra) how="Jest through Create React App (--watchAll=false)" ;;
      vitest) how="Vitest (--run)" ;;
      jest|mocha|karma) how=$fi_runner ;;
      node) how="node --test" ;;
      e2e) how="end-to-end tests only (the CI runs them)" ;;
      none) how="no test script" ;;
      *) how="its test script" ;;
    esac
    [ "$fi_watch" = 1 ] && how="$how; its test script watches: build-test.sh runs it without its watch option"
    echo "Front-end: $d — ${fi_framework:-no UI framework}, $fi_pm, tests: $how; Node: ${fi_node:-not installed}${fi_want:+, the package asks for $fi_want}"
  done
fi

# Related repositories (AGENTS.md « Dépôts liés »): related-repos.sh tells where they are and what they say of a ticket
if [ -f "$(git rev-parse --show-toplevel)/AGENTS.md" ]; then
  related=$(awk '/^## Dépôts liés/ { on = 1; next } /^## / { on = 0 } on && /^- / { sub(/^- */, ""); sub(/[[:space:]]*:.*/, ""); gsub(/`/, ""); printf "%s%s", sep, $0; sep = ", " }' "$(git rev-parse --show-toplevel)/AGENTS.md")
  [ -n "$related" ] && echo "Related repositories (AGENTS.md): $related — sh ~/.config/opencode/scripts/related-repos.sh <KEY> shows their sheet and contract for a ticket"
fi

if [ "$files" -eq 1 ]; then
  root=$(git rev-parse --show-toplevel)
  cd "$root" || exit 0
  echo "Repository root: $root"
  if [ -f AGENTS.md ]; then
    echo "AGENTS.md: $(git log -1 --format='exists, last changed in %h on %cs' -- AGENTS.md 2>/dev/null | grep . || echo 'exists, never committed')"
  else
    echo "AGENTS.md: none (creation mode)"
  fi
  echo "Solution and project files:"
  git -c core.quotePath=false ls-files '*.sln' '*.slnx' '*.slnf' '*.csproj' '*.vbproj' 'package.json' '*/package.json' \
    'Directory.Build.props' 'Directory.Packages.props' | grep -v node_modules
  echo "Build, code style, CI and contribution files:"
  git -c core.quotePath=false ls-files 'global.json' 'Directory.Build.targets' '.editorconfig' '*/.editorconfig' \
    '.config/dotnet-tools.json' '*.runsettings' '.gitlab-ci.yml' '.gitlab-ci/*' 'ci/*.yml' 'docker-compose*.yml' \
    '.gitlab/merge_request_templates/*' '.nvmrc' 'angular.json' '*/angular.json' 'jest.config.*' '*/jest.config.*' \
    'vitest.config.*' '*/vitest.config.*' 'karma.conf.*' '*/karma.conf.*' '.eslintrc*' '*/.eslintrc*' \
    'eslint.config.*' '*/eslint.config.*' '.prettierrc*' '*/.prettierrc*' '.csharpierrc*' | grep -v node_modules
fi
