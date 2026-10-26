// OpenCode v2 plugin of the pack: ~/.config/opencode/plugins/openrd-pack.js (restart OpenCode after a change).
// Written for OpenCode v2.1.3 (Plugin.define, hooks by domain, the v2 event stream), tested with v2.1.2 and v2.1.3;
// v2.1.4 changes nothing it uses (both sources compared: ANALYSE.md, analysis of 26 October).
// What it does:
//
// 1. Runs the "[[run <script> <arguments>]]" lines of the pack's commands with the pack's scripts, in the git root of
//    the folder of the session, before the prompt reaches the model. Each script runs without a terminal (git or ssh
//    can never wait there for a password) and is stopped, with everything it started, after 3 minutes.
//    "[[run <script> --raw <text>]]" passes the text as ONE argument, as typed (apostrophes included).
// 2. Gives every shell command of the agents a stable environment: English .NET messages, no .NET banner or
//    telemetry, no npm notices nor audit request, no analytics prompt of the Angular CLI nor telemetry of Next.js,
//    file names printed by git as they are (no octal escapes), git never waiting for a
//    password or an editor; and never the password of the OpenCode server (v2 keeps it in the environment of what it
//    runs when started with "serve"), nor a token of the MCP servers (Jira, Confluence, GitLab, Sonar, Fortify), nor
//    the XDG folders of an OpenCode v2 run next to 1.19 in ~/oc2.
// 3. Shows only "/<command> <arguments> — <repository folder> · branche <branch>" for a command of the pack in the
//    conversation (the web interface does not show the current branch), followed by "· ⏰ <n> rappel(s)" when items of
//    my todo list are due; the expanded prompt (workflow state, ticket sheet, diffs) still goes to the model. A command
//    whose prompt has a line "[[visible]]" shows what is above that line instead (/outil todo shows the list at once).
//    The pack's commands start with a line "[[command <name> $ARGUMENTS]]" that tells the plugin which command runs.
//    A command run in a session that has no title yet names it ("/go ABC-123"): no model request for the title.
// 4. Starts the command I choose in a multiple-choice question: an option whose label is a command of the pack
//    ("/go ABC-123", "/fix (recommandé)", "/push") runs by itself in the same session as soon as the agent's turn ends, unless
//    that turn failed or was stopped, and never in a subagent's session. Agents cannot run a command. A run of /go, /fix,
//    /fortify, /tests, /push or /sync ends with its « Suite » question (header "Suite", after its final answer): the run
//    is over while it waits for me, so the folder is free at once (9), the title keeps the outcome of the final answer
//    (10) and the run is never resumed (19), whatever ends the turn after it (the question closed, the model server down
//    once I answered: the command I chose still starts, unless I stopped the turn).
// 5. Shows the progress of the agent in the session title while it works, for example
//    "⏳ 1:42 réflexion 2,3k tokens — <title>", and while a subagent works, what it waits for ("⏳ 31:02 outil ·
//    Auto-review · nouvel essai 3 dans 45 s (serveur du modèle)", "… · rien reçu depuis 4 min", "❓ … · autorisation
//    attendue"). Several tools or subagents at once (the analyses of /fortify): "⏳ 3:10 outils (3) · Analyse V1,
//    Analyse V2, Analyse V3", and what the first of them that waits waits for. Phases: préparation (the scripts of the
//    command), attente du modèle, réflexion, rédaction, outil (with its description), réponse or autorisation attendue
//    (a question or an approval waits for me), nouvel essai (error of the model server, OpenCode retries), résumé du
//    contexte (the conversation is summarized, 17), and "rien reçu depuis <n> s" when the model has sent nothing for
//    30 s. The title follows every 10 s, and within a second when a tool starts or ends, a retry or a summary begins.
//    It comes back as it was when the turn ends. Never in a subagent's session, never on a session OpenCode has not
//    named yet (its title generation would be lost).
// 6. Refuses an agent's shell command that sets PATH or DOTNET_ROOT, or that writes a credential (an assignment or an
//    export of a password, token, secret or Artifactory variable, a password in a URL, in curl -u or in a NuGet source):
//    the environment of the agents comes from ~/.zshenv, and a credential written in a command stays in the session
//    history. OpenCode's permission rules cannot see these forms (assignments and export are not commands to its
//    parser). The agent is told to stop and report an environment problem instead.
// 7. Keeps the agents of the pack inside the repository of the session: a shell command of any agent that names a path
//    outside it (`~`, `$HOME`, `/home/…`, `../..`, a bare `cd`), even inside quotes, `sh -c '…'` or after a
//    redirection, is refused, and so is a read, search, edit, write or patch of an agent of the pack (pilot, analyst,
//    coder, checker, debugger, doc-writer, test-guardian) outside it. Allowed outside: the pack's scripts and skills,
//    the outputs OpenCode saves, the NuGet package cache for the file tools, the ticket sheets, the folders configured
//    as "references" in opencode.json and the folders I name myself (in the arguments of a command or in a message I
//    type in a top-level session; never in the arguments of a command chosen in a question, whose options the model
//    writes; a file names its folder, but never my home folder, a hidden folder of it or /proc, /sys, /dev): the
//    conversation agents and the read-only agents may use them in the shell, every agent of the pack with the file
//    tools. These folders are read-only: in the shell, only a command that reads (cat, grep, ls, git
//    log…) may name them, never cp, mv, rm, a redirection, a build, an interpreter or xargs running
//    another command; the agents of the pack write only in the repository. A cd is followed. Secrets (~/.zshenv, the
//    git credentials, ~/.nuget/NuGet) are outside every repository: no `grep -r <word> ~` can print them. The
//    arguments of the pack's scripts are not checked: a commit message may contain any text. OpenCode's own rules
//    cannot do this (tree-sitter does not look inside quotes, and `export -p` is not a command to it); an approval
//    answered "always" cannot lift it either. Also refused for every agent: an environment dump (`export`,
//    `declare -p`, `set` alone) and a recursive rm, whatever the order of its options.
// 8. Gives the long commands the time they need: a build or test command 20 minutes (OpenCode stops any command after
//    2 minutes unless the agent asks for more, and a stopped full test suite is run again from the start), ship.sh
//    and branch.sh 5 minutes. The agents of the pack never run a shell command or a subagent in the background: /go,
//    /fix and /fortify wait for each result, and the folder lock (9) ends with the turn. Nor a command without a time
//    limit: OpenCode v2 lets an agent turn the limit off (timeout 0), and a command that waits for a network that never
//    answers would hold the run for good; such a command gets 20 minutes, and none more than 2 hours.
// 9. Starts only one /go, /fix, /fortify, /tests, /push or /sync at a time per folder: two pilots in one working tree would
//    commit each other's changes. The second one gets a one-line answer and no tool runs in its turn. The lock is also a file in
//    the git folder of the working tree, so that a second OpenCode of the machine (the terminal client) sees it too;
//    a lock left by an OpenCode that stopped is ignored, except by OpenCode run as its background service: it resumes
//    the turn a restart interrupted, and the plugin keeps the folder for that resumed run (freed after 2 minutes if
//    the run does not start again).
// 10. Leaves the outcome of a /go, /fix, /fortify or /tests in the session title once it ends: "✅ " (merge request created
//    or updated, nothing left to do), "⏸ " (waits for me: an answer of the product owner), "↻ " (resumes by itself
//    soon, 19) or "⛔ " (stopped: its answer holds ⛔, or the run failed or was stopped and is not resumed). The mark
//    goes away when the next turn of the session starts.
// 11. Runs a build tool called by its full path (`~/.bin/dotnet build`, `/usr/bin/git log`) by its name (`dotnet
//    build`): the permission rules of the agents name the tools, and the folder of the tool is outside the repository.
// 12. Closes what OpenCode v2 opens that the guards above cannot check:
//    - code mode (`execute`): JavaScript that can call any address with fetch, without any permission, and the
//      opencode_* tools that move a session to another folder, create or remove a worktree. It is taken out of every
//      request, and the MCP servers (Jira, GitLab, Confluence…) are offered as plain tools instead, as in 1.19;
//    - the web search, which sends the query to an outside search service;
//    - the tools that move a session or create or remove a worktree, refused to every agent by their names (the
//      developer does it in the web interface);
//    - the question tool in a subagent's session (nobody answers during /go, /fix, /fortify or /tests; 1.19 did it with
//      experimental.primary_tools, which v2 ignores): taken out of its requests, and refused if called.
// 13. When "compaction.prune" is true in opencode.json, the outputs of old tool calls are cleared from what the model
//    receives, as 1.19 did (v2 ignores that setting): only the tool outputs before the last two messages I typed, and
//    beyond the 40 000 most recent tokens of them, and only when that frees more than 20 000 tokens. The skills are
//    never cleared. The conversation shown and the session history keep everything.
// 14. Waits for the MCP servers that are still connecting, as 1.19 did: v2 sends a request to the model with the tools
//    of the servers connected at that moment, and a /go whose first step has no Jira tool stops. During the first 5
//    minutes of an instance (OpenCode started, or its configuration changed), a prompt waits for them, 30 s at most.
// 15. Starts the title of every session of a worktree (an OpenCode workspace) with the folder of that worktree,
//    "[crisp-river] <title>" (after the ✅ or ⛔ of 10): the home page of OpenCode lists the sessions of all the
//    workspaces of a repository together, without their folder. Not in the main checkout, not in a subagent's session,
//    never on a title OpenCode has not generated yet.
// 16. Refuses the third identical tool call (same tool, same input) of one answer of the model, as 1.19 did with its
//    "doom_loop" rule (v2 no longer detects it): a model stuck in a loop gets an error and changes its approach, or
//    its subagent ends with an error the pilot handles, instead of running the same call again and again.
// 17. Keeps a run of /go, /fix, /fortify or /tests on its procedure when its context is full. OpenCode v2 then summarizes the
//    conversation and goes on from the summary alone, which it gives the model as "historical context, not new
//    instructions": the instructions of the command and the task of a subagent would be lost. The summary is asked to
//    keep the state of the run (ticket, sheet, batch folder, current step and phase, sessionIDs of the subagents,
//    commits), then every request that follows gets back, as instructions, the procedure of the command (the pilot,
//    who first reads the ticket sheet again) or the task the pilot gave (a subagent).
// 18. Gives the model server more time on a run of /go, /fix, /fortify or /tests and its subagents: OpenCode retries a failed
//    request 10 times within about 1.5 minutes, then the run fails; the same 10 retries are spread over about 8
//    minutes (a gateway that restarts, a 504 storm). A conversation keeps OpenCode's own timing.
// 19. Resumes a run of /go, /fix, /fortify or /tests that ended before its final answer, without me: after a failure of the
//    model server (once its retries are spent: 2 minutes later, then 5), or when the pilot ended its turn without its
//    final report (its step limit, or a model that stops halfway). The pilot gets, in the same session, a message that
//    tells it to read the ticket sheet again and to go on from the first step not done: nothing is redone. Two
//    automatic resumes at most in a row; never after a stop I asked for, a ⛔ of the run, or a refusal; a message I
//    type cancels a resume that waits.
// 20. Sends an assistant message made only of tool calls with an empty content instead of null. OpenCode v2 writes
//    null there (the OpenAI format allows it); a model gateway that validates content as a string or an array refuses
//    the whole request (HTTP 400 "Request doesn't match the schema", /messages/<n>/content), so every turn that calls a
//    tool failed on its next request. Only the body of chat completions requests that hold such a message changes.
// 21. Cuts an answer of the model that repeats itself (the same sentence, or the same few sentences, again and again: a
//    thinking model can loop until its output limit, half an hour or more of a shared server): the stream is watched
//    as it comes, and once its text ends in a loop it ends at once as an answer cut at the output limit, and the request
//    to the model server is cancelled. OpenCode then asks the model to go on; the plugin takes the cut answer and that
//    note out of the next request (the model gets the request that looped once more), with a presence penalty of 1.0,
//    then 1.5, until an answer ends normally: the sampling of the model card everywhere else. Every request also gets
//    the loops of its history (answers of an earlier loop, of a version without this guard) kept once. After three
//    cuts in a row OpenCode stops the turn, and a run is resumed (19).
// 22. Resumes a run of /go, /fix, /fortify or /tests that stopped before its end when I write « continue » (« reprends »,
//    « vas-y »…) in its session: the web interface switches the session to the agent selected under the prompt with
//    every message, so « continue » went to build, which carried on the pilot's work with none of its rules. The
//    session goes back to the pilot, and the message becomes the resume of 19 (never after ✅ or ⏸).
// 23. Lets the free conversation run a project with `dotnet run` only when the last commit holds it: a POC or the tests
//    of a Microsoft.Testing.Platform project, never a probe or reflection project made for the occasion, nor a C# file
//    run as a program (.NET 10). The agents of the pack never run `dotnet run` (permission rules).
// 24. Refuses a command that never ends by itself: a development server (`ng serve`, `npm start`, `npm run dev`,
//    `vite`, `next dev`, `dotnet watch`, `dotnet run` of a web, worker or Aspire project, `func start`…), a watch mode
//    (`--watch`, `ng test` without --watch=false, `react-scripts test` without --watchAll=false, `karma start` without
//    --single-run, `vitest --ui`), `tail -f`, `docker compose up` without -d, `ping` without -c. A package script is
//    judged by its name (start, dev, serve, watch…) and by what package.json says it runs: `npm test` is refused when
//    its script watches (`ng test` with Karma), never when it runs once (`jest`, `vitest`); and npm passes to the script
//    only the options after `--` (`npm test --watch=false` does not reach Karma: the refusal says so). A command run
//    through npx, env, nohup, sh -c or after a cd is judged the same. It would hold the turn until OpenCode stops it
//    (20 minutes for a test command, 8), and the agent would then try another form. The agent is told to use
//    build-test.sh, which builds a .NET or front-end folder and runs its tests once. The free conversation may run one
//    in the background (OpenCode v2, background: true) or bounded by `timeout` (5 minutes at most); the agents of the
//    pack never.
// 25. Refuses to the agents of the pack a command that changes the dependencies of the repository: `npm install` (with
//    or without a package: it resolves the tree again and rewrites package-lock.json), `npm i`, `npm update`,
//    `npm audit fix`, `yarn add`, `pnpm add`, a plain `yarn` or `pnpm install` without the frozen lockfile, through
//    `npx npm@11`, corepack, `sh -c` or a script of package.json; `dotnet add package`, `dotnet package add` (.NET 10),
//    `dotnet tool install`. And one that installs a tool on the machine: a global install, brew, apt, pip,
//    `corepack enable`, `nvm install`. The permission rules refuse them too, but their refusal sends the model every
//    bash rule (19 000 characters for the coder) and nothing it can do instead; this one says it in a sentence: a step
//    that needs a package is « BLOQUÉ », the dependencies of the lockfile are installed by build-test.sh (npm ci), a
//    missing tool is an ENVIRONMENT PROBLEM. `npm ci` and the frozen installs pass. The free conversation is mine.
// 26. Starts the commands of /outil planifier at their time (schedule.sh, ~/.config/opencode/schedules.md): each in a
//    new session of its repository (ctx.session.create, then the command), once per day and time even when several
//    instances of the plugin run (a marker file per schedule and minute, in the data folder of OpenCode). Only what
//    writes nothing in git or in Jira: /daily, /outil audit, /outil licences, /tests env <environment> (read only);
//    another line, even written by hand, is refused. The OpenCode service must run at that time; what it missed is not
//    started later. Each start, or why it did not start, goes to the log of the plugin.
// 27. Bounds the calls of the MCP servers (Jira, Confluence, GitLab, Sonar, Fortify) to 5 minutes: OpenCode v2 waits up
//    to 12 hours for an answer (1.19 gave up after its timeout), so a server or an API that never answers held the
//    run, its title showing the tool, for good. The call now ends in an error the agent handles (another way, or a
//    line in its report). A server whose configuration gives its own "timeout": { "execution": <ms> } keeps it.
// 28. Sends the options of each agent with its requests to the model, as 1.19 did: its temperature and top_p, and the
//    "options" of its configuration (top_k, chat_template_kwargs with reasoning_effort or enable_thinking…). OpenCode
//    v2 reads them into the agent but no request uses them (its source, v2.1.3 and v2.1.4): the 1.0 / 0.95 of the
//    agents of the pack, the reasoning effort of an agent and the title written without thinking were never sent.
//    They are merged into the body of each chat completions request of that agent (the title agent for a title, the
//    agent of the session for a summary), over the options of the model; never its messages, tools, model or output
//    limit, and never below the presence penalty of 21.
// 29. Measures where the time of each run goes and writes one line per run of a command of the pack to
//    <log folder>/openrd-pack-runs.tsv, read by /outil vitesse: the whole run; the model (its wait before the first
//    token, its thinking, its writing, per request and in all), the tools, the subagents (by agent) and the questions
//    on the path of the run; the retries, the summaries of the context, the silences of the model server, the answers
//    a gateway held back and gave all at once; the tokens the server counted. Never a prompt, a command or a text of the
//    conversation: names, durations and counts.
// Every refusal of 6, 7, 9, 12, 16, 23, 24 and 25 is written as "refused by the pack" to the log of the plugin,
// <XDG data folder>/opencode/log/openrd-pack.log (~/.local/share/opencode/log/openrd-pack.log), and to the output of
// the OpenCode server (lost when OpenCode runs as its background service): COMMANDES.md, "Logs d'OpenCode". So are
// the summaries of a run (17), its automatic resumes (19), the loops cut (21), the resumes I ask for (22), the end of a
// run at its « Suite » question (4), the MCP servers bounded (27), the options sent for each agent (28) and the time of
// each run (29). Any error leaves the prompt or the call as it is.
import { execFile, execFileSync, spawn } from "node:child_process"
import { Plugin } from "@opencode/plugin"
import {
  appendFileSync,
  closeSync,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
  writeSync,
} from "node:fs"
import { homedir, hostname, tmpdir } from "node:os"
import { basename, dirname, isAbsolute, join, resolve, sep } from "node:path"

const HOME = homedir()
const SCRIPTS = join(HOME, ".config", "opencode", "scripts")
const RUN = /\[\[run ([a-z][a-z0-9-]*\.sh)((?: [^\n]*?)?)\]\]/g
const VISIBLE = /\n?\[\[visible\]\]\n?/
const TIMEOUT_MS = 180000
// The environment of the commands the pack runs ([[run]] scripts, commands of the agents): never the password of the
// OpenCode server (v2.1.2 keeps it in the environment of what it runs when started with "serve"), never a credential of
// the MCP servers (a Jira, Confluence, GitLab, Sonar or Fortify token: the MCP servers get it from OpenCode itself, no
// command of an agent and no script of the pack uses it, and git has its own credential store), and the developer's
// usual folders when OpenCode v2 runs next to 1.19 with its own XDG folders in ~/oc2 (MIGRATION.md): git (its credential
// cache), dotnet (the NuGet caches) and the other tools then behave as in the developer's terminal. The Artifactory
// credentials stay: the builds need them.
const SERVER_SECRETS = ["OPENCODE_SERVER_PASSWORD", "OPENCODE_PASSWORD"]
const MCP_SERVICE = /^(?:JIRA|CONFLUENCE|ATLASSIAN|GITLAB|SONAR|SONARQUBE|FORTIFY|SSC)$/
const SECRET_WORD = /^(?:TOKEN|SECRET|KEY|APIKEY|PASSWORD|PASSWD|PAT|CREDENTIALS?)$/
export function mcpSecret(name) {
  const parts = String(name).toUpperCase().split(/[^A-Z0-9]+/)
  return parts.some((part) => MCP_SERVICE.test(part)) && parts.some((part) => SECRET_WORD.test(part))
}
const ISOLATED = join(HOME, "oc2")
function cleanEnv(env) {
  for (const name of SERVER_SECRETS) delete env[name]
  for (const name of Object.keys(env)) if (mcpSecret(name)) delete env[name]
  for (const name of ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME"]) {
    const value = env[name]
    if (typeof value === "string" && isAbsolute(value) && within(resolve(value), ISOLATED)) delete env[name]
  }
  return env
}
const MAX_OUTPUT = 32 * 1024 * 1024
// Commands of the pack that a multiple-choice answer may start (built-in OpenCode commands are never started)
const CHAINABLE = new Set(["go", "fix", "fortify", "tests", "push", "sync", "daily", "review", "compare", "outil"])
// An option that names a command: "/go ABC-123", "/daily (recommandé)" (the mark of the recommended option is no argument)
const RECOMMENDED = /\s*\((?:recommandé|recommended)\)\s*$/i
const CHOICE = /^\/([a-z][a-z0-9-]*)(?:\s+([\s\S]*))?$/i
// Progress in the title
const PROGRESS = /^(?:⏳|❓) [^—]*— /
// Outcome of the last /go, /fix, /fortify or /tests of a session (10): delivered, waits for me, resumes by itself, stopped
const OUTCOME = /^(?:✅|⏸|↻|⛔) /
// The title of a session OpenCode has not named yet
const DEFAULT_TITLE = /^(New session - |Child session - )\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
const TICK_MS = 10000
const NUDGE_MS = 1000
const SILENCE_MS = 30000
// Shell commands that set the environment or write a credential (point 6). An assignment starts a command (start of
// the text, after ; & | ( ` or a new line), possibly after export/declare/typeset/readonly/local/env and other
// assignments; quoted text is left out first, so that "token=null" in a commit message or "password=|secret=" in a
// search pattern is not one.
const ASSIGN = String.raw`(?:^|[;&|(\x60\n])\s*(?:(?:export|declare|typeset|readonly|local)\s+(?:-\w+\s+)*|env\s+(?:-\S+\s+)*)?(?:\w+=\S*\s+)*`
const SETS_ENVIRONMENT = new RegExp(ASSIGN + String.raw`(?:PATH|DOTNET_ROOT\w*)=`)
const SETS_SECRET = new RegExp(ASSIGN + String.raw`(?:\w*(?:PASSWORD|PASSWD|TOKEN|SECRET|API_?KEY|CREDENTIALS?)\w*|ARTIFACTORY\w*)=`, "i")
const QUOTED = /'[^']*'|"(?:[^"\\]|\\.)*"/g
// Commands that take minutes (8): a build or tests, a restore, the front-end tooling; the pack's git scripts
const LONG_COMMAND = /(?:^|[\s;&|(])(?:\S*build-test\.sh|\S*front-test\.sh|\S*env-tests\.sh|\S*fortify\.sh\s+prereq|\S*test-guardian\.sh\s+(?:coverage|red|green|changes|build|setup)|dotnet\s+(?:build|test|restore|format|ef|clean|pack)|npm\s+(?:test|ci|install|i|run\s+\S+)|npx\s+(?:jest|vitest|tsc|eslint|prettier|ng\s+(?:test|build|lint|generate|g))|yarn\s+(?:test|install|build|lint|run\s+\S+)|pnpm\s+(?:test|install|build|lint|run\s+\S+))(?=\s|$|[;&|)])/
const GIT_SCRIPT = /(?:^|[\s;&|(])\S*(?:ship|branch)\.sh(?=\s|$)/
// 8. the time of a full build and tests, and the longest a command of an agent of the pack may run
const COMMAND_MAX_MS = 20 * 60000
const COMMAND_CAP_MS = 2 * 3600000
// A build tool called by its full path at the start of a command (11): ~/.bin/dotnet, $HOME/.dotnet/dotnet, /usr/bin/git
const TOOL_PATH = /(^\s*|[;&|(`\n]\s*)((?:~|\$\{HOME\}|\$HOME)?\/(?:[^\s;&|()<>'"`]*\/)?)(dotnet|node|npm|npx|yarn|pnpm|git)(?=$|[\s;&|)`])/g

// 6/7. Harmless redirections an agent reaches for, removed before a command is checked and run: merging stderr into
// stdout (`2>&1`, `>&2`, `1>&2`, `2>&-`) or discarding output into /dev/null (`>/dev/null`, `&>/dev/null`,
// `2>>/dev/null`…), with or without a space. OpenCode already streams the two channels together, so dropping these
// does not change what the model sees; it stops the permission rules of the agents (which name commands, not their
// redirections) from being fooled — a `2>&1` must not re-open a command the agent is not allowed to run, nor force a
// deny on one it is. A real redirection to a file stays in the command, to be refused (shellOutside). Only unquoted
// occurrences are removed: `grep '2>&1' logs` keeps its search string.
const NOISE_REDIRECT = /(?:^|\s)(?:\d*>&\d+|\d*>&-|(?:\d+|&)?>>?[ \t]*\/dev\/null)(?=$|[\s;&|)`])/
function stripNoise(command) {
  const text = String(command || "")
  if (!/>/.test(text)) return text
  let masked = text.replace(QUOTED, (m) => " ".repeat(m.length))
  let out = text
  for (let guard = 0; guard < 64; guard++) {
    const m = NOISE_REDIRECT.exec(masked)
    if (!m) break
    out = out.slice(0, m.index) + out.slice(m.index + m[0].length)
    masked = masked.slice(0, m.index) + masked.slice(m.index + m[0].length)
  }
  return out
}
// A user and a password in a URL (https://user:token@host), in curl/wget -u, or in a NuGet source
const SECRET_IN_URL = /\b(?:https?|ssh|git|ftp):\/\/[\w.%-]+:[^\s/@*]+@/i
const SECRET_IN_OPTION = /\b(?:curl|wget)\b[^\n]*\s(?:-u|--user)\s*[\w.%-]+:\S|\bdotnet\s+nuget\s+(?:add|update)\s+source\b[^\n]*(?:\s-p\s|--password)/i

