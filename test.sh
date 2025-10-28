#!/usr/bin/env bash
set -euo pipefail

PORT=8080
BIN=./socks
LOG=.test.log

cleanup() {
  [[ -n "${PID:-}" ]] && kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] building..."
make -s clean
make -s

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
resp=$(printf '\x05\x01\x00' | nc 127.0.0.1 "$PORT" -w 1 | hexdump -v -e '/1 "%02x"' | tr -d '\n')
[[ "$resp" == "0500" ]] && echo "[ok] handshake" || echo "[warn] bad handshake ($resp)"

cleanup
echo "[done]"
