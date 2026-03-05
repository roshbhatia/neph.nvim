#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["msgpack>=1.0", "click>=8.0"]
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

import click
import msgpack

SOCKET_PATH = os.environ.get("NVIM_SOCKET_PATH", "")


# ── RPC client ───────────────────────────────────────────────────────────


class NvimRPC:
    """Minimal msgpack-rpc client for a Neovim Unix socket.

    Args:
        path: Path to the Neovim Unix socket.
        timeout: Socket read/write timeout in seconds. Pass None for no
                 timeout (interactive commands like preview). Default: 30.0.
    """

    def __init__(self, path: str, timeout: float | None = 30.0) -> None:
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.connect(path)
        if timeout is not None:
            self._sock.settimeout(timeout)
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
    click.echo(f"shim: {msg}", err=True)
    sys.exit(1)


def connect(timeout: float | None = 30.0) -> NvimRPC:
    if not SOCKET_PATH:
        die("NVIM_SOCKET_PATH is not set")
    if not os.path.exists(SOCKET_PATH):
        die(f"socket not found: {SOCKET_PATH}")
    try:
        return NvimRPC(SOCKET_PATH, timeout=timeout)
    except OSError as e:
        die(f"cannot connect to nvim: {e}")


# ── Lua ──────────────────────────────────────────────────────────────────

_LUA_DIR = Path(__file__).resolve().parent / "lua"
LUA_OPEN = (_LUA_DIR / "open.lua").read_text()
LUA_REVERT = (_LUA_DIR / "revert.lua").read_text()
LUA_PREVIEW = (_LUA_DIR / "preview.lua").read_text()


# ── Command implementations ─────────────────────────────────────────────
# Plain functions so tests can call them directly without Click overhead.


def cmd_status() -> None:
    nvim = connect()
    click.echo(f"connected: {SOCKET_PATH}")
    nvim.close()


def cmd_open(file_path: str) -> None:
    nvim = connect()
    nvim.exec_lua(LUA_OPEN, [file_path])
    nvim.close()


def cmd_preview(file_path: str) -> None:
    proposed_content = sys.stdin.read()
    # No timeout: this is interactive and blocks on user input.
    nvim = connect(timeout=None)
    result = nvim.exec_lua(LUA_PREVIEW, [file_path, proposed_content])
    click.echo(json.dumps(result))
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
    nvim = connect()
    nvim.exec_lua(f"vim.g[...] = {lua_value}", [name])
    nvim.close()


def cmd_unset(name: str) -> None:
    nvim = connect()
    nvim.exec_lua("vim.g[...] = nil", [name])
    nvim.close()


# ── Click CLI ─────────────────────────────────────────────────────────────


@click.group()
def cli() -> None:
    """Neovim msgpack-rpc integration shim for LLM agents.

    Connects to the Neovim instance at NVIM_SOCKET_PATH, runs a command,
    and exits. NVIM_SOCKET_PATH must be set in the environment.
    """


@cli.command("status")
def _cli_status() -> None:
    """Check connectivity to the Neovim socket."""
    cmd_status()


@cli.command("open")
@click.argument("file", metavar="FILE")
def _cli_open(file: str) -> None:
    """Open FILE in the agent tab (creates tab if needed)."""
    cmd_open(file)


@cli.command("preview")
@click.argument("file", metavar="FILE")
def _cli_preview(file: str) -> None:
    """Show a vimdiff review of FILE vs proposed content from stdin.

    Prints JSON result: {decision, content?, reason?}

    The proposed content is read from stdin. This call blocks until the user
    accepts or rejects the diff in Neovim, so no socket timeout is used.
    """
    cmd_preview(file)


@cli.command("revert")
@click.argument("file", metavar="FILE")
def _cli_revert(file: str) -> None:
    """Revert FILE to its on-disk state, closing any diff view."""
    cmd_revert(file)


@cli.command("close-tab")
def _cli_close_tab() -> None:
    """Close the agent tab in Neovim."""
    cmd_close_tab()


@cli.command("checktime")
def _cli_checktime() -> None:
    """Run :checktime to reload buffers from disk."""
    cmd_checktime()


@cli.command("set")
@click.argument("name", metavar="NAME")
@click.argument("lua_value", metavar="LUA_VALUE")
def _cli_set(name: str, lua_value: str) -> None:
    """Set vim.g.NAME to LUA_VALUE (raw Lua expression, e.g. 'true')."""
    cmd_set(name, lua_value)


@cli.command("unset")
@click.argument("name", metavar="NAME")
def _cli_unset(name: str) -> None:
    """Set vim.g.NAME to nil."""
    cmd_unset(name)


if __name__ == "__main__":
    cli()
