#!/usr/bin/env python3
"""Regenerates the one-line `permission:` frontmatter of every agent of the v2 pack (agents/), and opencode.snippet.json.

Run from the v2 folder: python3 tools/permissions.py
Then check every decision with the simulator of tools/README.md (a port of OpenCode 1.19's permission engine).

How OpenCode 1.19 decides (verified in its source):
- Each command of a shell call (pipes, &&, ;, $(...) included) is checked on its own, with its full text,
  redirections included. Rules are wildcards (`*` = anything, `?` = one character), case-sensitive, and the LAST
  matching rule wins: the order of the keys is the policy. A pattern ending with " *" also matches the bare command.
- An agent's rules are: OpenCode defaults, then the global `permission` of opencode.json, then the agent's own.
- A refusal sends the model EVERY bash rule of the agent as JSON (10 KB and more): each wrong refusal costs a turn,
  thousands of tokens, and shows the model which forms would pass. Hence: no rule that refuses a normal command
  (a path, a branch name or a commit message that contains "password" or "config", a C# generic inside a search).
- `export`, `declare`, `readonly`, `typeset`, `local` and `[ ... ]` are never checked (tree-sitter does not parse
  them as commands): the defense against an environment dump of these forms is the prompt (AGENTS.md "Speed").
- An approval answered "always" is stored for the whole OpenCode instance, for EVERY agent and session, and comes after
  every rule (permission/index.ts: evaluate(..., ruleset, approved)). Its pattern is wide: "rm *" for any rm, "dotnet *"
  for any dotnet command (arity.ts), "*" for the read and edit tools. One "always" on an ask would lift the refusals of
  every agent until OpenCode restarts. Hence: NO "ask" rule on bash, read or edit, anywhere; what used to ask is refused.
  Only external_directory still asks (its approval covers one folder), and only the build agent meets it: the pack
  plugin refuses a path outside the repository for the agents of the pack before OpenCode would ask.
- A shell command whose text names a path outside the repository is refused by the pack plugin (openrd-pack.js),
  which sees through quotes, `sh -c` and redirections: tree-sitter rules cannot.
Duplicate keys are forbidden: OpenCode's YAML parser (gray-matter) rejects them.
"""
import json
import re
import sys

# The ticket sheets: .git/opencode-tickets in the main checkout; from a worktree (an OpenCode workspace), the same
# folder of the main checkout, outside the worktree (a path that starts with ../ for the edit tools)
TICKET_SHEETS = ".git/opencode-tickets/**"
TICKET_SHEETS_OUTSIDE = "*/.git/opencode-tickets/*"

# The pack's scripts, whatever the way the model writes their path (~, $HOME or absolute). `sh -c ...` never matches:
# the script path must follow `sh ` directly.
SCRIPTS = ["sh ~/.config/opencode/scripts/*", "sh $HOME/.config/opencode/scripts/*",
           "sh /*/.config/opencode/scripts/*", "bash ~/.config/opencode/scripts/*"]

READ = ["ls*", "pwd", "cd *", "cat *", "head*", "tail*", "wc*", "sort*", "uniq*", "comm *", "paste *", "column *",
        "nl *", "tac *", "cut *", "tr *", "find *", "grep *",
        "egrep *", "rg *", "tree*", "file *", "stat *", "which *", "command -v *", "realpath *", "basename *",
        "dirname *", "date*", "echo *", "printf *", "sed -n*", "jq *", "diff *", "test *", "[ *", "true"]
GIT_READ = ["git status*", "git log*", "git diff*", "git show*", "git branch*", "git fetch*", "git rev-parse*",
            "git ls-files*", "git ls-tree*", "git grep*", "git blame*", "git describe*", "git tag", "git tag -l*",
            "git tag --list*", "git merge-base*", "git shortlog*", "git cat-file*", "git for-each-ref*",
            "git rev-list*", "git name-rev*", "git diff-tree*", "git remote", "git stash list*", "git stash show*",
            "git reflog", "git reflog show*", "git worktree list*", "git --no-pager log*", "git --no-pager diff*",
            "git --no-pager show*"]
