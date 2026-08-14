#!/usr/bin/env python3

import os
import socket
import sys
from urllib.parse import urlsplit

RELAY_HOST = "127.0.0.1"
RELAY_PORT = 43199
MAX_REQUEST_BYTES = 64 * 1024
CONNECTION_TIMEOUT_SECONDS = 2


def validated_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("only absolute HTTP(S) URLs are supported")
    if any(character.isspace() or ord(character) == 127 for character in value):
        raise ValueError("URL contains whitespace or control characters")
    return value


def send_url(url: str) -> None:
    with socket.create_connection((RELAY_HOST, RELAY_PORT), timeout=2) as relay:
        relay.sendall(url.encode("utf-8") + b"\n")
        relay.shutdown(socket.SHUT_WR)
        response = bytearray()
        while chunk := relay.recv(4096):
            response.extend(chunk)
    if response:
        raise RuntimeError(response.decode("utf-8", errors="replace").strip())


def read_request(connection: socket.socket) -> str:
    request = bytearray()
    while b"\n" not in request:
        chunk = connection.recv(4096)
        if not chunk:
            break
        request.extend(chunk)
        if len(request) > MAX_REQUEST_BYTES:
            raise ValueError("URL exceeds the relay size limit")
    if not request.endswith(b"\n"):
        raise ValueError("URL request is incomplete")
    return validated_url(request[:-1].decode("utf-8"))


def send_error(connection: socket.socket, error: Exception) -> None:
    try:
        connection.sendall(f"remote opener: {error}".encode("utf-8"))
    except OSError:
        pass


def proxy_connection(connection: socket.socket, opener_socket: str) -> None:
    try:
        connection.settimeout(CONNECTION_TIMEOUT_SECONDS)
        url = read_request(connection)
        with socket.socket(socket.AF_UNIX) as opener:
            opener.settimeout(CONNECTION_TIMEOUT_SECONDS)
            opener.connect(opener_socket)
            opener.sendall(url.encode("utf-8") + b"\n")
            opener.shutdown(socket.SHUT_WR)
            while response := opener.recv(4096):
                connection.sendall(response)
    except (OSError, UnicodeError, ValueError) as error:
        send_error(connection, error)


def run_proxy(proxy_socket: str, opener_socket: str) -> None:
    with socket.socket(socket.AF_UNIX) as proxy:
        proxy.bind(proxy_socket)
        os.chmod(proxy_socket, 0o600)
        proxy.listen()
        while True:
            connection, _ = proxy.accept()
            with connection:
                proxy_connection(connection, opener_socket)


def main() -> int:
    if sys.argv[1:] == ["--print-port"]:
        print(RELAY_PORT)
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "--proxy":
        try:
            run_proxy(sys.argv[2], sys.argv[3])
        except OSError as error:
            print(f"remote opener proxy: {error}", file=sys.stderr)
            return 1
        return 0

    try:
        url = validated_url(os.environ.get("HERDR_PLUGIN_CLICKED_URL", ""))
        send_url(url)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"remote opener: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
