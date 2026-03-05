#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pynvim>=0.5", "click>=8.0"]
# ///
"""
shim - Neovim RPC integration for LLM agents.

CLI contract is Neovim-agnostic: callers do not need to know Neovim is the
backing implementation. `review` runs offline (auto-accept) when
NVIM_SOCKET_PATH is absent or NEPH_DRY_RUN=1.

Commands:
  status
  open <file>
  review <file>         proposed content from stdin; non-blocking diff UI;
                        prints ReviewEnvelope JSON
  preview <file>        deprecated alias for review
  revert <file>
  close-tab
  checktime
  set <name> <value>
  unset <name>
"""

import difflib
import glob
import json
import os
import socket
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NoReturn

import click
import pynvim

# ── Lua scripts ──────────────────────────────────────────────────────────────

_LUA_DIR = Path(__file__).resolve().parent / "lua"
LUA_OPEN = (_LUA_DIR / "open.lua").read_text()
LUA_REVERT = (_LUA_DIR / "revert.lua").read_text()
LUA_OPEN_DIFF = (_LUA_DIR / "open_diff.lua").read_text()


# ── Helpers ──────────────────────────────────────────────────────────────────


def die(msg: str) -> NoReturn:
    click.echo(f"shim: {msg}", err=True)
    sys.exit(1)


def _get_pid_cwd(pid_str: str) -> str | None:
    proc_cwd = f"/proc/{pid_str}/cwd"
    if os.path.islink(proc_cwd):
        try:
            return os.readlink(proc_cwd)
        except OSError:
            return None
    try:
        result = subprocess.run(
            ["lsof", "-a", "-p", pid_str, "-d", "cwd", "-Fn"],
            capture_output=True, text=True, timeout=2,
        )
        for line in result.stdout.splitlines():
            if line.startswith("n/"):
                return line[1:]
    except Exception:
        pass
    return None


def discover_nvim_socket() -> str | None:
    """Scan OS temp dirs for a live Neovim socket.

    Prefers socket whose nvim process cwd matches os.getcwd().
    Returns the socket path, or None if nothing found.
    """
    patterns = [
        "/tmp/nvim.*/0",
        "/var/folders/*/*/T/nvim.*/*/nvim.*.0",
    ]
    candidates: list[tuple[str, str]] = []  # (pid_str, socket_path)

    for pattern in patterns:
        for path in glob.glob(pattern):
            if not os.path.exists(path):
                continue
            basename = os.path.basename(path)
            pid_str = ""
            if basename.startswith("nvim.") and basename.endswith(".0"):
                pid_str = basename[5:-2]
            elif basename == "0":
                parent = os.path.basename(os.path.dirname(path))
                pid_str = parent.split(".")[-1] if "." in parent else ""
            if not pid_str.isdigit():
                continue
            try:
                os.kill(int(pid_str), 0)
            except OSError:
                continue
            candidates.append((pid_str, path))

    if not candidates:
        return None

    cwd = os.getcwd()
    for pid_str, path in candidates:
        nvim_cwd = _get_pid_cwd(pid_str)
        if nvim_cwd and (
            nvim_cwd == cwd or cwd.startswith(nvim_cwd + "/")
        ):
            return path

    return candidates[0][1]


def get_nvim(timeout: float | None = 30.0) -> pynvim.Nvim:
    """Attach to Neovim and return a pynvim.Nvim.

    Reads NVIM_SOCKET_PATH at call time; falls back to auto-discovery.
    """
    path = (
        os.environ.get("NVIM_SOCKET_PATH", "")
        or discover_nvim_socket()
        or ""
    )
    if not path:
        die("NVIM_SOCKET_PATH is not set and no Neovim socket found")
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


def verify_buffer(
    nvim: pynvim.Nvim, file_path: str, expected: str
) -> dict:
    """Verify a Neovim buffer's content matches expected.

    Uses pynvim.Buffer API (buf[:]) — no disk reads.
    Returns {} on match, {"verification_error": diff} on mismatch,
    {"verification_skipped": True} if buffer not loaded.
    """
    abs_path = os.path.abspath(file_path)
    buf = None
    for b in nvim.buffers:
        try:
            if os.path.abspath(b.name) == abs_path:
                buf = b
                break
        except Exception:
            continue
    if buf is None:
        return {"verification_skipped": True}
    try:
        actual = "\n".join(buf[:])
    except Exception:
        return {"verification_skipped": True}
    if actual == expected:
        return {}
    diff = "".join(difflib.unified_diff(
        expected.splitlines(keepends=True),
        actual.splitlines(keepends=True),
        fromfile="expected",
        tofile="buffer",
        lineterm="",
    ))
    return {"verification_error": diff}