# Writes reachable through the read allows above (git branch*, git diff/log/show --output)
GIT_READ_GUARD = ["git branch -d*", "git branch -D*", "git branch -m*", "git branch -M*", "git branch -c*",
                  "git branch -C*", "git branch -f*", "git branch --delete*", "git branch --move*", "git branch --copy*",
                  "git branch --force*", "git branch * -D*", "git branch * -f*", "git branch * --force*",
                  "git diff*--output*", "git log*--output*", "git show*--output*"]
DOTNET_INFO = ["dotnet --info", "dotnet --version", "dotnet --list-sdks", "dotnet --list-runtimes", "dotnet list*",
               "dotnet nuget why*"]
DOTNET_RUN = ["dotnet build*", "dotnet test*", "dotnet restore*"]
FRONT_TEST = ["npm test*", "npm run test*", "npx jest*", "npx vitest*", "npx ng test*", "yarn test*", "pnpm test*",
              "npm ls*", "node --version", "npm --version"]
FRONT_BUILD = ["npm run build*", "npx tsc*", "npx ng build*"]
# The read-only forms of the format and lint checks that the CI runs (/check); their fixing forms stay refused
CHECKS = ["dotnet format *--verify-no-changes*", "npx eslint *", "npx prettier --check *", "npx prettier -c *"]

# Read-only agents never write a file with a redirection. `>` inside a quoted search string (C# generics, lambdas)
# is not refused: only a space before `>`, `2>` and `&>` are. The harmless forms (`2>&1`, `>/dev/null`) are re-allowed,
# then a file redirection combined with them is refused again (last match wins).
REDIRECT = [("* >*", "deny"), ("*2>*", "deny"), ("*&>*", "deny"),
            ("*2>&1*", "allow"), ("*>/dev/null*", "allow"), ("*> /dev/null*", "allow"),
            ("* >*2>&1*", "deny"), ("*2>&1 >*", "deny"), ("* >>*", "deny"),
            ("*>/dev/null 2>&1*", "allow"), ("*> /dev/null 2>&1*", "allow")]
# find, sed, sort and tree forms that write a file or run commands
OTHER_DENY = ["find *-exec*", "find *-execdir*", "find *-delete*", "find *-ok*", "find *-fprint*", "find *-fls*",
              "sed *-i*", "sed *--in-place*", "sort -o *", "sort * -o *", "sort *--output*", "tree -o *",
              "tree * -o *", "*--fix*", "*--write*"]
SUBST = ["*$(*", "*${*", "*`*"]

# ---------- secrets: refused for every agent, build and dev included ----------
# Files that hold credentials. *?u?et.?onfig* = nuget.config, NuGet.Config, NuGet.config, Nuget.Config.
SECRET_FILES = ["*?u?et.?onfig*", "*.nuget/NuGet*", "*/.z*", "*zshrc*", "*/.bash*", "*/.profile*", "*/.ssh/*",
                "*/.aws/*", "*/.docker/*", "*.npmrc*", "*.netrc*", "*.pypirc*", "*.git-credentials*",
                "*/proc/*environ*", "*appsec-ci.env*", "* .env*", "*/.env*", "*opencode.json*",
                "*opencode/auth.json*", "*/git/credential*", "*git-credential*"]
# Environment dumps and credential-bearing git output (a remote URL or the git config can hold a token)
ENV_DUMP = ["env", "env *", "printenv*", "set", "compgen*", "*echo *$*", "*printf *$*", "*artifactory_*",
            "dotnet user-secrets*", "git config*", "git remote -v*", "git remote get-url*", "git remote show*"]
