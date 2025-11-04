#!/usr/bin/env bash
set -euo pipefail

PORT=8080
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$REPO_ROOT/socks"
LOG="$REPO_ROOT/.test.log"
HEX_CMD=()
ECHO_PORT=9090
PYTHON_CMD="${PYTHON_CMD:-}"

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if command -v hexdump >/dev/null 2>&1; then
  HEX_CMD=(hexdump -v -e '/1 "%02x"')
elif command -v xxd >/dev/null 2>&1; then
  HEX_CMD=(xxd -p)
elif command -v od >/dev/null 2>&1; then
  HEX_CMD=(od -An -tx1)
else
  echo "missing hex tool: install hexdump, xxd, or od" >&2
  exit 1
fi

if [[ -n "$PYTHON_CMD" ]]; then
  if ! command -v "$PYTHON_CMD" >/dev/null 2>&1; then
    echo "python interpreter '$PYTHON_CMD' not found" >&2
    exit 1
  fi
else
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
  elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
  else
    echo "missing python interpreter: install python3 or python" >&2
    exit 1
  fi
fi

echo "[*] building..."
make -s -C "$REPO_ROOT" clean
make -s -C "$REPO_ROOT"

[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }

echo "[*] starting server on :$PORT"
"$BIN" -p "$PORT" -s >"$LOG" 2>&1 &
PID=$!
sleep 0.5

if ! ps -p "$PID" >/dev/null; then
  echo "server not running"
  cat "$LOG"
  exit 1
fi

echo "[*] checking port"
nc -z 127.0.0.1 "$PORT" || { echo "port closed"; exit 1; }

echo "[*] socks5 handshake"
resp=$(printf '\x05\x01\x00' | nc 127.0.0.1 "$PORT" -w 1 | "${HEX_CMD[@]}" | tr -d ' \n')
[[ "$resp" == "0500" ]] && echo "[ok] handshake" || echo "[warn] bad handshake ($resp)"

echo "[*] socks5 connect + proxy data"
"$PYTHON_CMD" "$SCRIPT_DIR/proxy_test.py" "$PORT" "$ECHO_PORT"

cleanup
echo "[done]"
