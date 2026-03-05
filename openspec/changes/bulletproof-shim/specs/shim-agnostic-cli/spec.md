# Shim Agnostic CLI

CLI contract that is Neovim-agnostic: callers do not need to know that Neovim is the backing implementation. The shim gracefully degrades when `NVIM_SOCKET_PATH` is absent or Neovim is not running.

## Capability

**shim-agnostic-cli** — CLI commands work offline (auto-accept/reject) when no Neovim socket is available.

## Rationale

For CI, testing, and offline usage, the shim should not hard-fail when Neovim is absent. Instead, `review` auto-accepts proposed content when `NVIM_SOCKET_PATH` is unset, `NEPH_DRY_RUN=1`, or socket discovery finds nothing. This allows the agent to complete operations without manual intervention when running headless or in a non-interactive environment.

## ADDED Requirements

### Requirement: discover_nvim_socket function

- Function `discover_nvim_socket() -> str | None`
  - Globs `/tmp/nvim.*/0` and `/var/folders/*/*/T/nvim.*/*/nvim.*.0`
  - Filters to sockets whose owning pid is alive (via `os.kill(pid, 0)`)
  - Prefers socket whose nvim process cwd matches `os.getcwd()` (uses `lsof` on macOS, `/proc/<pid>/cwd` on Linux)
  - Returns socket path or `None` if nothing found
- `get_nvim()` updated: if `NVIM_SOCKET_PATH` is empty, call `discover_nvim_socket()`; if still None, call `die()`
- `cmd_review()` updated: check `dry_run or os.environ.get("NEPH_DRY_RUN") == "1" or not (NVIM_SOCKET_PATH or discover_nvim_socket())`; if true, emit accept envelope without connecting to Neovim
- CLI `@cli.command("review")` updated: add `--dry-run` flag

### `tools/core/tests/test_shim.py`

- Class `TestSocketDiscovery` with tests:
  - `test_returns_none_when_no_sockets` — mock `glob.glob` → `[]`, expect `None`
  - `test_dead_pid_filtered_out` — mock `os.kill` raises `OSError`, expect `None`
- Class `TestReviewProtocol` updated:
  - `test_no_socket_auto_accepts` — mock `discover_nvim_socket` → `None`, expect exit 0 with accept envelope
  - `test_neph_dry_run_env_auto_accepts` — set `NEPH_DRY_RUN=1`, expect accept envelope
  - `test_review_cli_dry_run_exits_0` — invoke `review --dry-run`, expect exit 0
- Class `TestConnectErrors` updated:
  - `test_missing_socket_path_env_auto_discovers` — `status` without `NVIM_SOCKET_PATH` may pass or fail depending on live sockets; non-blocking

## Delta Headers

**shim-agnostic-cli**: ADDED (new capability — graceful degradation when Neovim absent)
