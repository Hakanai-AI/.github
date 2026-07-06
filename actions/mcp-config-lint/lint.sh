#!/usr/bin/env bash
# ops#337 — static guard on a plugin .mcp.json against the canonical launcher
# pattern. See action.yml for the four assertions. Exits non-zero on any
# violation, emitting ::error:: annotations.
set -euo pipefail

F="${1:-.mcp.json}"

if [[ ! -f "$F" ]]; then
  echo "::notice::no $F present at '$F' — nothing to lint"
  exit 0
fi

if ! jq empty "$F" 2>/dev/null; then
  echo "::error::$F is not valid JSON"
  exit 1
fi

# Servers may live under .mcpServers (plugin form) or top-level (rare). Use
# .mcpServers; if absent, there is nothing this guard applies to.
if ! jq -e '.mcpServers' "$F" >/dev/null 2>&1; then
  echo "::notice::$F has no .mcpServers object — nothing to lint"
  exit 0
fi

fail=0
while IFS= read -r s; do
  [[ -z "$s" ]] && continue

  cmd=$(jq -r --arg s "$s" '.mcpServers[$s].command // ""' "$F")
  if [[ "$cmd" != "node" ]]; then
    echo "::error::$F [$s]: command must be 'node' (got '$cmd') — ops#337"
    fail=1
  fi

  arg0=$(jq -r --arg s "$s" '.mcpServers[$s].args[0] // ""' "$F")
  if [[ "$arg0" != *launcher.mjs ]]; then
    echo "::error::$F [$s]: args[0] must be the per-plugin launcher.mjs (got '$arg0') — ops#337"
    fail=1
  fi

  # The archived Go launcher must never be referenced anywhere in command/args.
  if jq -e --arg s "$s" \
      '([.mcpServers[$s].command] + (.mcpServers[$s].args // [])) | any(test("claude-plugin-launcher"))' \
      "$F" >/dev/null; then
    echo "::error::$F [$s]: references the archived 'claude-plugin-launcher' Go binary — use node launcher.mjs — ops#337"
    fail=1
  fi

  # env must be empty: config comes from the plugin's own dotenv, not .mcp.json.
  envcount=$(jq -r --arg s "$s" '(.mcpServers[$s].env // {}) | length' "$F")
  if [[ "$envcount" != "0" ]]; then
    keys=$(jq -r --arg s "$s" '.mcpServers[$s].env | keys | join(", ")' "$F")
    echo "::error::$F [$s]: env must be {} — config belongs in the plugin's own dotenv (~/.claude/channels/<plugin>/.env), not .mcp.json env injection (got: $keys) — ops#337"
    fail=1
  fi
done < <(jq -r '.mcpServers | keys[]' "$F")

if [[ "$fail" == "1" ]]; then
  echo "::error::mcp-config-lint failed — see ops#337 canonical launcher pattern"
  exit 1
fi

echo "mcp-config-lint: OK — every server uses 'node <launcher.mjs>' with env {}"