// An environment dump: export, declare, typeset or readonly without a name, or set alone (point 7)
const DUMPS_ENVIRONMENT = /(?:^|[;&|(\x60\n])\s*(?:(?:export|declare|typeset|readonly)(?:\s+-[A-Za-z]+)*|set)\s*(?=$|[;&|)\x60\n])/
// rm with a recursive option, before or after its operands, also through xargs (point 7)
const RECURSIVE_RM = /(?:^|[;&|(\x60\n]|\bxargs\b[^;&|\n]*?)\s*rm\b[^;&|\n]*?\s(?:-[A-Za-z]*[rR][A-Za-z]*|--recursive)(?=\s|$|[;&|)])/

// Why a shell command of an agent is refused (points 6 and 7), or ""
function refusal(command) {
  const text = String(command || "")
  const unquoted = text.replace(QUOTED, "''")
  if (SETS_ENVIRONMENT.test(unquoted)) return "it sets PATH or DOTNET_ROOT"
  if (SETS_SECRET.test(unquoted) || SECRET_IN_URL.test(text) || SECRET_IN_OPTION.test(text)) return "it writes a credential"
  if (DUMPS_ENVIRONMENT.test(unquoted)) return "it prints the environment"
  if (RECURSIVE_RM.test(unquoted)) return "it deletes a folder (recursive rm)"
  return ""
}

// ---------- 7. the repository of the session, and the folders allowed outside it ----------
const PACK_AGENTS = new Set(["pilot", "analyst", "coder", "checker", "debugger", "doc-writer", "test-guardian"])
// agents that may read a reference or a folder I named through the shell (git log of another repository); the pilot,
// the coder, doc-writer and test-guardian read them with the file tools only
const SHELL_READERS = new Set(["analyst", "checker", "debugger", "build", "plan", "general", "explore"])
const PACK_DIRS = [SCRIPTS, join(HOME, ".config", "opencode", "skills")]
const SAVED_OUTPUTS = [
  join(process.env.XDG_DATA_HOME || join(HOME, ".local", "share"), "opencode", "tool-output"),
  join(tmpdir(), "opencode"),
]
const PACKAGE_CACHE = join(HOME, ".nuget", "packages")
const DEVICES = new Set(["/dev/null", "/dev/stdin", "/dev/stdout", "/dev/stderr"])
// commands that only print a path: `realpath ~` gives the home folder to the file tools, which do not expand ~
const PRINTS_PATH = new Set(["realpath", "echo", "printf", "basename", "dirname"])
const FILE_TOOLS = { read: "filePath", write: "filePath", edit: "filePath", grep: "path", glob: "path" }

const within = (target, dir) => target === dir || target.startsWith(dir.endsWith(sep) ? dir : dir + sep)

// Commands that only read what they are given. They alone may touch the folders outside the repository that an agent
// may read (the pack's scripts and skills, the outputs OpenCode saves, the references, the folders I name): anything
// else there (cp, mv, rm, a redirection, an interpreter, a build, xargs running another command) would change the
// pack, its guards included, or another repository.
const READERS = new Set(["cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "ls", "wc", "file", "comm",
  "paste", "column", "nl", "tac",
  "stat", "diff", "cmp", "realpath", "readlink", "basename", "dirname", "jq", "uniq", "cut", "tr", "md5sum", "sha1sum",
  "sha256sum", "du", "echo", "printf", "test", "[", "tree", "sort", "sed", "find", "git", "cd", "pushd"])
const GIT_READS = new Set(["log", "show", "diff", "blame", "grep", "ls-files", "ls-tree", "status", "rev-parse",
  "branch", "for-each-ref", "cat-file", "describe", "shortlog", "rev-list", "name-rev", "merge-base"])

// Whether a simple command only reads the files it names
function readsOnly(words) {
  const [name, ...rest] = words
  if (!READERS.has(name)) return false
  if (name === "sed") return !rest.some((w) => /^-[A-Za-z]*i/.test(w) || w.startsWith("--in-place"))
  if (name === "sort" || name === "tree") return !rest.some((w) => /^-[A-Za-z]*o/.test(w) || w.startsWith("--output"))
  if (name === "find") return !rest.some((w) => /^-(?:delete|exec|execdir|ok|okdir|fprint0?|fprintf|fls)$/.test(w))
  if (name === "git") {
    let i = 0
    while (i < rest.length && rest[i].startsWith("-")) i += /^-[Cc]$/.test(rest[i]) ? 2 : 1
    const sub = rest[i]
    if (sub === "branch" && rest.slice(i + 1).some((w) => /^-[A-Za-z]*[dDmMcCf]|^--(?:delete|move|copy|force)/.test(w))) return false
    return GIT_READS.has(sub) && !rest.some((w) => w.startsWith("--output"))
  }
  return true
}

// The words of a shell command, per simple command (split on ; & | ( ) ` < > and new lines outside quotes), with the
// quotes removed as the shell does; a quoted word keeps its spaces (it is checked again as a command: sh -c '...').
// Each list of words has `after`: the separator before it (">" for the target of a redirection).
function commandWords(text) {
  const out = []
  let words = []
  let word = ""
  let started = false
  let quote = ""
  let after = ""
  const push = () => {
    if (started) words.push(word)
    word = ""
    started = false
  }
  const end = (separator = "") => {
    push()
    if (words.length) out.push(Object.assign(words, { after }))
    words = []
    after = separator
  }
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (quote) {
      if (ch === quote) quote = ""
      else if (ch === "\\" && quote === '"' && i + 1 < text.length) word += text[++i]
      else word += ch
    } else if (ch === "'" || ch === '"') {
      quote = ch
      started = true
    } else if (ch === "\\" && i + 1 < text.length) {
      word += text[++i]
      started = true
    } else if (/[;&|()\n`<>]/.test(ch)) end(ch)
    else if (/\s/.test(ch)) push()
    else {
      word += ch
      started = true
    }
  }
  end()
  return out
}

// The path a word of a shell command points to, when it is one: ~, $HOME, an absolute path whose first folder exists
// (so that a route like /api/orders in a search is not one), or a path that goes up with ..
function pathOf(word, cwd) {
  if (!word) return undefined
  if (word === "~" || word.startsWith("~/")) return resolve(HOME, word.slice(2))
  if (/^~[A-Za-z0-9_.-]/.test(word)) return "/"
  const home = /^\$(?:\{HOME\}|HOME)(?=\/|$)(.*)$/.exec(word)
  if (home) return resolve(HOME + home[1])
  if (word.startsWith("/")) {
    const first = word.split("/")[1]
    return !first || existsSync("/" + first) ? resolve(word) : undefined
  }
  if (/(^|\/)\.\.(\/|$)/.test(word)) return resolve(cwd, word)
  return undefined
}

// The first word of a shell command that leaves the repository, as { piece, readOnly }, or null. readOnly: the word
// points into a folder the agent may read, but the command does more than read it. A cd is followed: the relative
// paths of the next commands are in its folder.
function shellOutside(command, cwd, root, readable, noWriteRedirect = false, depth = 0) {
  let here = cwd
  let readsReadable = false
  let xargsRuns = ""
  for (const words of commandWords(String(command || ""))) {
    // the target of a redirection is written: /dev/null is fine; a file in the repository is still a write, refused
    // for the agents of the pack (they write with the edit and write tools); a file outside it, for every agent
    if (words.after === ">") {
      const target = pathOf(words[0], here) || resolve(here, words[0])
      if (DEVICES.has(target)) continue
      if (within(target, root)) {
        if (noWriteRedirect) return { piece: words[0], redirect: true }
        continue
      }
      return { piece: words[0], readOnly: readable.some((dir) => within(target, dir)) }
    }
    // the pack's scripts check their own arguments, which may be free text (a commit message, a decision)
    if (/^(?:ba|da|z)?sh$/.test(words[0]) && words[1]) {
      const script = pathOf(words[1], here) || resolve(here, words[1])
      if (within(script, SCRIPTS)) continue
    }
    // a cd to the home folder, back, or along the folder stack goes where nothing can be checked
    if (/^(?:cd|pushd)$/.test(words[0]) && words.length === 1) return { piece: "~" }
    if (words[0] === "popd" || (/^(?:cd|pushd)$/.test(words[0]) && /^[-+]/.test(words[1]))) return { piece: words.join(" ") }
    if (words[0] === "xargs") {
      let i = 1
      while (i < words.length && words[i].startsWith("-")) i += /^-[nIdLPEsa]$/.test(words[i]) ? 2 : 1
      const run = words.slice(i)
      if (run.length && !readsOnly(run)) xargsRuns = run[0]
    }
    const reads = readsOnly(words)
    // after a cd out of the repository, every operand is in that folder
    const away = !within(here, root)
    for (let w = 0; w < words.length; w++) {
      const word = words[w]
      if (/\s/.test(word)) {
        if (depth < 3) {
          // a quoted word re-parsed here is data (a search string with => or a > inside), not a shell redirection: the
          // redirection refusal is a top-level concern, and a real nested shell (sh -c, bash -c, eval) is denied for the
          // agents of the pack by the rules anyway
          const inner = shellOutside(word, here, root, readable, false, depth + 1)
          if (inner) return inner
        }
        continue
      }
      for (const piece of word.split("=")) {
        let target = pathOf(piece, here)
        if (!target && away && piece && !piece.startsWith("-") && (w > 0 || words.after === "<")) target = resolve(here, piece)
        if (!target || DEVICES.has(target) || within(target, root)) continue
        if (target === HOME && PRINTS_PATH.has(words[0])) continue
        if (readable.some((dir) => within(target, dir))) {
          // a command that only reads, the source of a redirection, or a script of the pack run directly
          if (reads || words.after === "<" || (w === 0 && within(target, SCRIPTS))) {
            readsReadable = true
            continue
          }
          return { piece, readOnly: true }
        }
        return { piece }
      }
    }
    if (/^(?:cd|pushd)$/.test(words[0])) here = pathOf(words[1], here) || resolve(here, words[1])
  }
  // xargs runs a command on the names another command printed: never on a folder the agent may only read
  if (readsReadable && xargsRuns) return { piece: "xargs " + xargsRuns, readOnly: true }
  return null
}

// The folders named in a text I typed (command arguments, a message): existing folders or files outside the repository
// A folder I name never opens what holds secrets: never my home folder or one of its parents (a file named directly in
// it, such as ~/.zshenv, names no folder), never a hidden folder of my home (~/.ssh, ~/.config, ~/.local/share/opencode,
// ~/.nuget/NuGet…), never the folders of the processes and devices of the system
const SYSTEM_FOLDERS = ["/proc", "/sys", "/dev"]
function nameable(folder) {
  if (within(HOME, folder)) return false
  if (SYSTEM_FOLDERS.some((dir) => within(folder, dir))) return false
  if (within(folder, HOME) && folder.slice(HOME.length + 1).split(sep)[0].startsWith(".")) return false
  return true
}

function namedFolders(text, root) {
  const out = []
  for (const words of commandWords(String(text || ""))) {
    for (const word of words) {
      for (const raw of word.split(/\s+/)) {
        // a path at the end of a sentence: "~/repos/old-api," or "(~/repos/old-api)"
        const piece = raw.replace(/^[(«"']+/, "").replace(/[),.;:!?»"']+$/, "")
        const target = pathOf(piece, root) || (isAbsolute(piece) ? resolve(piece) : undefined)
        if (!target || within(target, root)) continue
        try {
          const info = statSync(target)
          // a file names its folder
          const folder = info.isDirectory() ? target : resolve(target, "..")
          if (nameable(folder)) out.push(folder)
        } catch {
          // not a folder or a file of this machine
        }
      }
    }
  }
  return out
}

// The first answer that is a command of the pack, as { command, arguments }
function chosenCommand(answers) {
  if (!Array.isArray(answers)) return undefined
  for (const list of answers) {
    for (const label of Array.isArray(list) ? list : []) {
      const match = CHOICE.exec(String(label).trim().replace(RECOMMENDED, ""))
      // OpenCode runs the !`...` of a command's arguments: an option that would run something is never started
      if (match && CHAINABLE.has(match[1].toLowerCase()) && !/[`$]/.test(match[2] || "")) {
        return { command: match[1].toLowerCase(), arguments: (match[2] || "").trim() }
      }
    }
  }
  return undefined
}

// Splits the arguments like a shell does for simple quoting ('...' and "..."), without any expansion: the
// arguments typed after a command can never run anything. "--raw <text>" keeps the text as one argument.
function words(text) {
  const raw = /^\s*--raw(?:\s+|$)([\s\S]*)$/.exec(text)
  if (raw) return ["--raw", raw[1].trim()]
  const out = []
  let word = ""
  let started = false
  let quote = ""
  for (const ch of text) {
    if (quote) {
      if (ch === quote) quote = ""
      else word += ch
    } else if (ch === "'" || ch === '"') {
      quote = ch
      started = true
    } else if (ch === " " || ch === "\t") {
      if (started) out.push(word)
      word = ""
      started = false
    } else {
      word += ch
      started = true
    }
  }
  if (started) out.push(word)
  return out
}

// A script of the pack, in its own process group and session (no terminal: nothing can wait for a password),
// stopped with everything it started after TIMEOUT_MS
function run(script, args, cwd) {
  return new Promise((resolve) => {
    let child
    try {
      child = spawn("sh", [join(SCRIPTS, script), ...words(args)], {
        cwd,
        detached: true,
        stdio: ["ignore", "pipe", "pipe"],
        // 29. the folder of the log of the plugin, where vitesse.sh reads the time of the runs (the XDG folders of an
        // OpenCode v2 in ~/oc2 are taken out of the environment: 2)
        env: cleanEnv({ ...process.env, GIT_TERMINAL_PROMPT: "0", OPENRD_PACK_LOG_DIR: dirname(LOG_FILE) }),
      })
    } catch (error) {
      resolve(script + " failed: " + String((error && error.message) || error))
      return
    }
    const out = []
    let size = 0
    let err = ""
    let stopped = false
    const group = () => {
      try {
        process.kill(-child.pid, "SIGKILL")
      } catch {
        // already gone
      }
    }
    const timer = setTimeout(() => {
      stopped = true
      group()
    }, TIMEOUT_MS)
    child.stdout.on("data", (chunk) => {
      if (size >= MAX_OUTPUT) return
      out.push(chunk)
      size += chunk.length
    })
    child.stderr.on("data", (chunk) => {
      if (err.length < 4000) err += chunk
    })
    // the script is done: nothing it left in the background may keep its output open
    child.on("exit", group)
    child.on("error", (error) => {
      clearTimeout(timer)
      resolve(script + " failed: " + String((error && error.message) || error))
    })
    child.on("close", (code) => {
      clearTimeout(timer)
      const text = Buffer.concat(out).toString("utf8").replace(/\s+$/, "")
      if (stopped) return resolve((text ? text + "\n" : "") + script + ": stopped after " + TIMEOUT_MS / 1000 + " s")
      if (text || code === 0) return resolve(text)
      resolve(script + " failed: " + (err.trim().split("\n")[0] || "exit code " + code))
    })
  })
}

// The git folder that every worktree of the repository shares (.git of the main checkout), absolute, or ""
function gitCommonDir(cwd) {
  return new Promise((done) => {
    execFile("git", ["rev-parse", "--git-common-dir"], { cwd, timeout: 5000 }, (error, stdout) => {
      const out = error ? "" : String(stdout).trim()
      done(out ? resolve(cwd, out) : "")
    })
  })
}

// "<repository folder> · branche <branch>" of the session's project, or "" outside a git repository. In a worktree,
// the folder of the main checkout names the repository, followed by the folder of the worktree:
// "<repository> · worktree <folder> · branche <branch>".
function where(cwd) {
  const git = (args) =>
    new Promise((resolve) => {
      execFile("git", args, { cwd, timeout: 5000 }, (error, stdout) => resolve(error ? "" : String(stdout).trim()))
    })
  return Promise.all([git(["rev-parse", "--show-toplevel"]), git(["symbolic-ref", "--short", "-q", "HEAD"]), gitCommonDir(cwd)]).then(
    async ([root, branch, common]) => {
      if (!root) return ""
      const name = branch ? "branche " + branch : "HEAD détachée " + (await git(["rev-parse", "--short", "HEAD"]))
      const repository = basename(common) === ".git" && resolve(common, "..") !== root ? basename(resolve(common, "..")) + " · worktree " + basename(root) : basename(root)
      return repository + " · " + name
    },
  )
}

// Items of my todo list (todo.sh) due today or overdue
function reminders() {
  try {
    const file = process.env.OPENCODE_TODO || join(homedir(), ".config", "opencode", "todo.md")
    const now = new Date()
    const today = [now.getFullYear(), now.getMonth() + 1, now.getDate()].map((n) => String(n).padStart(2, "0")).join("-")
    return readFileSync(file, "utf8")
      .split("\n")
      .filter((line) => {
        const match = /^- \[ \] #\d+ (\d{4}-\d{2}-\d{2}) /.exec(line)
        return match && match[1] <= today
      }).length
  } catch {
    return 0
  }
}

async function resolveRuns(text, cwd) {
  const found = [...text.matchAll(RUN)]
  if (found.length === 0) return text
  const outputs = await Promise.all(found.map((m) => run(m[1], m[2], cwd)))
  let i = 0
  return text.replace(RUN, () => outputs[i++])
}

const clock = (ms) => {
  const s = Math.max(0, Math.floor(ms / 1000))
  return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
}
const tokens = (chars) => {
  const t = Math.round(chars / 4)
  return t >= 1000 ? (t / 1000).toFixed(1).replace(".", ",") + "k" : String(t)
}

// "4 min" or "45 s"
const since = (ms) => (ms >= 120000 ? Math.floor(ms / 60000) + " min" : Math.round(ms / 1000) + " s")

// " dans 45 s" before a retry that OpenCode scheduled for later (18), "" when it is due
const retryIn = (item, now) => {
  const at = Number(item && item.at)
  return at && at - now >= 2000 ? " dans " + since(at - now) : ""
}

// The descriptions of the tools that run at once, in one short text: "Analyse V1, Analyse V2, Analyse V3"
function toolList(texts) {
  let out = ""
  for (const text of texts) {
    const next = out ? out + ", " + text : text
    if (next.length > 70) return out ? out + "…" : text.slice(0, 69) + "…"
    out = next
  }
  return out
}

// "⏳ 1:42 réflexion 2,3k tokens" for a run of a session; while tools or subagents work, what they do and what the
// first of them that waits waits for. `subagents` gives the state of a subagent session.
function progressLabel(state, now, subagents = new Map()) {
  const elapsed = clock(now - state.start)
  if (state.phase === "question") return "❓ " + elapsed + " réponse attendue"
  if (state.phase === "permission") return "❓ " + elapsed + " autorisation attendue"
  if (state.phase === "preparing") return "⏳ " + elapsed + " préparation"
  if (state.phase === "compaction") return "⏳ " + elapsed + " résumé du contexte (conversation trop longue)"
  if (state.phase === "tool") {
    const running = [...(state.running || new Map()).values()]
    const texts = running.length ? running.map((entry) => entry.text) : [state.tool]
    const base = "⏳ " + elapsed + (texts.length > 1 ? " outils (" + texts.length + ") · " + toolList(texts) : " outil · " + texts[0])
    const children = running.filter((entry) => entry.child && subagents.has(entry.child)).map((entry) => ({ text: entry.text, child: subagents.get(entry.child) }))
    const asking = children.find((entry) => entry.child.phase === "question" || entry.child.phase === "permission")
    if (asking) return "❓ " + elapsed + " " + asking.text + " · " + (asking.child.phase === "question" ? "réponse attendue" : "autorisation attendue")
    const retrying = children.find((entry) => entry.child.phase === "retry")
    if (retrying) return base + " · nouvel essai " + retrying.child.attempt + retryIn(retrying.child, now) + " (serveur du modèle)"
    if (children.some((entry) => entry.child.phase === "compaction")) return base + " · résumé du contexte"
    // silence: only when every subagent that runs has sent nothing for 30 s
    if (children.length && children.every((entry) => entry.child.phase !== "tool")) {
      const quiet = Math.min(...children.map((entry) => now - entry.child.last))
      if (quiet > SILENCE_MS) return base + " · rien reçu depuis " + since(quiet)
    }
    return base
  }
  if (state.phase === "retry") return "⏳ " + elapsed + " nouvel essai " + state.attempt + retryIn(state, now) + " (serveur du modèle)"
  const quiet = now - state.last
  if (quiet > SILENCE_MS) return "⏳ " + elapsed + " rien reçu depuis " + Math.round(quiet / 1000) + " s"
  if (state.phase === "reasoning") return "⏳ " + elapsed + " réflexion " + tokens(state.chars) + " tokens"
  if (state.phase === "text") return "⏳ " + elapsed + " rédaction " + tokens(state.chars) + " tokens"
  return "⏳ " + elapsed + " attente du modèle"
}

