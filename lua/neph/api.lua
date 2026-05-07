---@mod neph.api Public API for neph.nvim
---@brief [[
--- User-facing actions exposed as functions for keymap binding.
--- Use these with lazy.nvim's `keys` table or any keymap manager.
---
--- Example (lazy.nvim):
---
--- ```lua
--- {
---   "roshbhatia/neph.nvim",
---   keys = {
---     { "<leader>jj", function() require("neph.api").toggle() end, desc = "Neph: toggle / pick agent" },
---     { "<leader>ja", function() require("neph.api").ask() end, mode = { "n", "v" }, desc = "Neph: ask" },
---   },
--- }
--- ```
---@brief ]]

local M = {}

local gate_ui = require("neph.internal.gate_ui")

--- Return the current window if it is a normal (non-floating) window, or the
--- first non-floating window in the window list. Falls back to the current
--- window if no non-floating window can be found (unlikely in practice).
--- This prevents the gate winbar indicator from landing on a floating terminal
--- or picker window where it would be invisible or cosmetically broken.
---@return integer
local function non_floating_win()
  local cur = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(cur)
  -- relative == "" means the window is not floating
  if cfg.relative == "" then
    return cur
  end
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local wcfg = vim.api.nvim_win_get_config(w)
    if wcfg.relative == "" then
      return w
    end
  end
  return cur
end

--- Get the active agent name, notifying if none is set.
---@return string|nil
local function get_active()
  local active = require("neph.internal.session").get_active()
  if not active then
    vim.notify("No active AI terminal – pick one with <leader>jj", vim.log.levels.WARN)
  end
  return active
end

--- Read the visual-selection bounds from the `'<` and `'>` marks of *buf*.
--- Returns nil when the marks are unset (both at line 0). Reads
--- `vim.fn.visualmode()` to populate the kind so block-mode selections expand
--- correctly. Used by `M.ask` / `M.comment` to capture selections set by a
--- recent visual gesture — those keymap callbacks fire AFTER nvim has
--- already exited visual mode, so `vim.fn.mode()` is unreliable.
---@param buf integer
---@return {from: integer[], to: integer[], kind: string}|nil
local function get_visual_marks(buf)
  local from = vim.api.nvim_buf_get_mark(buf, "<")
  local to = vim.api.nvim_buf_get_mark(buf, ">")
  if from[1] == 0 and to[1] == 0 then
    return nil
  end
  if from[1] > to[1] or (from[1] == to[1] and from[2] > to[2]) then
    from, to = to, from
  end
  local kind_map = { v = "char", V = "line", ["\22"] = "block" }
  return {
    from = { from[1], from[2] },
    to = { to[1], to[2] },
    kind = kind_map[vim.fn.visualmode()] or "char",
  }
end

--- Open the input prompt for the active agent.
---@param action string
---@param default_text string
---@param opts? {selection_marks?: table}
local function input_for_active(action, default_text, opts)
  opts = opts or {}
  local active = get_active()
  if not active then
    return
  end
  local agent = require("neph.internal.agents").get_by_name(active)
  if not agent then
    vim.notify("Agent '" .. active .. "' not found", vim.log.levels.WARN)
    return
  end
  require("neph.internal.input").create_input(active, agent.icon, {
    action = action,
    default = default_text,
    selection_marks = opts.selection_marks,
    on_confirm = function(text)
      require("neph.internal.session").ensure_active_and_send(text)
    end,
  })
end

--- Toggle the active agent session, or open the picker if none is active.
---@return nil
function M.toggle()
  require("neph.internal.picker").pick_agent()
end

--- Kill the active session and open the picker to select a new one.
---@return nil
function M.kill_and_pick()
  require("neph.internal.picker").kill_and_pick()
end

--- Kill the active session.
---@return nil
function M.kill()
  require("neph.internal.picker").kill_active()
end