# Names of secret environment variables. Upper case only: code names (PasswordValidator, CancellationToken), branch
# names and paths (reset-password, credentials/) stay usable.
SECRET_NAMES = ["*PASSWORD*", "*PASSWD*", "*TOKEN*", "*SECRET*", "*CREDENTIAL*", "*API_KEY*", "*APIKEY*"]
SECRETS = SECRET_FILES + ENV_DUMP + SECRET_NAMES
# The GitLab credentials that git finds by itself (COMMANDES.md, "Identifiants GitLab"): `git credential fill` would
# print them, from any helper (cache, store, keychain, manager), and so would the socket of the cache helper or the
# keychain tools (macOS `security`, which may also hold the Artifactory token; Linux `secret-tool`). Global rules
# only, for build and dev: the agents with their own bash rules never allow these commands.
# (their files, ~/.git-credentials and ~/.config/git/credentials, are in SECRET_FILES)
CREDENTIAL_STORES = ["git credential*", "security", "security *", "secret-tool*"]
# build and dev: never look inside a package or build a tool to look inside an assembly (reflection program in /tmp
# or a console project, decompilers, `strings`). What the agents need about packages is printed by package-refs.sh
# (in-house or not, frameworks, XML documentation path), the API comes from the existing calls (AGENTS.md).
DECOMPILE = ["* /tmp/*", "* /tmp", "*=/tmp/*", "*\"/tmp/*", "*'/tmp/*", "mktemp*", "*.nuget/packages*", "*.dll*",
             "*.nupkg*", "dotnet new console*", "dotnet fsi*", "dotnet script*", "*ilspy*", "*ildasm*", "monodis*",
             "strings *"]
# Running a program or installing a tool (a reflection program is run with dotnet run): refused for every agent. They
# used to ask, but an "always" answer would have allowed "dotnet *" to every agent.
RUN_DENY = ["dotnet run*", "dotnet tool install*", "dotnet tool update*"]
# History-changing git commands and recursive deletions: refused for the conversation agents too (they used to ask, and
# "always" would have allowed "git push *" or "rm *" to every agent). Git history is written by /go and /fix only.
HISTORY_DENY = ["git push*", "git reset*", "git rebase*", "git commit*", "git merge", "git merge *", "git pull*",
                "git cherry-pick*", "git revert*", "git am*"]
# (the pack plugin refuses every recursive rm whatever the order of its options; these rules are the second layer)
RM_RECURSIVE = ["rm -r*", "rm -R*", "rm -fr*", "rm -fR*", "rm -f -r*", "rm -f -R*", "rm *--recursive*", "rm * -r*",
                "rm * -R*", "rm * -fr*", "rm * -fR*"]
# The pack's scripts that write: git (branch.sh, ship.sh) and the ticket sheet (ticket-sheet.sh). Only the pilot runs
# them: with SCRIPTS allowed, a read-only agent could otherwise commit and push through ship.sh.
# workspace.sh creates and removes worktree folders outside the repository: the developer runs it, never an agent.
DEVELOPER_SCRIPTS = ["*scripts/workspace.sh*"]
# fortify.sh discard puts work aside (git stash): the pilot only
WRITE_SCRIPTS = ["*ship.sh*", "*branch.sh*", "*ticket-sheet.sh*", "*fortify.sh discard*"] + DEVELOPER_SCRIPTS

# The only allowed read of appsec-ci.env: the line with the Fortify application name (re-allowed after SECRETS)
SSC_NAME = "git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'"

MCP_WRITE_DENY = [(p, "deny") for p in ["*create*", "*update*", "*delete*", "*remove*", "*upload*", "*add_*",
                                         "*approve*", "*assign*", "*accept*", "*transition_issue*", "*do_transition*",
                                         "*merge_merge_request*", "*change_status*", "*set_*",
                                         # status changes of Sonar and Fortify issues, comments, discussions and the
                                         # pipelines of GitLab (a retried or cancelled job is a write too)
                                         "*change_*", "*suppress*", "*resolve*", "*post_*", "*publish*", "*edit_*",
                                         "*close_*", "*reopen*", "*retry*", "*cancel*", "*trigger*", "*play_*",
                                         "*rebase*", "*mark_*"]]
CONFLUENCE_WRITE = [(p, "ask") for p in ["*confluence*create*", "*confluence*update*", "*confluence*upload*",
                                         "*Confluence*create*", "*Confluence*update*", "*Confluence*upload*"]]