// What a running tool is doing, in a few words: its description, the file it works on, its pattern, or its name
function toolText(name, input) {
  const args = input && typeof input === "object" ? input : {}
  const file = args.path || args.filePath
  const text = args.description || (file && basename(String(file))) || args.pattern || name || "outil"
  return String(text).replace(/\s+/g, " ").trim().slice(0, 40)
}

// The files a patch of the patch tool adds, updates, deletes or moves to ("*** Add File: <path>"…)
const PATCH_FILE = /^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+?)\s*$/gm
const patchFiles = (text) => [...String(text || "").matchAll(PATCH_FILE)].map((m) => m[1])

// The guards of the shell and file tools (6, 7, 11, the timeouts of 8) and the stable environment (2), for the folder
// of one location. `client` gives the session of an id ({ data: { parentID } }), the configuration (references) and
// the log.
export const Guards = async (input) => {
  const directory = (input && (input.directory || input.worktree)) || process.cwd()
  const client = input && input.client
  // the repository of this instance: its git root (OpenCode gives "/" as the worktree of a folder outside git)
  const root = resolve(input && input.worktree && input.worktree !== "/" ? input.worktree : directory)
  // the ticket sheets: <git folder>/opencode-tickets, shared by the worktrees of the repository; outside the folder of
  // the session when it runs in a worktree (an OpenCode workspace)
  const common = await gitCommonDir(root)
  const SHEETS = common ? join(common, "opencode-tickets") : ""
  const SHEET_WRITERS = new Set(["pilot", "analyst"])
  // session id -> name of the agent of its last tool call (7)
  const agents = new Map()
  // session id -> parent session id, "" for a top-level session (7)
  const parents = new Map()
  // session id -> folders outside the repository that I named in that session (7)
  const named = new Map()
  let references

  // ---------- 7. folders allowed outside the repository ----------
  async function parentOf(sessionID) {
    if (parents.has(sessionID)) return parents.get(sessionID)
    let parent = ""
    try {
      const info = client && (await client.session.get({ path: { id: sessionID } })).data
      parent = (info && info.parentID) || ""
    } catch {
      // unknown: treated as a top-level session
    }
    parents.set(sessionID, parent)
    return parent
  }

  // the folders configured as "references" in opencode.json (local paths; OpenCode lets every agent read them)
  async function referenceFolders() {
    if (references) return references
    references = []
    try {
      const config = client ? (await client.config.get()).data || {} : {}
      for (const entry of Object.values(config.references || config.reference || {})) {
        // a git reference ({ repository }, or "owner/repo") has no local path to allow: only the folders that exist
        const where = typeof entry === "string" ? entry : entry && entry.path
        if (!where) continue
        const expanded = where === "~" || where.startsWith("~/") ? join(HOME, where.slice(2)) : where
        for (const base of isAbsolute(expanded) ? [""] : [root, join(HOME, ".config", "opencode")]) {
          const target = resolve(base, expanded)
          if (existsSync(target)) references.push(target)
        }
      }
    } catch {
      // no reference
    }
    return references
  }

  async function namedIn(sessionID) {
    const own = named.get(sessionID) || []
    const parent = await parentOf(sessionID)
    return parent ? [...own, ...(named.get(parent) || [])] : own
  }

  function addNamed(sessionID, text) {
    const found = namedFolders(text, root)
    if (found.length) named.set(sessionID, [...new Set([...(named.get(sessionID) || []), ...found])])
  }

  // Where a tool call leaves the folders allowed to its agent (7), as { piece, readOnly }, or null
  async function escape(tool, sessionID, args) {
    const agent = agents.get(sessionID) || ""
    const cwd = args && typeof args.workdir === "string" && args.workdir ? resolve(directory, args.workdir) : directory
    const shared = [...PACK_DIRS, ...SAVED_OUTPUTS, ...(SHEETS ? [SHEETS] : [])]
    if (tool === "bash") {
      const extra = SHELL_READERS.has(agent) || !PACK_AGENTS.has(agent) ? [...(await referenceFolders()), ...(await namedIn(sessionID))] : []
      const readable = [...shared, ...extra]
      if (!within(cwd, root) && !readable.some((dir) => within(cwd, dir))) return { piece: args.workdir }
      return shellOutside(args && args.command, cwd, root, readable, PACK_AGENTS.has(agent))
    }
    if (!PACK_AGENTS.has(agent)) return null
    // a patch writes every file it names
    if (tool === "patch") {
      for (const file of patchFiles(args && args.patchText)) {
        const outside = await escape("write", sessionID, { filePath: file })
        if (outside) return outside
      }
      return null
    }
    const key = FILE_TOOLS[tool]
    if (!key) return null
    const value = args && args[key]
    if (typeof value !== "string" || !value) return null
    const target = value === "~" || value.startsWith("~/") ? join(HOME, value.slice(2)) : resolve(directory, value)
    if (DEVICES.has(target) || within(target, root)) return null
    const readable = [...shared, PACKAGE_CACHE, ...(await referenceFolders()), ...(await namedIn(sessionID))]
    const inReadable = readable.some((dir) => within(target, dir))
    // the agents of the pack write only in the repository, and the pilot and the analyst in the ticket sheets
    if (tool === "write" || tool === "edit") {
      if (SHEETS && within(target, SHEETS) && SHEET_WRITERS.has(agent)) return null
      return { piece: value, readOnly: inReadable }
    }
    return inReadable ? null : { piece: value }
  }

  // Each refusal goes to the log ("refused by the pack"): the agent, the tool, the reason, the path, never the command
  // (it may hold a credential)
  function logRefusal(call, reason, piece) {
    try {
      if (!client || !client.app || typeof client.app.log !== "function") return
      const extra = { agent: call.agent || agents.get(call.sessionID) || "", tool: call.tool, reason }
      if (piece) extra.path = piece
      Promise.resolve(client.app.log({ body: { service: "pack", level: "warn", message: "refused by the pack", extra } })).catch(() => {})
    } catch {
      // the log is best-effort
    }
  }

  return {
    logRefusal,
    // the agent of a session, as its last tool call says
    agent(sessionID, name) {
      if (sessionID && name) agents.set(sessionID, name)
    },
    // the folders I name in a text I typed in a top-level session (never in a subagent's session)
    async named(sessionID, text) {
      try {
        if (!sessionID || typeof text !== "string" || !text) return
        if (await parentOf(sessionID)) return
        addNamed(sessionID, text)
      } catch {
        // nothing named
      }
    },
    // 6, 7, 8 and 11 for a tool call: { tool (1.19 names: bash, read…), sessionID, agent }, { args } changed in place
    async before(call, output) {
      if (!call || !output || !output.args) return
      if (call.agent) agents.set(call.sessionID, call.agent)
      if (call.tool === "bash" && typeof output.args.command === "string") {
        // 11. a build tool called by its full path runs by its name: the rules of the agents know `dotnet build`, not
        // `/home/me/.bin/dotnet build`, and the folder of the tool is outside the repository
        output.args.command = output.args.command.replace(TOOL_PATH, "$1$3")
        // 6/7. the harmless stderr/stdout and /dev/null redirections do not reach the permission rules (nor change the run)
        output.args.command = stripNoise(output.args.command)
        const why = refusal(output.args.command)
        if (why) {
          logRefusal(call, why)
          throw new Error(
            "Refused by the pack: " + why + ". A command never sets PATH, DOTNET_ROOT or a credential, never prints the " +
              "environment and never deletes a folder: the environment of the agents comes from ~/.zshenv, and a " +
              "credential written in a command stays in the session history. If dotnet is missing or Artifactory " +
              "refuses access, it is an ENVIRONMENT PROBLEM: tell the user in one line and stop. Never try another " +
              "form of this command.",
          )
        }
      }
      // 23. dotnet run: only a project of the repository that the last commit holds
      if (call.tool === "bash" && typeof output.args.command === "string" && /\bdotnet\b[^;&|\n]*\brun\b/.test(output.args.command)) {
        const cwd = typeof output.args.workdir === "string" && output.args.workdir ? resolve(directory, output.args.workdir) : directory
        const target = dotnetRunTarget(output.args.command, cwd, root)
        if (target && !target.ok) {
          logRefusal(call, "dotnet run of a project the last commit does not hold", target.project)
          throw new Error(
            "Refused by the pack: dotnet run runs only a project of this repository that the last commit holds (" +
              target.project + " is new, not committed, outside the repository or a C# file): never a probe or " +
              "reflection program. The API of a package is in its XML documentation (sh ~/.config/opencode/scripts/" +
              "package-refs.sh --doc <package id> gives its file; grep tool on the member name) and in its existing " +
              "calls. Never try " +
              "another form of this command.",
          )
        }
      }
      // 24. a command that never ends by itself: refused, except in the free conversation (in the background or bounded)
      if (call.tool === "bash" && typeof output.args.command === "string") {
        const cwd = typeof output.args.workdir === "string" && output.args.workdir ? resolve(directory, output.args.workdir) : directory
        const found = neverEnding(output.args.command, cwd, root)
        if (found) {
          const agent = call.agent || agents.get(call.sessionID) || ""
          const conversation = !PACK_AGENTS.has(agent) && !(await parentOf(call.sessionID))
          // the free conversation: in the background (OpenCode v2 keeps it running and the turn goes on), or bounded
          if (!(conversation && (output.args.background === true || (found.bounded > 0 && found.bounded <= 300)))) {
            logRefusal(call, "a command that never ends: " + found.log)
            throw new Error(
              "Refused by the pack: " + found.what + " does not end by itself (a server or a watch mode): it would hold " +
                "the turn until OpenCode stops it. The build and the tests, once: sh ~/.config/opencode/scripts/" +
                "build-test.sh [<folder>] (a front-end folder: its build, then its tests once, with explicit TESTS " +
                "lines). A behavior: a test." +
                (conversation ? " Here, in the conversation: in the background (background: true), or bounded: timeout 60 <the command>." : "") +
                " Never try another form of this command.",
            )
          }
        }
      }
      // 25. the agents of the pack never change the dependencies of the repository, nor a tool of the machine
      if (call.tool === "bash" && typeof output.args.command === "string" && PACK_AGENTS.has(call.agent || agents.get(call.sessionID) || "")) {
        const cwd = typeof output.args.workdir === "string" && output.args.workdir ? resolve(directory, output.args.workdir) : directory
        const found = dependencyChange(output.args.command, cwd, root)
        if (found && found.machine) {
          logRefusal(call, "an install on the machine: " + found.log)
          throw new Error(
            "Refused by the pack: " + found.what + " installs or changes a tool of this machine: an agent never does. A " +
              "tool that is missing or in the wrong version (node, npm, Chrome, a .NET SDK) is an ENVIRONMENT PROBLEM: " +
              "tell the user in one line and stop. Never try another form of this command.",
          )
        }
        if (found) {
          logRefusal(call, "a change of the dependencies: " + found.log)
          throw new Error(
            "Refused by the pack: " + found.what + " changes the dependencies of the repository (a package added, " +
              "removed or upgraded, or the lockfile resolved again): the developer decides that, never an agent. A step " +
              "that needs a package is « BLOQUÉ » with what is needed (the package, its version, why). The dependencies " +
              "of the lockfile are installed by sh ~/.config/opencode/scripts/build-test.sh [<folder>] when they are " +
              "missing (npm ci, dotnet restore). Never try another form of this command.",
          )
        }
      }
      let outside = null
      try {
        outside = await escape(call.tool, call.sessionID, output.args)
      } catch {
        outside = null
      }
      if (outside && outside.redirect) {
        logRefusal(call, "writes a file with a redirection", outside.piece)
        throw new Error(
          "Refused by the pack: " + outside.piece + " is written by a redirection (> or >>). The agents of the pack " +
            "write files with the edit and write tools, never with a shell redirection (a read-only agent must stay " +
            "read-only, and a redirection escapes the edit rules). Only 2>&1 and /dev/null are allowed. Never try " +
            "another form of this command.",
        )
      }
      if (outside && outside.readOnly) {
        logRefusal(call, "read-only folder", outside.piece)
        throw new Error(
          "Refused by the pack: " + outside.piece + " is outside the repository of this session (" + root + "): the " +
            "agents may read it, never change it or run anything there (no cp, mv, rm, redirection, build, " +
            "interpreter or xargs on it). Work in the repository. Never try another form of this command.",
        )
      }
      if (outside) {
        logRefusal(call, "outside the repository", outside.piece)
        throw new Error(
          "Refused by the pack: " + outside.piece + " is outside the repository of this session (" + root + "). The " +
            "agents stay in the repository: secrets live outside it. Work with the files of the repository; a folder " +
            "outside it is readable only when the developer names it in the command or in a message, or configures " +
            "it as a reference. Never try another form of this path.",
        )
      }
      if (call.tool === "bash" && typeof output.args.command === "string") {
        // 8. long commands get the time they need (OpenCode stops a command after 2 minutes by default)
        const need = LONG_COMMAND.test(output.args.command) ? COMMAND_MAX_MS : GIT_SCRIPT.test(output.args.command) ? 5 * 60000 : 0
        if (need && !(Number(output.args.timeout) >= need)) output.args.timeout = need
        // 8. and a command of an agent of the pack always ends: never without a limit (OpenCode v2 turns it off with
        // timeout 0): the 20 minutes of a full build and tests instead, and 2 hours at most when the agent asks for more
        if (output.args.timeout !== undefined && PACK_AGENTS.has(call.agent || agents.get(call.sessionID) || "")) {
          const asked = Number(output.args.timeout)
          if (!(asked > 0)) output.args.timeout = COMMAND_MAX_MS
          else if (asked > COMMAND_CAP_MS) output.args.timeout = COMMAND_CAP_MS
        }
      }
    },
    // 2. the environment of every shell command of the agents
    env(env) {
      try {
        if (!env) return
        cleanEnv(env)
        const set = (name, value) => {
          if (process.env[name] === undefined && env[name] === undefined) env[name] = value
        }
        set("DOTNET_CLI_UI_LANGUAGE", "en")
        set("DOTNET_NOLOGO", "1")
        set("DOTNET_CLI_TELEMETRY_OPTOUT", "1")
        set("MSBUILDTERMINALLOGGER", "off")
        set("NPM_CONFIG_UPDATE_NOTIFIER", "false")
        set("NPM_CONFIG_FUND", "false")
        // npm ci without its audit request (a call to the registry that Artifactory may not answer), the Angular CLI and
        // Next.js without their analytics prompt or telemetry
        set("NPM_CONFIG_AUDIT", "false")
        set("NG_CLI_ANALYTICS", "false")
        set("NEXT_TELEMETRY_DISABLED", "1")
        // Nobody can answer a prompt or close an editor in an agent's command: forced, whatever the environment
        env.GIT_TERMINAL_PROMPT = "0"
        env.GIT_EDITOR = "true"
        const count = Number(env.GIT_CONFIG_COUNT ?? process.env.GIT_CONFIG_COUNT ?? 0)
        if (Number.isInteger(count) && count >= 0) {
          env["GIT_CONFIG_KEY_" + count] = "core.quotePath"
          env["GIT_CONFIG_VALUE_" + count] = "false"
          env.GIT_CONFIG_COUNT = String(count + 1)
        }
      } catch {
        // keep the environment as it is
      }
    },
  }
}

// ---------- OpenCode v2 ----------
// The log of the plugin, next to the log of OpenCode: never a command or a text of the conversation (they may hold a
// credential), only what the plugin did and why
const LOG_FILE = join(process.env.XDG_DATA_HOME || join(HOME, ".local", "share"), "opencode", "log", "openrd-pack.log")
const LOG_MAX = 1024 * 1024
function writeLog(line) {
  try {
    try {
      if (statSync(LOG_FILE).size > LOG_MAX) renameSync(LOG_FILE, LOG_FILE + ".1")
    } catch {
      // no log yet
    }
    mkdirSync(dirname(LOG_FILE), { recursive: true })
    appendFileSync(LOG_FILE, new Date().toISOString() + " " + line + "\n", { mode: 0o600 })
  } catch {
    // the log is best-effort
  }
}
// 29. One line per run of a command of the pack, next to the log, for /outil vitesse (vitesse.sh): the date, "run", then
// key=value fields separated by tabs (seconds, counts, names: never a prompt nor a command)
const RUNS_FILE = join(dirname(LOG_FILE), "openrd-pack-runs.tsv")
function writeRunLine(fields) {
  try {
    try {
      if (statSync(RUNS_FILE).size > LOG_MAX) renameSync(RUNS_FILE, RUNS_FILE + ".1")
    } catch {
      // no file yet
    }
    mkdirSync(dirname(RUNS_FILE), { recursive: true })
    const date = new Date()
    const two = (n) => String(n).padStart(2, "0")
    // the local time of the machine too, as the developer reads it
    const local = date.getFullYear() + "-" + two(date.getMonth() + 1) + "-" + two(date.getDate()) + " " + two(date.getHours()) + ":" + two(date.getMinutes())
    const values = Object.entries({ at: local, ...fields }).map(([key, value]) => key + "=" + String(value === undefined ? "" : value).replace(/[\t\r\n]+/g, " "))
    appendFileSync(RUNS_FILE, [date.toISOString(), "run", ...values].join("\t") + "\n", { mode: 0o600 })
  } catch {
    // the measure is best-effort
  }
}
// ---------- 26. scheduled commands ----------
// The schedules of /outil planifier (schedule.sh), one per line of ~/.config/opencode/schedules.md
// ($OPENCODE_SCHEDULES): "- #1 08:45 lun,mar,mer,jeu,ven /daily — /home/dev/repos/api (ajoutée le 2026-10-24)"
const SCHEDULE_MS = 20000
const SCHEDULE_DAYS = ["dim", "lun", "mar", "mer", "jeu", "ven", "sam"]
const SCHEDULE_LINE = /^- #(\d+) (\d{2}):(\d{2}) ([a-z,]+) \/([a-z][a-z0-9-]*)((?: [^\n]*?)?) — (\/.*?) \(ajoutée le [0-9-]+\)\s*$/
export function scheduleEntries(text) {
  const entries = []
  for (const line of String(text || "").split("\n")) {
    const m = SCHEDULE_LINE.exec(line.replace(/\r$/, ""))
    if (!m) continue
    const days = new Set(m[4].split(",").map((d) => SCHEDULE_DAYS.indexOf(d)).filter((d) => d >= 0))
    entries.push({ id: m[1], hour: Number(m[2]), minute: Number(m[3]), days, command: m[5], args: m[6].trim(), directory: m[7] })
  }
  return entries
}
// The wizards of /tests env: they ask questions and write AGENTS.md, never started without the developer
const SCHEDULE_WIZARDS = /^(?:config|configurer|configuration|setup|ajouter|r[ée]glages|r[ée]gler|param[ée]trer|nouvel|nouveau)$/i
// What may start without the developer: what writes nothing in git or in Jira (schedule.sh refuses the others; a line
// edited by hand is checked again here)
export function scheduleAllowed(entry) {
  const args = entry.args.split(/\s+/).filter(Boolean)
  if (entry.command === "daily") return true
  if (entry.command === "outil") return args[0] === "audit" || args[0] === "licences"
  // /tests env <environment>, read only: never its wizards (/tests env config asks questions and writes AGENTS.md)
  if (entry.command === "tests") {
    return args[0] === "env" && args.length >= 2 && !SCHEDULE_WIZARDS.test(args[1]) &&
      !args.some((word) => /^(?:--)?(?:writes|allow-writes|[eé]criture)$/i.test(word))
  }
  return false
}
// The schedules due at this minute of the local time of the machine
export function dueSchedules(text, now = new Date()) {
  return scheduleEntries(text).filter((e) => e.hour === now.getHours() && e.minute === now.getMinutes() && e.days.has(now.getDay()))
}
const pad2 = (n) => String(n).padStart(2, "0")

// v2 names the shell tool "shell" (1.19: "bash") and the subagent tool "subagent" (1.19: "task"), and the file path
// "path" (1.19: "filePath")
const V2_TOOLS = { shell: "bash", subagent: "task" }
// 12. tools that move a session or create or remove a worktree, by their names and by their names in code mode
const V2_REFUSED = new Set(["session_move", "worktree_create", "worktree_remove"].flatMap((name) => [name, "opencode_" + name]))
// 12. tools taken out of every request to the model: code mode and the web search
const V2_HIDDEN = ["execute", "websearch"]
// the first line of the prompt of a new subagent session in OpenCode v2.1.2 (its subagent tool)
const SUBAGENT_PROMPT = "You are a subagent spawned by another session."
// 3. the first line of every command of the pack: "[[command <name> <arguments>]]"
const COMMAND_LINE = /^\s*\[\[command ([a-z][a-z0-9-]*)(?:[ \t]+([\s\S]*?))?\]\][ \t]*(?:\r?\n|$)/
// (/tests: the unit tests of a code without a ticket, a run of the pilot like the others)
const PILOT_COMMANDS = new Set(["go", "fix", "fortify", "tests"])
// 9. the commands that write to git: one at a time per folder (/push and /sync are not resumed: 19)
const LOCKING_COMMANDS = new Set([...PILOT_COMMANDS, "push", "sync"])
// a command file of an older pack, without its [[command]] line: the first sentence of the body of each pilot command
const PILOT_RUNS = [
  ["go", "Take the ticket from its analysis to its Draft merge request"],
  ["fix", "Bring the branch to a green, review-ready state"],
  ["fortify", "Fix a batch of Fortify vulnerabilities"],
]
const LOCK_MS = 4 * 3600 * 1000
const LOCK_FILE_NAME = "opencode-pilot.lock"
// 9. how long a lock taken over from a stopped OpenCode waits for its resumed run to start
const ADOPT_MS = 2 * 60000
// 14. how long a prompt waits for the MCP servers still connecting, during the first minutes of an instance
const MCP_WAIT_MS = 30000
const MCP_BOOT_MS = 5 * 60000
// 27. the longest a call of an MCP server may take, when its configuration gives none (OpenCode v2: 12 hours)
const MCP_CALL_MS = 5 * 60000
// 28. how often the options of the agents are read again (a configuration that changed)
const AGENT_OPTIONS_MS = 60000
// 16. the identical calls of one answer of the model that make a loop (1.19: DOOM_LOOP_THRESHOLD)
const LOOP_CALLS = 3
// 13. what 1.19 kept of the tool outputs when it pruned (compaction.prune)
const PRUNE_PROTECT = 40000
const PRUNE_MINIMUM = 20000
const PRUNE_PROTECTED_TOOLS = new Set(["skill"])
const PRUNED = "[Old tool result content cleared]"
// the end of a turn in v2 (durable execution events), and the status events of older shapes
const TURN_END = new Set(["session.execution.succeeded", "session.execution.failed", "session.execution.interrupted"])
// 17. the first text of the message that replaces a summarized conversation (OpenCode v2.1.3)
const CHECKPOINT = "<conversation-checkpoint>"
// 17. what is kept of a procedure or of a task, and of how many sessions
const PROCEDURE_MAX = 40000
const TASK_MAX = 12000
const REMEMBERED_SESSIONS = 200
// 18. the least wait before each retry of a request of a run of the pack (OpenCode's attempts 2 to 11): about 8
// minutes in all, against about 1.5 by default. Longer would only delay the resume of 19 when the server is down for
// good, or when a gateway answers 503 to a request too long for the model (a wrong limit.context)
const PATIENCE_MS = [0, 0, 10000, 20000, 30000, 45000, 60000, 60000, 60000, 60000, 60000, 60000]
// 19. automatic resumes: how many in a row, and the wait before each one after a failure of the model server
const RESUMES_MAX = 2
const RESUME_AFTER_FAILURE_MS = [2 * 60000, 5 * 60000]
const RESUME_AFTER_UNFINISHED_MS = 5000
// 19. failures that a resume cannot solve (OpenCode v2.1.3 error types): the provider refuses the credentials, the
// quota, the content or the request itself, the model is not configured, a permission was refused
const FINAL_ERRORS = new Set(["provider.auth", "provider.quota", "provider.free-limit", "provider.content-filter",
  "provider.invalid-request", "provider.unsupported-operation", "provider.no-route", "permission.rejected", "aborted"])
