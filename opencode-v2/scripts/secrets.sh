#!/bin/sh
# Read by env-tests.sh and http-files.sh (`. secrets.sh`), never run: the value of a secret that AGENTS.md
# « ## Environnements » names, for these scripts only, never printed by them:
#   - `RECETTE_CLIENT_SECRET`: a variable of this machine (~/.zshenv, which OpenCode reads again at each command);
#   - `vault:<path>#<field>`: a secret of HashiCorp Vault, read with the vault CLI of this machine
#     (`vault kv get -field=<field> <path>`: KV version 1 or 2, its VAULT_ADDR, VAULT_NAMESPACE, VAULT_CACERT and the
#     token of `vault login`, as the developer set them). Nothing of Vault is ever printed: neither the secret nor the
#     token, nor what the CLI prints on success.
# secret_get <reference> <variable>   the value in that variable of the script (never on an output), exit 0; otherwise
#                            the variable empty, exit 1, and in $secret_why one sentence (English) that says why and
#                            what to do
# secret_where <reference>   the reference in words: "the variable X" or "Vault <path> (field <field>)"
# secret_ref_ok <reference>  exit 0 when it is a variable name or a vault:<path>#<field>
# The agents never run the vault CLI themselves (their rules refuse it): what it prints would reach the model.
# shellcheck disable=SC2034 # secret_why is read by the scripts that read this file
case "${0##*/}" in
  secrets.sh) echo "STOP: secrets.sh is read by env-tests.sh and http-files.sh, never run"; exit 1 ;;
esac

secret_why=""
secret_is_vault() {
  case "$1" in
    vault:?*'#'?*) return 0 ;;
  esac
  return 1
}
secret_ref_ok() {
  if secret_is_vault "$1"; then
    printf '%s' "${1#vault:}" | grep -q -E '^[A-Za-z0-9_./-]+#[A-Za-z0-9_.-]+$'
    return $?
  fi
  case "$1" in
    ''|*[!A-Za-z0-9_]*|[0-9]*) return 1 ;;
  esac
  return 0
}
secret_where() {
  if secret_is_vault "$1"; then
    s_r=${1#vault:}
    printf 'Vault %s (field %s)' "${s_r%%#*}" "${s_r#*#}"
  else
    printf 'the variable %s' "$1"
  fi
}
secret_get() {
  secret_why=""
  eval "$2=''"
  if ! secret_ref_ok "$1"; then
    secret_why="« $1 » is neither the name of a variable nor vault:<path>#<field>: /tests env config writes it again"
    return 1
  fi
  if ! secret_is_vault "$1"; then
    s_v=$(printenv "$1" 2>/dev/null)
    if [ -z "$s_v" ]; then
      secret_why="the variable $1 is not set in the environment of OpenCode: export $1='…' in ~/.zshenv (OpenCode reads ~/.zshenv again at each command: nothing to restart)"
      return 1
    fi
    eval "$2=\$s_v"
    s_v=""
    return 0
  fi
  s_r=${1#vault:}
  s_path=${s_r%%#*} s_field=${s_r#*#}
  if ! command -v vault > /dev/null 2>&1; then
    secret_why="the vault CLI of HashiCorp is not on the PATH of OpenCode's shell: install it on this machine (its VAULT_ADDR in ~/.zshenv), or keep this secret in a variable of ~/.zshenv"
    return 1
  fi
  s_err=$(mktemp "${TMPDIR:-/tmp}/secrets.XXXXXX") || { secret_why="no temporary file"; return 1; }
  # never a prompt (a login that would wait for a password): no terminal
  s_v=$(vault kv get -field="$s_field" "$s_path" 2> "$s_err" < /dev/null)
  s_status=$?
  s_text=$(tr '\n' ' ' < "$s_err" | sed 's/  */ /g')
  rm -f "$s_err"
  if [ "$s_status" -eq 0 ] && [ -n "$s_v" ]; then
    eval "$2=\$s_v"
    s_v=""
    return 0
  fi
  s_v=""
  s_addr=${VAULT_ADDR:-not set: the CLI calls https://127.0.0.1:8200}
  case "$s_text" in
    *"missing client token"*)
      secret_why="you are not logged in to Vault ($s_addr): vault login, in your terminal, as your Vault asks (OIDC, LDAP, a token)" ;;
    *"permission denied"*|*"Code: 403"*)
      # no token at all (none in the environment, no ~/.vault-token of vault login): Vault answers 403 as well
      if [ -z "${VAULT_TOKEN:-}" ] && [ ! -s "${HOME:-/nonexistent}/.vault-token" ] && [ ! -f "${VAULT_CONFIG_PATH:-${HOME:-/nonexistent}/.vault}" ]; then
        secret_why="you are not logged in to Vault ($s_addr): vault login, in your terminal, as your Vault asks (OIDC, LDAP, a token)"
      else
        secret_why="Vault refuses $s_path to your token ($s_addr): its policy does not give it, or the token expired (vault login again)"
      fi ;;
    *"No value found"*|*"Code: 404"*)
      secret_why="nothing in Vault at $s_path ($s_addr): the path of « $1 » in AGENTS.md (vault kv list <its folder> shows the paths), or a secret not put there yet" ;;
    *"not present in secret"*|*"not present"*)
      secret_why="Vault has $s_path but no field $s_field in it ($s_addr): the field after # in « $1 »" ;;
    *sealed*)
      secret_why="Vault is sealed ($s_addr): the team that runs it unseals it" ;;
    *x509*|*certificate*)
      secret_why="the certificate of Vault ($s_addr) is not trusted on this machine: VAULT_CACERT (the PEM file of its authority) in ~/.zshenv" ;;
    *"connection refused"*|*"no such host"*|*"dial tcp"*|*"i/o timeout"*|*"deadline exceeded"*|*"connect:"*)
      secret_why="Vault cannot be reached from this machine ($s_addr): VPN, or VAULT_ADDR in ~/.zshenv" ;;
    *)
      if [ "$s_status" -eq 0 ]; then
        secret_why="Vault gives an empty value at $s_path, field $s_field ($s_addr)"
      else
        secret_why="vault kv get answers: $(printf '%s' "$s_text" | sed 's/^ *//' | cut -c1-200) ($s_addr)"
      fi ;;
  esac
  return 1
}
