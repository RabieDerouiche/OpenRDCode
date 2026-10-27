#!/bin/sh
# Says, from the output of a dotnet command, when the machine and not the code is the problem, in ONE line for the
# agent: "ENVIRONMENT PROBLEM: …" (it stops and tells the user instead of investigating). Exit 0 when it found one,
# 1 otherwise. Used by build-test.sh, test-guardian.sh and fortify.sh on the output of their dotnet commands.
#   - the .NET SDK that global.json asks for is not installed (never change global.json to make it build);
#   - a project targets a .NET newer than the SDK of the machine (NETSDK1045);
#   - the tests need a runtime the machine does not have (a net8.0 test project with only the .NET 10 runtime: never
#     change the target framework or roll it forward to make it run);
#   - the test host does not find .NET at all (DOTNET_ROOT missing);
#   - a workload is missing (NETSDK1147), a Windows project on this machine (NETSDK1100), a .NET Framework project
#     without its reference assemblies (MSB3644);
#   - tests that need Docker (Testcontainers) or SQL Server LocalDB, which this machine does not run;
#   - the package feed refuses access or cannot be reached (NU1301, 401, 403);
#   - a file of the build held by another process, the workers of MSBuild that stop (MSB4166), still after the retries.
# Usage: dotnet-problem.sh <file with the output of dotnet>

log=$1
[ -f "$log" ] || exit 1

# A compatible SDK was not found: the version global.json requested, the global.json, and what is installed
if grep -q 'A compatible \.NET SDK was not found' "$log"; then
  want=$(sed -n 's/^[[:space:]]*Requested SDK version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$log" | head -n 1)
  file=$(sed -n 's/^[[:space:]]*global\.json file:[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p' "$log" | head -n 1)
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -n "$root" ] && file=${file#"$root"/}
  # the list of the host ("8.0.425 [/usr/share/dotnet/sdk]"): wherever it lands in the output (the host writes it on
  # another stream than its message, so it often comes last)
  have=$(awk '/^[0-9]+\.[0-9]+\.[0-9]+[^ ]* \[.*\]$/ { printf "%s%s", sep, $1; sep = ", " }' "$log")
  echo "ENVIRONMENT PROBLEM: ${file:-global.json} asks for the .NET SDK ${want:-of its version}, which is not installed on this machine (installed: ${have:-none}). Stop and tell the user in one line: install that SDK (or the team moves global.json to an installed one). Never change global.json or its rollForward yourself."
  exit 0
fi

# A project that targets a .NET newer than the SDK
if grep -q 'NETSDK1045' "$log"; then
  what=$(grep -m 1 'NETSDK1045' "$log" | sed -n 's/.*does not support targeting \(\.NET [0-9][0-9.]*[0-9]\).*/\1/p')
  echo "ENVIRONMENT PROBLEM: a project targets ${what:-a .NET} newer than the .NET SDK of this machine ($(dotnet --version 2>/dev/null | head -n 1)). Stop and tell the user in one line: install the SDK of that .NET version. Never lower the target framework of a project yourself."
  exit 0
fi

# The test host needs a runtime that is not installed: "Framework: 'Microsoft.NETCore.App', version '8.0.0' (x64)"
if grep -q -E 'You must install (or update )?\.NET to run this application' "$log"; then
  need=$(sed -n "s/.*Framework: '\([^']*\)', version '\([^']*\)'.*/\1 \2/p" "$log" | head -n 1)
  if [ -n "$need" ]; then
    name=${need% *} version=${need#* }
    major=${version%%.*}
    found=$(awk '/The following frameworks were found:/ { on = 1; next }
                 on && /^[[:space:]]+[0-9]/ { sub(/^[[:space:]]+/, ""); printf "%s%s", sep, $1; sep = ", " }
                 on && !/^[[:space:]]+[0-9]/ && !/frameworks were found/ { if (sep != "") exit }' "$log")
    case "$name" in
      Microsoft.AspNetCore.App) runtime="the ASP.NET Core runtime $major" ;;
      Microsoft.WindowsDesktop.App) runtime="the Windows Desktop runtime $major (Windows only)" ;;
      *) runtime="the .NET runtime $major" ;;
    esac
    echo "ENVIRONMENT PROBLEM: the tests run on $name $version (a net$major.0 project), which is not installed on this machine (found: ${found:-none}). Stop and tell the user in one line: install $runtime. Never change the target framework of a project, never roll it forward to another runtime yourself."
  else
    echo "ENVIRONMENT PROBLEM: the test host does not find the .NET runtime (DOTNET_ROOT is missing). Stop and tell the user in one line: add DOTNET_ROOT to ~/.zshenv (see the README of the pack), then restart OpenCode."
  fi
  exit 0