# MCP servers, matched by tool name (OpenCode names MCP tools "<server>_<tool>"). Hiding a server from an agent
# removes its tool descriptions from every request of that agent: faster and less confusing for the model.
MCP_SERVERS = {
    "jira": ["*jira*", "*Jira*", "*JIRA*"],
    "confluence": ["*confluence*", "*Confluence*"],
    "gitlab": ["*gitlab*", "*GitLab*", "*Gitlab*"],
    "sonar": ["*sonar*", "*Sonar*"],
    "fortify": ["*fortify*", "*Fortify*"],
    "kibana": ["*kibana*", "*Kibana*", "*elastic*", "*Elastic*"],
}


def allow(patterns):
    return [(p, "allow") for p in patterns]


def deny(patterns):
    return [(p, "deny") for p in patterns]


def mcp_only(keep):
    return [(p, "deny") for server, patterns in MCP_SERVERS.items() if server not in keep for p in patterns]


# /doc: configuration values never reach the documentation. config-keys.sh prints every key without its value; the
# configuration files themselves stay closed to doc-writer, through the read tool and through the shell.
CONFIG_FILES_READ = ["*appsettings*.json", "*launchSettings.json", "*?eb.config", "*?eb.*.config", "*?pp.config",
                     "*?pp.*.config", "*.env", "*.env.*", "*/environments/environment*.ts"]
CONFIG_FILES_BASH = ["*appsettings*", "*launchSettings*", "*eb.config*", "*eb.*.config*", "*pp.config*",
                     "*pp.*.config*", "*environments/environment*"]


# Read-only agents never browse the package cache or look at assemblies either (their read allows would let them):
# package-refs.sh gives what they need. Not for the debugger, which may check the assemblies of bin/ (FileLoadException).
PACKAGE_GUARD = ["*.nuget/packages*", "*.dll*", "*.nupkg*"]


def read_only_bash(extra_allows=(), after_secrets=(), package_guard=True):
    rules = [("*", "deny")]
    rules += allow(READ + GIT_READ + SCRIPTS + DOTNET_INFO + list(extra_allows))
    rules += REDIRECT
    rules += deny(GIT_READ_GUARD + OTHER_DENY + SUBST + SECRETS + WRITE_SCRIPTS
                  + (PACKAGE_GUARD if package_guard else []))
    rules += allow(after_secrets)
    return rules


def only(paths):
    return [("*", "deny")] + allow(paths)


BASE = [("webfetch", "deny"), ("websearch", "deny"), ("question", "allow")]
# The agents that work while nobody watches never ask anything: a question would stop the whole run
SILENT = [("webfetch", "deny"), ("websearch", "deny"), ("question", "deny")]
# The same tool call repeated three times in a row (doom_loop) is refused for every agent (global rule below): a
# subagent of /go then ends with an error that the pilot handles, instead of waiting for an approval nobody gives
NO_TASK = [("task", "deny")]
SHEET = [("edit", only([TICKET_SHEETS, TICKET_SHEETS_OUTSIDE]))]
NO_EDIT = [("edit", "deny")]

# The pack scripts that receive free text (a commit message, a decision, a line of the ticket sheet): re-allowed after
# the secret rules, so that a message that mentions a TOKEN constant or nuget.config is not refused, then refused
# again when a part of it would come from a command (substitution rules come last)
TEXT_SCRIPTS = [s + p for s in ["sh ~/.config/opencode/scripts/", "sh $HOME/.config/opencode/scripts/",
                                "sh /*/.config/opencode/scripts/"]
                for p in ["ship.sh *", "ticket-sheet.sh *", "branch.sh *"]]