# ── Command implementations ──────────────────────────────────────────────────


def cmd_status() -> None:
    nvim = get_nvim()
    _ = nvim  # confirm connection
    path = os.environ.get("NVIM_SOCKET_PATH", "<auto-discovered>")
    click.echo(f"connected: {path}")


def cmd_open(file_path: str) -> None:
    nvim = get_nvim()
    nvim.exec_lua(LUA_OPEN, file_path)


def cmd_review(file_path: str, dry_run: bool = False) -> None:
    """Non-blocking vimdiff review. Proposed content read from stdin.

    Dry-run / offline: auto-accept when NEPH_DRY_RUN=1 or no socket found.
    """
    proposed = sys.stdin.read()

    dry = dry_run or os.environ.get("NEPH_DRY_RUN") == "1"
    has_socket = bool(
        os.environ.get("NVIM_SOCKET_PATH", "") or discover_nvim_socket()
    )
    if dry or not has_socket:
        _emit_envelope({
            "schema": "review/v1",
            "decision": "accept",
            "content": proposed,
            "hunks": [],
        })
        return

    prop_fd, prop_path = tempfile.mkstemp(suffix=".proposed.txt")
    res_fd, result_path = tempfile.mkstemp(suffix=".review.json")
    try:
        with os.fdopen(prop_fd, "w") as f:
            f.write(proposed)
        os.close(res_fd)
        # Remove so Lua creation signals readiness
        os.unlink(result_path)

        nvim = get_nvim(timeout=30)
        channel_id = nvim.channel_id

        nvim.subscribe("neph_review_done")
        nvim.exec_lua(
            LUA_OPEN_DIFF,
            file_path, prop_path, result_path, channel_id,
        )

        # Block until the keymap fires vim.rpcnotify or result file exists
        import time
        timeout_sec = 300  # 5 minutes should be enough for any review
        start = time.time()
        
        while True:
            # Check if result file exists (notification might have failed)
            if os.path.exists(result_path):
                time.sleep(0.05)  # Brief pause to ensure write is complete
                break
                
            # Check for timeout
            if time.time() - start > timeout_sec:
                raise TimeoutError(f"Review timed out after {timeout_sec}s")
            
            # Try to read message (blocks briefly)
            time.sleep(0.1)
            # Skip message reading if in dry-run or no nvim
            if nvim:
                try:
                    msg = nvim.next_message()
                    if msg and len(msg) > 1 and msg[1] == "neph_review_done":
                        break
                except Exception:
                    # Channel might be closed, check file
                    continue

        with open(result_path) as f:
            envelope = json.load(f)

        final_content = envelope.get("content") or ""
        if final_content:
            vcheck = verify_buffer(nvim, file_path, final_content)
            envelope.update(vcheck)

        _emit_envelope(envelope)
    finally:
        for p in (prop_path, result_path):
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass


def _emit_envelope(envelope: dict) -> None:
    # Drop None values for clean JSON output
    click.echo(json.dumps(
        {k: v for k, v in envelope.items() if v is not None}
    ))


def cmd_preview(file_path: str) -> None:
    """Deprecated alias for cmd_review."""
    click.echo("shim: 'preview' is deprecated; use 'review'", err=True)
    cmd_review(file_path)


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


# ── Click CLI ────────────────────────────────────────────────────────────────


@click.group()
def cli() -> None:
    """Neovim RPC integration shim for LLM agents."""


@cli.command("status")
def _cli_status() -> None:
    """Check connectivity to the Neovim socket."""
    cmd_status()


@cli.command("open")
@click.argument("file", metavar="FILE")
def _cli_open(file: str) -> None:
    """Open FILE in the agent tab."""
    cmd_open(file)


@cli.command("review")
@click.argument("file", metavar="FILE")
@click.option("--dry-run", is_flag=True, default=False,
              help="Auto-accept without connecting to Neovim.")
def _cli_review(file: str, dry_run: bool) -> None:
    """Non-blocking vimdiff review of FILE vs proposed content (stdin).

    Prints ReviewEnvelope JSON:
      {schema, decision, content, hunks[], reason?}

    decision: accept | reject | partial
    """
    cmd_review(file, dry_run=dry_run)


@cli.command("preview", deprecated=True)
@click.argument("file", metavar="FILE")
def _cli_preview(file: str) -> None:
    """Deprecated alias for 'review'."""
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
    """Set vim.g.NAME to LUA_VALUE (raw Lua expression)."""
    cmd_set(name, lua_value)


@cli.command("unset")
@click.argument("name", metavar="NAME")
def _cli_unset(name: str) -> None:
    """Set vim.g.NAME to nil."""
    cmd_unset(name)


if __name__ == "__main__":
    cli()