--- Open the ask prompt. When invoked from visual mode, prefills with
--- `+selection` and captures the selection bounds via marks `'<`/`'>`
--- (vim.fn.mode() is unreliable from keymap callbacks because the visual
--- mode has already transitioned to normal by the time we run).
---@return nil
function M.ask()
  local marks = get_visual_marks(vim.api.nvim_get_current_buf())
  local default = marks and "+selection " or "+cursor "
  input_for_active("Ask", default, { selection_marks = marks })
end

--- Open the fix-diagnostics prompt.
---@return nil
function M.fix()
  input_for_active("Fix diagnostics", "Fix +diagnostics ")
end

--- Open the comment prompt. Same marks-based selection capture as `M.ask`.
---@return nil
function M.comment()
  local marks = get_visual_marks(vim.api.nvim_get_current_buf())
  local default = marks and "Comment +selection " or "Comment +cursor "
  input_for_active("Comment", default, { selection_marks = marks })
end

--- Open an interactive review of buffer vs disk changes.
---
--- NOTE: When `path` is relative it is expanded to an absolute path at
--- call-time using the cwd that is current *right now*. If the cwd changes
--- between this call and the moment the review window opens (e.g. an
--- autocmd or another plugin changes directories in the same tick), the
--- resolved path will still point to the file that was intended, because
--- the expansion is done eagerly before any async work begins.
---@param path? string  File path (defaults to current buffer's file)
---@return {ok: boolean, msg?: string, error?: string}
function M.review(path)
  if not path then
    local bufname = vim.api.nvim_buf_get_name(0)
    if bufname == "" then
      vim.notify("Neph: buffer has no file", vim.log.levels.ERROR)
      return { ok = false, error = "Buffer has no file" }
    end
    path = bufname
  end
  -- Resolve to absolute path eagerly so the value is stable even if the cwd
  -- changes before the review UI opens (see NOTE above).
  path = vim.fn.fnamemodify(path, ":p")
  local result = require("neph.api.review").open_manual(path)
  if not result.ok then
    vim.notify("Neph: " .. (result.error or "review failed"), vim.log.levels.ERROR)
  end
  return result
end

--- Maximum byte length for a resent prompt. Prompts longer than this are
--- likely accidentally-pasted file contents and would flood the agent's
--- input pipe. Adjust via this constant if your workflow requires longer
--- prompts (the right fix is to use context slots instead).
local RESEND_MAX_BYTES = 8192

--- Resend the previous prompt to the active agent.
--- Prompts longer than RESEND_MAX_BYTES are blocked with a warning to avoid
--- flooding the agent with accidentally-pasted file contents.
---@return nil
function M.resend()
  local active = get_active()
  if not active then
    return
  end
  local last = require("neph.internal.terminal").get_last_prompt(active)
  if not last or last == "" then
    vim.notify("No previous prompt found", vim.log.levels.WARN)
    return
  end
  if #last > RESEND_MAX_BYTES then
    vim.notify(
      string.format(
        "Neph: last prompt is %d bytes (limit %d) — use context slots for large inputs",
        #last,
        RESEND_MAX_BYTES
      ),
      vim.log.levels.WARN
    )
    return
  end
  require("neph.internal.session").ensure_active_and_send(last)
end

--- Cycle the review gate: normal → hold → bypass → normal.
--- normal: each write triggers an immediate review UI.
--- hold: writes queue silently; drain on release.
--- bypass: all writes auto-accepted without UI.
---@return nil
function M.gate()
  local gate = require("neph.internal.gate")
  local current = gate.get()
  -- Resolve a non-floating window at call-time so the indicator is placed on
  -- a regular editor split rather than a floating terminal or picker.
  local win = non_floating_win()
  if current == "normal" then
    gate.set("hold")
    gate_ui.set("hold", win)
    vim.notify("Neph: reviews held — writes will accumulate", vim.log.levels.INFO)
  elseif current == "hold" then
    gate.set("bypass")
    gate_ui.set("bypass", win)
    vim.notify("Neph: bypass mode — all writes auto-accepted without review", vim.log.levels.WARN)
  else -- bypass
    gate.release()
    gate_ui.clear()
    require("neph.internal.review_queue").drain()
    vim.notify("Neph: gate released — draining pending reviews", vim.log.levels.INFO)
  end
end

--- Set gate to hold mode explicitly.
--- No-op (with notification) if gate is already in hold mode.
---@return nil
function M.gate_hold()
  local gate = require("neph.internal.gate")
  if gate.is_hold() then
    vim.notify("Neph: gate is already in hold mode", vim.log.levels.INFO)
    return
  end
  local win = non_floating_win()
  gate.set("hold")
  gate_ui.set("hold", win)
  vim.notify("Neph: reviews held", vim.log.levels.INFO)
end

--- Set gate to bypass mode explicitly (auto-accepts all writes without review).
--- No-op (with notification) if gate is already in bypass mode.
---@return nil
function M.gate_bypass()
  local gate = require("neph.internal.gate")
  if gate.is_bypass() then
    vim.notify("Neph: gate is already in bypass mode", vim.log.levels.WARN)
    return
  end
  local win = non_floating_win()
  gate.set("bypass")
  gate_ui.set("bypass", win)
  vim.notify("Neph: bypass mode — all writes auto-accepted without review", vim.log.levels.WARN)
end

--- Release hold or bypass, returning to normal state, and drain any accumulated reviews.
--- No-op (with notification) if gate is already in normal state.
---@return nil
function M.gate_release()
  local gate = require("neph.internal.gate")
  if gate.is_normal() then
    vim.notify("Neph: gate is already in normal state", vim.log.levels.INFO)
    return
  end
  local was_hold = gate.is_hold()
  gate.release()
  gate_ui.clear()
  -- Only drain the queue when releasing from hold — bypass discards reviews
  -- rather than queuing them, so there is nothing to drain.
  if was_hold then
    require("neph.internal.review_queue").drain()
    vim.notify("Neph: gate released — draining pending reviews", vim.log.levels.INFO)
  else
    vim.notify("Neph: gate released", vim.log.levels.INFO)
  end
end

--- Return the current gate state string.
---@return neph.GateState
function M.gate_status()
  return require("neph.internal.gate").get()
end

--- Open the NephStatus floating buffer showing agent integration state.
---@return nil
function M.tools_status()
  require("neph.api.status_buf").open()
end

--- Show a dry-run preview of what tools.install would change.
---@return nil
function M.tools_preview()
  require("neph.api.status_buf").open_preview()
end

--- Open the review queue inspector floating window.
---@return nil
function M.queue()
  require("neph.api.review.queue_ui").open()
end

local DIFF_REVIEW_SCOPES = {
  head = true,
  staged = true,
  branch = true,
  file = true,
  hunk = true,
}

local DIFF_PICKER_SCOPES = {
  head = true,
  staged = true,
  branch = true,
}

--- Send a git diff to the active agent for review.
--- scope: "head" | "staged" | "branch" | "file" | "hunk"
---@param scope string
---@param opts? { prompt?: string, cwd?: string, file?: string, merge_base_targets?: string[], branch_fallback?: string, submit?: boolean }
---@return boolean, string|nil
function M.diff_review(scope, opts)
  if not DIFF_REVIEW_SCOPES[scope] then
    local msg = string.format("diff_review: invalid scope %q (expected head|staged|branch|file|hunk)", tostring(scope))
    vim.notify("Neph: " .. msg, vim.log.levels.ERROR)
    return false, msg
  end
  return require("neph.api.diff").review(scope, opts)
end

--- Open a snacks.nvim git diff picker.
--- scope: "head" | "staged" | "branch"
---@param scope string
---@param opts? { cwd?: string, merge_base_targets?: string[], branch_fallback?: string }
---@return boolean, string|nil
function M.diff_picker(scope, opts)
  if not DIFF_PICKER_SCOPES[scope] then
    local msg = string.format("diff_picker: invalid scope %q (expected head|staged|branch)", tostring(scope))
    vim.notify("Neph: " .. msg, vim.log.levels.ERROR)
    return false, msg
  end
  return require("neph.api.diff").picker(scope, opts)
end

return M