def pilot_bash():
    # Read-only, plus the build and tests (full suite before the push) and the pack scripts; every git write goes
    # through branch.sh and ship.sh, which refuse protected branches, force-pushes and rebases. The substitution rules
    # come last, after the scripts that take free text: a commit message never runs a command.
    rules = [("*", "deny")]
    rules += allow(READ + GIT_READ + SCRIPTS + DOTNET_INFO + DOTNET_RUN + FRONT_TEST + FRONT_BUILD + CHECKS)
    rules += REDIRECT
    rules += deny(GIT_READ_GUARD + OTHER_DENY + SECRETS + PACKAGE_GUARD + DEVELOPER_SCRIPTS)
    rules += allow([SSC_NAME] + TEXT_SCRIPTS)
    rules += deny(SUBST)
    return rules


# The coder works alone, so it gets an allowlist like the pilot (it used to have "*": allow minus refusals, which let
# through curl, `dotnet add package`, `dotnet ef database update`, `bash -c`, a redirection into .git/config or into
# ~/.config/opencode, and ship.sh): reads, git reads, the build and its tools, the front-end tooling, file moves inside
# the repository. Everything else is refused at once, without asking. Files are written with the edit and write tools.
CODER_BUILD = ["dotnet clean*", "dotnet format*", "dotnet build-server shutdown*", "dotnet tool restore*",
               # EF Core migrations that never touch a database (`database update`, `migrations remove` and a plain
               # `migrations list` connect to one)
               "dotnet ef migrations add *", "dotnet ef migrations script*", "dotnet ef migrations list --no-connect*",
               "dotnet ef migrations has-pending-model-changes*", "dotnet ef --version",
               # project references between projects of the repository (a PACKAGE reference is never added here)
               "dotnet add * reference *", "dotnet add reference *", "dotnet remove * reference *",
               "dotnet remove reference *", "dotnet sln list*", "dotnet sln * list*"]
CODER_FRONT = ["npm run lint*", "npm run format*", "npx eslint *", "npx prettier *", "npx ng lint*", "npx ng generate *",
               "npx ng g *", "npm ci*", "npm install", "npm i", "yarn install --frozen-lockfile*",
               "yarn install --immutable*", "pnpm install --frozen-lockfile*"]
CODER_FILES = ["mkdir *", "touch *", "cp *", "mv *", "rm *", "chmod +x *",
               "xargs grep *", "xargs -0 grep *", "xargs -r grep *", "xargs -0r grep *", "xargs -r0 grep *",
               "xargs wc *", "xargs -0 wc *", "xargs ls *"]
# One file removed at a time, never a folder (the plugin refuses a path outside the repository)
CODER_RM_GUARD = RM_RECURSIVE + ["rm *..*"]
# find and sed forms that write or run commands; the fixing forms of the linters stay allowed for the coder
CODER_OTHER_DENY = [p for p in OTHER_DENY if p not in ("*--fix*", "*--write*")]


def coder_bash():
    rules = [("*", "deny")]
    rules += allow(READ + GIT_READ + SCRIPTS + DOTNET_INFO + DOTNET_RUN + CODER_BUILD + FRONT_TEST + FRONT_BUILD
                   + CODER_FRONT + CODER_FILES)
    rules += REDIRECT
    # (the commands of CREDENTIAL_STORES and DECOMPILE are not in the allowlist; their paths are outside the repository)
    rules += deny(GIT_READ_GUARD + CODER_OTHER_DENY + CODER_RM_GUARD + SECRETS + WRITE_SCRIPTS + PACKAGE_GUARD
                  + ["* /tmp/*", "* /tmp", "*=/tmp/*", "*\"/tmp/*", "*'/tmp/*"] + SUBST)
    return rules


