// Shows only "/<command> <arguments>" in the conversation when a command runs. The expanded prompt (workflow state,
// ticket sheet, diffs) is still sent to the model, as a "synthetic" part that the web interface does not display.
// Any error leaves the command unchanged.
export const CompactCommands = async () => ({
  "command.execute.before": async (input, output) => {
    try {
      const parts = output && output.parts
      if (!Array.isArray(parts)) return
      const prompt = parts.find((part) => part && part.type === "text" && !part.synthetic)
      if (!prompt) return
      prompt.synthetic = true
      const label = ("/" + input.command + " " + (input.arguments || "")).trim()
      parts.unshift({ type: "text", text: label })
    } catch {
      // keep the command as it is
    }
  },
})
