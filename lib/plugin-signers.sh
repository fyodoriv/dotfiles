#!/bin/bash
# Plugin signers (issue #145, step 5). Shared with agentbrew (#208):
#
#   ${AGENT_PLUGINS_ALLOWED_SIGNERS:-${XDG_CONFIG_HOME:-~/.config}/agent-plugins/allowed_signers}
#
# The file uses git's gpg.ssh.allowedSignersFile format. The principal is
# the plugin name, so a key trusted for one plugin cannot sign another:
#
#   acme namespaces="git" ssh-ed25519 AAAA...
#
# Tags are checked with a scratch allowed-signers file that holds only this
# plugin's keys, so the user's own git config cannot widen trust.

plugin_signers_file() {
  printf '%s' "${AGENT_PLUGINS_ALLOWED_SIGNERS:-${XDG_CONFIG_HOME:-$HOME/.config}/agent-plugins/allowed_signers}"
}

# Prints "<keytype> <base64>" (no comment), or fails for anything else.
plugin_normalize_key() {
  local type b64
  read -r type b64 _ <<< "$1"
  case "$type" in ssh-* | ecdsa-* | sk-*) ;; *) return 1 ;; esac
  [[ "$b64" =~ ^[A-Za-z0-9+/=]+$ ]] || return 1
  printf '%s %s' "$type" "$b64"
}

# Prints the trusted keys for plugin "$1", one per line.
plugin_signers_for() {
  local file
  file="$(plugin_signers_file)"
  [ -f "$file" ] || return 0
  awk -v p="$1" '$1 == p {
      i = 2; if ($i ~ /^namespaces=/) i++
      if ($i != "" && $(i + 1) != "") print $i " " $(i + 1)
    }' "$file"
}

# plugin_trust_signer <name> <key>: idempotent.
plugin_trust_signer() {
  local name="$1" key file
  key="$(plugin_normalize_key "$2")" || { echo "not an SSH public key" >&2; return 1; }
  plugin_signers_for "$name" | grep -qxF -- "$key" && return 0
  file="$(plugin_signers_file)"
  mkdir -p "$(dirname "$file")"
  (umask 077; printf '%s namespaces="git" %s\n' "$name" "$key" >> "$file")
}

# plugin_revoke_signer <name> <key>: fails when the key was not trusted.
plugin_revoke_signer() {
  local name="$1" key file tmp
  key="$(plugin_normalize_key "$2")" || { echo "not an SSH public key" >&2; return 1; }
  plugin_signers_for "$name" | grep -qxF -- "$key" || { echo "signer is not trusted for $name" >&2; return 1; }
  file="$(plugin_signers_file)"
  tmp="$(mktemp "$file.XXXXXX")"
  awk -v p="$name" -v k="$key" '{
      i = 2; if ($i ~ /^namespaces=/) i++
      if ($1 == p && ($i " " $(i + 1)) == k) next
      print
    }' "$file" > "$tmp" && mv "$tmp" "$file"
}

_plugin_key_fingerprint() {
  local tmp fp
  tmp="$(mktemp)"
  printf '%s\n' "$1" > "$tmp"
  fp="$(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{ print $2 }')"
  rm -f "$tmp"
  printf '%s' "$fp"
}

# plugin_verify_signed_tag <dir> <ref> <name> [<extra key>...]: succeeds and
# prints the signing key when <ref> is an annotated tag signed by a key
# trusted for <name> (or one of the extra keys). Otherwise prints why.
plugin_verify_signed_tag() {
  local dir="$1" ref="$2" name="$3" keys scratch out fp key
  shift 3
  keys="$( { plugin_signers_for "$name"; for key in "$@"; do plugin_normalize_key "$key" && echo; done; } | sed '/^$/d' | sort -u)"
  [ -n "$keys" ] || { echo "no trusted signer for plugin $name; pass --signer <ssh-public-key>"; return 1; }
  [ "$(git -C "$dir" cat-file -t "refs/tags/$ref" 2>/dev/null)" = tag ] ||
    { echo "$ref is not a signed tag; plugins install only from signed tags"; return 1; }
  scratch="$(mktemp)"
  printf '%s\n' "$keys" | sed "s/^/$name namespaces=\"git\" /" > "$scratch"
  out="$(git -C "$dir" -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$scratch" verify-tag "$ref" 2>&1)" || {
    rm -f "$scratch"
    echo "tag $ref is not signed by a trusted signer for $name"
    return 1
  }
  rm -f "$scratch"
  fp="$(printf '%s' "$out" | grep -oE 'SHA256:[A-Za-z0-9+/=]+' | head -1)"
  while IFS= read -r key; do
    if [ "$(_plugin_key_fingerprint "$key")" = "$fp" ]; then
      printf '%s' "$key"
      return 0
    fi
  done <<< "$keys"
  echo "could not match the signing key of $ref to a trusted signer"
  return 1
}
