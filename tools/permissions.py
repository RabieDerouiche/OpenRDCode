#!/usr/bin/env python3
"""Regenerates the one-line `permission:` frontmatter of every agent in ../agents, and opencode.snippet.json.

Run from the repository root: python3 tools/permissions.py
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
Duplicate keys are forbidden: OpenCode's YAML parser (gray-matter) rejects them.
"""
import json
import re
import sys

TICKET_SHEETS = ".git/opencode-tickets/**"

# The pack's scripts, whatever the way the model writes their path (~, $HOME or absolute). `sh -c ...` never matches:
# the script path must follow `sh ` directly.
SCRIPTS = ["sh ~/.config/opencode/scripts/*", "sh $HOME/.config/opencode/scripts/*",
           "sh /*/.config/opencode/scripts/*", "bash ~/.config/opencode/scripts/*"]

READ = ["ls*", "pwd", "cd *", "cat *", "head*", "tail*", "wc*", "sort*", "uniq*", "cut *", "tr *", "find *", "grep *",
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

# Read-only agents never write a file with a redirection. `>` inside a quoted search string (C# generics, lambdas)
# is not refused: only a space before `>`, `2>` and `&>` are. The harmless forms (`2>&1`, `>/dev/null`) are re-allowed,
# then a file redirection combined with them is refused again (last match wins).
REDIRECT = [("* >*", "deny"), ("*2>*", "deny"), ("*&>*", "deny"),
            ("*2>&1*", "allow"), ("*>/dev/null*", "allow"), ("*> /dev/null*", "allow"),
            ("* >*2>&1*", "deny"), ("*2>&1 >*", "deny"), ("* >>*", "deny"),
            ("*>/dev/null 2>&1*", "allow"), ("*> /dev/null 2>&1*", "allow")]
# find and sed forms that write or run commands
OTHER_DENY = ["find *-exec*", "find *-execdir*", "find *-delete*", "find *-ok*", "find *-fprint*", "find *-fls*",
              "sed *-i*", "sed *--in-place*"]
SUBST = ["*$(*", "*${*", "*`*"]

# ---------- secrets: refused for every agent, build and dev included ----------
# Files that hold credentials. *?u?et.?onfig* = nuget.config, NuGet.Config, NuGet.config, Nuget.Config.
SECRET_FILES = ["*?u?et.?onfig*", "*.nuget/NuGet*", "*/.z*", "*zshrc*", "*/.bash*", "*/.profile*", "*/.ssh/*",
                "*/.aws/*", "*/.docker/*", "*.npmrc*", "*.netrc*", "*.pypirc*", "*.git-credentials*",
                "*/proc/*environ*", "*appsec-ci.env*", "* .env*", "*/.env*", "*opencode.json*",
                "*opencode/auth.json*"]
# Environment dumps and credential-bearing git output (a remote URL or the git config can hold a token)
ENV_DUMP = ["env", "env *", "printenv*", "set", "compgen*", "*echo *$*", "*printf *$*", "*artifactory_*",
            "dotnet user-secrets*", "git config*", "git remote -v*", "git remote get-url*", "git remote show*"]
# Names of secret environment variables. Upper case only: code names (PasswordValidator, CancellationToken), branch
# names and paths (reset-password, credentials/) stay usable.
SECRET_NAMES = ["*PASSWORD*", "*PASSWD*", "*TOKEN*", "*SECRET*", "*CREDENTIAL*", "*API_KEY*", "*APIKEY*"]
SECRETS = SECRET_FILES + ENV_DUMP + SECRET_NAMES

# The only allowed read of appsec-ci.env: the line with the Fortify application name (re-allowed after SECRETS)
SSC_NAME = "git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'"

MCP_WRITE_DENY = [(p, "deny") for p in ["*create*", "*update*", "*delete*", "*remove*", "*upload*", "*add_*",
                                         "*approve*", "*assign*", "*accept*", "*transition_issue*", "*do_transition*",
                                         "*merge_merge_request*", "*change_status*", "*set_*"]]
# release-writer: may create or update ONE Confluence page, each write asks first...
MCP_RELEASE = [("*create*", "ask"), ("*update*", "ask"), ("*upload*", "ask")] + \
              [r for r in MCP_WRITE_DENY if r[0] not in ("*create*", "*update*", "*upload*")]
# ...but never in Jira
MCP_RELEASE += [(p, "deny") for p in ["*jira*create*", "*jira*update*", "*Jira*create*", "*Jira*update*",
                                      "*JIRA*create*", "*JIRA*update*"]]

# test-writer: test projects at the root or nested (App.Tests/, tests/App.Tests/, src/App.UnitTests/, App.Test/),
# test folders, and front-end test files. Never production code.
TEST_PATHS = ["*Tests/**", "*.Test/**", "test/**", "tests/**", "*/test/**", "*/tests/**", "*__tests__/**",
              "*.spec.ts", "*.test.ts", "*.spec.tsx", "*.test.tsx", "*.spec.js", "*.test.js", "*.spec.jsx",
              "*.test.jsx"]

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


def ask(patterns):
    return [(p, "ask") for p in patterns]


def deny(patterns):
    return [(p, "deny") for p in patterns]


def mcp_only(keep):
    return [(p, "deny") for server, patterns in MCP_SERVERS.items() if server not in keep for p in patterns]


def read_only_bash(extra_allows=(), after_secrets=()):
    rules = [("*", "deny")]
    rules += allow(READ + GIT_READ + SCRIPTS + DOTNET_INFO + list(extra_allows))
    rules += REDIRECT
    rules += deny(GIT_READ_GUARD + OTHER_DENY + SUBST + SECRETS)
    rules += allow(after_secrets)
    return rules


def git_bash():
    rules = [("*", "deny")]
    rules += allow(READ + GIT_READ + SCRIPTS + DOTNET_INFO)
    # writes the git agent may do without asking (`git commit -m` comes after the secret rules, see below)
    rules += allow(["git switch *", "git checkout -b *", "git add *", "git add -A", "git commit --no-edit",
                    "git merge --abort", "git merge --ff-only origin/*", "git restore --staged *"])
    # writes that need my approval each time
    rules += ask(["git push*", "git merge origin/*", "git merge --no-edit origin/*", "git pull*", "git stash",
                  "git stash push*", "git stash pop*", "git commit --amend*", "git commit *--amend*"])
    rules += REDIRECT
    # always forbidden among the forms that the rules above let through
    rules += deny(GIT_READ_GUARD + [
        "git push", "git push origin", "git push -u origin", "git push --set-upstream origin", "git push*--force*",
        "git push* -f*", "git push*+*", "git push*HEAD*", "git push* origin develop*", "git push* origin master*",
        "git push* origin main*", "git push*:develop*", "git push*:master*", "git push*:main*", "git push*--all*",
        "git push*--mirror*", "git push*--delete*", "git push* -d *", "git push*--tags*", "git push*--prune*",
        "git pull*--rebase*", "git pull* -r*", "git pull*--force*",
        "git switch -C*", "git switch * -C*", "git switch -f*", "git switch * -f*", "git switch*--force*",
        "git switch*--discard-changes*", "git checkout -b * -f*", "git checkout*--force*"])
    rules += deny(OTHER_DENY + SECRETS)
    # /abandon: delete a ticket branch started by mistake (-d refuses a branch with unmerged work; -D and -f stay
    # forbidden) and its ticket sheet, each time with my approval
    rules += ask(["git branch -d *", "rm .git/opencode-tickets/*.md"])
    rules += deny(["git branch -d -f*", "git branch -d * -f*", "git branch -d *--force*", "git branch -d * -D*",
                   "rm .git/opencode-tickets/* ?*", "rm *..*"])
    # A commit message is free text: one that mentions a password, a TOKEN variable or nuget.config is not a secret.
    # Allowed after the secret rules, then refused again when the message would come from a file or a command
    # (the command substitution rules come last, so they apply to every command of this agent).
    rules += allow(["git commit -m *"])
    rules += ask(["git commit -m *--amend*"])
    rules += deny(["git commit -m *-F*", "git commit -m *--file*"] + SUBST)
    return rules


def only(paths):
    return [("*", "deny")] + allow(paths)


BASE = [("webfetch", "deny"), ("websearch", "deny"), ("question", "allow")]
NO_TASK = [("task", "deny")]
SHEET = [("edit", only([TICKET_SHEETS]))]
NO_EDIT = [("edit", "deny")]

AGENTS = {
    "analyst": SHEET + BASE + NO_TASK + [("bash", read_only_bash(after_secrets=[SSC_NAME]))] + MCP_WRITE_DENY,
    "architect": NO_EDIT + BASE + NO_TASK + [("bash", read_only_bash())] + mcp_only([]),
    "debugger": NO_EDIT + BASE + NO_TASK + [("bash", read_only_bash(DOTNET_RUN + FRONT_TEST + FRONT_BUILD))]
    + MCP_WRITE_DENY + mcp_only(["kibana"]),
    "reviewer": SHEET + BASE + NO_TASK + [("bash", read_only_bash(DOTNET_RUN + FRONT_TEST + FRONT_BUILD))]
    + MCP_WRITE_DENY + mcp_only(["jira"]),
    "test-writer": [("edit", only(TEST_PATHS + [TICKET_SHEETS]))] + BASE + NO_TASK
    + [("bash", read_only_bash(DOTNET_RUN + FRONT_TEST))] + MCP_WRITE_DENY + mcp_only(["jira"]),
    "release-writer": NO_EDIT + BASE + NO_TASK + [("bash", read_only_bash())] + MCP_RELEASE
    + mcp_only(["jira", "confluence"]),
    "git": SHEET + BASE + [("task", only(["reviewer", "analyst"])), ("bash", git_bash())] + MCP_WRITE_DENY
    + mcp_only(["jira", "gitlab"]),
    # build without the MCP tools (smaller requests); edit and bash stay as for build (global rules of opencode.json)
    "dev": [("task", only(["test-writer", "debugger", "architect"]))] + mcp_only([]),
}

TOOL_KEYS = {"edit", "bash", "webfetch", "websearch", "question", "task"}


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
    return {k: as_dict(v) if isinstance(v, list) else v for k, v in rules}


# Qwen 3.6 recommended sampling for thinking mode and precise coding
SAMPLING = [("temperature", 0.6), ("top_p", 0.95)]
SNIPPET = as_dict([
    ("$schema", "https://opencode.ai/config.json"),
    ("agent", [
        ("build", SAMPLING),
        ("general", SAMPLING),
        ("explore", SAMPLING),
        ("plan", SAMPLING + [("permission", [("bash", read_only_bash())])]),
    ]),
    # Every agent, built-in ones included (build, plan, general, explore): no secret read through the shell or the
    # read tool, destructive git asks first, and MCP write tools are hidden (read-only on Jira, Confluence, GitLab,
    # Sonar, Fortify; release-writer re-allows its Confluence page with its own rules, which come after these ones).
    ("permission", [
        ("question", "allow"),
        ("skill", [("*", "allow")]),
        ("bash", ask(["git push*", "git reset*", "git rebase*", "rm -rf*"]) + deny(SECRETS)),
        # the read tool sees paths relative to the repository root (../../.nuget/NuGet/NuGet.Config)
        ("read", deny(["*/.nuget/NuGet/*", "*?u?et.?onfig", "*appsec-ci.env", "*opencode.json",
                       "*opencode/auth.json", "*/.ssh/*", "*/.aws/*", "*/.z*", "*zshrc*", "*.netrc",
                       "*.git-credentials", "*.npmrc"])),
    ] + MCP_WRITE_DENY),
])
with open("opencode.snippet.json", "w") as out:
    json.dump(SNIPPET, out, indent=2, ensure_ascii=False)
    out.write("\n")
print("updated opencode.snippet.json")