AGENTS = {
    # /go, /fix, /daily: every MCP server, read-only, except the creation of the merge request of the branch
    "pilot": SHEET + BASE + [("task", only(["analyst", "coder", "checker", "debugger", "test-guardian"]))]
    + [("bash", pilot_bash())] + MCP_WRITE_DENY + [("*create_merge_request", "allow")]
    + mcp_only(["jira", "confluence", "gitlab", "sonar", "fortify"]),
    "analyst": SHEET + SILENT + NO_TASK + [("bash", read_only_bash())] + MCP_WRITE_DENY
    + mcp_only(["jira", "confluence", "gitlab"]),
    # code and tests anywhere in the repository except .git (the ticket sheet is the pilot's), no MCP
    "coder": [("edit", [("*", "allow"), ("../*", "deny"), (".git/**", "deny"), ("*/.git/**", "deny")])] + SILENT
    + NO_TASK + [("bash", coder_bash())] + mcp_only([]),
    # /fortify: the tests of one vulnerability, in the test projects only (fortify.sh tests-only checks it again), no MCP
    "test-guardian": [("edit", only(["*Tests/**", "*Test/**", "tests/**", "test/**", "*/tests/**", "*/test/**"]))] + SILENT
    + NO_TASK + [("bash", coder_bash())] + mcp_only([]),
    "checker": NO_EDIT + SILENT + NO_TASK
    + [("bash", read_only_bash(DOTNET_RUN + FRONT_TEST + FRONT_BUILD + CHECKS))] + MCP_WRITE_DENY + mcp_only(["jira"]),
    # /compare asks me which check I make when the cause is not confirmed (as the agent of the command); as a subagent
    # of /go or /fix it cannot ask (experimental.primary_tools in opencode.json)
    "debugger": NO_EDIT + BASE + NO_TASK
    + [("bash", read_only_bash(DOTNET_RUN + FRONT_TEST + FRONT_BUILD, package_guard=False))]
    + MCP_WRITE_DENY + mcp_only(["kibana"]),
    # /outil doc: writes docs/ and the root README.md only, never opens a configuration file, never publishes
    "doc-writer": [("edit", only(["docs/**", "README.md"])), ("read", deny(CONFIG_FILES_READ))] + SILENT
    + NO_TASK + [("bash", read_only_bash() + deny(CONFIG_FILES_BASH))] + MCP_WRITE_DENY + mcp_only([]),
}

TOOL_KEYS = {"edit", "read", "bash", "webfetch", "websearch", "question", "task", "doom_loop"}


def q(key):
    # Only tool names stay bare: a bare `true` or `on` would be read as a boolean by YAML.
    if key in TOOL_KEYS:
        return key
    return '"' + key.replace("\\", "\\\\").replace('"', '\\"') + '"'


def check_dupes(rules):
    keys = [k for k, _ in rules]
    dupes = {k for k in keys if keys.count(k) > 1}
    if dupes:
        sys.exit(f"duplicate keys: {sorted(dupes)}")


def flow(rules):
    check_dupes(rules)
    return "{ " + ", ".join(f"{q(k)}: {flow(v) if isinstance(v, list) else v}" for k, v in rules) + " }"


for name, rules in AGENTS.items():
    path = f"agents/{name}.md"
    text = open(path).read()
    text, count = re.subn(r"^permission: .*$", lambda _: "permission: " + flow(rules), text, count=1, flags=re.M)
    if count != 1:
        sys.exit(f"{path}: no permission line")
    open(path, "w").write(text)
    print("updated", path)


# ---------- opencode.snippet.json (merged by hand into ~/.config/opencode/opencode.json) ----------

def as_dict(rules):
    check_dupes(rules)
    return {k: as_dict(v) if isinstance(v, list) and v and isinstance(v[0], tuple) else v for k, v in rules}


