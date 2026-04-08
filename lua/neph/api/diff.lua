---@mod neph.api.diff Git diff review and picker
---@brief [[
--- Implements diff review (sending a git diff to the active agent) and the
--- snacks.nvim diff picker (browsing diffs without sending to any agent).
---
--- review(scope, opts)  – get diff lines, build prompt message, send to agent
--- picker(scope)        – open snacks git diff picker for the given scope
---
--- Both functions return boolean, string|nil (success, error) for testability.
---@brief ]]

local M = {}

local git = require("neph.internal.git")

--- Build the prompt message combining the review prompt and the diff block.
---@param prompt string     Preamble text placed above the diff fence
---@param lines  string[]   Raw diff output lines
---@return string
local function build_message(prompt, lines)
  local diff_text = table.concat(lines, "\n")
  return string.format("%s\n\n```diff\n%s\n```", prompt, diff_text)
end

--- Return the diff lines for the hunk at the cursor position via gitsigns.
--- Falls back to the first hunk in the buffer when the cursor is between hunks.
--- Returns nil + error string when gitsigns is unavailable or the buffer has no hunks.
---@return string[]|nil, string|nil
local function current_hunk_lines()
  local ok, gs = pcall(require, "gitsigns")
  if not ok then
    return nil, "gitsigns.nvim is not available"
  end

  local hunks = gs.get_hunks and gs.get_hunks()
  if not hunks or #hunks == 0 then
    return nil, "No hunks in buffer"
  end

  local cursor_line = vim.fn.line(".")
  local selected

  for _, hunk in ipairs(hunks) do
    local start_line = hunk.added.start
    local end_line = start_line + math.max(hunk.added.count - 1, 0)
    if cursor_line >= start_line and cursor_line <= end_line then
      selected = hunk
      break
    end
  end

  selected = selected or hunks[1]
  return vim.list_extend({ selected.head }, selected.lines), nil
end

--- Resolve the prompt text for the given scope.
--- Uses the caller-supplied prompt when provided, otherwise falls back to the
--- configured hunk/review prompt from neph.config.
---@param scope  string   Diff scope (used to pick hunk vs review prompt)
---@param prompt? string  Optional caller override
---@return string
local function resolve_prompt(scope, prompt)
  if prompt and prompt ~= "" then
    return prompt
  end
  local cfg = require("neph.config").current
  local diff_cfg = (type(cfg.diff) == "table" and cfg.diff) or {}
  local prompts = (type(diff_cfg.prompts) == "table" and diff_cfg.prompts) or {}
  if scope == "hunk" then
    return prompts.hunk
      or "Review this specific hunk. What does it change, is the change correct, and are there any issues?"
  end
  return prompts.review
    or "Review this diff carefully. Identify any bugs, logic errors, "
      .. "security issues, missing edge-cases, or places where the intent "
      .. "of the change is unclear. Be concise and specific — cite line numbers where relevant."
end

--- Send a git diff to the active agent for review.
---
--- scope values:
---   "head"    – all uncommitted changes (staged + unstaged) vs HEAD
---   "staged"  – staged changes only
---   "branch"  – changes from merge-base to HEAD
---   "file"    – HEAD diff for the current buffer file (or opts.file)
---   "hunk"    – the hunk at the cursor position (via gitsigns)
---
---@param scope string  Diff scope
---@param opts? { prompt?: string, cwd?: string, file?: string, merge_base_targets?: string[], branch_fallback?: string, submit?: boolean }
---@return boolean, string|nil
function M.review(scope, opts)
  opts = opts or {}

  local cfg = require("neph.config").current
  local diff_cfg = (type(cfg.diff) == "table" and cfg.diff) or {}

  -- Resolve branch_fallback: caller > config > built-in
  local branch_fallback = opts.branch_fallback
    or (type(diff_cfg.branch_fallback) == "string" and diff_cfg.branch_fallback)
    or "HEAD~1"

  local lines, err

  if scope == "hunk" then
    lines, err = current_hunk_lines()
  elseif scope == "file" then
    local file = opts.file
    if not file or file == "" then
      file = vim.fn.expand("%:p")
    end
    if not file or file == "" then
      local msg = "No file in current buffer"
      vim.notify("Neph: " .. msg, vim.log.levels.WARN)
      return false, msg
    end
    lines, err = git.diff_lines("file", {
      cwd = opts.cwd,
      file = file,
      merge_base_targets = opts.merge_base_targets,
      branch_fallback = branch_fallback,
    })
  else
    lines, err = git.diff_lines(scope, {
      cwd = opts.cwd,
      file = opts.file,
      merge_base_targets = opts.merge_base_targets,
      branch_fallback = branch_fallback,
    })
  end

  if err then
    vim.notify("Neph: " .. err, vim.log.levels.WARN)
    return false, err
  end

  if not lines or #lines == 0 then
    local msg = "No diff output — nothing to review"
    vim.notify("Neph: " .. msg, vim.log.levels.WARN)
    return false, msg
  end

  local message = build_message(resolve_prompt(scope, opts.prompt), lines)
  require("neph.internal.session").ensure_active_and_send(message)
  return true, nil
end

--- Open a snacks.nvim git diff picker for the given scope.
---
--- scope values:
---   "head"    – unstaged changes
---   "staged"  – staged changes
---   "branch"  – changes from merge-base to HEAD
---
---@param scope string  Picker scope
---@param opts? { cwd?: string, merge_base_targets?: string[], branch_fallback?: string }
---@return boolean, string|nil
function M.picker(scope, opts)
  opts = opts or {}

  local ok, snacks = pcall(require, "snacks")
  if not ok then
    local msg = "snacks.nvim is not available"
    vim.notify("Neph: " .. msg, vim.log.levels.ERROR)
    return false, msg
  end

  if scope == "head" then
    snacks.picker.git_diff()
    return true, nil
  end

  if scope == "staged" then
    snacks.picker.git_diff({ staged = true })
    return true, nil
  end

  if scope == "branch" then
    local cfg = require("neph.config").current
    local diff_cfg = (type(cfg.diff) == "table" and cfg.diff) or {}
    local branch_fallback = opts.branch_fallback
      or (type(diff_cfg.branch_fallback) == "string" and diff_cfg.branch_fallback)
      or "HEAD~1"

    local base, err = git.merge_base({
      cwd = opts.cwd,
      merge_base_targets = opts.merge_base_targets,
    })
    if not base or base == "" then
      base = branch_fallback
      if not base or base == "" then
        local msg = err or "Could not determine merge-base"
        vim.notify("Neph: " .. msg, vim.log.levels.WARN)
        return false, msg
      end
    end
    snacks.picker.git_diff({ base = base })
    return true, nil
  end

  local msg = string.format("Unsupported picker scope: %s", tostring(scope))
  vim.notify("Neph: " .. msg, vim.log.levels.ERROR)
  return false, msg
end

return M
