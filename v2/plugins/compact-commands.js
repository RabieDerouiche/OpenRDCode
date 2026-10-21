// OpenCode plugin of the pack: ~/.config/opencode/plugins/compact-commands.js (restart OpenCode after a change).
//
// 1. Runs the "[[run <script> <arguments>]]" lines of the pack's commands with the pack's scripts, in the folder of
//    the session's project. OpenCode 1.19 runs the !`...` injections of a command in the folder where the server
//    was started; `opencode web` serves every project from one server, so they described the wrong repository.
//    Each script runs without a terminal (git or ssh can never wait there for a password) and is stopped, with
//    everything it started, after 3 minutes. "[[run <script> --raw <text>]]" passes the text as ONE argument, as
//    typed (apostrophes included).
// 2. Gives every shell command of the agents a stable environment: English .NET messages, no .NET banner or
//    telemetry, no npm notices, file names printed by git as they are (no octal escapes), and git never waiting for
//    a password or an editor (a command that waits ends only at the 2-minute timeout). Other variables already set
//    in the environment are kept.
// 3. Shows only "/<command> <arguments> — <repository folder> · branche <branch>" in the conversation (the web
//    interface does not show the current branch in a session), followed by "· ⏰ <n> rappel(s)" when items of my
//    todo list are due today or overdue; the expanded prompt (workflow state, ticket sheet, diffs) is still sent to
//    the model, as a "synthetic" part that the web interface does not display. A command whose prompt has a line
//    "[[visible]]" shows what is above that line instead (/outil todo shows the list at once).
// 4. Starts the command I choose in a multiple-choice question: an option whose label is a command of the pack
//    ("/go ABC-123", "/fix (recommandé)") runs by itself in the same session as soon as the agent's turn ends, unless
//    that turn ended with an error or was stopped, and never in a subagent's session. Agents cannot run a command.
// 5. Shows the progress of the agent in the session title while it works, for example
//    "⏳ 1:42 réflexion 2,3k tokens — <title>": the web interface only shows a small "Réflexion" that keeps moving
//    even when nothing comes from the model, and that is out of sight when the conversation is scrolled up. Phases:
//    préparation (the scripts of the command), attente du modèle, réflexion, rédaction, outil (with its
//    description), réponse or autorisation attendue (a question or an approval waits for me), nouvel essai (error of
//    the model server, OpenCode retries), and "rien reçu depuis <n> s" when the model has sent nothing for 30 s.
//    The title comes back as it was when the turn ends. Never in a subagent's session; in a new session, only once
//    OpenCode has written its title (or after 90 s), so that its title generation is not disturbed.
// 6. Refuses an agent's shell command that sets PATH or DOTNET_ROOT, or that writes a credential (an assignment or an
//    export of a password, token, secret or Artifactory variable, a password in a URL, in curl -u or in a NuGet source):
//    the environment of the agents comes from ~/.zshenv, and a credential written in a command stays in the session
//    history. OpenCode's permission rules cannot see these forms (assignments and export are not commands to its
//    parser). The agent is told to stop and report an environment problem instead.
// 7. Keeps the agents of the pack inside the repository of the session: a shell command of any agent that names a path
//    outside it (`~`, `$HOME`, `/home/…`, `../..`, a bare `cd`), even inside quotes, `sh -c '…'` or after a
//    redirection, is refused, and so is a read, search, edit or write of an agent of the pack (pilot, analyst, coder,
//    checker, debugger, doc-writer) outside it. Allowed outside: the pack's scripts and skills, the outputs OpenCode
//    saves, the NuGet package cache for the file tools, the folders configured as "references" in opencode.json and
//    the folders I name myself (in the arguments of a command or in a message I type): the conversation agents and the
//    read-only agents may use them in the shell, every agent of the pack with the file tools. These folders are
//    read-only: in the shell, only a command that reads (cat, grep, ls, git log…) may name them, never cp, mv, rm, a
//    redirection, a build, an interpreter or xargs running another command (the pack's own guards stay as installed);
//    the agents of the pack write only in the repository. A cd is followed. Secrets (~/.zshenv, the
//    git credentials, ~/.nuget/NuGet) are outside every repository: no `grep -r <word> ~` can print them. The
//    arguments of the pack's scripts are not checked: a commit message may contain any text.
//    OpenCode's own rules cannot do this (tree-sitter does not look inside quotes, and `export -p` is not a command to
//    it); an approval answered "always" cannot lift it either. Also refused for every agent: an environment dump
//    (`export`, `declare -p`, `set` alone) and a recursive rm, whatever the order of its options.
// 8. Gives the long commands the time they need: a build or test command 20 minutes (OpenCode stops any command after
//    2 minutes unless the agent asks for more, and a stopped full test suite is run again from the start), ship.sh
//    and branch.sh 5 minutes.
// 9. Starts only one /go or /fix at a time per repository: two pilots in one working tree would commit each other's
//    changes. The second one is replaced by a one-line answer that names the session that runs (no tool runs).
// 10. Leaves the outcome of a /go or /fix in the session title once it ends: "✅ " (merge request created or updated,
//    nothing left to do) or "⛔ " (stopped: its answer holds ⛔, or the run ended with an error). With several
//    /go running in several repositories, the list of sessions says which one needs me. The mark goes away when the
//    next turn of the session starts.
// 11. Runs a build tool called by its full path (`~/.bin/dotnet build`, `/usr/bin/git log`) by its name (`dotnet
//    build`): the permission rules of the agents name the tools, and the folder of the tool is outside the repository.
// Every refusal of 6, 7 and 9 is written to OpenCode's log as "refused by the pack" (COMMANDES.md, "Logs d'OpenCode").
// Any error leaves the command as it is: a "[[run ...]]" line left in the prompt is then run by the model itself.
import { execFile, spawn } from "node:child_process"
import { existsSync, readFileSync, statSync } from "node:fs"
import { homedir, tmpdir } from "node:os"
import { basename, isAbsolute, join, resolve, sep } from "node:path"

