#!/usr/bin/env bash
# PreToolUse: block writes that would commit a plaintext secret.
# Exit 2 = block the tool call (message on stderr is shown to Claude).
set -uo pipefail
input=$(cat)
f=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[ -z "$f" ] && exit 0
case "$f" in
  *settings.local.json)
    echo "Blocked: settings.local.json holds local credentials — edit it manually, not via Claude." >&2
    exit 2 ;;
  *.env)
    echo "Blocked: '$f' is an env file. Route secrets through External Secrets + OpenBao." >&2
    exit 2 ;;
esac
# Judge the content, not the name: a `kind: Secret` with data is plaintext
# wherever it lives. ExternalSecrets have `kind: ExternalSecret` and pass.
body=$(jq -r '.tool_input.content // .tool_input.new_string // empty' <<<"$input")
if grep -Eq '^\s*kind:\s*Secret\s*$' <<<"$body" && grep -Eq '^\s*(data|stringData):' <<<"$body"; then
  echo "Blocked: '$f' contains a kind: Secret with data. Use an ExternalSecret + OpenBao; confirm manually if intentional." >&2
  exit 2
fi
exit 0
