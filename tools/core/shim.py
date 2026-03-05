#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["msgpack>=1.0"]
# ///
"""
shim - Neovim msgpack-rpc integration for LLM agents.

One-shot: connect to the nvim instance at NVIM_SOCKET_PATH, run a command,
print any result as JSON to stdout, and exit.

All Lua runs via nvim_exec_lua which is a blocking RPC call — nvim processes
the request, including any blocking vim.fn.confirm / vim.fn.input calls, and
only sends the response when the Lua returns. No polling, no temp files.

Commands:
  status
  open <file>
  preview <file>            proposed content read from stdin;
                            prints JSON: {decision, content?, reason?}
  revert <file>
  close-tab
  checktime
  set <name> <lua-value>    e.g. set pi_active true
  unset <name>
"""

import json
import os
import socket
import sys
from pathlib import Path
from typing import NoReturn

import msgpack

SOCKET_PATH = os.environ.get("NVIM_SOCKET_PATH", "")


# ── RPC client ───────────────────────────────────────────────────────────


class NvimRPC:
    """Minimal msgpack-rpc client for a Neovim Unix socket."""

    def __init__(self, path: str) -> None:
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.connect(path)
        self._msgid = 0
        self._buf = msgpack.Unpacker(raw=False, strict_map_key=False)

    def request(self, method: str, *params) -> object:
        msgid = self._msgid
        self._msgid += 1
        self._sock.sendall(msgpack.packb([0, msgid, method, list(params)]))
        while True:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise RuntimeError("nvim socket closed unexpectedly")
            self._buf.feed(chunk)
            for msg in self._buf:
                if msg[0] == 1 and msg[1] == msgid:  # our response
                    if msg[2]:
                        raise RuntimeError(f"nvim: {msg[2]}")
                    return msg[3]
                # msg[0] == 2 is a notification; skip and keep reading

    def exec_lua(self, code: str, args: list | None = None) -> object:
        return self.request("nvim_exec_lua", code, args or [])

    def close(self) -> None:
        self._sock.close()


# ── Helpers ───────────────────────────────────────────────────────────────


def die(msg: str) -> NoReturn:
    print(f"shim: {msg}", file=sys.stderr)
    sys.exit(1)


def connect() -> NvimRPC:
    if not SOCKET_PATH:
        die("NVIM_SOCKET_PATH is not set")
    if not os.path.exists(SOCKET_PATH):
        die(f"socket not found: {SOCKET_PATH}")
    try:
        return NvimRPC(SOCKET_PATH)
    except OSError as e:
        die(f"cannot connect to nvim: {e}")


# ── Lua ──────────────────────────────────────────────────────────────────

_LUA_DIR = Path(__file__).resolve().parent / "lua"
LUA_OPEN    = (_LUA_DIR / "open.lua").read_text()

LUA_REVERT  = (_LUA_DIR / "revert.lua").read_text()

# Vimdiff review with fully blocking hunk-by-hunk confirm / input.
# Args passed via nvim_exec_lua varargs:
#   raw_path (string), proposed_content (string)
# Returns a Lua table decoded by msgpack into a Python dict:
#   {decision="accept", content="...", reason="..."}
#                                           -- partial or full accept
#   {decision="reject", reason="..."}
LUA_PREVIEW = (_LUA_DIR / "preview.lua").read_text()


# ── Commands ─────────────────────────────────────────────────────────────


def cmd_status() -> None:
    nvim = connect()
    print(f"connected: {SOCKET_PATH}")
    nvim.close()


def cmd_open(file_path: str) -> None:
    nvim = connect()
    nvim.exec_lua(LUA_OPEN, [file_path])
    nvim.close()


def cmd_preview(file_path: str) -> None:
    proposed_content = sys.stdin.read()
    nvim = connect()
    result = nvim.exec_lua(LUA_PREVIEW, [file_path, proposed_content])
    print(json.dumps(result))
    nvim.close()


def cmd_revert(file_path: str) -> None:
    nvim = connect()
    nvim.exec_lua(LUA_REVERT, [file_path])
    nvim.close()


def cmd_close_tab() -> None:
    nvim = connect()
    nvim.exec_lua(r"""
if vim.g.agent_tab then
  pcall(vim.cmd, 'tabclose ' .. vim.g.agent_tab)
  vim.g.agent_tab = nil
end
""")
    nvim.close()


def cmd_checktime() -> None:
    nvim = connect()
    nvim.exec_lua("vim.cmd('checktime')")
    nvim.close()


def cmd_set(name: str, lua_value: str) -> None:
    # lua_value is a raw Lua expression, e.g. "true" or "false"
    nvim = connect()
    nvim.exec_lua(f"vim.g[...] = {lua_value}", [name])
    nvim.close()


def cmd_unset(name: str) -> None:
    nvim = connect()
    nvim.exec_lua("vim.g[...] = nil", [name])
    nvim.close()


# ── Dispatch ─────────────────────────────────────────────────────────────

USAGE = """\
usage: shim <command> [args]

  status
  open <file>
  preview <file>           proposed content on stdin; prints JSON result
  revert <file>
  close-tab
  checktime
  set <name> <lua-value>
  unset <name>
"""


def main() -> None:
    args = sys.argv[1:]
    if not args:
        print(USAGE, file=sys.stderr)
        sys.exit(1)

    cmd, *rest = args
    try:
        match cmd:
            case "status":
                cmd_status()
            case "open":
                cmd_open(rest[0])
            case "preview":
                cmd_preview(rest[0])
            case "revert":
                cmd_revert(rest[0])
            case "close-tab":
                cmd_close_tab()
            case "checktime":
                cmd_checktime()
            case "set":
                cmd_set(rest[0], rest[1])
            case "unset":
                cmd_unset(rest[0])
            case _:
                die(f"unknown command: {cmd}")
    except (RuntimeError, OSError, IndexError) as e:
        die(str(e))


if __name__ == "__main__":
    main()
