#!/usr/bin/env python3
"""Regenerates the one-line `permission:` frontmatter of every agent in ../agents, and opencode.snippet.json.

Run from the repository root: python3 tools/permissions.py
Rules are last-match-wins in OpenCode, so the order of the keys is the policy.
Duplicate keys are forbidden: OpenCode's YAML parser (gray-matter) rejects them.
"""
import json
import re
import sys

DETECT = "sh ~/.config/opencode/scripts/detect-project-type.sh*"
RELEASE = "sh ~/.config/opencode/scripts/release-commits.sh *"
STATE = "sh ~/.config/opencode/scripts/workflow-state.sh*"
LICENSES = "sh ~/.config/opencode/scripts/package-licenses.sh*"
BUILD_TEST = "sh ~/.config/opencode/scripts/build-test.sh*"
TICKET_SHEETS = ".git/opencode/**"

READ = ["ls*", "pwd", "cd *", "cat *", "head*", "tail*", "wc*", "sort*", "uniq*", "cut *", "tr *",
        "find *", "grep *", "egrep *", "rg *", "tree*", "file *", "stat *", "which *", "basename *",
        "dirname *", "date*", "echo *", "printf *", "sed -n*", "jq *", "diff *", "test *", "[ *", "true"]
GIT_READ = ["git status*", "git log*", "git diff*", "git show*", "git branch*", "git fetch*", "git rev-parse*",
            "git ls-files*", "git ls-tree*", "git grep*", "git blame*", "git describe*", "git tag", "git tag -l*",
            "git tag --list*", "git merge-base*", "git shortlog*", "git cat-file*", "git for-each-ref*",
            "git rev-list*", "git name-rev*", "git remote", "git remote -v", "git remote show*", "git remote get-url*",
            "git stash list*", "git reflog*", "git --no-pager *", "git -C *"]
DOTNET_INFO = ["dotnet --info", "dotnet --version", "dotnet --list-sdks", "dotnet --list-runtimes", "dotnet list*"]
DOTNET_RUN = ["dotnet build*", "dotnet test*", "dotnet restore*"]
FRONT_TEST = ["npm test*", "npm run test*", "npx jest*", "npx vitest*", "yarn test*", "pnpm test*", "npm ls*",
              "node --version", "npm --version"]
FRONT_BUILD = ["npm run build*", "npx tsc*"]

REDIRECT = [("*>*", "deny"), ("*2>&1*", "allow"), ("*> *", "deny"), ("*>>*", "deny"), ("*>/*", "deny"),
            ("*>~*", "deny"), ("*>.*", "deny")]
GIT_WRITE = ["git* push*", "git* commit*", "git* reset*", "git* checkout*", "git* switch*", "git* rebase*",
             "git* merge *", "git* cherry-pick*", "git* revert*", "git stash", "git* stash push*", "git* stash pop*",
             "git* stash drop*", "git* stash apply*", "git* stash clear*", "git* clean*", "git* rm *", "git* mv *",
             "git* add *", "git* restore*", "git* tag -d*", "git* tag -a*", "git* tag -f*", "git* branch -d*",
             "git* branch -D*", "git* branch -m*", "git* branch -M*", "git* branch -f*", "git* branch --delete*",
             "git* branch --move*", "git* config*", "git* remote add*", "git* remote set-url*", "git* remote remove*",
             "git* remote rm*", "git* gc*", "git* update-ref*", "git* apply*", "git* am *", "git* worktree*",
             "git* submodule*"]
OTHER_DENY = ["*-exec*", "*-execdir*", "*-delete*", "*-ok *", "*-fprint*", "*-fls*", "*sed*-i*", "*sed*--in-place*"]
SECRETS = ["*zshenv*", "*zshrc*", "*bash_profile*", "*appsec-ci.env*", "*/.ssh/*", "*/.aws/*", "*.npmrc*",
           "*credentials*", "*artifactory_*", "*echo *$*", "*printf *$*", "*$(*", "*${*", "*`*"]

MCP_WRITE_DENY = [(p, "deny") for p in ["*create*", "*update*", "*delete*", "*remove*", "*upload*", "*add_*",
                                         "*approve*", "*assign*", "*accept*", "*transition_issue*", "*do_transition*",
                                         "*merge_merge_request*", "*change_status*", "*set_*"]]