const FINAL_STATUS = new Set([401, 402, 403])
// 19. the line after [[command]] of a resume the plugin sends: "[[resume <reason, in French>]]"
const RESUME_LINE = /^[ \t]*\[\[resume(?:[ \t]+([^\]\n]*))?\]\][ \t]*(?:\r?\n|$)/

// JSON with comments and trailing commas, as OpenCode reads its configuration (strings kept as they are)
const STRING = String.raw`"(?:\\.|[^"\\])*"`
function parseJsonc(text) {
  const noComments = text.replace(new RegExp(STRING + String.raw`|\/\/[^\n]*|\/\*[\s\S]*?\*\/`, "g"), (m) => (m[0] === '"' ? m : ""))
  return JSON.parse(noComments.replace(new RegExp(STRING + String.raw`|,(\s*[}\]])`, "g"), (m, tail) => (m[0] === '"' ? m : tail)))
}

// The OpenCode configuration as the plugin reads it: in the configuration folder of OpenCode v2 (OPENCODE_CONFIG_DIR,
// as MIGRATION.md starts it next to 1.19; otherwise the XDG one), opencode.json then opencode.jsonc, the second one
// winning as in OpenCode
function configuration() {
  const dir = process.env.OPENCODE_CONFIG_DIR || join(process.env.XDG_CONFIG_HOME || join(HOME, ".config"), "opencode")
  const out = { references: {}, prune: false }
  for (const name of ["opencode.json", "opencode.jsonc"]) {
    try {
      const data = parseJsonc(readFileSync(join(dir, name), "utf8")) || {}
      Object.assign(out.references, data.references || data.reference || {})
      if (data.compaction && typeof data.compaction.prune === "boolean") out.prune = data.compaction.prune
    } catch {
      // no file, or a file OpenCode rejects as well
    }
  }
  return out
}

// The text of a tool result as the model receives it
function resultText(result) {
  if (!result || typeof result !== "object") return ""
  if (typeof result.value === "string") return result.value
  try {
    return JSON.stringify(result.value) || ""
  } catch {
    return ""
  }
}

// 13. Clears the outputs of old tool calls in the messages of a request, as 1.19 did; returns how many
export function prune(messages) {
  if (!Array.isArray(messages)) return 0
  let turns = 0
  let total = 0
  let freed = 0
  const parts = []
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i]
    if (!message) continue
    if (message.role === "user") turns++
    if (turns < 2 || message.role !== "tool" || !Array.isArray(message.content)) continue
    for (let j = message.content.length - 1; j >= 0; j--) {
      const part = message.content[j]
      if (!part || part.type !== "tool-result" || PRUNE_PROTECTED_TOOLS.has(part.name)) continue
      const text = resultText(part.result)
      if (text === PRUNED) continue
      const estimate = Math.round(text.length / 4)
      total += estimate
      if (total > PRUNE_PROTECT) {
        freed += estimate
        parts.push(part)
      }
    }
  }
  if (freed <= PRUNE_MINIMUM) return 0
  for (const part of parts) part.result = { type: "text", value: PRUNED }
  return parts.length
}

// 20. The JSON body of a chat completions request with "" instead of null as the content of an assistant message that
// holds only tool calls (OpenCode v2 sends null there, as the OpenAI format allows; a gateway that validates content as
// a string or an array answers HTTP 400 "Request doesn't match the schema" at /messages/<n>/content). Returns the new
// body, or null when there is nothing to change (not JSON, no messages, no null content).
export function fillNullContent(body) {
  if (typeof body !== "string" || !/"content"\s*:\s*null/.test(body)) return null
  let request
  try {
    request = JSON.parse(body)
  } catch {
    return null
  }
  if (!request || !Array.isArray(request.messages)) return null
  let changed = 0
  for (const message of request.messages) {
    if (message && message.role === "assistant" && message.content === null) {
      message.content = ""
      changed++
    }
  }
  return changed ? JSON.stringify(request) : null
}

// 28. What the options of an agent never change in a request: what OpenCode builds (the conversation, the tools, the
// model, the stream, the output limit it fits to the context window)
const REQUEST_OWN = new Set(["model", "messages", "tools", "tool_choice", "functions", "function_call", "stream",
  "stream_options", "n", "max_tokens", "max_completion_tokens", "parallel_tool_calls", "response_format", "prompt"])
const plainObject = (value) => !!value && typeof value === "object" && !Array.isArray(value)
// `over` merged into `base`, objects key by key (chat_template_kwargs of the model and of the agent together), the value
// of `over` winning; a new object, the inputs unchanged
function mergeOptions(base, over) {
  const out = { ...base }
  for (const [key, value] of Object.entries(over)) {
    if (value === undefined) continue
    out[key] = plainObject(value) && plainObject(out[key]) ? mergeOptions(out[key], value) : value
  }
  return out
}
// The options of the agent (temperature, top_p, top_k, chat_template_kwargs…: the "request.body" OpenCode v2 reads from
// its configuration) in the JSON body of one of its chat completions requests. The presence penalty of a loop cut (21)
// stays when it is higher. Returns the new body, or null when there is nothing to change (not a chat completions body,
// no option, the same values already).
export function withAgentOptions(body, options) {
  if (typeof body !== "string" || !plainObject(options)) return null
  const own = Object.entries(options).filter(([key, value]) => !REQUEST_OWN.has(key) && value !== undefined)
  if (!own.length) return null
  let request
  try {
    request = JSON.parse(body)
  } catch {
    return null
  }
  if (!plainObject(request) || !Array.isArray(request.messages)) return null
  const merged = mergeOptions(request, Object.fromEntries(own))
  const loopPenalty = Number(request.presence_penalty)
  if (Number.isFinite(loopPenalty) && !(Number(merged.presence_penalty) >= loopPenalty)) merged.presence_penalty = loopPenalty
  const text = JSON.stringify(merged)
  return text === JSON.stringify(request) ? null : text
}

// The metadata of a user message that the web interface shows instead of its text
const presentation = (metadata, displayText) => ({ ...(metadata && typeof metadata === "object" ? metadata : {}), displayText, comments: [], attachments: [] })

// ---------- 17. a run that goes on after a summary of its conversation ----------
// The text of a message of a request (a string, or parts)
function messageText(message) {
  const content = message && message.content
  if (typeof content === "string") return content
  if (!Array.isArray(content)) return ""
  return content.map((part) => (part && typeof part.text === "string" ? part.text : "")).join("\n")
}
// Whether the messages of a request start from a summary of the conversation
const summarized = (messages) =>
  Array.isArray(messages) && messages.slice(0, 3).some((message) => message && message.role === "user" && messageText(message).trimStart().startsWith(CHECKPOINT))

// The instructions of a pilot command as they reach the model, without the outputs of its scripts: they were true when
// the run started, and the ticket sheet is newer
function procedureOf(text) {
  return String(text || "")
    .replace(RUN, (match, script, args) => "(output of " + script + (args || "") + ": printed when the run started)")
    .replace(VISIBLE, "\n")
    .trim()
    .slice(0, PROCEDURE_MAX)
}

// The instructions of a pilot command from its file, when this instance of the plugin did not see the run start (a
// run resumed by OpenCode's background service after a restart, or the plugin loaded again during the run)
function commandFile(command, args) {
  const dir = process.env.OPENCODE_CONFIG_DIR || join(process.env.XDG_CONFIG_HOME || join(HOME, ".config"), "opencode")
  try {
    const body = readFileSync(join(dir, "commands", command + ".md"), "utf8").replace(/^---\r?\n[\s\S]*?\r?\n---\r?\n?/, "")
    return procedureOf(body.replace(COMMAND_LINE, "").replaceAll("$ARGUMENTS", args || ""))
  } catch {
    return ""
  }
}

const runName = (run) => "/" + run.command + (run.args ? " " + run.args : "")

// What the summary of a run must keep (asked of the model that writes it)
const keepRunNote = (run) =>
  "## Summary of a run of the pack\n" +
  "This session runs " + runName(run) + " of the pack, which goes on after this summary. Keep in the summary, " +
  "exactly (in « Work State » and « Important Context »): the ticket key and the branch, the path of the ticket sheet " +
  "and of the batch folder, the step or the vulnerability under way and its phase, the sessionID and the role of each " +
  "subagent that may be taken up again (for example the test-guardian of V2, the coder of step 3), the commits made " +
  "(hash and message), the merge request link, the tests that already failed on develop, the decisions recorded, and " +
  "the failures met with the rounds already spent on them. The instructions of the command are given again after the " +
  "summary: do not copy them."

// What every request of a run gets after a summary: its procedure, as instructions
const procedureNote = (run, text) =>
  "## The run of /" + run.command + " goes on after a summary\n" +
  "The conversation of this run was summarized to fit the context of the model (the conversation checkpoint). The " +
  "instructions of /" + run.command + " still apply, unchanged: they are below, as the run started; the outputs of " +
  "its scripts were printed at that time, and the ticket sheet, git and the batch folder are newer. If you have not " +
  "done it since the checkpoint, first run `sh ~/.config/opencode/scripts/workflow-state.sh --no-fetch --sheet` (for " +
  "/fortify, also read the card of the vulnerability under way), then go on from the first step that is not done. " +
  "Never redo a step whose commit or tick exists; take up a subagent again with its sessionID when the checkpoint " +
  "gives it.\n\n<instructions of /" + run.command + ">\n" + text + "\n</instructions of /" + run.command + ">"

// What the summary of a subagent must keep
const KEEP_TASK_NOTE =
  "## Summary of the work of a subagent\n" +
  "This session is a subagent of the pack working on ONE task for the pilot, and it goes on after this summary. Keep " +
  "in the summary, exactly: the files read and changed (paths), the commands run with their result lines (BUILD, " +
  "TESTS, RED, GREEN, FLAKY, COVERAGE, STOP), the decisions taken with their reasons, what remains to do, and the " +
  "report the task must end with. The task itself is given again after the summary: do not copy it."

// What every request of a subagent gets after a summary: its task, as instructions
const taskNote = (texts) =>
  "## Your task goes on after a summary\n" +
  "Your conversation was summarized to fit the context of the model (the conversation checkpoint). Your task, as the " +
  "pilot gave it, still applies unchanged; it is below. What you already did is in the checkpoint and in the files: " +
  "look at them (git status, the files you changed) before going on, never redo what is done, and end with your " +
  "report in the format of your instructions.\n\n<task>\n" + texts.join("\n\n(Then the pilot wrote:)\n") + "\n</task>"

// ---------- 19. automatic resumes ----------
// A mark of the final answer of a pilot run, at the start of one of its lines (a ✅ in a table cell is no outcome)
const MARK_LINE = /^[\s>*_#|-]*(🚀|🔁|✅|⏸|⛔)/u
// The answer the model writes when OpenCode stops its tools at the step limit of the agent
const STEP_LIMIT = /maximum (?:number of )?steps|step limit|nombre max(?:imum|imal) d'étapes|max(?:imum)? d'étapes|limite d'étapes/i

// The text OpenCode gives the pilot when the plugin resumes its run
const resumeText = (run, why) =>
  "The run of " + runName(run) + " stopped before its end: " + why.en + ". Continue it now, in this session, without " +
  "asking anything:\n" +
  "1. `sh ~/.config/opencode/scripts/workflow-state.sh --no-fetch --sheet`: the ticket sheet says what is done (its " +
  "ticked steps and its « ## Suivi » lines), git what is committed" +
  (run.command === "fortify" ? "; the card of the vulnerability under way, in the batch folder that `sh ~/.config/opencode/scripts/fortify.sh batch` prints, says which of its phases are done" : "") +
  (run.command === "fix" ? "; `git log` shows the fixes this run already committed" : "") +
  (run.command === "tests" ? "; `git status` and `git log` show the tests this run already wrote or committed (there is no ticket sheet)" : "") +
  ".\n2. Go on with the instructions of /" + run.command + " from the first step that is not done. Never redo a step " +
  "whose commit or tick exists; a subagent whose report you have is not called again, and one that failed is taken up " +
  "again with its sessionID.\n3. End with the final answer of /" + run.command + ", in its format."

// ---------- 21. a model that repeats itself ----------
// A thinking model can fall into a loop: the same sentence, or the same few sentences, again and again until the output
// limit (32k tokens: half an hour or more on a shared server), then OpenCode asks it to continue twice, with the loop
// in its context, then the run fails and is resumed. These helpers find such a loop in a text: the end of a text is a
// block of 1 to 8 sentences repeated back to back (exactly, apart from spaces and case), or a stretch of characters
// repeated back to back when there is no sentence boundary. The thresholds are those of a real loop, never of a text
// that repeats a line here and there (code drafted several times, a table): at least 600 repeated characters, and 4
// to 8 repetitions in a row depending on the length of the block.
const LOOP_BOUNDARY = /\n+|(?<=[.!?;…])\s+/
const LOOP_MIN_CHARS = 600
const LOOP_MAX_BLOCK = 8
const loopNeed = (chars) => (chars >= 200 ? 4 : chars >= 80 ? 5 : 8)
const normalizeSegment = (text) =>
  text
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^(?:[-*•>]|\d+[.)])\s+/, "")
    .replace(/[.!?;:…,\s]+$/, "")
    .toLowerCase()
// The sentences (or lines) of a text, normalized; empty ones left out
export function segmentsOf(text) {
  const out = []
  for (const raw of String(text || "").split(LOOP_BOUNDARY)) {
    const segment = normalizeSegment(raw)
    if (segment) out.push(segment)
  }
  return out
}
// The block of sentences repeated back to back at the end of `segments`, as { repeats, chars }, or null
export function trailingLoop(segments) {
  const n = segments.length
  for (let size = 1; size <= LOOP_MAX_BLOCK && size * 4 <= n; size++) {
    const block = segments.slice(n - size)
    const chars = block.reduce((sum, segment) => sum + segment.length, 0)
    if (chars < 24) continue
    let repeats = 1
    while ((repeats + 1) * size <= n) {
      const start = n - (repeats + 1) * size
      let same = true
      for (let i = 0; i < size && same; i++) same = segments[start + i] === block[i]
      if (!same) break
      repeats++
    }
    if (repeats >= loopNeed(chars) && repeats * chars >= LOOP_MIN_CHARS) return { repeats, chars, size }
  }
  return null
}
// A stretch of 20 to 400 characters repeated back to back at the end of a text (a loop without sentence boundaries)
export function periodicTail(text) {
  const tail = String(text || "").replace(/\s+/g, " ").slice(-4000)
  for (let period = 20; period <= 400; period++) {
    const need = period >= 100 ? 5 : 8
    if (tail.length < period * need) continue
    const unit = tail.slice(tail.length - period)
    let repeats = 1
    while (repeats < need && tail.slice(tail.length - (repeats + 1) * period, tail.length - repeats * period) === unit) repeats++
    if (repeats >= need && repeats * period >= LOOP_MIN_CHARS) return { repeats, chars: period, size: 0 }
  }
  return null
}
// Whether a text ends in a loop; `partial`: the last sentence may still be written (a stream), so it is left out
export function loopAtEnd(text, partial = false) {
  const segments = segmentsOf(text)
  if (partial) segments.pop()
  return trailingLoop(segments) || periodicTail(text)
}

// The text with each loop kept once: a block of sentences repeated back to back (same thresholds) is written once,
// followed by a note; null when there is none. For the history sent to the model: a loop left in a message of the
// conversation pulls the next answers into the same loop.
export function collapseRepeats(text) {
  const source = String(text || "")
  if (source.length < LOOP_MIN_CHARS) return null
  // the sentences with their separators, and their normalized form
  const pieces = source.split(/(\n+|(?<=[.!?;…])\s+)/)
  const raw = []
  for (let i = 0; i < pieces.length; i += 2) raw.push(pieces[i] + (pieces[i + 1] || ""))
  const norm = raw.map((piece) => normalizeSegment(piece))
  let out = ""
  let changed = false
  let i = 0
  while (i < raw.length) {
    let done = false
    for (let size = 1; size <= LOOP_MAX_BLOCK && i + size * 4 <= raw.length && !done; size++) {
      const block = norm.slice(i, i + size)
      if (block.some((segment) => !segment)) continue
      const chars = block.reduce((sum, segment) => sum + segment.length, 0)
      if (chars < 24) continue
      let repeats = 1
      while (i + (repeats + 1) * size <= raw.length) {
        let same = true
        for (let k = 0; k < size && same; k++) same = norm[i + repeats * size + k] === block[k]
        if (!same) break
        repeats++
      }
      if (repeats >= loopNeed(chars) && repeats * chars >= LOOP_MIN_CHARS) {
        out += raw.slice(i, i + size).join("") + "[the same " + (size > 1 ? size + " sentences" : "sentence") + " repeated " +
          (repeats - 1) + " more times: removed by the pack]\n"
        i += repeats * size
        changed = true
        done = true
      }
    }
    if (!done) {
      out += raw[i]
      i++
    }
  }
  return changed ? out : null
}

// The text OpenCode v2 sends after an answer cut at the output limit
const OUTPUT_LIMIT_NOTE = "Your last response hit the output token limit"
const partsOf = (message) => (Array.isArray(message && message.content) ? message.content : [])
const hasToolCall = (message) => partsOf(message).some((part) => part && (part.type === "tool-call" || part.type === "tool_call"))
const spokenText = (message) =>
  typeof (message && message.content) === "string"
    ? message.content
    : partsOf(message)
        .filter((part) => part && (part.type === "text" || part.type === "reasoning") && typeof part.text === "string")
        .map((part) => part.text)
        .join("\n")
// What a request carries of the loops of the conversation (messages of the context hook, changed in place): an answer
// that ended in a loop and was cut at the output limit, with the note OpenCode added after it, is taken out (the
// request is then the one that looped, sent again); any other loop in an answer is kept once. Returns what changed.
export function sanitizeLoops(messages) {
  let dropped = 0
  let collapsed = 0
  if (!Array.isArray(messages)) return { dropped, collapsed }
  for (let i = messages.length - 1; i >= 1; i--) {
    const note = messages[i]
    if (!note || note.role !== "user" || !spokenText(note).trimStart().startsWith(OUTPUT_LIMIT_NOTE)) continue
    const answer = messages[i - 1]
    if (answer && answer.role === "assistant" && !hasToolCall(answer) && loopAtEnd(spokenText(answer))) {
      messages.splice(i - 1, 2)
      dropped++
      i--
    }
  }
  for (const message of messages) {
    if (!message || message.role !== "assistant") continue
    for (const part of partsOf(message)) {
      if (!part || (part.type !== "text" && part.type !== "reasoning") || typeof part.text !== "string") continue
      const shorter = collapseRepeats(part.text)
      if (shorter === null) continue
      part.text = shorter
      collapsed++
    }
  }
  return { dropped, collapsed }
}

// The text of the reasoning and of the answer in one data line of an OpenAI-compatible stream, and its finish reason
function streamDelta(line) {
  if (!line.startsWith("data:")) return undefined
  const data = line.slice(5).trim()
  if (!data || data === "[DONE]") return undefined
  try {
    const event = JSON.parse(data)
    const choice = event && Array.isArray(event.choices) ? event.choices[0] : undefined
    const delta = (choice && choice.delta) || {}
    const text = [delta.reasoning_content, delta.reasoning, delta.content].filter((value) => typeof value === "string").join("")
    return { text, finish: choice && choice.finish_reason, id: event.id, model: event.model }
  } catch {
    return undefined
  }
}
// A streamed chat completion (SSE) watched for a loop: passed through event by event; once the text of the answer ends
// in a loop, the stream ends at once as an answer cut at the output limit (finish_reason "length"), and the request to
// the model server is cancelled (vLLM stops generating). `onLoop` is called with { repeats, chars, total }; `onEnd`
// when the stream ends without a loop.
export function watchStream(body, { onLoop, onEnd, checkEvery = 400 } = {}) {
  const reader = body.getReader()
  const decoder = new TextDecoder()
  const encoder = new TextEncoder()
  let pending = ""
  let text = ""
  let checked = 0
  let last = { id: "chatcmpl-pack", model: "" }
  let stopped = false
  const finish = (controller, found) => {
    stopped = true
    const chunk = { id: last.id || "chatcmpl-pack", object: "chat.completion.chunk", created: Math.floor(Date.now() / 1000),
      model: last.model || "", choices: [{ index: 0, delta: {}, finish_reason: "length" }] }
    controller.enqueue(encoder.encode("data: " + JSON.stringify(chunk) + "\n\ndata: [DONE]\n\n"))
    controller.close()
    reader.cancel().catch(() => {})
    if (onLoop) onLoop({ ...found, total: text.length })
  }
  return new ReadableStream({
    // each pull ends with something given to the reader (a stream calls pull again only after it got something)
    async pull(controller) {
      while (!stopped) {
        const { value, done } = await reader.read()
        if (done) {
          pending += decoder.decode()
          if (pending) controller.enqueue(encoder.encode(pending))
          controller.close()
          if (onEnd) onEnd()
          return
        }
        pending += decoder.decode(value, { stream: true })
        // complete events only (an event ends with a blank line)
        const end = Math.max(pending.lastIndexOf("\n\n"), pending.lastIndexOf("\r\n\r\n"))
        if (end < 0) continue
        const cut = pending.charAt(end) === "\r" ? end + 4 : end + 2
        const events = pending.slice(0, cut)
        pending = pending.slice(cut)
        let finished = false
        for (const line of events.split(/\r?\n/)) {
          const delta = streamDelta(line)
          if (!delta) continue
          if (delta.id) last = { id: delta.id, model: delta.model || last.model }
          if (delta.text) text += delta.text
          if (delta.finish) finished = true
        }
        if (!finished && text.length - checked >= checkEvery) {
          checked = text.length
          const found = loopAtEnd(text.slice(-24000), true)
          if (found) return finish(controller, found)
        }
        controller.enqueue(encoder.encode(events))
        return
      }
    },
    cancel(reason) {
      stopped = true
      return reader.cancel(reason)
    },
  })
}

