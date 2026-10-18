#!/bin/sh
# Detects the project type of a git repository from tracked files only (read-only).
# Usage: detect-project-type.sh [--files] [repository path]
#   --files  also print the repository root, the state of its AGENTS.md and its solution and project files
# Output is injected into OpenCode commands. A "Project type" section in AGENTS.md overrides it.

files=0
repo=""
for arg in "$@"; do
  case "$arg" in
    --files) files=1 ;;
    *) [ -z "$repo" ] && repo=$arg ;;
  esac
done

# Optional argument: path of the repository to analyze (default: current directory).
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
    front_build="$runner run build"
    front_test="none (no test script)"
    git grep -q -E '"test"[[:space:]]*:' -- "$first" 2>/dev/null && front_test="$runner test"
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
  git -c core.quotePath=false ls-files '*.sln' '*.slnx' '*.csproj' '*.vbproj' 'package.json' '*/package.json' \
    'Directory.Build.props' 'Directory.Packages.props' | grep -v node_modules
fi