# release-writer: may create or update ONE Confluence page, each write asks first
MCP_RELEASE = [("*create*", "ask"), ("*update*", "ask"), ("*upload*", "ask")] + \
              [r for r in MCP_WRITE_DENY if r[0] not in ("*create*", "*update*", "*upload*")]
# ...but never in Jira
MCP_RELEASE += [(p, "deny") for p in ["*jira*create*", "*jira*update*", "*Jira*create*", "*Jira*update*", "*JIRA*create*", "*JIRA*update*"]]

TEST_PATHS = ["**/*Tests/**", "**/*.Tests/**", "**/*Test/**", "tests/**", "test/**", "**/__tests__/**",
              "**/*.spec.ts", "**/*.test.ts", "**/*.spec.tsx", "**/*.test.tsx", "**/*.spec.js", "**/*.test.js"]


# The only allowed read of appsec-ci.env: the line with the Fortify application name (re-allowed after SECRETS).
SSC_NAME = "git grep -h ^APPSEC_PROJECT_NAME= -- '*appsec-ci.env'"


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


def mcp_only(keep):
    return [(p, "deny") for server, patterns in MCP_SERVERS.items() if server not in keep for p in patterns]


def read_only_bash(extra_allows, after_secrets=()):
    rules = [("*", "deny")]
    rules += [(p, "allow") for p in READ + GIT_READ + extra_allows]
    rules += REDIRECT
    rules += [(p, "deny") for p in GIT_WRITE + OTHER_DENY + SECRETS]
    rules += [(p, "allow") for p in after_secrets]
    return rules


def git_bash():
    rules = [("*", "deny")]
    rules += [(p, "allow") for p in READ + GIT_READ + [DETECT, STATE]]
    # writes the git agent may do without asking
    rules += [(p, "allow") for p in ["git switch *", "git checkout -b *", "git add *", "git add -A", "git commit -m *",
                                     "git commit -F *", "git commit --no-edit", "git merge --abort",
                                     "git merge --ff-only origin/*"]]
    # writes that need my approval each time
    rules += [(p, "ask") for p in ["git push*", "git merge origin/*", "git merge --no-edit origin/*", "git pull*",
                                   "git stash", "git stash push*", "git stash pop*", "git commit --amend*"]]
    rules += REDIRECT
    # always forbidden
    rules += [(p, "deny") for p in [
        "*--force*", "*push* -f*", "*push*+*", "git* push* origin develop*", "git* push* origin master*",
        "git* push* origin main*", "*push*:develop*", "*push*:master*", "*push*:main*", "git* push* --all*",
        "git* push* --mirror*", "git* push* --delete*", "git* push* --tags*", "git* reset*", "git* rebase*",
        "git* clean*", "git* branch -d*", "git* branch -D*", "git* branch -m*", "git* branch -M*", "git* branch -f*",
        "git* branch --delete*", "git* tag -*", "git* config*", "git* remote add*", "git* remote set-url*",
        "git* remote remove*", "git* remote rm*", "git* gc*", "git* update-ref*", "git* cherry-pick*", "git* revert*",
        "git* stash drop*", "git* stash clear*", "git* worktree*", "git* submodule*", "git* restore *",
        "git* checkout -- *", "git* checkout .", "git* switch*--discard-changes*", "git* switch -C*",
        "git* checkout -B*", "git* rm *", "git* mv *", "git* apply*", "git* am *", "git* filter-branch*",
        "git* reflog delete*", "git* reflog expire*"]]
    # unstaging is safe (after the generic restore deny)
    rules += [("git restore --staged *", "allow")]
    rules += [(p, "deny") for p in OTHER_DENY + SECRETS]
    return rules


def only(paths):
    return [("*", "deny")] + [(p, "allow") for p in paths]


BASE = [("webfetch", "deny"), ("websearch", "deny"), ("question", "allow")]

NO_TASK = [("task", "deny")]