// ---------- 22. « continue » after a run that stopped ----------
// A short message that asks to go on: the command of the run resumes, with its agent, instead of the agent the web
// interface selected (it switches the session to it with every message, so « continue » after /go went to build,
// which carried on with none of the rules of the pilot)
const CONTINUE = /^(?:(?:ok|oui|bon|alors|allez|stp|svp|please|yes)[\s,.!]+)*(?:continue[sz]?|continuer|continu|on continue|reprends?|reprise|reprendre|poursuis|poursuivre|vas[- ]?y|go|la suite|suite|relance|termine|finis|keep going|resume|carry on)(?:[\s,.!]+(?:stp|svp|please|merci|thanks))*[\s.!]*$/i
export const isContinue = (text) => CONTINUE.test(String(text || "").trim())

// ---------- 23. dotnet run: a project of the repository only ----------
// The free conversation may run a project of the repository (a POC, the tests of a Microsoft.Testing.Platform project),
// never a project made for the occasion (a probe or reflection program that dumps an assembly) nor a C# file run as
// a program (`dotnet run Probe.cs`, .NET 10): the project must be in the last commit. Returns "" when the command
// runs no project, or { project, ok }.
export function dotnetRunTarget(command, cwd, root) {
  for (const words of commandWords(String(command || ""))) {
    let i = words.findIndex((word, k) => word === "dotnet" && words[k + 1] === "run")
    if (i < 0) continue
    let project = ""
    let file = ""
    for (i += 2; i < words.length && words[i] !== "--"; i++) {
      const word = words[i]
      if (word === "--project" || word === "-p") project = words[++i] || ""
      else if (word.startsWith("--project=")) project = word.slice(10)
      else if (/\.cs$/i.test(word)) file = word
    }
    if (file) return { project: file, ok: false }
    const target = resolve(cwd, project || ".")
    let csproj = target
    try {
      if (statSync(target).isDirectory()) {
        const found = execFileSync("git", ["ls-files", "--", "*.csproj", "*.fsproj"], { cwd: target, encoding: "utf8", timeout: 5000 })
          .split("\n").filter((line) => line && !line.includes("/"))
        csproj = found.length === 1 ? join(target, found[0]) : join(target, found[0] || "?.csproj")
      }
    } catch {
      return { project: project || ".", ok: false }
    }
    if (!within(csproj, root)) return { project: project || ".", ok: false }
    try {
      execFileSync("git", ["cat-file", "-e", "HEAD:" + csproj.slice(root.length + 1).split(sep).join("/")], { cwd: root, timeout: 5000, stdio: "ignore" })
      return { project: project || ".", ok: true }
    } catch {
      return { project: project || ".", ok: false }
    }
  }
  return ""
}

// ---------- 24. commands that never end by themselves ----------
// The name of a package script that starts a server or a watch ("start", "dev", "serve", "watch", "preview", "develop",
// "start:prod", "dev:ssr", "build:watch", "api:serve", "api-start"). A name that only ends in ":dev" or "-dev"
// ("build:dev") is decided by its script.
const SERVER_SCRIPT = /^(?:start|dev|develop|serve|watch|preview)(?:[:-][\w:.-]*)?$|^[\w.-]*[:-](?:watch|serve|start)$/
// The options that make a test command run once
const SINGLE_RUN = /^(?:--watch=false|--no-watch|--watchAll=false|--watch-all=false|--run|--single-run|--singleRun|--single-run=true|--singleRun=true)$/
// The tools whose -w is their watch mode (elsewhere -w is a word match, a word count or a workspace)
const W_WATCH = new Set(["kubectl", "tsc", "rollup", "webpack", "babel", "tailwindcss", "postcss", "sass", "vite", "esbuild", "tsup", "swc", "mocha", "nodemon", "less-watch-compiler"])
// The commands of yarn and pnpm that are not the name of a script
const PM_COMMANDS = new Set(["install", "i", "add", "remove", "rm", "uninstall", "un", "ci", "exec", "dlx", "why", "list", "ls", "outdated",
  "audit", "info", "view", "pack", "publish", "version", "versions", "config", "cache", "init", "create", "link", "unlink", "upgrade", "up",
  "update", "rebuild", "prune", "dedupe", "store", "import", "patch", "patch-commit", "licenses", "env", "bin", "root", "fetch", "setup",
  "help", "login", "logout", "whoami", "set", "node", "workspaces", "constraints", "plugin", "explain", "unplug", "stage", "search",
  "owner", "doctor", "check", "global", "generate-lock-entry", "policies", "tag", "team", "upgrade-interactive", "deploy"])
