#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pynvim>=0.5", "click>=8.0"]
# ///
"""
shim - Neovim msgpack-rpc integration for LLM agents.

One-shot: connect to the nvim instance at NVIM_SOCKET_PATH, run a command,
print any result as JSON to stdout, and exit.

All Lua runs via nvim.exec_lua which is a blocking RPC call — nvim processes
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
import pynvim

# ── Helpers ───────────────────────────────────────────────────────────────


def die(msg: str) -> NoReturn:
    click.echo(f"shim: {msg}", err=True)
    sys.exit(1)


def get_nvim(timeout: float | None = 30.0) -> pynvim.Nvim:
    """Attach to Neovim at NVIM_SOCKET_PATH and return a pynvim.Nvim.

    Reads NVIM_SOCKET_PATH from the environment at call time so that changes
    made after module load (e.g. os.environ updates in tests) are respected.

    Args:
        timeout: Socket timeout in seconds passed via socket.setdefaulttimeout
                 before attaching. Pass None for no timeout (e.g. interactive
                 preview that blocks on user input). Default: 30.0.

    Raises:
        SystemExit(1): If NVIM_SOCKET_PATH is unset, the file does not exist,
                       or pynvim cannot connect.
    """
    path = os.environ.get("NVIM_SOCKET_PATH", "")
    if not path:
        die("NVIM_SOCKET_PATH is not set")
    if not os.path.exists(path):
        die(f"socket not found: {path}")
    socket.setdefaulttimeout(timeout)
    try:
        nvim = pynvim.attach("socket", path=path)
    except OSError as e:
        die(f"cannot connect to nvim: {e}")
    finally:
        socket.setdefaulttimeout(None)
    return nvim


# ── Lua ──────────────────────────────────────────────────────────────────

_LUA_DIR = Path(__file__).resolve().parent / "lua"
LUA_OPEN = (_LUA_DIR / "open.lua").read_text()
LUA_REVERT = (_LUA_DIR / "revert.lua").read_text()
LUA_PREVIEW = (_LUA_DIR / "preview.lua").read_text()


# ── Command implementations ─────────────────────────────────────────────
# Plain functions so tests can call them directly without Click overhead.


def cmd_status() -> None:
    get_nvim()
    click.echo(f"connected: {os.environ.get('NVIM_SOCKET_PATH', '')}")


def cmd_open(file_path: str) -> None:
    nvim = get_nvim()
    nvim.exec_lua(LUA_OPEN, file_path)


def cmd_preview(file_path: str) -> None:
    proposed_content = sys.stdin.read()
    # No timeout: this is interactive and blocks on user input.
    nvim = get_nvim(timeout=None)
    result = nvim.exec_lua(LUA_PREVIEW, file_path, proposed_content)
    click.echo(json.dumps(result))


def cmd_revert(file_path: str) -> None:
    nvim = get_nvim()
    nvim.exec_lua(LUA_REVERT, file_path)


def cmd_close_tab() -> None:
    nvim = get_nvim()
    nvim.exec_lua("""
if vim.g.agent_tab then
  pcall(vim.cmd, 'tabclose ' .. vim.g.agent_tab)
  vim.g.agent_tab = nil
end
""")


def cmd_checktime() -> None:
    nvim = get_nvim()
    nvim.exec_lua("vim.cmd('checktime')")


def cmd_set(name: str, lua_value: str) -> None:
    nvim = get_nvim()
    nvim.exec_lua(f"vim.g[...] = {lua_value}", name)


def cmd_unset(name: str) -> None:
    nvim = get_nvim()
    nvim.exec_lua("vim.g[...] = nil", name)


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
