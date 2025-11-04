#!/usr/bin/env python3

import argparse
import socket
import struct
import sys
import threading

PAYLOAD = b"proxy-test"
RESPONSE = b"proxy-ok"
TARGET_HOST = "127.0.0.1"


def read_exact(sock: socket.socket, size: int) -> bytes:
    """Receive exactly size bytes or raise."""
    chunks = bytearray()
    while len(chunks) < size:
        chunk = sock.recv(size - len(chunks))
        if not chunk:
            raise RuntimeError("connection closed prematurely")
        chunks.extend(chunk)
    return bytes(chunks)


def run_proxy_flow(socks_port: int, target_port: int) -> None:
    ready = threading.Event()
    outcome = {"error": None}

    def echo_server() -> None:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as srv:
                srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                srv.bind((TARGET_HOST, target_port))
                srv.listen(1)
                ready.set()
                conn, _ = srv.accept()
                with conn:
                    data = read_exact(conn, len(PAYLOAD))
                    if data != PAYLOAD:
                        outcome["error"] = f"unexpected payload {data!r}"
                        return
                    conn.sendall(RESPONSE)
        except Exception as exc:  # pylint: disable=broad-except
            outcome["error"] = f"target server error: {exc}"
        finally:
            ready.set()

    server_thread = threading.Thread(target=echo_server, daemon=True)
    server_thread.start()

    if not ready.wait(timeout=1.0):
        raise RuntimeError("echo server failed to start")
    if outcome["error"] is not None:
        raise RuntimeError(outcome["error"])

    with socket.create_connection((TARGET_HOST, socks_port), timeout=2.0) as sock:
        sock.settimeout(2.0)
        sock.sendall(b"\x05\x01\x00")
        choice = read_exact(sock, 2)
        if choice != b"\x05\x00":
            raise RuntimeError(f"unexpected auth reply {choice!r}")

        host_bytes = TARGET_HOST.encode("ascii")
        request = (
            b"\x05\x01\x00\x03"
            + bytes([len(host_bytes)])
            + host_bytes
            + struct.pack("!H", target_port)
        )
        sock.sendall(request)
        header = read_exact(sock, 4)
        if header[1] != 0x00:
            raise RuntimeError(f"connect failed with code {header[1]:#x}")

        atyp = header[3]
        if atyp == 0x01:
            read_exact(sock, 4)
        elif atyp == 0x03:
            name_len = read_exact(sock, 1)[0]
            read_exact(sock, name_len)
        elif atyp == 0x04:
            read_exact(sock, 16)
        else:
            raise RuntimeError(f"unexpected ATYP {atyp:#x}")
        read_exact(sock, 2)  # bound port

        sock.sendall(PAYLOAD)
        echoed = read_exact(sock, len(RESPONSE))
        if echoed != RESPONSE:
            raise RuntimeError(f"unexpected echoed response {echoed!r}")

    server_thread.join(timeout=1.0)
    if server_thread.is_alive():
        raise RuntimeError("echo server did not stop")

    if outcome["error"] is not None:
        raise RuntimeError(outcome["error"])


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Socks proxy integration test")
    parser.add_argument("socks_port", type=int, help="Port where socks proxy listens")
    parser.add_argument("target_port", type=int, help="Port for local echo server")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        run_proxy_flow(args.socks_port, args.target_port)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"[fail] {exc}", file=sys.stderr)
        return 1
    print("[ok] proxy data path")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