# Qwen 3.8 recommended sampling for thinking mode (its model card: temperature 1.0, top_p 0.95, top_k 20 in the model options)
SAMPLING = [("temperature", 1.0), ("top_p", 0.95)]
# The conversation agents (build, general, explore) run any command but these. They are not global rules: the agents
# of the pack have complete shell rules of their own (starting with "*": deny), and OpenCode repeats every rule that
# applies to an agent in the message of each refusal (5 KB more per refusal for nothing).
CONVERSATION_BASH = deny(HISTORY_DENY + RM_RECURSIVE + RUN_DENY + WRITE_SCRIPTS + SECRETS + CREDENTIAL_STORES + DECOMPILE)
SNIPPET = as_dict([
    ("$schema", "https://opencode.ai/config.json"),
    ("agent", [
        # build runs /outil and the free conversation: it may publish a Confluence page of /outil doc or
        # /outil release-notes, each write asked first; never in Jira
        ("build", SAMPLING + [("permission", [("task", [("*", "allow")]), ("bash", CONVERSATION_BASH)]
                                         + CONFLUENCE_WRITE)]),
        ("general", SAMPLING + [("permission", [("bash", CONVERSATION_BASH)])]),
        ("explore", SAMPLING + [("permission", [("bash", CONVERSATION_BASH)])]),
        ("plan", SAMPLING + [("permission", [("bash", read_only_bash())])]),
    ]),
    # Every agent, built-in ones included (build, plan, general, explore): no secret read through the shell or the
    # read tool, no git history written outside /go and /fix, nothing that asks (an "always" answer would apply to every
    # agent), and MCP write tools hidden (read-only on Jira, Confluence, GitLab, Sonar, Fortify; the pilot re-allows the
    # creation of its merge request, build its Confluence pages with approval, with their own rules, which come after).
    ("permission", [
        ("question", "allow"),
        # the built-in skill "report" of OpenCode v2 collects the configuration and publishes a GitHub issue with gh
        ("skill", [("*", "allow"), ("report", "deny")]),
        ("doom_loop", "deny"),
        # OpenCode v2 tools: a worktree or a moved session is the developer's choice, in the web interface (the pack
        # plugin refuses them too), by their names and by their names in code mode
        ("session_move", "deny"),
        ("worktree_create", "deny"),
        ("worktree_remove", "deny"),
        ("opencode_session_move", "deny"),
        ("opencode_worktree_create", "deny"),
        ("opencode_worktree_remove", "deny"),
        # code mode runs JavaScript that can call any address, without any permission; the web search sends the query
        # to an outside service (the pack plugin takes both out of every request)
        ("execute", "deny"),
        ("websearch", "deny"),
        # Readable without asking: the NuGet package cache (XML documentation of in-house packages), the skills and the
        # pack's scripts (an approval is kept only until OpenCode restarts, and per project). Never written: the edit
        # rules below, and the pack plugin for the shell (these folders are read-only to every agent)
        ("external_directory", allow(["~/.nuget/packages/*", "~/.config/opencode/skills/*",
                                      "~/.config/opencode/scripts/*", TICKET_SHEETS_OUTSIDE])),
        # No agent writes outside the repository of its session (the edit tools see paths relative to the repository:
        # ../ means outside), except /outil pattern into a pattern skill
        ("edit", deny(["../*"]) + allow(["*/.config/opencode/skills/pattern-*"])),
        # the read tool sees paths relative to the repository root too (../../.nuget/NuGet/NuGet.Config). The .env
        # files are refused instead of asked: "always" on that question would allow every read of every agent.
        ("read", deny(["*/.nuget/NuGet/*", "*?u?et.?onfig", "*appsec-ci.env", "*opencode.json",
                       "*opencode/auth.json", "*/.ssh/*", "*/.aws/*", "*/.z*", "*zshrc*", "*.netrc",
                       "*.git-credentials", "*.npmrc", "*.env", "*.env.*"])
         + allow(["*.env.example", "*.env.sample", "*.env.template"])),
    ] + MCP_WRITE_DENY),
    # A subagent never gets the question tool: nobody answers during /go or /fix (the debugger keeps it as the agent of
    # /compare, a primary session)
    ("experimental", [("primary_tools", ["question"])]),
    # Outputs of tools from the older turns of a long session (/daily, then /go, then /fix) are erased from the
    # context; the last two turns stay whole
    ("compaction", [("prune", True)]),
    # Nothing goes to opencode.ai or to a search service: no session shared on a public link, no update checked or
    # installed by OpenCode itself (a new version is a package you download on purpose, MIGRATION.md), no web search
    # (also refused by the rules above and taken out of every request by the pack plugin)
    ("share", "disabled"),
    ("autoupdate", False),
    ("websearch", False),
])
with open("opencode.snippet.json", "w") as out:
    json.dump(SNIPPET, out, indent=2, ensure_ascii=False)
    out.write("\n")
print("updated opencode.snippet.json")