AGENTS = {
    "analyst": [("edit", only([TICKET_SHEETS]))] + BASE + NO_TASK + [("bash", read_only_bash([DETECT, STATE], [SSC_NAME]))] + MCP_WRITE_DENY,
    "architect": [("edit", "deny")] + BASE + NO_TASK + [("bash", read_only_bash(DOTNET_INFO + [DETECT, LICENSES]))] + mcp_only([]),
    "debugger": [("edit", "deny")] + BASE + NO_TASK + [("bash", read_only_bash(DOTNET_INFO + DOTNET_RUN + FRONT_TEST + FRONT_BUILD + [DETECT, BUILD_TEST]))] + MCP_WRITE_DENY + mcp_only(["kibana"]),
    "reviewer": [("edit", only([TICKET_SHEETS]))] + BASE + NO_TASK + [("bash", read_only_bash(DOTNET_INFO + DOTNET_RUN + FRONT_TEST + FRONT_BUILD + [DETECT, STATE, LICENSES, BUILD_TEST]))] + MCP_WRITE_DENY + mcp_only(["jira"]),
    "test-writer": [("edit", only(TEST_PATHS + [TICKET_SHEETS]))] + BASE + NO_TASK + [("bash", read_only_bash(DOTNET_INFO + DOTNET_RUN + FRONT_TEST + [DETECT, STATE, BUILD_TEST]))] + MCP_WRITE_DENY + mcp_only(["jira"]),
    "release-writer": [("edit", "deny")] + BASE + NO_TASK + [("bash", read_only_bash([RELEASE]))] + MCP_RELEASE + mcp_only(["jira", "confluence"]),
    "git": [("edit", only([TICKET_SHEETS]))] + BASE + [("task", only(["reviewer", "analyst"])), ("bash", git_bash())] + MCP_WRITE_DENY + mcp_only(["jira", "gitlab"]),
    # build without the MCP tools (smaller requests); edit and bash stay as for build (global rules of opencode.json)
    "dev": [("task", only(["test-writer", "debugger", "architect"]))] + mcp_only([]),
}


TOOL_KEYS = {"edit", "bash", "webfetch", "websearch", "question", "task"}


def q(key):
    # Only tool names stay bare: a bare `true` or `on` would be read as a boolean by YAML.
    if key in TOOL_KEYS:
        return key
    return '"' + key.replace("\\", "\\\\").replace('"', '\\"') + '"'


def flow(rules):
    keys = [k for k, _ in rules]
    dupes = {k for k in keys if keys.count(k) > 1}
    if dupes:
        sys.exit(f"duplicate keys: {sorted(dupes)}")
    parts = []
    for key, value in rules:
        parts.append(f"{q(key)}: {flow(value) if isinstance(value, list) else value}")
    return "{ " + ", ".join(parts) + " }"


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
    keys = [k for k, _ in rules]
    dupes = {k for k in keys if keys.count(k) > 1}
    if dupes:
        sys.exit(f"duplicate keys: {sorted(dupes)}")
    return {k: as_dict(v) if isinstance(v, list) else v for k, v in rules}


# Qwen 3.6 recommended sampling for thinking mode and precise coding
SAMPLING = [("temperature", 0.6), ("top_p", 0.95)]
SNIPPET = as_dict([
    ("$schema", "https://opencode.ai/config.json"),
    ("agent", [
        ("build", SAMPLING),
        ("plan", SAMPLING + [("permission", [("bash", read_only_bash(DOTNET_INFO + [DETECT, LICENSES]))])]),
    ]),
    # Every agent, built-in ones included (build, plan, general, explore): no secrets read through the shell,
    # destructive git asks first, and MCP write tools are hidden (read-only on Jira, Confluence, GitLab, Sonar, Fortify;
    # release-writer re-allows its Confluence page with its own rules, which come after these ones).
    ("permission", [
        ("question", "allow"),
        ("skill", [("*", "allow")]),
        ("bash", [("env", "deny"), ("env *", "deny"), ("printenv*", "deny"), ("set", "deny"), ("*zshenv*", "deny"),
                  ("*zshrc*", "deny"), ("git push*", "ask"), ("git reset*", "ask"), ("git rebase*", "ask"),
                  ("rm -rf*", "ask")]),
    ] + MCP_WRITE_DENY),
])
with open("opencode.snippet.json", "w") as out:
    json.dump(SNIPPET, out, indent=2, ensure_ascii=False)
    out.write("\n")
print("updated opencode.snippet.json")
