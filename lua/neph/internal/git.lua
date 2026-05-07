---@mod neph.internal.git Pure git utilities
---@brief [[
--- Thin wrappers around git CLI commands used by the diff review feature.
--- All functions are synchronous (vim.system + :wait()) and pure: they
--- perform no side effects beyond running git processes.
---
--- Sync calls use a 5s hard timeout to prevent freezes on weird filesystems
--- (e.g. session-manager state dirs that walk a long path looking for .git).
---
--- Ported from sysinit/utils/diff_review/git.lua.
---@brief ]]

local M = {}

local SYNC_TIMEOUT_MS = 5000

local DEFAULT_MERGE_BASE_TARGETS = {
  "origin/HEAD",
  "origin/main",
  "origin/master",
}

--- Return true when the current working directory (or cwd) is inside a git repo.
---@param cwd? string  Working directory for the git check (defaults to Neovim cwd)
---@return boolean
function M.in_git_repo(cwd)
  local result = vim
    .system({ "git", "rev-parse", "--is-inside-work-tree" }, {
      cwd = cwd,
      text = true,
    })
    :wait(SYNC_TIMEOUT_MS)
  if not result or result.code == nil then
    return false
  end
  return result.code == 0 and vim.trim(result.stdout or "") == "true"
end

--- Run a git command and return its output as a list of non-empty lines.
--- Returns nil + error string on non-zero exit.
---@param args string[]           Arguments passed to git (do NOT include "git" itself)
---@param opts? { cwd?: string }  Optional working directory
---@return string[]|nil, string|nil
function M.git_lines(args, opts)
  opts = opts or {}
  local cmd = vim.list_extend({ "git" }, args)
  local result = vim
    .system(cmd, {
      cwd = opts.cwd,
      text = true,
    })
    :wait(SYNC_TIMEOUT_MS)

  if not result or result.code == nil then
    return nil, string.format("git %s timed out after %dms", table.concat(args, " "), SYNC_TIMEOUT_MS)
  end
  if result.code ~= 0 then
    local stderr = vim.trim(result.stderr or "")
    if stderr == "" then
      stderr = string.format("git %s failed with exit code %d", table.concat(args, " "), result.code)
    end
    return nil, stderr
  end

  local lines = vim.split(result.stdout or "", "\n", { trimempty = true })
  if #lines == 0 then
    return nil, nil
  end
  return lines, nil
end

--- Resolve the merge-base commit between HEAD and one of the remote tracking
--- branches in merge_base_targets. Tries each target in order and returns the
--- first successful SHA.
---@param opts? { cwd?: string, merge_base_targets?: string[] }
---@return string|nil, string|nil  SHA of the merge-base, or nil + error
function M.merge_base(opts)
  opts = opts or {}
  local targets = opts.merge_base_targets or DEFAULT_MERGE_BASE_TARGETS
  local last_err = nil

  for _, target in ipairs(targets) do
    local result = vim
      .system({ "git", "merge-base", "HEAD", target }, {
        cwd = opts.cwd,
        text = true,
      })
      :wait(SYNC_TIMEOUT_MS)

    if not result or result.code == nil then
      last_err = string.format("git merge-base %s timed out after %dms", target, SYNC_TIMEOUT_MS)
    elseif result.code == 0 then
      local base = vim.trim(result.stdout or "")
      if base ~= "" then
        return base, nil
      end
    else
      local stderr = vim.trim(result.stderr or "")
      if stderr ~= "" then
        last_err = stderr
      end
    end
  end

  return nil, last_err or "Could not determine merge-base"
end

--- Return the diff output for the given scope as a list of lines.
---
--- Supported scopes:
---   "head"    – unstaged + staged changes vs HEAD
---   "staged"  – staged changes only
---   "branch"  – changes from merge-base to HEAD (branch diff)
---   "file"    – HEAD diff for a single file (requires opts.file)
---
--- Hunk-scope diffs are handled separately in api/diff.lua via gitsigns.
---@param scope "head"|"staged"|"branch"|"file"
---@param opts? { cwd?: string, file?: string, merge_base_targets?: string[], branch_fallback?: string }
---@return string[]|nil, string|nil
function M.diff_lines(scope, opts)
  opts = opts or {}

  if not M.in_git_repo(opts.cwd) then
    return nil, "Not inside a git repository"
  end

  if scope == "head" then
    return M.git_lines({ "--no-pager", "diff", "HEAD" }, opts)
  end

  if scope == "staged" then
    return M.git_lines({ "--no-pager", "diff", "--cached" }, opts)
  end

  if scope == "branch" then
    local base, err = M.merge_base(opts)
    if not base or base == "" then
      base = opts.branch_fallback
      if not base or base == "" then
        return nil, err or "Could not determine merge-base"
      end
    end
    return M.git_lines({ "--no-pager", "diff", base, "HEAD" }, opts)
  end

  if scope == "file" then
    if not opts.file or opts.file == "" then
      return nil, "No file path provided"
    end
    return M.git_lines({ "--no-pager", "diff", "HEAD", "--", opts.file }, opts)
  end

  return nil, string.format("Unsupported diff scope: %s", scope)
end

return M
