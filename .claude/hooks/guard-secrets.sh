#!/usr/bin/env bash
# PreToolUse: block edits to credential-bearing / local config files.
# Exit 2 = block the tool call (message on stderr is shown to Claude).
set -uo pipefail
f=$(jq -r '.tool_input.file_path // empty')
[ -z "$f" ] && exit 0
case "$f" in
  # ExternalSecret / *store manifests are the reference layer (remoteRef
  # pointers into OpenBao, no plaintext) — allow.
  *externalsecret*|*external-secret*|*clustersecretstore*|*secretstore*)
    exit 0 ;;
  *settings.local.json)
    echo "Blocked: settings.local.json holds local credentials — edit it manually, not via Claude." >&2
    exit 2 ;;
  *Secret*.yaml|*secret.yaml|*secrets.yaml|*.env)
    echo "Blocked: '$f' looks secret-bearing. Route secrets through External Secrets + OpenBao; confirm manually if intentional." >&2
    exit 2 ;;
esac
exit 0
