# OpenCode shortcuts: run commands from the terminal without opening the OpenCode UI.
# Usage: add `source ~/opencode-pack/scripts/oc-aliases.zsh` to ~/.zshrc, then open a new terminal.
# Run them from the root of a repository.

alias oc-review='opencode run --command review'
alias oc-review-branch='opencode run --command review-branch'
alias oc-commit-msg='opencode run --command commit-msg'
alias oc-fortify='opencode run --command fortify'
alias oc-quality='opencode run --command quality'
alias oc-daily='opencode run --command daily'

# Prepare work on a Jira ticket: oc-ticket ABC-123
oc-ticket() {
  if [ -z "$1" ]; then
    echo "Usage: oc-ticket <JIRA-KEY>"
    return 1
  fi
  opencode run --command start-ticket "$1"
}