fi

# A workload the project needs (Blazor WebAssembly AOT, MAUI…)
if grep -q 'NETSDK1147' "$log"; then
  names=$(grep -m 1 'NETSDK1147' "$log" | sed -n 's/.*must be installed: \([^[]*\).*/\1/p' | sed 's/[[:space:]]*$//')
  echo "ENVIRONMENT PROBLEM: this project needs the .NET workload ${names:-it names}, not installed on this machine. Stop and tell the user in one line: install it outside OpenCode (dotnet workload install ${names:-<workload>})."
  exit 0
fi

# A Windows project (WPF, Windows Forms, a -windows framework) on this machine
if grep -q 'NETSDK1100' "$log"; then
  project=$(grep -m 1 'NETSDK1100' "$log" | sed -n 's/.*\[\([^]]*\.[a-z]*proj\)\].*/\1/p')
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  [ -n "$root" ] && project=${project#"$root"/}
  echo "ENVIRONMENT PROBLEM: ${project:-a project} targets Windows (WPF, Windows Forms or a -windows framework) and does not build on this machine. Stop and tell the user in one line: build a solution filter (.slnf) without it, named in AGENTS.md « Build & test »."
  exit 0
fi

# A .NET Framework project (net48) without its reference assemblies: it builds on Windows only
if grep -q 'MSB3644' "$log"; then
  what=$(grep -m 1 'MSB3644' "$log" | sed -n 's/.*for \(\.NETFramework,Version=v[0-9.]*\).*/\1/p')
  echo "ENVIRONMENT PROBLEM: a .NET Framework project (${what:-.NETFramework}) needs the reference assemblies of Windows to build. Stop and tell the user in one line: build a solution filter (.slnf) without it, named in AGENTS.md « Build & test » (or the team adds the Microsoft.NETFramework.ReferenceAssemblies package). Never change its target framework yourself."
  exit 0
fi

# Tests that need a service of the machine: Docker (Testcontainers), SQL Server LocalDB (Windows only)
if grep -q -E 'Docker is either not running or misconfigured|DockerUnavailableException|Cannot connect to the Docker daemon' "$log"; then
  echo "ENVIRONMENT PROBLEM: some tests need Docker (Testcontainers), which is not running on this machine: they fail for that reason, not because of the code. Stop and tell the user in one line, or run the other tests with the filter of AGENTS.md « Build & test » (for instance --filter \"Category!=Integration\"). Never change or skip these tests."
  exit 0
fi
if grep -q -E 'LocalDB is not supported on this platform' "$log"; then
  echo "ENVIRONMENT PROBLEM: some tests need SQL Server LocalDB, which exists on Windows only: they fail for that reason, not because of the code. Stop and tell the user in one line, or run the other tests with the filter of AGENTS.md « Build & test ». Never change or skip these tests."
  exit 0
fi

# A file of the build that another process holds (the scripts retried it first: transient.sh): the application started
# from a terminal or by Rider, a build of Rider at the same moment; or the workers of MSBuild that stop
if grep -q -E 'used by another process|is locked by' "$log"; then
  who=$(grep -o -E 'locked by: "[^"]*"' "$log" | head -n 1 | sed 's/^locked by: //')
  echo "ENVIRONMENT PROBLEM: a file of the build is held by another process${who:+ ($who)}, again after the retries: the application started from a terminal or by Rider, or a build of Rider at the same moment. Stop and tell the user in one line: stop it, then run again. Never change a project or its output folder to get around it."
  exit 0
fi
if grep -q 'MSB4166' "$log"; then
  echo "ENVIRONMENT PROBLEM: the worker processes of MSBuild stopped during the build (MSB4166), again after the retries: the machine lacks memory, or a build server is stuck. Stop and tell the user in one line: dotnet build-server shutdown, outside OpenCode, then run again."
  exit 0
fi

# The package feed
if grep -q -E 'NU1301|Response status code does not indicate success: 40[13]|\((Unauthorized|Forbidden)\)' "$log"; then
  echo "ENVIRONMENT PROBLEM: the package feed (Artifactory) refused access or cannot be reached (NU1301, 401 or 403). Stop and tell the user in one line. Never read nuget.config, NuGet.Config or environment variables, never set them in a command, and never retry with other options."
  exit 0
fi
exit 1
