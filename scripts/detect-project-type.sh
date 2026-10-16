#!/bin/sh
# Detects the project type of the current git repository from tracked files only (read-only).
# Output is injected into OpenCode commands. A "Project type" section in AGENTS.md overrides it.

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

  if [ -n "$legacy_projects" ] || [ -n "$legacy_web" ]; then
    add_type legacy
    evidence="$evidence
- legacy .NET Framework: $(echo "$legacy_projects $legacy_web" | tr '\n' ' ' | cut -c1-200)"
    build="not buildable on macOS (.NET Framework)"
    test="none on macOS"
  fi

  if [ -n "$web_sdk" ] && [ -n "$handlers" ]; then
    add_type cqrs-api
    evidence="$evidence
- CQRS handlers: $(echo "$handlers" | tr '\n' ' ')"
    [ -n "$mediatr" ] && evidence="$evidence
- WARNING: MediatR package still referenced in $mediatr"
  elif [ -n "$web_sdk" ]; then
    add_type api
    evidence="$evidence
- ASP.NET Core web project(s) without CQRS handlers: $(echo "$web_sdk" | tr '\n' ' ' | cut -c1-200)"
  fi

  if [ -z "$web_sdk" ] && [ -z "$legacy_projects" ] && [ -z "$legacy_web" ]; then
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

[ -z "$types" ] && types="unknown"
echo "Project type (auto-detected): $types"
echo "Build: ${build:-unknown}"
echo "Test: ${test:-unknown}"
echo "Evidence:$evidence"
