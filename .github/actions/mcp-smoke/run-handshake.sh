#!/usr/bin/env bash
# run-handshake.sh — MCP initialize handshake smoke test
#
# Bundled with the mcp-smoke composite action (Hakanai-AI/.github).
# Extracted from claude-plugin-line/hack/mcp-smoke.sh (ops#342 canary).
# Called by action.yml after the binary is already built.
#
# Required env:
#   BINARY      — path to the pre-built plugin binary
#   MCP_TIMEOUT — seconds to wait for the first response line
#
# Caller's job env must supply dummy plugin-specific env vars
# (e.g. LINE_CHANNEL_ACCESS_TOKEN, DISCORD_BOT_TOKEN) before running the action.
set -euo pipefail

INIT_REQUEST='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0.0.1"}}}'

STDERR_TMP="$(mktemp -t mcp-smoke-stderr-XXXXXX)"
cleanup() { rm -f "$STDERR_TMP"; }
trap cleanup EXIT

echo "[smoke] running: $BINARY --stdio (timeout ${MCP_TIMEOUT}s)"

EXIT_CODE=0
RESPONSE=$(
    printf '%s\n' "$INIT_REQUEST" \
    | timeout "$MCP_TIMEOUT" "$BINARY" --stdio 2>"$STDERR_TMP" \
    | grep -m1 '^{'
) || EXIT_CODE=$?
# grep -m1 exits after first match; binary gets SIGPIPE (141) or timeout (124).

STDERR_CONTENT="$(cat "$STDERR_TMP" 2>/dev/null || true)"

if echo "$STDERR_CONTENT" | grep -q "^panic:"; then
    echo "[smoke] FAIL: panic detected in stderr:"
    echo "$STDERR_CONTENT" | grep "^panic:" | head -5
    exit 1
fi

if echo "$STDERR_CONTENT" | grep -q "flag provided but not defined"; then
    echo "[smoke] FAIL: unrecognised CLI flag:"
    echo "$STDERR_CONTENT" | grep "flag provided but not defined"
    exit 1
fi

# Accept: 0 (clean exit on stdin EOF), 124 (timeout after response), 141 (SIGPIPE from grep -m1).
if [[ $EXIT_CODE -ne 0 && $EXIT_CODE -ne 124 && $EXIT_CODE -ne 141 ]]; then
    echo "[smoke] FAIL: binary exited with unexpected code $EXIT_CODE"
    echo "[smoke] stderr:"
    echo "$STDERR_CONTENT"
    exit 1
fi

if [[ -z "$RESPONSE" ]]; then
    echo "[smoke] FAIL: no response received within ${MCP_TIMEOUT}s"
    echo "[smoke] stderr:"
    echo "$STDERR_CONTENT"
    exit 1
fi

echo "[smoke] response: $RESPONSE"

PROTOCOL_VERSION=$(printf '%s' "$RESPONSE" | python3 -c "
import sys, json
raw = sys.stdin.read()
try:
    obj = json.loads(raw)
except Exception as e:
    print(f'not valid JSON: {e}', file=sys.stderr)
    sys.exit(1)
if obj.get('jsonrpc') != '2.0':
    print(f\"missing jsonrpc:2.0, got {obj.get('jsonrpc')!r}\", file=sys.stderr)
    sys.exit(1)
if 'result' not in obj:
    print(f\"missing result field; got keys: {list(obj)}\", file=sys.stderr)
    sys.exit(1)
pv = obj['result'].get('protocolVersion')
if not pv:
    print('missing result.protocolVersion', file=sys.stderr)
    sys.exit(1)
print(pv)
") || {
    echo "[smoke] FAIL: invalid MCP initialize response (see above)"
    exit 1
}

echo "[smoke] PASS: MCP initialize OK — protocolVersion=${PROTOCOL_VERSION}"
