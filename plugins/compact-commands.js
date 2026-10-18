// OpenCode plugin of the pack: ~/.config/opencode/plugins/compact-commands.js (restart OpenCode after a change).
//
// 1. Runs the "[[run <script> <arguments>]]" lines of the pack's commands with the pack's scripts, in the folder of
//    the session's project. OpenCode 1.19 runs the !`...` injections of a command in the folder where the server
//    was started; `opencode web` serves every project from one server, so they described the wrong repository.
// 2. Gives every shell command of the agents a stable environment: English .NET messages, no .NET banner or
//    telemetry, no npm notices, file names printed by git as they are (no octal escapes), and git never waiting for
//    a password or an editor (a command that waits ends only at the 2-minute timeout). Other variables already set
//    in the environment are kept.
// 3. Shows only "/<command> <arguments>" in the conversation; the expanded prompt (workflow state, ticket sheet,
//    diffs) is still sent to the model, as a "synthetic" part that the web interface does not display.
// Any error leaves the command as it is: a "[[run ...]]" line left in the prompt is then run by the model itself.
import { execFile } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const SCRIPTS = join(homedir(), ".config", "opencode", "scripts")
const RUN = /\[\[run ([a-z][a-z0-9-]*\.sh)((?: [^\]\n]*)?)\]\]/g
const TIMEOUT_MS = 180000

// Splits the arguments like a shell does for simple quoting ('...' and "..."), without any expansion: the
// arguments typed after a command can never run anything.
function words(text) {
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

function run(script, args, cwd) {
  return new Promise((resolve) => {
    execFile(
      "sh",
      [join(SCRIPTS, script), ...words(args)],
      { cwd, timeout: TIMEOUT_MS, maxBuffer: 32 * 1024 * 1024 },
      (error, stdout, stderr) => {
        const text = String(stdout || "").replace(/\s+$/, "")
        if (text || !error) return resolve(text)
        resolve(script + " failed: " + String(stderr || error.message).trim().split("\n")[0])
      },
    )
  })
}

async function resolveRuns(text, cwd) {
  const found = [...text.matchAll(RUN)]
  if (found.length === 0) return text
  const outputs = await Promise.all(found.map((m) => run(m[1], m[2], cwd)))
  let i = 0
  return text.replace(RUN, () => outputs[i++])
}

export const CompactCommands = async (input) => {
  const directory = (input && (input.directory || input.worktree)) || process.cwd()
  return {
    "command.execute.before": async (command, output) => {
      const parts = output && output.parts
      if (!Array.isArray(parts)) return
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
        const prompt = parts.find((part) => part && part.type === "text" && !part.synthetic)
        if (!prompt) return
        prompt.synthetic = true
        const label = ("/" + command.command + " " + (command.arguments || "")).trim()
        parts.unshift({ type: "text", text: label })
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
