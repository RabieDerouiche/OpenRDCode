#!/bin/sh
# The other repositories of the same application (AGENTS.md « Dépôts liés »: one line per repository, its name first,
# then optionally its path, then what links them), where they are on this machine, and what each says of a ticket:
# its branch for the key, its ticket sheet (<its git folder>/opencode-tickets/<KEY>.md), the « ## Contrat » section
# of that sheet (the routes, fields and public API the ticket changes there) and its last « ## Suivi » line (delivered?
# its merge request). Read-only: it never fetches, never checks out, never writes.
# A repository is found, in this order: at the path of the reference of the same name in opencode.json of this machine
# (each developer's own layout; /outil liens writes it), at the path its line gives between parentheses after its name
# (~ allowed): "- `front-factures` (`~/repos/front-factures`) : <role>", otherwise next to this one (the same parent
# folder as the main checkout). The agents read its files only when it is a reference of opencode.json (COMMANDES.md,
# « Lire un autre dépôt »); its ticket sheet, always.
# For /go and /fix: the analyst of the front plans on the contract of the back, the pilot says what the other
# repository has to follow.
# Usage: related-repos.sh [<KEY>]

key=$1
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "RELATED: none (not in a git repository)"; exit 0; }
agents="$root/AGENTS.md"
if [ ! -f "$agents" ]; then
  echo "RELATED: none (no AGENTS.md: its « ## Dépôts liés » section names the repositories of the same application)"
  exit 0
fi
lines=$(awk '/^## Dépôts liés/ { on = 1; next } /^## / { on = 0 } on && /^- / { sub(/^- */, ""); print }' "$agents")
if [ -z "$lines" ]; then
  echo "RELATED: none (AGENTS.md has no « ## Dépôts liés » section: /outil liens declares them)"
  exit 0
fi
# the references of opencode.json of this machine: "<name>\t<path>"
refs=$(sh "$(cd "$(dirname "$0")" && pwd)/related-setup.sh" references 2>/dev/null)
# the parent folder of the main checkout (a worktree of an OpenCode workspace is elsewhere)
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir)
case "$common" in /*) ;; *) common="$root/$common" ;; esac
main=$(dirname "$common")
parent=$(dirname "$main")

printf '%s\n' "$lines" | while IFS= read -r line; do
  name=$(printf '%s\n' "$line" | sed 's/`//g' | awk '{ print $1 }' | sed 's/[:,;]*$//')
  [ -n "$name" ] || continue
  # its path, between parentheses right after its name: "- `front-factures` (`~/repos/front-factures`) : …"
  path=$(printf '%s\n' "$line" | sed 's/`//g' | sed -n 's/^[^[:space:](]*[[:space:]]*(\([^)]*\)).*/\1/p' | sed 's/[[:space:]]*$//')
  # the reference of this machine wins over the path of the line (AGENTS.md is shared, the layouts of the machines are not)
  how="next to this repository"
  refpath=$(printf '%s\n' "$refs" | awk -F '\t' -v n="$name" '$1 == n { print $2; exit }')
  if [ -n "$refpath" ]; then path=$refpath how="reference of opencode.json"
  elif [ -n "$path" ]; then how="path of its line"
  fi
  # shellcheck disable=SC2088 # a literal ~ written in AGENTS.md is matched on purpose
  case "$path" in '~/'*) path="$HOME/${path#'~/'}" ;; '~') path=$HOME ;; esac
  [ -n "$path" ] || path="$parent/$name"
  role=$(printf '%s\n' "$line" | sed 's/`//g' | sed -n 's/^[^:]*:[[:space:]]*//p')
  if [ ! -d "$path" ]; then
    echo "RELATED: $name — not found at $path ($how): /outil liens finds it and declares where it is on this machine (a reference of opencode.json), or clone it next to this repository"
    continue
  fi
  if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "RELATED: $name — $path is not a git repository"
    continue
  fi
  where=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)
  current=$(git -C "$path" branch --show-current 2>/dev/null)
  echo "RELATED: $name — $where (branch ${current:-detached}; $how): ${role:-no role given}"
  [ -n "$key" ] || continue
  # (a pattern of for-each-ref never crosses a /: feature/ABC-123-x is found by its name)
  branch=$(git -C "$path" for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin 2>/dev/null | grep -F -- "$key" | grep -v '/HEAD$' | head -n 1)
  gitdir=$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  case "$gitdir" in /*) ;; *) gitdir="$where/${gitdir:-.git}" ;; esac
  sheet="$gitdir/opencode-tickets/$key.md"
  if [ ! -f "$sheet" ]; then
    echo "  $key there: ${branch:+branch $branch, }no ticket sheet (no /go of this ticket in that repository yet)"
    continue
  fi
  delivered=$(awk '/^## Suivi/ { on = 1; next } /^## / { on = 0 } on && /livré/ { last = $0 } END { print last }' "$sheet")
  echo "  $key there: ${branch:+branch $branch, }sheet $sheet${delivered:+; ${delivered#- }}"
  contract=$(awk '/^## Contrat/ { on = 1; next } /^## / { on = 0 } on && NF { print "    " $0 }' "$sheet")
  if [ -n "$contract" ]; then
    echo "  Contrat of $name for $key:"
    printf '%s\n' "$contract"
  else
    echo "  Contrat of $name for $key: none (its sheet has no « ## Contrat » section: the ticket changes nothing other repositories rely on there)"
  fi
done
exit 0