const HOME = homedir()
const SCRIPTS = join(HOME, ".config", "opencode", "scripts")
const RUN = /\[\[run ([a-z][a-z0-9-]*\.sh)((?: [^\n]*?)?)\]\]/g
const VISIBLE = /\n?\[\[visible\]\]\n?/
const TIMEOUT_MS = 180000
const MAX_OUTPUT = 32 * 1024 * 1024
// Commands of the pack that a multiple-choice answer may start (built-in OpenCode commands are never started)
const CHAINABLE = new Set(["go", "fix", "daily", "review", "compare", "outil"])
const CHOICE = /^\/([a-z][a-z0-9-]*)((?:\s+\S.*?)?)\s*(?:\((?:recommandé|recommended)\))?\s*$/i
// Progress in the title
const PROGRESS = /^(?:⏳|❓) [^—]*— /
// Outcome of the last /go or /fix of a session (10)
const OUTCOME = /^(?:✅|⛔) /
const DEFAULT_TITLE = /^(New session - |Child session - )\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
const TICK_MS = 5000
const SILENCE_MS = 30000
const DEFAULT_WAIT_MS = 90000
// Shell commands that set the environment or write a credential (point 6). An assignment starts a command (start of
// the text, after ; & | ( ` or a new line), possibly after export/declare/typeset/readonly/local/env and other
// assignments; quoted text is left out first, so that "token=null" in a commit message or "password=|secret=" in a
// search pattern is not one.
const ASSIGN = String.raw`(?:^|[;&|(\x60\n])\s*(?:(?:export|declare|typeset|readonly|local)\s+(?:-\w+\s+)*|env\s+(?:-\S+\s+)*)?(?:\w+=\S*\s+)*`
const SETS_ENVIRONMENT = new RegExp(ASSIGN + String.raw`(?:PATH|DOTNET_ROOT\w*)=`)
const SETS_SECRET = new RegExp(ASSIGN + String.raw`(?:\w*(?:PASSWORD|PASSWD|TOKEN|SECRET|API_?KEY|CREDENTIALS?)\w*|ARTIFACTORY\w*)=`, "i")
const QUOTED = /'[^']*'|"(?:[^"\\]|\\.)*"/g
// Commands that take minutes (8): a build or tests, a restore, the front-end tooling; the pack's git scripts
const LONG_COMMAND = /(?:^|[\s;&|(])(?:\S*build-test\.sh|dotnet\s+(?:build|test|restore|format|ef|clean)|npm\s+(?:test|ci|install|i|run\s+(?:test|build|lint))|npx\s+(?:jest|vitest|tsc|eslint|prettier|ng\s+(?:test|build|lint))|yarn\s+(?:test|install|build|lint)|pnpm\s+(?:test|install|build|lint))(?=\s|$|[;&|)])/
const GIT_SCRIPT = /(?:^|[\s;&|(])\S*(?:ship|branch)\.sh(?=\s|$)/
// A build tool called by its full path at the start of a command (11): ~/.bin/dotnet, $HOME/.dotnet/dotnet, /usr/bin/git
const TOOL_PATH = /(^\s*|[;&|(`\n]\s*)((?:~|\$\{HOME\}|\$HOME)?\/(?:[^\s;&|()<>'"`]*\/)?)(dotnet|node|npm|npx|yarn|pnpm|git)(?=$|[\s;&|)`])/g
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
const PACK_AGENTS = new Set(["pilot", "analyst", "coder", "checker", "debugger", "doc-writer"])
// agents that may read a reference or a folder I named through the shell (git log of another repository); the pilot,
// the coder and doc-writer read them with the file tools only
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
const READERS = new Set(["cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "ls", "wc", "file",
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
function shellOutside(command, cwd, root, readable, depth = 0) {
  let here = cwd
  let readsReadable = false
  let xargsRuns = ""
  for (const words of commandWords(String(command || ""))) {
    // the target of a redirection is written
    if (words.after === ">") {
      const target = pathOf(words[0], here) || resolve(here, words[0])
      if (DEVICES.has(target) || within(target, root)) continue
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
          const inner = shellOutside(word, here, root, readable, depth + 1)
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
function namedFolders(text, root) {
  const out = []
  for (const words of commandWords(String(text || ""))) {
    for (const word of words) {
      for (const raw of word.split(/\s+/)) {
        // a path at the end of a sentence: "~/repos/old-api," or "(~/repos/old-api)"
        const piece = raw.replace(/^[(«"']+/, "").replace(/[),.;:!?»"']+$/, "")
        const target = pathOf(piece, root) || (isAbsolute(piece) ? resolve(piece) : undefined)
        if (!target || target === "/" || target === HOME || within(target, root)) continue
        try {
          const info = statSync(target)
          out.push(info.isDirectory() ? target : resolve(target, ".."))
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
      const match = CHOICE.exec(String(label).trim())
      // OpenCode runs the !`...` of a command's arguments: an option that would run something is never started
      if (match && CHAINABLE.has(match[1].toLowerCase()) && !/[`$]/.test(match[2])) {
        return { command: match[1].toLowerCase(), arguments: match[2].trim() }
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
        env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
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

// "<repository folder> · branche <branch>" of the session's project, or "" outside a git repository
function where(cwd) {
  const git = (args) =>
    new Promise((resolve) => {
      execFile("git", args, { cwd, timeout: 5000 }, (error, stdout) => resolve(error ? "" : String(stdout).trim()))
    })
  return Promise.all([git(["rev-parse", "--show-toplevel"]), git(["symbolic-ref", "--short", "-q", "HEAD"])]).then(
    async ([root, branch]) => {
      if (!root) return ""
      const name = branch ? "branche " + branch : "HEAD détachée " + (await git(["rev-parse", "--short", "HEAD"]))
      return basename(root) + " · " + name
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

// "⏳ 1:42 réflexion 2,3k tokens" for a run of a session
function progressLabel(state, now) {
  const elapsed = clock(now - state.start)
  if (state.phase === "question") return "❓ " + elapsed + " réponse attendue"
  if (state.phase === "permission") return "❓ " + elapsed + " autorisation attendue"
  if (state.phase === "preparing") return "⏳ " + elapsed + " préparation"
  if (state.phase === "tool") return "⏳ " + elapsed + " outil · " + state.tool
  if (state.phase === "retry") return "⏳ " + elapsed + " nouvel essai " + state.attempt + " (serveur du modèle)"
  const quiet = now - state.last
  if (quiet > SILENCE_MS) return "⏳ " + elapsed + " rien reçu depuis " + Math.round(quiet / 1000) + " s"
  if (state.phase === "reasoning") return "⏳ " + elapsed + " réflexion " + tokens(state.chars) + " tokens"
  if (state.phase === "text") return "⏳ " + elapsed + " rédaction " + tokens(state.chars) + " tokens"
  return "⏳ " + elapsed + " attente du modèle"
}

// What a running tool part is doing, in a few words
function toolText(part) {
  const state = part.state || {}
  const input = state.input || {}
  const text =
    state.title ||
    input.description ||
    (input.filePath && basename(String(input.filePath))) ||
    input.pattern ||
    part.tool ||
    "outil"
  return String(text).replace(/\s+/g, " ").trim().slice(0, 40)
}

export const CompactCommands = async (input) => {
  const directory = (input && (input.directory || input.worktree)) || process.cwd()
  const client = input && input.client
  // the repository of this instance: its git root (OpenCode gives "/" as the worktree of a folder outside git)
  const root = resolve(input && input.worktree && input.worktree !== "/" ? input.worktree : directory)
  // session id -> name of the agent of its last request to the model (7)
  const agents = new Map()
  // session id -> parent session id, "" for a top-level session (7)
  const parents = new Map()
  // session id -> folders outside the repository that I named in that session (7)
  const named = new Map()
  // session id -> the /go or /fix that runs in it (9, 10)
  const pilots = new Map()
  // sessions whose /go or /fix was refused: no tool runs in their turn (9)
  const refused = new Set()
  let references
  // session id -> the command chosen in its last multiple-choice question, started when the session becomes idle
  const chosen = new Map()
  // session id -> progress of its current turn (5)
  const runs = new Map()
  const children = new Set()
  let ticker

  async function startChosen(sessionID) {
    const next = chosen.get(sessionID)
    if (!next || !client) return
    chosen.delete(sessionID)
    const session = await client.session.get({ path: { id: sessionID } })
    if (!session || !session.data || session.data.parentID) return
    // the turn that asked must have ended normally: no error, not stopped
    const recent = await client.session.messages({ path: { id: sessionID }, query: { limit: 4 } })
    const last = (Array.isArray(recent && recent.data) ? recent.data : [])
      .map((message) => message && message.info)
      .filter((info) => info && info.role === "assistant")
      .sort((a, b) => ((a.time && a.time.created) || 0) - ((b.time && b.time.created) || 0))
      .pop()
    if (!last || last.error) return
    client.session
      .command({ path: { id: sessionID }, body: { command: next.command, arguments: next.arguments } })
      .catch(() => {})
  }

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
    const shared = [...PACK_DIRS, ...SAVED_OUTPUTS]
    if (tool === "bash") {
      const extra = SHELL_READERS.has(agent) || !PACK_AGENTS.has(agent) ? [...(await referenceFolders()), ...(await namedIn(sessionID))] : []
      const readable = [...shared, ...extra]
      if (!within(cwd, root) && !readable.some((dir) => within(cwd, dir))) return { piece: args.workdir }
      return shellOutside(args && args.command, cwd, root, readable)
    }
    const key = FILE_TOOLS[tool]
    if (!key || !PACK_AGENTS.has(agent)) return null
    const value = args && args[key]
    if (typeof value !== "string" || !value) return null
    const target = value === "~" || value.startsWith("~/") ? join(HOME, value.slice(2)) : resolve(directory, value)
    if (DEVICES.has(target) || within(target, root)) return null
    const readable = [...shared, PACKAGE_CACHE, ...(await referenceFolders()), ...(await namedIn(sessionID))]
    const inReadable = readable.some((dir) => within(target, dir))
    // the agents of the pack write only in the repository
    if (tool === "write" || tool === "edit") return { piece: value, readOnly: inReadable }
    return inReadable ? null : { piece: value }
  }

  // Each refusal of the plugin goes to OpenCode's log ("refused by the pack"): the agent, the tool, the reason, the path,
  // never the command (it may hold a credential)
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

  // ---------- 9 and 10. one /go or /fix at a time, and its outcome in the title ----------
  async function markOutcome(sessionID, failed) {
    if (!pilots.has(sessionID) || !client) return
    pilots.delete(sessionID)
    try {
      let mark = failed ? "⛔ " : ""
      if (!mark) {
        const recent = await client.session.messages({ path: { id: sessionID }, query: { limit: 6 } })
        const last = (Array.isArray(recent && recent.data) ? recent.data : [])
          .filter((message) => message && message.info && message.info.role === "assistant")
          .sort((a, b) => ((a.info.time && a.info.time.created) || 0) - ((b.info.time && b.info.time.created) || 0))
          .pop()
        if (!last) return
        if (last.info.error) mark = "⛔ "
        else {
          const text = (last.parts || []).filter((part) => part && part.type === "text").map((part) => part.text).join("\n")
          // a stop wins over everything else of the answer (a table of done steps may hold ✅ before it)
          if (text.includes("⛔")) mark = "⛔ "
          else if (/🚀|🔁|✅/u.test(text)) mark = "✅ "
        }
      }
      if (!mark) return
      const info = (await client.session.get({ path: { id: sessionID } })).data
      if (!info || info.parentID) return
      const title = (info.title || "").replace(PROGRESS, "").replace(OUTCOME, "")
      await client.session.update({ path: { id: sessionID }, body: { title: mark + title } })
    } catch {
      // the title stays as it is
    }
  }

  // ---------- 5. progress in the session title ----------
  function track(sessionID, phase) {
    if (!client || !sessionID || children.has(sessionID)) return undefined
    let state = runs.get(sessionID)
    if (!state) {
      const now = Date.now()
      state = { start: now, last: now, chars: 0, phase: "waiting", tool: "", attempt: 0, kinds: new Map() }
      runs.set(sessionID, state)
      if (!ticker) {
        ticker = setInterval(() => {
          if (runs.size === 0) {
            clearInterval(ticker)
            ticker = undefined
            return
          }
          for (const [id, item] of runs) void show(id, item)
        }, TICK_MS)
        if (ticker && typeof ticker.unref === "function") ticker.unref()
      }
    }
    if (phase) state.phase = phase
    return state
  }

  async function show(sessionID, state) {
    if (state.writing || state.done) return
    state.writing = true
    try {
      const info = (await client.session.get({ path: { id: sessionID } })).data
      if (!info) return
      if (info.parentID) {
        children.add(sessionID)
        runs.delete(sessionID)
        return
      }
      const current = info.title || ""
      // a title written by someone else (OpenCode's title generation, a rename) becomes the one to come back to
      if (current !== state.written) state.original = current.replace(PROGRESS, "").replace(OUTCOME, "")
      const now = Date.now()
      if (DEFAULT_TITLE.test(state.original) && state.phase !== "preparing" && now - state.start < DEFAULT_WAIT_MS) return
      const title = progressLabel(state, now) + " — " + state.original
      if (title === current) return
      await client.session.update({ path: { id: sessionID }, body: { title } })
      state.written = title
    } catch {
      // the title stays as it is
    } finally {
      state.writing = false
    }
  }

  async function restore(sessionID, state) {
    for (let i = 0; i < 30 && state.writing; i++) await new Promise((resolve) => setTimeout(resolve, 100))
    if (!state.written || state.original === undefined) return
    try {
      const info = (await client.session.get({ path: { id: sessionID } })).data
      if (info && info.title === state.written) {
        await client.session.update({ path: { id: sessionID }, body: { title: state.original } })
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
    await restore(sessionID, state)
  }

  function progressEvent(event) {
    const props = event.properties || {}
    switch (event.type) {
      case "session.status": {
        const type = props.status && props.status.type
        if (type === "busy") track(props.sessionID)
        else if (type === "retry") {
          const state = track(props.sessionID, "retry")
          if (state) {
            state.attempt = props.status.attempt || state.attempt + 1
            state.last = Date.now()
          }
        } else if (type === "idle") {
          refused.delete(props.sessionID)
          void finish(props.sessionID).then(() => markOutcome(props.sessionID, false))
        }
        return
      }
      case "session.idle":
      case "session.error": {
        refused.delete(props.sessionID)
        const failed = event.type === "session.error"
        void finish(props.sessionID).then(() => markOutcome(props.sessionID, failed))
        return
      }
      case "message.part.updated": {
        const part = props.part
        const state = part && runs.get(part.sessionID)
        if (!state) return
        state.last = Date.now()
        state.kinds.set(part.id, part.type)
        if (part.type === "reasoning") state.phase = "reasoning"
        else if (part.type === "text") state.phase = "text"
        else if (part.type === "tool") {
          const status = part.state && part.state.status
          if (part.tool === "question") return
          if (status === "running" || status === "pending") {
            state.phase = "tool"
            state.tool = toolText(part)
          } else if (state.phase === "tool") state.phase = "waiting"
        }
        return
      }
      case "message.part.delta": {
        const state = runs.get(props.sessionID)
        if (!state) return
        state.last = Date.now()
        state.chars += String(props.delta || "").length
        const kind = state.kinds.get(props.partID)
        if (kind === "reasoning") state.phase = "reasoning"
        else if (kind === "text") state.phase = "text"
        return
      }
      case "question.asked":
      case "permission.asked": {
        const state = runs.get(props.sessionID)
        if (!state) return
        state.phase = event.type === "question.asked" ? "question" : "permission"
        void show(props.sessionID, state)
        return
      }
      case "question.replied":
      case "question.rejected":
      case "permission.replied": {
        const state = runs.get(props.sessionID)
        if (!state) return
        state.phase = "waiting"
        state.last = Date.now()
        return
      }
    }
  }

  // A title left with a progress prefix (OpenCode stopped during a turn) gets its own title back
  if (client) {
    const cleanup = setTimeout(async () => {
      try {
        const list = (await client.session.list()).data || []
        for (const info of list) {
          if (info && !info.parentID && PROGRESS.test(info.title || "") && !runs.has(info.id)) {
            await client.session.update({ path: { id: info.id }, body: { title: info.title.replace(PROGRESS, "") } })
          }
        }
      } catch {
        // nothing to clean
      }
    }, 15000)
    if (cleanup && typeof cleanup.unref === "function") cleanup.unref()
  }

  return {
    "chat.params": async (request) => {
      try {
        if (request && request.sessionID && request.agent) agents.set(request.sessionID, request.agent)
      } catch {
        // nothing to remember
      }
    },
    "chat.message": async (message, output) => {
      try {
        // folders I name in a message I type in a top-level session (never the prompt that an agent writes to a
        // subagent, never the expanded text of a command)
        if (!message || !message.sessionID || !output || !Array.isArray(output.parts)) return
        if (await parentOf(message.sessionID)) return
        for (const part of output.parts) {
          if (part && part.type === "text" && !part.synthetic && typeof part.text === "string") addNamed(message.sessionID, part.text)
        }
      } catch {
        // nothing named
      }
    },
    "tool.execute.before": async (call, output) => {
      if (!call || !output || !output.args) return
      if (refused.has(call.sessionID)) {
        throw new Error("Refused by the pack: this /go or /fix was refused (another one runs in this repository). Answer with the sentence of the request only.")
      }
      if (call.tool === "bash" && typeof output.args.command === "string") {
        // 11. a build tool called by its full path runs by its name: the rules of the agents know `dotnet build`, not
        // `/home/me/.bin/dotnet build`, and the folder of the tool is outside the repository
        output.args.command = output.args.command.replace(TOOL_PATH, "$1$3")
      }
      if (call.tool === "bash") {
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
      let outside = null
      try {
        outside = await escape(call.tool, call.sessionID, output.args)
      } catch {
        outside = null
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
        const need = LONG_COMMAND.test(output.args.command) ? 20 * 60000 : GIT_SCRIPT.test(output.args.command) ? 5 * 60000 : 0
        if (need && !(Number(output.args.timeout) >= need)) output.args.timeout = need
      }
    },
    "tool.execute.after": async (call, result) => {
      try {
        if (!call || call.tool !== "question" || !client) return
        const next = chosenCommand(result && result.metadata && result.metadata.answers)
        if (next) chosen.set(call.sessionID, next)
      } catch {
        // no command to start
      }
    },
    event: async ({ event }) => {
      try {
        if (!event || !event.properties) return
        progressEvent(event)
        const sessionID = event.properties.sessionID
        if (!sessionID || !chosen.has(sessionID)) return
        if (event.type === "session.error") chosen.delete(sessionID)
        else if (event.type === "session.idle") await startChosen(sessionID)
      } catch {
        // never start a command after a failure
      }
    },
    "command.execute.before": async (command, output) => {
      const parts = output && output.parts
      if (!Array.isArray(parts)) return
      const sessionID = command && command.sessionID
      // 9. one /go or /fix at a time in this repository. A hook that throws would only show "Unexpected server error":
      // the command is replaced by a request to say why it is refused, and every tool of that turn is refused.
      if (command && (command.command === "go" || command.command === "fix") && sessionID) {
        let other
        for (const [id, run] of pilots) if (id !== sessionID && Date.now() - run.start < 8 * 3600000) other = run
        if (other) {
          const notice =
            "⛔ /" + command.command + " refusé : /" + other.command + " tourne déjà sur ce dépôt dans la session « " +
            other.title + " ». Un seul /go ou /fix à la fois par dépôt : deux pilotes dans le même dossier " +
            "mélangeraient leurs commits. Relance-le quand l'autre aura fini (titre ✅ ou ⛔), ou arrête l'autre."
          logRefusal({ sessionID, tool: "/" + command.command, agent: "pilot" }, "another /" + other.command + " runs in this repository")
          refused.add(sessionID)
          parts.length = 0
          parts.push({ type: "text", text: ("/" + command.command + " " + (command.arguments || "")).trim() })
          parts.push({
            type: "text",
            synthetic: true,
            text: "The pack refused this command before it started: another /go or /fix runs in this repository. " +
              "Answer with exactly the sentence below, as it is, and nothing else; call no tool.\n\n" + notice,
          })
          return
        }
        let title = sessionID
        try {
          const info = client && (await client.session.get({ path: { id: sessionID } })).data
          if (info && info.title) title = info.title.replace(PROGRESS, "").replace(OUTCOME, "")
        } catch {
          // the id names it
        }
        pilots.set(sessionID, { command: command.command, start: Date.now(), title })
      }
      try {
        // 7. a folder outside the repository named in the arguments of a command may be read in this session
        if (sessionID && command && command.arguments) addNamed(sessionID, command.arguments)
      } catch {
        // nothing named
      }
      let state
      try {
        state = track(sessionID, "preparing")
        if (state) await show(sessionID, state)
      } catch {
        // no progress title
      }
      try {
        for (const part of parts) {
          if (part && part.type === "text" && typeof part.text === "string") {
            part.text = await resolveRuns(part.text, directory)
          } else if (part && part.type === "subtask" && typeof part.prompt === "string") {
            part.prompt = await resolveRuns(part.prompt, directory)
          }
        }
      } catch {
        // keep the lines: the model runs them
      }
      try {
        if (state) {
          state.phase = "waiting"
          state.last = Date.now()
          // a new session gets its default title back before the turn starts, so that OpenCode generates its title
          if (state.written && DEFAULT_TITLE.test(state.original || "")) await restore(sessionID, state)
        }
      } catch {
        // the title stays as it is
      }
      try {
        const prompt = parts.find((part) => part && part.type === "text" && !part.synthetic)
        if (!prompt) return
        const split = VISIBLE.exec(prompt.text)
        if (split) {
          // what is above [[visible]] is shown as my message, the rest only goes to the model
          const shown = prompt.text.slice(0, split.index).trim()
          prompt.text = prompt.text.slice(split.index + split[0].length).trim()
          prompt.synthetic = true
          parts.unshift({ type: "text", text: shown || "/" + command.command })
          return
        }
        prompt.synthetic = true
        const label = ("/" + command.command + " " + (command.arguments || "")).trim()
        const place = await where(directory).catch(() => "")
        const due = reminders()
        const reminder = due > 0 ? " · ⏰ " + due + (due > 1 ? " rappels" : " rappel") : ""
        parts.unshift({ type: "text", text: (place ? label + " — " + place : label) + reminder })
      } catch {
        // keep the command as it is
      }
    },
    "shell.env": async (shell, output) => {
      try {
        // Only the commands of the agents (they have a call id), not the terminal of the web interface
        if (!shell || !shell.callID || !output || !output.env) return
        const env = output.env
        const set = (name, value) => {
          if (process.env[name] === undefined && env[name] === undefined) env[name] = value
        }
        set("DOTNET_CLI_UI_LANGUAGE", "en")
        set("DOTNET_NOLOGO", "1")
        set("DOTNET_CLI_TELEMETRY_OPTOUT", "1")
        set("MSBUILDTERMINALLOGGER", "off")
        set("NPM_CONFIG_UPDATE_NOTIFIER", "false")
        set("NPM_CONFIG_FUND", "false")
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
