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
// Any error leaves the command as it is: a "[[run ...]]" line left in the prompt is then run by the model itself.
import { execFile, spawn } from "node:child_process"
import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { basename, join } from "node:path"

const SCRIPTS = join(homedir(), ".config", "opencode", "scripts")
const RUN = /\[\[run ([a-z][a-z0-9-]*\.sh)((?: [^\n]*?)?)\]\]/g
const VISIBLE = /\n?\[\[visible\]\]\n?/
const TIMEOUT_MS = 180000
const MAX_OUTPUT = 32 * 1024 * 1024
// Commands of the pack that a multiple-choice answer may start (built-in OpenCode commands are never started)
const CHAINABLE = new Set(["go", "fix", "daily", "review", "compare", "outil"])
const CHOICE = /^\/([a-z][a-z0-9-]*)((?:\s+\S.*?)?)\s*(?:\((?:recommandé|recommended)\))?\s*$/i
// Progress in the title
const PROGRESS = /^(?:⏳|❓) [^—]*— /
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
// A user and a password in a URL (https://user:token@host), in curl/wget -u, or in a NuGet source
const SECRET_IN_URL = /\b(?:https?|ssh|git|ftp):\/\/[\w.%-]+:[^\s/@*]+@/i
const SECRET_IN_OPTION = /\b(?:curl|wget)\b[^\n]*\s(?:-u|--user)\s*[\w.%-]+:\S|\bdotnet\s+nuget\s+(?:add|update)\s+source\b[^\n]*(?:\s-p\s|--password)/i

// Why a shell command of an agent is refused (point 6), or ""
function refusal(command) {
  const text = String(command || "")
  const unquoted = text.replace(QUOTED, "''")
  if (SETS_ENVIRONMENT.test(unquoted)) return "it sets PATH or DOTNET_ROOT"
  if (SETS_SECRET.test(unquoted) || SECRET_IN_URL.test(text) || SECRET_IN_OPTION.test(text)) return "it writes a credential"
  return ""
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
      if (current !== state.written) state.original = current.replace(PROGRESS, "")
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
        } else if (type === "idle") void finish(props.sessionID)
        return
      }
      case "session.idle":
      case "session.error":
        void finish(props.sessionID)
        return
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
    "tool.execute.before": async (call, output) => {
      if (!call || call.tool !== "bash" || !output || !output.args) return
      const why = refusal(output.args.command)
      if (why) {
        throw new Error(
          "Refused by the pack: " + why + ". A command never sets PATH, DOTNET_ROOT or a credential: the environment of " +
            "the agents comes from ~/.zshenv, and a credential written in a command stays in the session history. If " +
            "dotnet is missing or Artifactory refuses access, it is an ENVIRONMENT PROBLEM: tell the user in one line " +
            "and stop. Never try another form of this command.",
        )
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