// The project of `dotnet run` is an application that serves until it is stopped: a web, worker or Blazor WebAssembly
// project, or an Aspire AppHost
function serverProject(words, cwd) {
  let project = ""
  for (let i = 0; i < words.length && words[i] !== "--"; i++) {
    if (words[i] === "--project" || words[i] === "-p") project = words[++i] || ""
    else if (words[i].startsWith("--project=")) project = words[i].slice(10)
  }
  try {
    let file = resolve(cwd, project || ".")
    if (statSync(file).isDirectory()) {
      const found = readdirSync(file).filter((name) => /\.csproj$/i.test(name))
      if (found.length !== 1) return false
      file = join(file, found[0])
    }
    const text = readFileSync(file, "utf8")
    return /Sdk="Microsoft\.NET\.Sdk\.(?:Web|Worker|BlazorWebAssembly)"/i.test(text) || /Aspire\.AppHost\.Sdk|<IsAspireHost>\s*true/i.test(text)
  } catch {
    return false
  }
}
// The package.json a package manager reads: the one of the folder, otherwise of a parent folder up to the repository
const readPackage = (dir, root) => {
  for (let d = dir; ; d = dirname(d)) {
    try {
      const json = JSON.parse(readFileSync(join(d, "package.json"), "utf8"))
      return { dir: d, scripts: json && typeof json.scripts === "object" && json.scripts ? json.scripts : {} }
    } catch {
      // not here
    }
    if (!root || d === root || dirname(d) === d || !within(d, root)) return null
  }
}
const shellWord = (word) => (/^[\w@%+=:,./-]+$/.test(word) ? word : "'" + word.replace(/'/g, "'\\''") + "'")
// The script a package manager runs (npm test, npm run build, yarn dev, pnpm --filter web serve), as
// { label, script, passed, dir }, or null. passed: the words the script gets (npm: its positional words and those
// after --, its options before -- being settings of npm itself; yarn and pnpm: every word after the name of the script).
function packageScript(cmd, rest, cwd) {
  let dir = cwd
  const dash = rest.indexOf("--")
  const end = dash < 0 ? rest.length : dash
  const named = []
  let need = 0
  let at = -1
  for (let i = 0; i < end; i++) {
    if (at >= 0 && cmd !== "npm") break
    const word = rest[i]
    const option = /^(--prefix|--dir|--cwd|-C)(?:=(.*))?$/.exec(word)
    if (option) {
      const value = option[2] !== undefined ? option[2] : rest[++i]
      if (value) dir = resolve(cwd, value)
      continue
    }
    if (/^(?:--workspace|-w|--filter|-F)$/.test(word)) {
      i++
      continue
    }
    if (word.startsWith("-")) continue
    named.push(i)
    if (named.length === 1) need = (cmd === "npm" ? /^(?:run|run-script|rum|urn)$/.test(word) : word === "run") ? 2 : cmd !== "npm" && word === "workspace" ? 3 : 1
    if (at < 0 && named.length === need) at = i
  }
  if (at < 0) return null
  const first = rest[named[0]]
  let script = ""
  if (cmd === "npm") {
    if (need === 2) script = rest[named[1]]
    // npm cit (install-ci-test): npm ci, then the test script
    else if (["test", "t", "tst", "cit", "clean-install-test", "sit", "install-ci-test"].includes(first)) script = "test"
    else if (first === "start" || first === "restart") script = "start"
    else return null
  } else if (need === 2) script = rest[named[1]]
  else if (need === 3) {
    script = rest[named[2]]
    dir = ""
  } else if (PM_COMMANDS.has(first)) return null
  else script = first
  if (!script) return null
  const passed = cmd === "npm"
    ? [...named.filter((k) => k > at).map((k) => rest[k]), ...(dash < 0 ? [] : rest.slice(dash + 1))]
    : rest.slice(at + 1).filter((word) => word !== "--")
  return { label: [cmd, ...named.slice(0, need).map((k) => rest[k])].join(" "), script, passed, dir }
}
// What never ends in a shell command, as { what, log, bounded } (log: what without the scripts of package.json, which
// may hold a credential; bounded: the seconds of a `timeout` before it), or "".
// cwd: the folder of the command (a cd in the command moves it); root: the repository (a package.json is looked for up
// to it); ci: CI is set for it (CI=true npm test: Create React App runs once).
// What runs a command, taken off its words: VAR=value, env, nohup, setsid, time, nice, exec, command, sudo, cross-env,
// timeout, npx and the exec commands of the package managers, corepack before one of them; a package manager run in a
// version of its own (npx npm@11) by its name. As { words, bounded, ci }: bounded, the seconds of a `timeout` before
// it; ci, CI set for it (CI=true npm test: Create React App runs once).
function unwrap(all, inCi = false) {
  let words = all.slice()
  let bounded = 0
  let ci = inCi
  for (let guard = 0; guard < 12 && words.length; guard++) {
    const [w0, w1] = words
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(w0)) {
      if (/^CI=(?!$|0$|false$)/i.test(w0)) ci = true
      words = words.slice(1)
    } else if (w0 === "env" || w0 === "cross-env" || w0 === "cross-env-shell") {
      words = words.slice(1)
      while (words[0] && words[0].startsWith("-")) words = words.slice(1)
    } else if (["nohup", "setsid", "time", "exec", "command", "builtin", "stdbuf", "unbuffer", "nice", "ionice"].includes(w0)) {
      words = words.slice(1)
      while (words[0] && words[0].startsWith("-")) words = words.slice(/^-[nc]$/.test(words[0]) ? 2 : 1)
    } else if (w0 === "sudo" || w0 === "doas") {
      words = words.slice(1)
      while (words[0] && words[0].startsWith("-")) words = words.slice(/^-[ugpCDhrt]$/.test(words[0]) ? 2 : 1)
    } else if (w0 === "timeout") {
      let i = 1
      while (i < words.length && words[i].startsWith("-")) i += /^(?:-k|-s|--kill-after|--signal)$/.test(words[i]) ? 2 : 1
      const time = /^(\d+(?:\.\d+)?)([smhd])?$/.exec(words[i] || "")
      if (!time) {
        words = []
        break
      }
      const seconds = Number(time[1]) * { s: 1, m: 60, h: 3600, d: 86400 }[time[2] || "s"]
      bounded = bounded ? Math.min(bounded, seconds) : seconds
      words = words.slice(i + 1)
    } else if (w0 === "npx" || w0 === "pnpx" || w0 === "bunx" || ((w0 === "pnpm" || w0 === "yarn" || w0 === "npm") && (w1 === "exec" || w1 === "dlx"))) {
      words = words.slice(w0 === "npx" || w0 === "pnpx" || w0 === "bunx" ? 1 : 2)
      while (words[0] && words[0].startsWith("-")) words = words.slice(/^(?:-p|--package)$/.test(words[0]) ? 2 : 1)
    } else if (w0 === "corepack" && /^(?:npm|yarn|pnpm)(?:@|$)/.test(w1 || "")) {
      words = words.slice(1)
    } else break
  }
  if (words[0] && /^(?:npm|yarn|pnpm)@/.test(words[0])) words = [words[0].replace(/@.*$/, ""), ...words.slice(1)]
  return { words, bounded, ci }
}
export function neverEnding(command, cwd = process.cwd(), root = "", depth = 0, inCi = false) {
  let here = cwd
  for (const all of commandWords(String(command || ""))) {
    if (all.after === ">" || all.after === "<") continue
    if ((all[0] === "cd" || all[0] === "pushd") && all.length <= 2) {
      here = all[1] && all[1] !== "-" ? resolve(here, all[1].replace(/^~(?=\/|$)/, HOME)) : HOME
      continue
    }
    // what runs the command (VAR=value, env, nohup, timeout, npx…) is taken off
    const { words, bounded, ci } = unwrap(all, inCi)
    const [cmd, ...rest] = words
    if (!cmd) continue
    const flag = (name) => rest.includes(name)
    const once = rest.some((word, k) => SINGLE_RUN.test(word) || (word === "--watch" && rest[k + 1] === "false"))
    let what = ""
    let log = ""
    let inner = null
    if (/^(?:sh|bash|dash|zsh)$/.test(cmd) && rest[0] === "-c" && depth < 3) inner = neverEnding(rest[1], here, root, depth + 1, ci)
    else if (cmd === "npm" || cmd === "yarn" || cmd === "pnpm") {
      const run = packageScript(cmd, rest, here)
      if (run) {
        const pkg = run.dir ? readPackage(run.dir, root) : null
        const body = pkg && typeof pkg.scripts[run.script] === "string" ? pkg.scripts[run.script] : null
        if (SERVER_SCRIPT.test(run.script)) what = run.label
        else if (body !== null && depth < 3) {
          const found = neverEnding(body + (run.passed.length ? " " + run.passed.map(shellWord).join(" ") : ""), pkg.dir, root, depth + 1, ci)
          if (found) {
            const short = body.length > 60 ? body.slice(0, 57) + "..." : body
            log = run.label + " (its script: " + (found.log || found.what) + ")"
            what = run.label + " (its script \"" + short + "\": " + found.what + ")" +
              (cmd === "npm" && rest.some((word) => SINGLE_RUN.test(word)) && !run.passed.some((word) => SINGLE_RUN.test(word)) ? "; npm passes to the script only the options after --: npm " + (run.script === "test" ? "test" : "run " + run.script) + " -- <option>" : "")
          }
        } else if (body === null && run.passed.some((word, k) => /^--watch(?:All)?(?:=true)?$/.test(word) && run.passed[k + 1] !== "false")) what = run.label + " with a watch option"
      }
    } else if (cmd === "concurrently" || cmd === "run-p" || cmd === "run-s" || cmd === "npm-run-all") {
      // what they start together: a server or a watch among them never ends
      for (const word of rest.filter((w) => !w.startsWith("-"))) {
        const name = word.replace(/^npm:/, "")
        if (/^(?:start|dev|develop|serve|watch|preview)\b|[:-](?:watch|serve|start|dev)\b/.test(name)) what = cmd + " " + word
        else if (/\s/.test(word) && depth < 3) {
          const found = neverEnding(word, here, root, depth + 1, ci)
          if (found) {
            what = cmd + " \"" + word + "\" (" + found.what + ")"
            log = cmd + " (" + (found.log || found.what) + ")"
          }
        }
        if (what) break
      }
    } else if (rest.some((word, k) => (/^--watch(?:All)?(?:=true)?$/.test(word) && rest[k + 1] !== "false") || (W_WATCH.has(cmd) && word === "-w"))) what = cmd + " with a watch option"
    else if (cmd === "ng" && (rest[0] === "serve" || rest[0] === "s" || (rest[0] === "run" && /:serve/.test(rest[1] || "")))) what = "ng serve"
    else if (cmd === "ng" && (rest[0] === "test" || rest[0] === "t" || (rest[0] === "run" && /:test(?::|$)/.test(rest[1] || ""))) && !once) what = "ng test without --watch=false"
    else if (["react-scripts", "craco", "rescripts", "react-app-rewired"].includes(cmd) && rest[0] === "test" && !ci && !flag("--watchAll=false")) what = cmd + " test without --watchAll=false (Create React App watches by default)"
    else if (["react-scripts", "craco", "rescripts", "react-app-rewired"].includes(cmd) && rest[0] === "start") what = cmd + " start"
    else if (cmd === "vitest" && (rest[0] === "watch" || rest[0] === "dev" || flag("--ui"))) what = "vitest " + (flag("--ui") ? "--ui" : rest[0])
    else if (cmd === "karma" && rest[0] === "start" && !once) what = "karma start without --single-run"
    else if (cmd === "playwright" && (flag("--ui") || rest[0] === "show-report" || rest[0] === "codegen")) what = "playwright " + (flag("--ui") ? "test --ui" : rest[0])
    else if (cmd === "cypress" && rest[0] === "open") what = "cypress open"
    else if (cmd === "vite" && !["build", "optimize"].includes(rest[0])) what = "vite (a development server)"
    else if (cmd === "webpack" && rest[0] === "serve") what = "webpack serve"
    else if ((cmd === "next" && ["dev", "start"].includes(rest[0])) || ((cmd === "nuxt" || cmd === "nuxi") && ["dev", "preview", "start"].includes(rest[0])) ||
      (cmd === "astro" && ["dev", "preview"].includes(rest[0])) || (cmd === "remix" && rest[0] === "dev") || (cmd === "gatsby" && ["develop", "serve"].includes(rest[0])) ||
      (cmd === "vue-cli-service" && rest[0] === "serve") || (cmd === "storybook" && rest[0] === "dev") || (cmd === "swa" && rest[0] === "start") ||
      (cmd === "parcel" && !["build"].includes(rest[0])) || (cmd === "esbuild" && rest.some((word) => /^--serve(?:=|$)/.test(word))) || (cmd === "php" && flag("-S"))) what = cmd + (rest[0] && !rest[0].startsWith("-") ? " " + rest[0] : "")
    else if (["webpack-dev-server", "nodemon", "ts-node-dev", "live-server", "http-server", "json-server", "lite-server", "browser-sync", "serve", "start-storybook", "azurite", "ngrok", "watch"].includes(cmd)) what = cmd
    else if (cmd === "dotnet" && rest[0] === "watch") what = "dotnet watch"
    else if (cmd === "dotnet" && rest[0] === "run" && serverProject(rest.slice(1), here)) what = "dotnet run of a web, worker or Aspire project"
    else if (cmd === "func" && (rest[0] === "start" || (rest[0] === "host" && rest[1] === "start"))) what = "func start"
    else if ((cmd === "tail" || cmd === "journalctl") && rest.some((word) => /^-[A-Za-z]*[fF]/.test(word) || word === "--follow")) what = cmd + " -f"
    else if ((cmd === "docker" || cmd === "kubectl" || cmd === "docker-compose") && rest.some((word) => word === "-f" || word === "--follow") && rest.includes("logs")) what = cmd + " logs -f"
    else if (cmd === "kubectl" && rest[0] === "port-forward") what = "kubectl port-forward"
    else if (((cmd === "docker" && rest[0] === "compose" && rest[1] === "up") || (cmd === "docker-compose" && rest[0] === "up")) && !flag("-d") && !flag("--detach")) what = "docker compose up"
    else if (/^python3?$/.test(cmd) && rest[0] === "-m" && rest[1] === "http.server") what = "python -m http.server"
    else if (cmd === "ping" && !rest.some((word) => /^-[A-Za-z]*[cw]/.test(word))) what = "ping without -c"
    if (inner) return { what: inner.what, log: inner.log || inner.what, bounded: bounded ? (inner.bounded ? Math.min(bounded, inner.bounded) : bounded) : inner.bounded }
    if (what) return { what, log: log || what, bounded }
  }
  return ""
}

// ---------- 25. a change of the dependencies, an install on the machine ----------
// npm's commands (and their aliases) that add, remove, upgrade or link a package, or resolve the tree again and rewrite
// package-lock.json: every install but `npm ci`, which installs the lockfile as it is
const NPM_CHANGES = new Set(["install", "i", "in", "ins", "inst", "insta", "instal", "isnt", "isnta", "isntal", "isntall", "add",
  "install-test", "it", "uninstall", "unlink", "remove", "rm", "r", "un", "update", "up", "upgrade", "udpate", "dedupe", "ddp",
  "link", "ln", "prune"])
// yarn's and pnpm's; their plain install (`yarn`, `yarn install`, `pnpm install`) without its frozen option too
const PM_CHANGES = new Set(["add", "remove", "rm", "uninstall", "un", "update", "up", "upgrade", "upgrade-interactive", "dedupe",
  "link", "unlink", "import", "patch-commit", "global"])
const FROZEN = /^(?:--frozen-lockfile(?:=true)?|--immutable)$/
const GLOBAL = /^(?:-g|--global|--location=global)$/
// The tools of the machine: an agent never installs or changes one (a missing one is an ENVIRONMENT PROBLEM)
const MACHINE_INSTALLS = {
  brew: ["install", "reinstall", "upgrade", "uninstall", "remove", "rm", "link", "tap"],
  "apt-get": ["install", "reinstall", "upgrade", "dist-upgrade", "remove", "purge"],
  apt: ["install", "reinstall", "upgrade", "full-upgrade", "remove", "purge"],
  pip: ["install", "uninstall"], pip3: ["install", "uninstall"], pipx: ["install", "upgrade", "uninstall"],
  gem: ["install", "update", "uninstall"], corepack: ["enable", "disable", "prepare", "install", "use", "up"],
  nvm: ["install", "uninstall", "alias"], fnm: ["install", "uninstall", "default"], volta: ["install", "pin", "uninstall"],
  sdk: ["install", "uninstall", "default"],
}
// The command of a package manager after its options (npm --prefix web install: install), as { name, at }, or null
function pmSubcommand(rest) {
  for (let i = 0; i < rest.length; i++) {
    const word = rest[i]
    if (word === "--") return null
    if (/^(?:--prefix|--dir|--cwd|-C|--workspace|-w|--filter|-F)$/.test(word)) {
      i++
      continue
    }
    if (word.startsWith("-")) continue
    return { name: word, at: i }
  }
  return null
}
// What changes the dependencies of the repository, or a tool of the machine, in a shell command, as
// { what, log, machine }, or "": every install of npm but `npm ci`, the add, remove and upgrade commands of npm, yarn
// and pnpm, their install without the frozen lockfile (also through npx npm@11, corepack, sh -c or a script of
// package.json), `dotnet add package`, `dotnet package add` (.NET 10), `dotnet tool install`; a global install, brew,
// apt, pip, corepack enable, nvm install. log: what without the scripts of package.json (they may hold a credential).
export function dependencyChange(command, cwd = process.cwd(), root = "", depth = 0) {
  let here = cwd
  for (const all of commandWords(String(command || ""))) {
    if (all.after === ">" || all.after === "<") continue
    if ((all[0] === "cd" || all[0] === "pushd") && all.length <= 2) {
      here = all[1] && all[1] !== "-" ? resolve(here, all[1].replace(/^~(?=\/|$)/, HOME)) : HOME
      continue
    }
    const [cmd, ...rest] = unwrap(all).words
    if (!cmd) continue
    if (/^(?:sh|bash|dash|zsh)$/.test(cmd) && rest[0] === "-c") {
      const inner = depth < 3 ? dependencyChange(rest[1], here, root, depth + 1) : ""
      if (inner) return inner
      continue
    }
    let what = ""
    let log = ""
    let machine = false
    if (cmd === "npm" || cmd === "yarn" || cmd === "pnpm") {
      const sub = pmSubcommand(rest)
      const name = sub ? sub.name : ""
      const after = sub ? rest.slice(sub.at + 1) : []
      const frozen = rest.some((word) => FROZEN.test(word))
      const info = rest.some((word) => /^(?:-v|--version|-h|--help)$/.test(word))
      machine = rest.some((word) => GLOBAL.test(word)) || (cmd === "yarn" && name === "global")
      if (cmd === "npm" && NPM_CHANGES.has(name)) what = "npm " + name
      else if (cmd === "npm" && name === "audit" && after.includes("fix")) what = "npm audit fix"
      else if (cmd === "npm" && name === "pkg" && ["set", "delete", "fix"].includes(after[0])) what = "npm pkg " + after[0]
      else if (cmd !== "npm" && PM_CHANGES.has(name)) what = cmd + " " + name
      else if (cmd === "yarn" && name === "workspace" && PM_CHANGES.has((pmSubcommand(after.slice(1)) || {}).name)) what = "yarn workspace " + after[0] + " " + pmSubcommand(after.slice(1)).name
      else if (cmd === "yarn" && (name === "install" || (name === "" && !info)) && !frozen) what = "yarn" + (name ? " install" : "") + " without --frozen-lockfile"
      else if (cmd === "pnpm" && (name === "install" || name === "i") && !frozen) what = "pnpm " + name + " without --frozen-lockfile"
      else if (depth < 3) {
        // a script of package.json: what it runs
        const run = packageScript(cmd, rest, here)
        const pkg = run && run.dir ? readPackage(run.dir, root) : null
        const body = pkg && typeof pkg.scripts[run.script] === "string" ? pkg.scripts[run.script] : null
        const found = body !== null ? dependencyChange(body, pkg.dir, root, depth + 1) : ""
        if (found) {
          what = run.label + " (its script runs " + found.what + ")"
          log = run.label + " (its script: " + found.log + ")"
          machine = found.machine
        }
      }
    } else if (cmd === "dotnet") {
      if ((rest[0] === "add" || rest[0] === "remove") && (rest[1] === "package" || rest[2] === "package")) what = "dotnet " + rest[0] + " package"
      else if (rest[0] === "package" && ["add", "remove", "update"].includes(rest[1])) what = "dotnet package " + rest[1]
      else if (rest[0] === "tool" && ["install", "update", "uninstall"].includes(rest[1])) {
        what = "dotnet tool " + rest[1]
        machine = rest.some((word) => word === "-g" || word === "--global" || word === "--tool-path")
      }
    } else if (Object.hasOwn(MACHINE_INSTALLS, cmd)) {
      const sub = pmSubcommand(rest)
      if (sub && MACHINE_INSTALLS[cmd].includes(sub.name)) {
        what = cmd + " " + sub.name
        machine = true
      }
    }
    if (what) return { what, log: log || what, machine }
  }
  return ""
}

export default Plugin.define({
  id: "openrd-pack",
  setup: async (ctx) => {
    const options = (ctx && ctx.options) || {}
    const tickMs = Number(options.tickMs) > 0 ? Number(options.tickMs) : TICK_MS
    const nudgeMs = Math.min(NUDGE_MS, tickMs)
    const mcpWaitMs = Number(options.mcpWaitMs) >= 0 ? Number(options.mcpWaitMs) : MCP_WAIT_MS
    const mcpBootMs = Number(options.mcpBootMs) >= 0 ? Number(options.mcpBootMs) : MCP_BOOT_MS
    const mcpCallMs = Number(options.mcpCallMs) > 0 ? Number(options.mcpCallMs) : MCP_CALL_MS
    const adoptMs = Number(options.adoptMs) > 0 ? Number(options.adoptMs) : ADOPT_MS
    const resumeFailureMs = Array.isArray(options.resumeFailureMs) ? options.resumeFailureMs.map(Number) : RESUME_AFTER_FAILURE_MS
    const resumeUnfinishedMs = Number(options.resumeUnfinishedMs) >= 0 ? Number(options.resumeUnfinishedMs) : RESUME_AFTER_UNFINISHED_MS
    const patienceMs = Array.isArray(options.patienceMs) ? options.patienceMs.map(Number) : PATIENCE_MS
    // 29. the clock of the measures (a test gives its own)
    const clockNow = typeof options.now === "function" ? () => Number(options.now()) : () => Date.now()
    const directory = String((ctx && ctx.location && ctx.location.directory) || process.cwd())
    const git = (args, cwd) => {
      try {
        return execFileSync("git", args, { cwd, encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] }).trim()
      } catch {
        return ""
      }
    }
    // the git root of the folder (a folder outside git: the folder itself), and its git folder (per worktree)
    const worktree = git(["rev-parse", "--show-toplevel"], directory) || directory
    const gitDir = git(["rev-parse", "--absolute-git-dir"], worktree)
    // 15. the folder of a worktree at the start of the titles of its sessions ("" in the main checkout)
    const real = (path) => {
      try {
        return realpathSync(path)
      } catch {
        return resolve(path)
      }
    }
    const commonDir = gitDir ? git(["rev-parse", "--git-common-dir"], worktree) : ""
    const TAG = gitDir && commonDir && real(gitDir) !== real(resolve(worktree, commonDir)) ? "[" + basename(worktree) + "] " : ""
    const tagged = (title) => {
      if (!TAG || !title || PROGRESS.test(title)) return title
      const mark = (OUTCOME.exec(title) || [""])[0]
      const rest = title.slice(mark.length)
      return !rest || DEFAULT_TITLE.test(rest) || rest.startsWith(TAG) ? title : mark + TAG + rest
    }
    const api = (ctx && ctx.session) || {}
    const log = (message, extra) => {
      const line = "[openrd-pack] " + message + (extra ? " " + JSON.stringify(extra) : "")
      console.error(line)
      writeLog(line)
    }
    const sessionInfo = async (sessionID) => {
      try {
        return typeof api.get === "function" ? await api.get({ sessionID }) : undefined
      } catch {
        return undefined
      }
    }
    const rename = async (sessionID, title) => {
      if (typeof api.update === "function") await api.update({ sessionID, title })
    }
    const guards = await Guards({
      directory,
      worktree,
      client: {
        app: { log: async ({ body }) => log(body.message, body.extra || {}) },
        config: { get: async () => ({ data: { references: configuration().references } }) },
        session: { get: async ({ path }) => ({ data: await sessionInfo(path.id) }) },
      },
    })
    const pruning = configuration().prune

    // 14. 1.19 waited for the MCP servers before the first request to the model; v2 sends it with the tools of the
    // servers connected at that moment, and Jira or GitLab missing from the first step of a /go stops it. A prompt of
    // the first minutes of this instance waits for the servers still connecting (30 s at most).
    const booted = Date.now()
    const pause = (ms) => new Promise((done) => setTimeout(done, ms))
    const mcpReady = async () => {
      try {
        if (Date.now() - booted > mcpBootMs || !ctx.mcp || typeof ctx.mcp.list !== "function") return
        const end = Date.now() + mcpWaitMs
        let waited = false
        while (Date.now() < end) {
          const result = await ctx.mcp.list()
          const servers = Array.isArray(result) ? result : result && result.data
          if (!Array.isArray(servers) || !servers.some((server) => server && server.status && server.status.status === "pending")) break
          waited = true
          await pause(250)
        }
        // the tools of a server that has just connected reach the tool list 100 ms later
        if (waited) await pause(500)
      } catch {
        // the prompt goes on
      }
    }

    // the sessions of this folder (their prompts or tools went through this instance), and their subagent sessions
    const mine = new Set()
    const parents = new Map()
    const subagentSessions = new Set()
    // session id -> the command of the pack its current turn runs: { command, args, pilot }
    const commandRuns = new Map()
    // 9. the pilot runs of this folder: session id -> { command, since }; the sessions whose run was refused
    const runningPilots = new Map()
    const refusedRuns = new Set()
    // 4. session id -> the command chosen in its last multiple-choice question; the sessions where the plugin starts
    // it (the options are written by the model: their arguments never name a folder, 7)
    const chosen = new Map()
    const chained = new Set()
    // 16. session id -> { message, calls: signature -> count } of the answer of the model being run
    const loops = new Map()
    const looping = (event) => {
      if (!event.sessionID || !event.messageID) return false
      let entry = loops.get(event.sessionID)
      if (!entry || entry.message !== event.messageID) {
        loops.delete(event.sessionID)
        // the sessions of the last answers only
        if (loops.size >= 200) loops.delete(loops.keys().next().value)
        entry = { message: event.messageID, calls: new Map() }
        loops.set(event.sessionID, entry)
      }
      let signature
      try {
        signature = event.tool + "\u0000" + JSON.stringify(event.input === undefined ? null : event.input)
      } catch {
        return false
      }
      const count = (entry.calls.get(signature) || 0) + 1
      entry.calls.set(signature, count)
      return count >= LOOP_CALLS
    }
    // 5. session id -> progress of its current turn; subagent session -> { phase, attempt, at, last }
    const runs = new Map()
    const subagents = new Map()
    // 17. session id -> the instructions of the pilot command it runs { command, args, text }; subagent session id ->
    // its task (the first prompt of the pilot, then the last ones that took it up again)
    const procedures = new Map()
    const tasks = new Map()
    const remember = (map, key, value) => {
      map.delete(key)
      map.set(key, value)
      if (map.size > REMEMBERED_SESSIONS) map.delete(map.keys().next().value)
    }
    // 19. session id -> automatic resumes in a row; session id -> the timer of the resume that waits
    const resumes = new Map()
    const resumeTimers = new Map()
    // 19. the sessions whose last request was the one OpenCode sends at the step limit of the agent (tools disabled)
    const stepLimited = new Set()
    // 21. session id -> { count } of its answers cut because they repeated themselves, until an answer ends normally;
    // the sessions whose history had a loop taken out (logged once)
    const loopCuts = new Map()
    const loopLogged = new Set()
    // tool call id -> tool name (the v2 events give it once); session id -> the texts of its last answer (10)
    const toolNames = new Map()
    const answers = new Map()
    // 4. session id -> the outcome mark of the last text of its turn that has one (the final answer of a run, before
    // its « Suite » question); session id -> that mark, once the « Suite » question of the run is asked
    const lastMarks = new Map()
    const suites = new Map()
    let ticker

    // ---------- 9. the lock of the folder, in this process and in the git folder for the other ones ----------
    const lockFile = gitDir ? join(gitDir, LOCK_FILE_NAME) : ""
    const readLock = () => {
      try {
        return JSON.parse(readFileSync(lockFile, "utf8"))
      } catch {
        return undefined
      }
    }
    // a lock of a running OpenCode of this machine (or of another machine, until it is 4 hours old)
    const held = (lock) => {
      if (!lock || typeof lock.since !== "number" || Date.now() - lock.since > LOCK_MS) return false
      if (lock.host !== hostname()) return true
      try {
        process.kill(lock.pid, 0)
        return true
      } catch (error) {
        return !!error && error.code === "EPERM"
      }
    }
    const writeLock = (sessionID, command, since, args = "") => {
      if (!lockFile) return true
      const data = JSON.stringify({ session: sessionID, command, args, since, pid: process.pid, host: hostname() })
      for (let attempt = 0; attempt < 2; attempt++) {
        try {
          const fd = openSync(lockFile, "wx", 0o600)
          writeSync(fd, data)
          closeSync(fd)
          return true
        } catch (error) {
          if (!error || error.code !== "EEXIST") return true
          const lock = readLock()
          if (lock && lock.session === sessionID && lock.pid === process.pid) {
            try {
              writeFileSync(lockFile, data)
            } catch {
              // the lock stays as it is
            }
            return true
          }
          if (held(lock)) return false
          try {
            unlinkSync(lockFile)
          } catch {
            // another process took it meanwhile
          }
        }
      }
      return false
    }
    // the run that holds the folder, or undefined when this session may run
    const acquire = (sessionID, command, args) => {
      const now = Date.now()
      for (const [id, item] of runningPilots) if (now - item.since > LOCK_MS) runningPilots.delete(id)
      const other = [...runningPilots.entries()].find(([id]) => id !== sessionID)
      if (other) return other[1]
      if (!writeLock(sessionID, command, now, args)) {
        const lock = readLock() || {}
        return { command: "/" + (lock.command || "go"), since: lock.since || now, elsewhere: true }
      }
      runningPilots.set(sessionID, { command: "/" + command, since: now })
      return undefined
    }
    const release = (sessionID) => {
      runningPilots.delete(sessionID)
      refusedRuns.delete(sessionID)
      if (adopted && adopted.session === sessionID) adopted = undefined
      if (!lockFile) return
      const lock = readLock()
      if (lock && lock.session === sessionID && lock.pid === process.pid) {
        try {
          unlinkSync(lockFile)
        } catch {
          // already gone
        }
      }
    }
    // OpenCode run as its background service resumes, at its start, the turns that a restart interrupted ("The server
    // restarted while you were working…"), without a prompt the plugin sees: the run of a lock left by the stopped
    // process goes on. The plugin takes that lock over until the turn ends, or frees it when the run does not start
    // again within 2 minutes. OpenCode run with "serve" resumes nothing: its stale locks stay ignored.
    let adopted
    const adoptLock = (service) => {
      try {
        if (!lockFile || !service) return
        const lock = readLock()
        if (!lock || typeof lock.since !== "number" || Date.now() - lock.since > LOCK_MS) return
        if (lock.host !== hostname() || lock.pid === process.pid || held(lock)) return
        if (typeof lock.session !== "string" || !lock.session || !PILOT_COMMANDS.has(lock.command)) return
        const args = typeof lock.args === "string" ? lock.args : ""
        unlinkSync(lockFile)
        if (!writeLock(lock.session, lock.command, lock.since, args)) return
        runningPilots.set(lock.session, { command: "/" + lock.command, since: lock.since })
        commandRuns.set(lock.session, { command: lock.command, args, pilot: true })
        mine.add(lock.session)
        adopted = { session: lock.session, started: false }
        const timer = setTimeout(() => {
          if (adopted && adopted.session === lock.session && !adopted.started) {
            commandRuns.delete(lock.session)
            release(lock.session)
            log("freed the folder: the interrupted run did not start again", { command: "/" + lock.command })
          }
        }, adoptMs)
        if (timer && typeof timer.unref === "function") timer.unref()
        log("kept the folder for a run resumed after a restart", { command: "/" + lock.command })
      } catch {
        // the lock stays as it is: ignored, as any lock of a stopped OpenCode
      }
    }

    // A subagent's session: its first prompt says so, or OpenCode gives it a parent (a subagent taken up again by the
    // pilot gets a prompt without the first line)
    const topLevel = new Set()
    const isSubagent = async (sessionID, text) => {
      if (!sessionID) return false
      if (subagentSessions.has(sessionID) || parents.has(sessionID)) return true
      if (typeof text === "string" && text.startsWith(SUBAGENT_PROMPT)) {
        subagentSessions.add(sessionID)
        return true
      }
      if (topLevel.has(sessionID)) return false
      const info = await sessionInfo(sessionID)
      if (info && info.parentID) {
        parents.set(sessionID, info.parentID)
        subagentSessions.add(sessionID)
        return true
      }
      if (info) topLevel.add(sessionID)
      return false
    }

    // ---------- 5. progress in the session title ----------
    function track(sessionID, phase) {
      if (!sessionID || parents.has(sessionID) || subagentSessions.has(sessionID)) return undefined
      let state = runs.get(sessionID)
      if (!state) {
        const now = Date.now()
        // running: tool call id -> { text, child } of each tool that runs (several at once: 5)
        state = { start: now, last: now, chars: 0, phase: "waiting", tool: "", attempt: 0, running: new Map() }
        runs.set(sessionID, state)
        if (!ticker) {
          ticker = setInterval(() => {
            if (runs.size === 0) {
              clearInterval(ticker)
              ticker = undefined
              return
            }
            for (const [id, item] of runs) void show(id, item)
          }, tickMs)
          if (ticker && typeof ticker.unref === "function") ticker.unref()
        }
      }
      if (phase) state.phase = phase
      return state
    }

    // A change worth showing now (tools that start or end, a retry, a summary): the title within a second, once for
    // the changes of that second, instead of at the next tick
    function nudge(sessionID, state) {
      if (!state || state.nudged || state.done) return
      state.nudged = setTimeout(() => {
        state.nudged = undefined
        void show(sessionID, state)
      }, nudgeMs)
      if (state.nudged && typeof state.nudged.unref === "function") state.nudged.unref()
    }

    async function show(sessionID, state) {
      if (!state || state.writing || state.done) return
      state.writing = true
      try {
        const info = await sessionInfo(sessionID)
        if (!info) return
        if (info.parentID) {
          parents.set(sessionID, info.parentID)
          runs.delete(sessionID)
          return
        }
        const current = info.title || ""
        // a title written by someone else (OpenCode's title generation, a rename) becomes the one to come back to
        if (current !== state.written) state.original = current.replace(PROGRESS, "").replace(OUTCOME, "")
        // never on a session OpenCode has not named yet: its title generation would be thrown away
        if (!state.original || DEFAULT_TITLE.test(state.original)) return
        const title = progressLabel(state, Date.now(), subagents) + " — " + tagged((state.mark || "") + state.original)
        if (title === current) return
        await rename(sessionID, title)
        state.written = title
      } catch {
        // the title stays as it is
      } finally {
        state.writing = false
      }
    }

    async function restore(sessionID, state) {
      for (let i = 0; i < 30 && state.writing; i++) await new Promise((done) => setTimeout(done, 100))
      try {
        if (state.written && state.original !== undefined) {
          const info = await sessionInfo(sessionID)
          if (info && info.title === state.written) await rename(sessionID, tagged(state.original))
        } else if (TAG) {
          // 15. a title OpenCode generated during a turn too short to show its progress
          const info = await sessionInfo(sessionID)
          if (info && !info.parentID && info.title && tagged(info.title) !== info.title) await rename(sessionID, tagged(info.title))
        }
        state.written = undefined
      } catch {
        // the next turn will clean it
      }
    }

    async function finish(sessionID) {
      const state = sessionID && runs.get(sessionID)
      if (!state) return
      runs.delete(sessionID)
      state.done = true
      if (state.nudged) clearTimeout(state.nudged)
      for (const entry of state.running.values()) if (entry.child) subagents.delete(entry.child)
      await restore(sessionID, state)
    }

    // ---------- 10. the outcome of a pilot run in the title ----------
    async function markOutcome(sessionID, mark) {
      if (!mark) return
      try {
        const info = await sessionInfo(sessionID)
        if (!info || info.parentID) return
        const title = (info.title || "").replace(PROGRESS, "").replace(OUTCOME, "")
        if (!title || DEFAULT_TITLE.test(title)) return
        await rename(sessionID, tagged(mark + title))
      } catch {
        // the title stays as it is
      }
    }
    // The mark of the last answer of a pilot run: "⛔ " (stopped), "⏸ " (waits for me), "✅ " (delivered, or nothing
    // left to do), "" (no final answer: 19). The marks of the final answers start a line (a ✅ in a table cell is no
    // outcome); a ⛔ anywhere is a stop.
    const markOf = (text) => {
      const marks = text.split("\n").map((line) => (MARK_LINE.exec(line) || [])[1]).filter(Boolean)
      // a stop wins over everything else of the answer (a table of done steps may hold ✅ before it)
      if (text.includes("⛔")) return "⛔ "
      if (marks.includes("⏸")) return "⏸ "
      if (marks.length) return "✅ "
      return ""
    }
    const outcomeOf = (sessionID) => markOf(((answers.get(sessionID) || {}).texts || []).join("\n"))

    // 4, 9, 10 and 19. The « Suite » question of a run, after its final answer: the run is over and waits for nothing
    const suiteAsked = async (event) => {
      const run = commandRuns.get(event.sessionID)
      if (!run || suites.has(event.sessionID)) return
      const questions = event.input && Array.isArray(event.input.questions) ? event.input.questions : []
      if (!questions.some((q) => q && /^suite$/i.test(String(q.header || "").trim()))) return
      // the events of the final answer come by the event stream: a second at most behind the call
      let mark = ""
      for (let i = 0; i < 5 && run.pilot && !mark; i++) {
        mark = outcomeOf(event.sessionID) || lastMarks.get(event.sessionID) || ""
        if (!mark && i < 4) await new Promise((done) => setTimeout(done, 200))
      }
      // a question of the run itself, before its final answer: the run goes on after it
      if (run.pilot && !mark) return
      if (commandRuns.get(event.sessionID) !== run || suites.has(event.sessionID)) return
      suites.set(event.sessionID, mark)
      const state = runs.get(event.sessionID)
      if (state && mark) {
        state.mark = mark
        nudge(event.sessionID, state)
      }
      // the commands that hold the folder (9) free it now; the others (/compare, /outil) hold nothing
      if (!LOCKING_COMMANDS.has(run.command)) return
      release(event.sessionID)
      log("the run ended with its « Suite » question: the folder is free", { command: "/" + run.command })
    }

    // ---------- 19. a run that ended before its final answer resumes by itself ----------
    // Why a pilot run that just ended is resumed, as { fr, en, failure }, or undefined. `limited`: its last request
    // was the one OpenCode sends at the step limit of the agent, tools disabled.
    function resumeReason(type, data, mark, limited) {
      if (type === "session.execution.failed") {
        const error = (data && data.error) || {}
        if (FINAL_ERRORS.has(error.type) || FINAL_STATUS.has(Number(error.status))) return undefined
        const what = String(error.message || error.type || "error").replace(/\s+/g, " ").slice(0, 160)
        // 21. OpenCode gave up after three answers cut at the output limit (loops the pack cut, or answers too long)
        if (error.type === "output-limit") {
          return { fr: "réponses coupées en boucle", en: "your answers were cut three times at the output limit (they repeated themselves): think briefly, then act", failure: false }
        }
        if (String(error.type || "").startsWith("compaction")) {
          return { fr: "résumé du contexte en échec", en: "OpenCode could not summarize the conversation (" + what + ")", failure: true }
        }
        return { fr: "panne du serveur du modèle", en: "the model server failed after OpenCode's retries (" + what + ")", failure: true }
      }
      if (type === "session.execution.interrupted") {
        if (data && data.reason === "inactivity") return { fr: "tour interrompu par OpenCode", en: "OpenCode interrupted the turn (inactivity)", failure: true }
        return undefined
      }
      if (type !== "session.execution.succeeded") return undefined
      if (limited) return { fr: "limite d'étapes du pilote atteinte", en: "you reached the step limit of your agent and OpenCode disabled your tools", failure: false }
      if (!mark) return { fr: "réponse finale manquante", en: "your last answer did not end the run (it has no final report line starting with 🚀, 🔁, ✅, ⏸ or ⛔)", failure: false }
      return undefined
    }

    // Plans the resume of a run; false when two resumes in a row were already made
    function scheduleResume(sessionID, run, why) {
      const done = resumes.get(sessionID) || 0
      if (typeof api.prompt !== "function") return false
      if (done >= RESUMES_MAX) {
        log("run not resumed: " + RESUMES_MAX + " automatic resumes in a row already", { command: "/" + run.command, reason: why.en })
        return false
      }
      resumes.set(sessionID, done + 1)
      const delay = why.failure ? resumeFailureMs[Math.min(done, resumeFailureMs.length - 1)] || 0 : resumeUnfinishedMs
      const previous = resumeTimers.get(sessionID)
      if (previous) clearTimeout(previous)
      const timer = setTimeout(() => {
        resumeTimers.delete(sessionID)
        resumeRun(sessionID, run, why).catch(() => {})
      }, delay)
      if (timer && typeof timer.unref === "function") timer.unref()
      resumeTimers.set(sessionID, timer)
      log("run resumed in " + Math.round(delay / 1000) + " s", { command: "/" + run.command, resume: done + 1, reason: why.en })
      return true
    }

    // The resume itself: a message to the pilot, in its session, that the plugin handles as a run of the command
    async function resumeRun(sessionID, run, why) {
      // a turn that started meanwhile (a message I typed) replaces the resume
      if (runs.has(sessionID)) return
      const info = await sessionInfo(sessionID)
      if (!info || info.parentID) return
      // another agent was chosen in the session since the run: I am there, nothing to resume
      if (info.agent !== undefined && info.agent !== "pilot") {
        log("run not resumed: the session is on another agent now", { command: "/" + run.command })
        await markOutcome(sessionID, "⛔ ")
        return
      }
      await api.prompt({ sessionID, text: "[[command " + run.command + (run.args ? " " + run.args : "") + "]]\n[[resume " + why.fr + "]]\n" + resumeText(run, why) })
    }

    // The end of a turn: the title without progress, the outcome of a pilot run (or its resume, 19), the folder free,
    // the command chosen in a question started
    function end(sessionID, type, data) {
      const run = commandRuns.get(sessionID)
      commandRuns.delete(sessionID)
      release(sessionID)
      const next = chosen.get(sessionID)
      chosen.delete(sessionID)
      const suite = suites.get(sessionID)
      suites.delete(sessionID)
      lastMarks.delete(sessionID)
      const limited = stepLimited.delete(sessionID)
      const reason = data && data.reason
      const stopped = type === "session.execution.failed" || (type === "session.execution.interrupted" && reason !== "superseded")
      void (async () => {
        await finish(sessionID)
        let mark
        if (run && run.pilot && reason !== "superseded") {
          if (suite !== undefined) {
            // 4. its final answer came before its « Suite » question: that outcome, never a resume
            mark = suite
            resumes.delete(sessionID)
          } else {
            mark = stopped ? "⛔ " : outcomeOf(sessionID)
            const why = next ? undefined : resumeReason(type, data, mark, limited)
            if (why) mark = scheduleResume(sessionID, run, why) ? "↻ " : "⛔ "
            // a final answer of the run: the next failure may be resumed again
            else if (!stopped) resumes.delete(sessionID)
          }
          await markOutcome(sessionID, mark)
        }
        // 29. the time of this turn of the run
        try {
          closeRunClock(sessionID, mark || (stopped ? "⛔ " : suite || ""))
        } catch {
          // the measure is best-effort
        }
        // the command I chose: after a turn that ended well, or after the « Suite » question of a run whatever
        // failed then (never after a stop I asked for)
        const startable = type === "session.execution.succeeded" || (suite !== undefined && type === "session.execution.failed")
        if (next && startable && typeof api.command === "function") {
          chained.add(sessionID)
          try {
            await api.command({ sessionID, name: next.command, text: next.arguments })
          } finally {
            chained.delete(sessionID)
          }
        }
      })().catch(() => {})
    }

    // What a subagent does while its task runs, shown in the title of its parent
    function childEvent(sessionID, type, data) {
      const child = subagents.get(sessionID)
      if (!child) return
      const now = Date.now()
      switch (type) {
        case "session.retry.scheduled":
          child.phase = "retry"
          child.attempt = data.attempt || child.attempt + 1
          child.at = data.at
          child.last = now
          nudge(parents.get(sessionID), runs.get(parents.get(sessionID)))
          return
        case "session.step.started":
        case "session.reasoning.started":
        case "session.reasoning.delta":
        case "session.text.started":
        case "session.text.delta":
          if (child.phase !== "tool") child.phase = "work"
          child.last = now
          return
        case "session.tool.called":
          child.phase = "tool"
          child.last = now
          return
        case "session.tool.success":
        case "session.tool.failed":
        case "session.compaction.ended":
        case "session.compaction.failed":
          child.phase = "waiting"
          child.last = now
          return
        case "session.compaction.started":
          child.phase = "compaction"
          child.last = now
          nudge(parents.get(sessionID), runs.get(parents.get(sessionID)))
          return
        case "form.created":
        case "permission.asked": {
          child.phase = type === "form.created" ? "question" : "permission"
          const parent = runs.get(parents.get(sessionID))
          if (parent) void show(parents.get(sessionID), parent)
          return
        }
        case "form.replied":
        case "form.cancelled":
        case "permission.replied":
          child.phase = "waiting"
          child.last = now
          return
      }
    }

    // What the agent of a top-level session does now
    function topEvent(sessionID, type, data) {
      if (TURN_END.has(type)) return end(sessionID, type, data)
      if (type === "session.execution.started") {
        track(sessionID)
        lastMarks.delete(sessionID)
        return
      }
      const state = runs.get(sessionID)
      const now = Date.now()
      switch (type) {
        case "session.step.started":
          answers.set(sessionID, { message: data.assistantMessageID, texts: [] })
          if (state) {
            state.phase = "waiting"
            state.last = now
          }
          return
        case "session.text.ended": {
          const answer = answers.get(sessionID)
          if (answer && answer.message === data.assistantMessageID) answer.texts.push(String(data.text || ""))
          const mark = markOf(String(data.text || ""))
          if (mark) lastMarks.set(sessionID, mark)
          return
        }
        case "session.reasoning.started":
        case "session.reasoning.delta":
        case "session.text.started":
        case "session.text.delta":
          if (!state) return
          state.phase = type.startsWith("session.reasoning") ? "reasoning" : "text"
          state.chars += String(data.delta || "").length
          state.last = now
          return
        case "session.tool.input.started":
          toolNames.set(data.id, data.name)
          if (state && data.name !== "question") {
            const entry = state.running.get(data.id) || {}
            entry.text = toolText(data.name, {})
            state.running.set(data.id, entry)
            state.phase = "tool"
            state.tool = entry.text
            state.last = now
            nudge(sessionID, state)
          }
          return
        case "session.tool.called": {
          const name = toolNames.get(data.id) || ""
          if (state && name !== "question") {
            const entry = state.running.get(data.id) || {}
            entry.text = toolText(name, data.input)
            state.running.set(data.id, entry)
            state.phase = "tool"
            state.tool = entry.text
            state.last = now
            nudge(sessionID, state)
          }
          return
        }
        case "session.tool.progress": {
          // the session of the subagent that a subagent tool runs
          const child = data.metadata && data.metadata.sessionID
          if (!child || child === sessionID) return
          parents.set(child, sessionID)
          subagentSessions.add(child)
          mine.add(child)
          if (state) {
            const entry = state.running.get(data.id) || { text: toolText(toolNames.get(data.id) || "subagent", {}) }
            if (entry.child !== child) {
              entry.child = child
              if (!subagents.has(child)) subagents.set(child, { phase: "waiting", attempt: 0, last: now })
            }
            state.running.set(data.id, entry)
          }
          return
        }
        case "session.tool.success":
        case "session.tool.failed": {
          toolNames.delete(data.id)
          if (!state) return
          const entry = state.running.get(data.id)
          if (entry && entry.child) subagents.delete(entry.child)
          state.running.delete(data.id)
          // the other tools of the answer may still run (several subagents at once)
          if (state.running.size === 0) {
            if (state.phase === "tool") state.phase = "waiting"
          } else state.tool = [...state.running.values()].at(-1).text
          state.last = now
          nudge(sessionID, state)
          return
        }
        case "session.retry.scheduled":
          if (!state) return
          state.phase = "retry"
          state.attempt = data.attempt || state.attempt + 1
          state.at = data.at
          state.last = now
          nudge(sessionID, state)
          return
        case "session.compaction.started": {
          if (state) {
            state.phase = "compaction"
            state.last = now
            nudge(sessionID, state)
          }
          const run = commandRuns.get(sessionID)
          if (run && run.pilot) log("the conversation of a run is summarized (context full)", { command: "/" + run.command })
          return
        }
        case "session.compaction.ended":
        case "session.compaction.failed":
          if (state && state.phase === "compaction") {
            state.phase = "waiting"
            state.last = now
            nudge(sessionID, state)
          }
          if (type === "session.compaction.failed" && commandRuns.has(sessionID)) {
            log("the summary of a run failed", { command: "/" + commandRuns.get(sessionID).command, error: String((data.error && data.error.type) || "") })
          }
          return
        case "form.created":
        case "permission.asked":
          if (!state) return
          state.phase = type === "form.created" ? "question" : "permission"
          void show(sessionID, state)
          return
        case "form.replied":
        case "form.cancelled":
        case "permission.replied":
          if (!state) return
          state.phase = "waiting"
          state.last = now
          return
      }
    }

    // ---------- 29. where the time of a run goes ----------
    // run clock: one turn of a command of the pack in a top-level session, with the subagents it ran; session clock: the
    // model request under way in a session (its step), its tools, a summary or a question that waits
    const runClocks = new Map()
    const clocks = new Map()
    const timedTools = new Map()
    function startRunClock(sessionID, run, now) {
      const key = /^[A-Z][A-Z0-9_]*-\d+$/.test((run.args || "").split(/\s+/)[0] || "") ? run.args.split(/\s+/)[0]
        : /^sans ticket\b/i.test(run.args || "") ? "sans-ticket" : ""
      const clock = { command: run.command, key, start: now, prep: 0, steps: 0, model: { wait: 0, think: 0, write: 0 },
        top: { model: 0, tools: 0, subagents: 0, questions: 0 }, ttft: [], warm: [], ttftMax: 0, stallMax: 0, stalls: 0,
        cold: [], buffered: 0, tokens: { in: 0, cached: 0, out: 0, reasoning: 0 }, chars: 0, retries: 0, retryWait: 0,
        compactions: 0, compaction: 0, questions: 0, loops: 0, agents: new Map(), tools: new Map(), toolMax: ["", 0] }
      runClocks.set(sessionID, clock)
      clocks.set(sessionID, { run: clock, top: true, steps: 0, tools: new Map() })
    }
    // the clock of a session: its own, or a new one for a subagent of a run
    function clockOf(sessionID) {
      const own = clocks.get(sessionID)
      if (own) return own
      const parent = parents.get(sessionID)
      const run = parent && runClocks.get(parent)
      if (!run) return undefined
      const clock = { run, top: false, steps: 0, tools: new Map() }
      clocks.set(sessionID, clock)
      return clock
    }
    const addTo = (map, label, ms) => {
      const entry = map.get(label) || { n: 0, ms: 0 }
      entry.n++
      entry.ms += ms
      map.set(label, entry)
    }
    // the name of a tool in the measures: a script of the pack (with the mode of test-guardian.sh and fortify.sh), the
    // program of a shell command, or the tool itself; never its arguments
    function toolLabel(name, input) {
      if (name !== "shell" && name !== "bash") return String(name || "outil").replace(/[,:\s]+/g, "_").slice(0, 40)
      const command = String((input && input.command) || "")
      const script = /scripts\/([a-z0-9-]+\.sh)(?:\s+([a-z-]+))?/.exec(command)
      if (script) return script[1] + (/^(?:test-guardian|fortify)\.sh$/.test(script[1]) && script[2] ? "_" + script[2] : "")
      const first = (command.trim().split(/\s+/)[0] || "shell").split("/").pop()
      return first.replace(/[,:\s]+/g, "_").slice(0, 30) || "shell"
    }
    // the end of the model request of a step (its stream), then of the step (its tools)
    function streamEnd(clock, step, now) {
      if (step.streamed) return
      step.streamed = now
      const run = clock.run
      // the wait for the first token, then the time after the last delta with what that delta was doing
      step.wait = (step.first || now) - step.start
      run.model.wait += step.wait
      if (step.first) {
        if (step.lastKind === "think") step.think += now - step.last
        else step.write += now - step.last
        run.model.think += step.think
        run.model.write += step.write
      }
      if (clock.top) run.top.model += now - step.start
    }
    function stepEnd(clock, data, now) {
      const step = clock.step
      if (!step) return
      streamEnd(clock, step, now)
      clock.step = undefined
      const run = clock.run
      const tokens = (data && data.tokens) || {}
      const output = (Number(tokens.output) || 0) + (Number(tokens.reasoning) || 0)
      run.tokens.in += (Number(tokens.input) || 0) + (Number(tokens.cache && tokens.cache.read) || 0)
      run.tokens.cached += Number(tokens.cache && tokens.cache.read) || 0
      run.tokens.out += Number(tokens.output) || 0
      run.tokens.reasoning += Number(tokens.reasoning) || 0
      if (step.first) {
        // an answer that came all at once after a long wait: a gateway held it back (its buffer); its wait is not the
        // time to the first token of the server, nor are its deltas a stream
        if (step.streamed - step.first < 1000 && (output > 300 || step.chars > 1200)) run.buffered++
        else {
          run.ttft.push(step.wait)
          // the first request of a session reads its whole prompt; the next ones only what was added, when the
          // server keeps the prefix of the conversation (prefix caching)
          if (clock.steps > 1) run.warm.push(step.wait)
          else run.cold.push(step.wait)
          run.ttftMax = Math.max(run.ttftMax, step.wait)
          if (step.gap > 60000) run.stalls++
          run.stallMax = Math.max(run.stallMax, step.gap)
        }
      }
      if (clock.top) {
        const after = Math.max(0, now - step.streamed)
        if (step.asked) run.top.questions += after
        else if (step.subagents) run.top.subagents += after
        else run.top.tools += after
      }
    }
    function timeEvent(sessionID, type, data, now) {
      const clock = clockOf(sessionID)
      if (!clock) return
      const run = clock.run
      switch (type) {
        case "session.step.started": {
          const started = Number(data.started)
          clock.steps++
          run.steps++
          clock.step = { start: started > 0 && started <= now && now - started < 600000 ? started : now, first: 0, last: 0,
            gap: 0, streamed: 0, think: 0, write: 0, lastKind: "", chars: 0, subagents: false, asked: false }
          return
        }
        case "session.reasoning.started":
        case "session.reasoning.delta":
        case "session.text.started":
        case "session.text.delta":
        case "session.tool.input.started":
        case "session.tool.input.delta": {
          if (type === "session.tool.input.started" && data.id) timedTools.set(data.id, String(data.name || ""))
          const step = clock.step
          if (!step || step.streamed) return
          const kind = type.startsWith("session.reasoning") ? "think" : "write"
          if (typeof data.delta === "string") {
            step.chars += data.delta.length
            run.chars += data.delta.length
          }
          // the time since the last delta goes with what that delta was doing (thinking, or writing)
          if (!step.first) step.first = now
          else {
            step.gap = Math.max(step.gap, now - step.last)
            if (step.lastKind === "think") step.think += now - step.last
            else step.write += now - step.last
          }
          step.last = now
          step.lastKind = kind
          return
        }
        case "session.step.streamed":
          if (clock.step) streamEnd(clock, clock.step, now)
          return
        case "session.step.ended":
        case "session.step.failed":
          stepEnd(clock, data, now)
          return
        case "session.tool.called": {
          const name = timedTools.get(data.id) || ""
          clock.tools.set(data.id, { name, label: toolLabel(name, data.input), start: now,
            agent: name === "subagent" && data.input && data.input.agent ? String(data.input.agent) : "" })
          if (clock.step && name === "subagent") clock.step.subagents = true
          if (clock.step && name === "question") clock.step.asked = true
          return
        }
        case "session.tool.success":
        case "session.tool.failed": {
          timedTools.delete(data.id)
          const tool = clock.tools.get(data.id)
          if (!tool) return
          clock.tools.delete(data.id)
          const ms = now - tool.start
          if (tool.name === "question") return
          if (tool.name === "subagent") addTo(run.agents, (tool.agent || "subagent").replace(/[,:\s]+/g, "_"), ms)
          else {
            addTo(run.tools, tool.label, ms)
            if (ms > run.toolMax[1]) run.toolMax = [tool.label, ms]
          }
          return
        }
        case "session.retry.scheduled":
          run.retries++
          run.retryWait += Math.max(0, Math.min(Number(data.at) - now, 3600000) || 0)
          return
        case "session.compaction.started":
          clock.compaction = now
          return
        case "session.compaction.ended":
        case "session.compaction.failed":
          if (clock.compaction) {
            run.compactions++
            run.compaction += now - clock.compaction
            clock.compaction = 0
          }
          return
        case "form.created":
        case "permission.asked":
          clock.asked = now
          if (clock.step) clock.step.asked = true
          return
        case "form.replied":
        case "form.cancelled":
        case "permission.replied":
          if (clock.asked) run.questions += now - clock.asked
          clock.asked = 0
          return
      }
    }
    // The line of a run in openrd-pack-runs.tsv, when its turn ends: seconds, counts and names only
    function closeRunClock(sessionID, mark) {
      const run = runClocks.get(sessionID)
      if (!run) return
      runClocks.delete(sessionID)
      for (const [id, clock] of clocks) if (clock.run === run) clocks.delete(id)
      if (timedTools.size > 500) timedTools.clear()
      const now = clockNow()
      const s = (ms) => Math.round(ms / 1000)
      const avg = (list) => (list.length ? Math.round(list.reduce((a, b) => a + b, 0) / list.length / 100) / 10 : 0)
      const list = (map, max) => [...map].sort((a, b) => b[1].ms - a[1].ms).slice(0, max).map(([label, e]) => label + ":" + e.n + ":" + s(e.ms)).join(",")
      const fields = {
        command: run.command, key: run.key, outcome: (mark || "").trim() || "-", total: s(now - run.start), prep: s(run.prep),
        top_model: s(run.top.model), top_tools: s(run.top.tools), top_subagents: s(run.top.subagents), questions: s(run.questions),
        steps: run.steps, wait: s(run.model.wait), think: s(run.model.think), write: s(run.model.write),
        ttft_avg: avg(run.ttft), ttft_cold: avg(run.cold), cold_n: run.cold.length, ttft_warm: avg(run.warm), warm_n: run.warm.length,
        ttft_max: s(run.ttftMax), stall_max: s(run.stallMax), stalls: run.stalls,
        buffered: run.buffered, retries: run.retries, retry_wait: s(run.retryWait), compactions: run.compactions,
        compaction: s(run.compaction), loops: run.loops, tokens_in: run.tokens.in, tokens_cached: run.tokens.cached,
        tokens_out: run.tokens.out, tokens_reasoning: run.tokens.reasoning, chars: run.chars,
        agents: list(run.agents, 12), tools: list(run.tools, 8), tool_max: run.toolMax[0] ? run.toolMax[0] + ":" + s(run.toolMax[1]) : "",
      }
      writeRunLine(fields)
      log("time of the run", { command: "/" + run.command, total: fields.total, model: fields.top_model, tools: fields.top_tools,
        subagents: fields.top_subagents, questions: fields.questions, retries: fields.retries, compactions: fields.compactions })
    }

    function onEvent(e) {
      if (!e || !e.type) return
      const data = e.data || e.properties || {}
      if (e.type === "session.created") {
        if (data.parentID && data.sessionID && mine.has(data.parentID)) {
          parents.set(data.sessionID, data.parentID)
          subagentSessions.add(data.sessionID)
          mine.add(data.sessionID)
        }
        return
      }
      const sessionID = data.sessionID || (data.form && data.form.sessionID) || ""
      if (!sessionID) return
      if (adopted && adopted.session === sessionID && !TURN_END.has(e.type)) adopted.started = true
      // the older status events of OpenCode v2 also end a turn
      const idle = e.type === "session.idle" || (e.type === "session.status" && !!data.status && (data.status === "idle" || data.status.type === "idle"))
      // 9. the lock file of a run of this process ends with its turn, even when this instance of the plugin started
      // after it (the plugin was loaded again)
      if ((idle || TURN_END.has(e.type)) && !mine.has(sessionID)) {
        const lock = readLock()
        if (lock && lock.session === sessionID && lock.pid === process.pid) release(sessionID)
      }
      if (!mine.has(sessionID)) return
      // 29. the measures of the run, before anything else changes its state
      try {
        timeEvent(sessionID, e.type, data, clockNow())
      } catch {
        // the measure is best-effort
      }
      if (idle) {
        if (!parents.has(sessionID) && !subagentSessions.has(sessionID)) release(sessionID)
        return
      }
      if (parents.has(sessionID) || subagentSessions.has(sessionID)) return childEvent(sessionID, e.type, data)
      if (e.type === "session.renamed") {
        // 15. a title OpenCode generated, or that I typed, between two turns gets the folder of the worktree (during a
        // turn, the progress and its end write it)
        const title = String(data.title || "")
        if (TAG && !runs.has(sessionID) && tagged(title) !== title) {
          void (async () => {
            const info = await sessionInfo(sessionID)
            if (info && !info.parentID && info.title === title) await rename(sessionID, tagged(title))
          })().catch(() => {})
        }
        return
      }
      topEvent(sessionID, e.type, data)
    }

    if (ctx.event && typeof ctx.event.subscribe === "function") {
      ;(async () => {
        try {
          let connected = false
          for await (const e of ctx.event.subscribe()) {
            if (!connected) {
              connected = true
              log("event stream connected for " + worktree)
            }
            try {
              onEvent(e)
            } catch {
              // never stop reading the events
            }
          }
        } catch {
          // no event stream: the 4-hour limit frees the folder
        }
      })()
    }

    // 9. the lock of a run that OpenCode's background service resumes after a restart
    const isService = () => {
      if (options.service !== undefined) return !!options.service
      if (process.argv.includes("--service")) return true
      try {
        return readFileSync("/proc/self/cmdline", "utf8").split("\0").includes("--service")
      } catch {
        return false
      }
    }
    adoptLock(isService())

    // 12. the MCP servers as plain tools (code mode is taken out of every request), and 27. their calls bounded
    if (ctx.mcp && typeof ctx.mcp.transform === "function") {
      try {
        // the transform runs again with each change of the configuration: each server is logged once
        const bounded = new Set()
        await ctx.mcp.transform((editor) => {
          const fresh = []
          for (const [name, server] of editor.list()) {
            server.codemode = false
            const timeout = server.timeout && typeof server.timeout === "object" ? server.timeout : {}
            if (!(Number(timeout.execution) > 0)) {
              server.timeout = { ...timeout, execution: mcpCallMs }
              if (!bounded.has(String(name))) fresh.push(String(name))
              bounded.add(String(name))
            }
          }
          if (fresh.length) log("calls of the MCP servers bounded to " + Math.round(mcpCallMs / 1000) + " s", { servers: fresh })
        })
      } catch (error) {
        log("MCP servers left as they are", { error: String((error && error.message) || error) })
      }
    }

    await ctx.tool.hook("execute.before", async (event) => {
      if (!event) return
      if (event.sessionID) mine.add(event.sessionID)
      if (V2_REFUSED.has(event.tool)) {
        guards.logRefusal({ sessionID: event.sessionID, agent: event.agent, tool: event.tool }, "moves the session or a worktree")
        throw new Error("Refused by the pack: " + event.tool + " is for the developer, in the web interface. Work in the repository of this session.")
      }
      if (V2_HIDDEN.includes(event.tool)) {
        guards.logRefusal({ sessionID: event.sessionID, agent: event.agent, tool: event.tool }, "not offered by the pack")
        throw new Error("Refused by the pack: " + event.tool + " is not available. Use the other tools of this request.")
      }
      if (looping(event)) {
        guards.logRefusal({ sessionID: event.sessionID, agent: event.agent, tool: event.tool }, "same call three times in one answer")
        throw new Error(
          "Refused by the pack: this is the third identical " + event.tool + " call of your answer, a loop. Its result " +
            "will not change: use the results you already have, take another approach, or report what blocks you.",
        )
      }
      if (event.tool === "question" && (await isSubagent(event.sessionID))) {
        throw new Error("Refused by the pack: a subagent never asks a question, nobody answers during /go, /fix, /fortify or /tests. Decide with the rules of your instructions, or write the question in your report.")
      }
      if (refusedRuns.has(event.sessionID)) {
        throw new Error("Refused by the pack: this run was refused (another /go, /fix, /fortify, /tests, /push or /sync runs in this folder). Answer with the sentence of the request only.")
      }
      if (event.tool === "question") await suiteAsked(event)
      const tool = V2_TOOLS[event.tool] || event.tool
      const input = event.input && typeof event.input === "object" ? event.input : {}
      // 8. the agents of the pack wait for each command and each subagent
      if (PACK_AGENTS.has(event.agent) && (tool === "bash" || tool === "task") && input.background === true) input.background = false
      const args = { ...input }
      if (typeof args.path === "string" && ["read", "edit", "write"].includes(tool)) args.filePath = args.path
      const output = { args }
      await guards.before({ tool, sessionID: event.sessionID, agent: event.agent, callID: event.id }, output)
      if (tool === "bash" && typeof output.args.command === "string") {
        input.command = output.args.command
        if (output.args.timeout !== undefined) input.timeout = output.args.timeout
      }
    })

    // 4. the command chosen in a multiple-choice question of a top-level session
    await ctx.tool.hook("execute.after", async (event) => {
      try {
        if (!event || event.tool !== "question" || event.status !== "completed") return
        if (event.sessionID) mine.add(event.sessionID)
        if (await isSubagent(event.sessionID)) return
        const result = event.result || {}
        const answered = (result.output && result.output.answers) || (result.metadata && result.metadata.answers)
        const next = chosenCommand(answered)
        if (next) chosen.set(event.sessionID, next)
      } catch {
        // no command to start
      }
    })

    await ctx.shell.hook("create.before", async (invocation) => {
      if (!invocation || !invocation.env) return
      guards.env(invocation.env)
    })

    // 18. the sessions of a run of /go, /fix, /fortify or /tests: the pilot's, and those of its subagents
    const inPilotRun = async (sessionID) => {
      let id = sessionID
      for (let depth = 0; depth < 4 && id; depth++) {
        const run = commandRuns.get(id)
        if (run && run.pilot) return true
        let parent = parents.get(id)
        if (parent === undefined && subagentSessions.has(id)) {
          const info = await sessionInfo(id)
          parent = (info && info.parentID) || ""
          if (parent) parents.set(id, parent)
        }
        id = parent
      }
      return false
    }

    // 28. the options of each agent, as OpenCode v2 reads them from the configuration (its request.body): read at the
    // first request, then again every minute (a configuration that changed) without making a request wait
    const agentBodies = { at: 0, map: new Map(), loading: undefined }
    const loadAgentBodies = async () => {
      try {
        if (!ctx.agent || typeof ctx.agent.list !== "function") return
        const out = await ctx.agent.list()
        const list = Array.isArray(out) ? out : out && Array.isArray(out.data) ? out.data : []
        const map = new Map()
        for (const agent of list) {
          const body = agent && agent.request && agent.request.body
          if (agent && agent.id && plainObject(body) && Object.keys(body).length) map.set(String(agent.id), body)
        }
        agentBodies.map = map
      } catch {
        // the options read before
      } finally {
        agentBodies.at = Date.now()
        agentBodies.loading = undefined
      }
    }
    async function agentOptions(agentID) {
      if (!agentBodies.loading && Date.now() - agentBodies.at > AGENT_OPTIONS_MS) agentBodies.loading = loadAgentBodies()
      if (agentBodies.loading && agentBodies.at === 0) await agentBodies.loading
      return agentBodies.map.get(agentID)
    }

    // 12, 13, 17 and 19. what each request to the model carries
    if (typeof api.hook === "function") {
      await api.hook("context", async (event) => {
        try {
          if (!event) return
          if (event.tools) {
            for (const name of V2_HIDDEN) delete event.tools[name]
            if (event.tools.question && (await isSubagent(event.sessionID))) delete event.tools.question
          }
          if (pruning) prune(event.messages)
          // 21. the loops of the conversation are kept once (an answer cut in a loop is taken out, with the note that
          // followed it), and after a cut the next answers are sampled with a presence penalty that breaks the loop
          const cleaned = sanitizeLoops(event.messages)
          if (cleaned.dropped || (cleaned.collapsed && !loopLogged.has(event.sessionID))) {
            loopLogged.add(event.sessionID)
            log("loops taken out of a request", { agent: event.agent || "", dropped: cleaned.dropped, collapsed: cleaned.collapsed })
          }
          const cut = loopCuts.get(event.sessionID)
          if (cut && event.options && typeof event.options === "object") {
            const penalty = cut.count >= 2 ? 1.5 : 1.0
            if (!(Number(event.options.presencePenalty) >= penalty)) event.options.presencePenalty = penalty
          }
          // 19. the request OpenCode sends at the step limit of the agent ends with its instruction
          const last = Array.isArray(event.messages) ? event.messages[event.messages.length - 1] : undefined
          if (last && last.role === "assistant" && messageText(last).trimStart().startsWith("CRITICAL - MAXIMUM STEPS REACHED")) {
            stepLimited.add(event.sessionID)
          }
          // 17. after a summary: the procedure of the run, or the task of the subagent, as instructions again
          if (Array.isArray(event.system) && summarized(event.messages)) {
            const run = commandRuns.get(event.sessionID)
            if (run && run.pilot) {
              const kept = procedures.get(event.sessionID)
              const text = kept && kept.command === run.command ? kept.text : commandFile(run.command, run.args)
              if (text) event.system.push({ type: "text", text: procedureNote(run, text) })
            } else if (tasks.has(event.sessionID)) {
              event.system.push({ type: "text", text: taskNote(tasks.get(event.sessionID)) })
            }
          }
        } catch {
          // the request goes as it is
        }
      })

      // 17. the summary of a run, or of the work of a subagent, keeps what the next requests need
      await api.hook("compaction", async (event) => {
        try {
          if (!event || !Array.isArray(event.system)) return
          const run = commandRuns.get(event.sessionID)
          if (run && run.pilot) event.system.push({ type: "text", text: keepRunNote(run) })
          else if (tasks.has(event.sessionID)) event.system.push({ type: "text", text: KEEP_TASK_NOTE })
        } catch {
          // the summary is written as OpenCode asks it
        }
      })

      // 18. more time for the model server during a run of the pack: the same retries, spread over about 8 minutes
      await api.hook("retry", async (event) => {
        try {
          if (!event || !event.decision || event.decision.retry !== true || !(await inPilotRun(event.sessionID))) return
          const least = patienceMs[Math.min(Math.max(Number(event.attempt) || 0, 0), patienceMs.length - 1)] || 0
          if (least > (Number(event.decision.delay) || 0)) event.decision.delay = least
        } catch {
          // OpenCode's own timing
        }
      })

      // 20. an assistant message made only of tool calls goes with "" as its content instead of null
      let filledLogged = false
      // 21. a streamed answer that repeats itself is cut at once, as an answer cut at the output limit
      await api.hook("http.response", async (event) => {
        try {
          const response = event && event.response
          if (!response || event.kind !== "primary" || !response.body || response.status !== 200) return
          if (!/event-stream/i.test(response.headers.get("content-type") || "")) return
          const sessionID = event.sessionID
          event.response = new Response(
            watchStream(response.body, {
              onLoop: (found) => {
                const cut = loopCuts.get(sessionID) || { count: 0 }
                cut.count++
                loopCuts.set(sessionID, cut)
                const clock = clocks.get(sessionID)
                if (clock) clock.run.loops++
                log("an answer that repeated itself was cut", { agent: event.agent || "", repeats: found.repeats, block: found.chars, chars: found.total, cut: cut.count })
              },
              onEnd: () => loopCuts.delete(sessionID),
            }),
            { status: response.status, statusText: response.statusText, headers: response.headers },
          )
        } catch {
          // the answer goes as it is
        }
      })

      // 28. the options of the agent of each request, as 1.19 sent them (OpenCode v2 reads them and never sends them)
      const optionsLogged = new Set()
      await api.hook("http.request", async (event) => {
        try {
          const request = event && event.request
          if (!request || request.method !== "POST" || !request.body) return
          if (!/json/i.test(request.headers.get("content-type") || "")) return
          const original = await request.clone().text()
          let body = original
          const filled = fillNullContent(body)
          if (filled !== null) {
            body = filled
            if (!filledLogged) {
              filledLogged = true
              log("assistant messages made only of tool calls are sent with an empty content instead of null")
            }
          }
          const agent = String((event && event.agent) || "")
          const options = agent ? await agentOptions(agent) : undefined
          const optioned = options ? withAgentOptions(body, options) : null
          if (optioned !== null) {
            body = optioned
            if (!optionsLogged.has(agent)) {
              optionsLogged.add(agent)
              log("the options of the agent are sent with its requests", { agent, options: Object.keys(options).filter((key) => !REQUEST_OWN.has(key)) })
            }
          }
          if (body === original) return
          const headers = new Headers(request.headers)
          headers.delete("content-length")
          event.request = new Request(request.url, { method: request.method, headers, body, signal: request.signal })
        } catch {
          // the request goes as it is
        }
      })
    }

    await api.hook("prompt", async (event) => {
      const ready = mcpReady()
      try {
        await onPrompt(event)
      } finally {
        await ready
      }
    })

    // 22. the run of /go, /fix, /fortify or /tests that a session stopped before its end (no ✅ nor ⏸ in its title), or undefined:
    // the one this instance saw start, otherwise the one its title names (after a restart of OpenCode)
    async function stoppedRun(sessionID) {
      if (!sessionID || runs.has(sessionID)) return undefined
      const info = await sessionInfo(sessionID)
      if (!info || info.parentID) return undefined
      const title = String(info.title || "")
      const mark = (OUTCOME.exec(title) || [""])[0]
      if (mark.startsWith("✅") || mark.startsWith("⏸")) return undefined
      const known = procedures.get(sessionID)
      if (known && PILOT_COMMANDS.has(known.command)) return { command: known.command, args: known.args }
      const rest = title.replace(OUTCOME, "").replace(/^\[[^\]]*\] /, "").trim()
      const named = /^\/(go|fix|fortify|tests)(?:\s+([\s\S]*))?$/.exec(rest)
      return named ? { command: named[1], args: (named[2] || "").trim() } : undefined
    }

    async function onPrompt(event) {
      const prompt = event && event.prompt
      if (!prompt || typeof prompt.text !== "string") return
      const sessionID = event.sessionID
      if (sessionID) mine.add(sessionID)
      const subagent = await isSubagent(sessionID, prompt.text)
      // 17. the task the pilot gives a subagent: its first prompt, then the last ones that take it up again
      if (subagent) {
        const first = prompt.text.startsWith(SUBAGENT_PROMPT)
        const list = first ? [] : [...(tasks.get(sessionID) || [])]
        list.push((first ? prompt.text.slice(SUBAGENT_PROMPT.length) : prompt.text).trim().slice(0, TASK_MAX))
        remember(tasks, sessionID, list.length > 3 ? [list[0], ...list.slice(-2)] : list)
      }
      // 22. « continue » after a run of /go, /fix, /fortify or /tests that stopped before its end: that run resumes, with the
      // pilot, instead of the agent the web interface switched the session to
      if (!subagent && !COMMAND_LINE.test(prompt.text) && isContinue(prompt.text)) {
        const run = await stoppedRun(sessionID)
        if (run) {
          const pending = resumeTimers.get(sessionID)
          if (pending) {
            clearTimeout(pending)
            resumeTimers.delete(sessionID)
          }
          resumes.delete(sessionID)
          try {
            if (typeof api.switchAgent === "function") await api.switchAgent({ sessionID, agent: "pilot" })
          } catch {
            // the session keeps its agent
          }
          log("run resumed at the developer's request", { command: "/" + run.command })
          prompt.text = "[[command " + run.command + (run.args ? " " + run.args : "") + "]]\n[[resume reprise demandée]]\n" +
            resumeText(run, { en: "it stopped before its end, and the developer asks you to continue it" })
        }
      }
      // the command of the pack this prompt runs: its [[command]] line, or the first sentence of an older pilot command
      let command = ""
      let args = ""
      // 19. the reason of a resume the plugin sent ("[[resume <reason>]]" after the [[command]] line)
      let resume = ""
      const line = subagent ? null : COMMAND_LINE.exec(prompt.text)
      if (line) {
        command = line[1]
        args = (line[2] || "").trim()
        prompt.text = prompt.text.slice(line[0].length)
        const again = RESUME_LINE.exec(prompt.text)
        if (again) {
          resume = (again[1] || "").trim() || "reprise"
          prompt.text = prompt.text.slice(again[0].length)
        }
      } else if (!subagent) {
        const run = PILOT_RUNS.find(([, sentence]) => prompt.text.includes(sentence))
        if (run) command = run[0]
      }
      // 19. a message I type replaces a resume that waits, and the next failure may be resumed again
      if (!subagent && !resume) {
        const pending = resumeTimers.get(sessionID)
        if (pending) {
          clearTimeout(pending)
          resumeTimers.delete(sessionID)
          log("automatic resume cancelled: a new message in the session")
        }
        resumes.delete(sessionID)
      }
      const label = command ? ("/" + command + " " + args).trim() : ""
      // 3. a session with no title yet takes the name of the command (OpenCode then asks no model for a title)
      if (command) {
        try {
          const info = await sessionInfo(sessionID)
          if (info && !info.parentID && (!info.title || DEFAULT_TITLE.test(info.title))) await rename(sessionID, tagged(label.slice(0, 80)))
        } catch {
          // OpenCode names it
        }
      }
      // 9. one /go, /fix, /fortify, /tests, /push or /sync at a time per folder
      if (LOCKING_COMMANDS.has(command)) {
        const other = acquire(sessionID, command, args)
        if (other) {
          refusedRuns.add(sessionID)
          const notice =
            "⛔ /" + command + " refusé : " + other.command + " tourne déjà dans ce dossier" +
            (other.elsewhere ? " (dans un autre OpenCode de cette machine)" : "") + " depuis " +
            Math.round((Date.now() - other.since) / 60000) + " min. Attends sa fin, ou ouvre un espace de travail pour " +
            "travailler en parallèle (s'il est fini ou arrêté, redémarrer OpenCode libère le dossier)."
          guards.logRefusal({ sessionID, agent: "pilot", tool: "/" + command }, "another " + other.command + " runs in this folder")
          prompt.text = "Answer exactly this sentence and nothing else, without any tool: « " + notice + " »"
          event.metadata = presentation(event.metadata, label)
          return
        }
        refusedRuns.delete(sessionID)
      }
      if (command) commandRuns.set(sessionID, { command, args, pilot: PILOT_COMMANDS.has(command) })
      // 29. the time of the run, from its scripts on
      if (command && !subagent) startRunClock(sessionID, commandRuns.get(sessionID), clockNow())
      // 17. the instructions of the run, for the requests that follow a summary of its conversation (a resume keeps
      // those of the run it resumes)
      if (PILOT_COMMANDS.has(command) && !resume) remember(procedures, sessionID, { command, args, text: procedureOf(prompt.text) })
      // 7. the folders I name, in a message or in the arguments of a command I type, in a top-level session
      if (!subagent && !chained.has(sessionID) && !resume) await guards.named(sessionID, command ? args : prompt.text)
      // 5. the progress of the turn in the title, from the scripts of the command on
      let state
      if (command) {
        state = track(sessionID, "preparing")
        if (state) void show(sessionID, state)
      }
      // 1. the scripts of the command, in the git root of the folder
      const prepared = clockNow()
      try {
        if (prompt.text.includes("[[run ")) prompt.text = await resolveRuns(prompt.text, worktree)
      } catch {
        // keep the lines: the model runs them
      }
      const runClock = command && runClocks.get(sessionID)
      if (runClock) runClock.prep += clockNow() - prepared
      if (state) {
        state.phase = "waiting"
        state.last = Date.now()
      }
      // 3. what the conversation shows
      if (!command) return
      try {
        const split = VISIBLE.exec(prompt.text)
        if (split) {
          const shown = prompt.text.slice(0, split.index).trim()
          prompt.text = prompt.text.slice(split.index + split[0].length).trim()
          event.metadata = presentation(event.metadata, shown || label)
          return
        }
        const place = await where(directory).catch(() => "")
        const due = reminders()
        const reminder = due > 0 ? " · ⏰ " + due + (due > 1 ? " rappels" : " rappel") : ""
        // 19. a resume shows as such: "↻ /go ABC-1 · reprise automatique (panne du serveur du modèle) — api · branche …"
        const shown = resume ? "↻ " + label + " · " + (resume.startsWith("reprise") ? resume : "reprise automatique (" + resume + ")") : label
        event.metadata = presentation(event.metadata, (place ? shown + " — " + place : shown) + reminder)
      } catch {
        // the expanded prompt is shown
      }
    }

    // 26. the scheduled commands: each instance of the plugin looks every 20 s; a marker file per schedule and minute,
    // created by one instance only, starts it once, in a new session of its repository
    const schedulesFile = options.schedulesFile || process.env.OPENCODE_SCHEDULES || join(HOME, ".config", "opencode", "schedules.md")
    const firedDir = join(process.env.XDG_DATA_HOME || join(HOME, ".local", "share"), "opencode", "openrd-pack", "scheduled")
    const startScheduled = async (now) => {
      let text = ""
      try {
        text = readFileSync(schedulesFile, "utf8")
      } catch {
        return
      }
      const day = now.getFullYear() + "-" + pad2(now.getMonth() + 1) + "-" + pad2(now.getDate())
      for (const entry of dueSchedules(text, now)) {
        const label = "/" + entry.command + (entry.args ? " " + entry.args : "")
        const marker = join(firedDir, entry.id + "-" + day + "-" + pad2(entry.hour) + pad2(entry.minute))
        try {
          mkdirSync(firedDir, { recursive: true })
          closeSync(openSync(marker, "wx"))
        } catch {
          continue
        }
        // the markers of the days before
        try {
          for (const name of readdirSync(firedDir)) if (!name.includes("-" + day + "-")) unlinkSync(join(firedDir, name))
        } catch {
          // kept
        }
        if (!scheduleAllowed(entry)) {
          log("scheduled command refused: it may write", { schedule: entry.id, command: label })
          continue
        }
        if (!existsSync(entry.directory)) {
          log("scheduled command not started: its folder is missing", { schedule: entry.id, command: label, directory: entry.directory })
          continue
        }
        try {
          if (typeof api.create !== "function") throw new Error("this OpenCode cannot create a session from a plugin")
          const created = await api.create({ location: { directory: entry.directory } })
          const sessionID = created && (created.id || (created.data && created.data.id))
          if (!sessionID) throw new Error("no session id")
          await api.command({ sessionID, name: entry.command, text: entry.args })
          log("scheduled command started", { schedule: entry.id, command: label, directory: entry.directory, sessionID })
        } catch (error) {
          log("scheduled command not started", { schedule: entry.id, command: label, error: String((error && error.message) || error).slice(0, 200) })
        }
      }
    }
    const scheduleMs = Number(options.scheduleMs) > 0 ? Number(options.scheduleMs) : SCHEDULE_MS
    const scheduler = options.schedules === false ? undefined : setInterval(() => void startScheduled(new Date()), scheduleMs)
    if (scheduler && typeof scheduler.unref === "function") scheduler.unref()

    // the lock file of a run that goes on stays until its turn ends (an instance loaded again frees it then)
    return () => {
      if (scheduler) clearInterval(scheduler)
      if (ticker) clearInterval(ticker)
      for (const timer of resumeTimers.values()) clearTimeout(timer)
    }
  },
})
