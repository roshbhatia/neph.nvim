---@mod neph.api.review.popup Floating-popup review UI
---@brief [[
--- A lightweight alternative to the vimdiff tab. Renders the proposed
--- change as a small floating window with single-key resolution:
---
---   a → accept the entire change
---   r → reject the entire change
---   v → close popup, fall through to vimdiff tab (granular hunk keymaps)
---   q / <Esc> → close popup but leave the review at the head of the queue
---
--- The popup body shows the file path, hunk count, line counts, and the
--- actual hunks rendered inline (capped to a bounded height; scrollable
--- inside the float). Used by default for peer agents (`type = "peer"`)
--- and opt-in everywhere else via `setup({ review = { style = "popup" } })`.
---
--- gate=bypass and gate=hold short-circuit before reaching this module
--- (the queue handles those states inline). The popup is only invoked
--- under gate=normal.
---@brief ]]

local M = {}

local engine = require("neph.api.review.engine")
local log = require("neph.internal.log")

--- Render hunk content into a list of buffer lines.
--- HunkRange schema (from engine.compute_hunks): {start_a, end_a, start_b, end_b},
--- 1-indexed and clamped. We derive count = end - start + 1 and protect against
--- the "pure insertion / pure deletion" case where end < start signals an empty
--- side. (compute_hunks clamps end >= start so this is mostly defensive.)
---@param old_lines string[]
---@param new_lines string[]
---@param hunks table[]  HunkRange[] from engine.compute_hunks
---@param max_lines integer  Cap visible lines so the popup stays bounded
---@return string[] body_lines
---@return integer plus_count
---@return integer minus_count
local function render_hunks(old_lines, new_lines, hunks, max_lines)
  local out = {}
  local plus_count, minus_count = 0, 0
  local truncated = false

  for _, h in ipairs(hunks) do
    if #out >= max_lines then
      truncated = true
      break
    end
    local count_a = math.max(0, (h.end_a or h.start_a) - h.start_a + 1)
    local count_b = math.max(0, (h.end_b or h.start_b) - h.start_b + 1)
    plus_count = plus_count + count_b
    minus_count = minus_count + count_a

    table.insert(out, string.format("@@ -%d,%d +%d,%d @@", h.start_a, count_a, h.start_b, count_b))
    -- Show removed lines first, then added — standard unified-diff order.
    for i = 0, count_a - 1 do
      if #out >= max_lines then
        truncated = true
        break
      end
      local line = old_lines[h.start_a + i] or ""
      table.insert(out, "- " .. line)
    end
    if truncated then
      break
    end
    for i = 0, count_b - 1 do
      if #out >= max_lines then
        truncated = true
        break
      end
      local line = new_lines[h.start_b + i] or ""
      table.insert(out, "+ " .. line)
    end
  end

  if truncated then
    table.insert(out, "── content truncated — press [v] to view the full diff ──")
  end

  return out, plus_count, minus_count
end

--- Read existing file content (lines) for diff computation.
---@param path string
---@return string[]
local function read_file_lines(path)
  if not path or path == "" then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return {}
  end
  return lines
end

--- Build envelope for the bypass/accept/reject paths.
---@param decision "accept"|"reject"
---@param params table  Review request
---@param reason string
---@return table envelope
local function build_envelope(decision, params, reason)
  return {
    schema = "review/v1",
    decision = decision,
    content = decision == "accept" and (params.content or "") or "",
    hunks = {},
    reason = reason,
    request_id = params.request_id,
  }
end

--- Resolve a review with accept or reject.
---@param decision "accept"|"reject"
---@param params table
---@param reason string
local function resolve(decision, params, reason)
  local envelope = build_envelope(decision, params, reason)
  local review = require("neph.api.review")
  if params.result_path or (params.channel_id and params.channel_id ~= 0) then
    review.write_result(params.result_path, params.channel_id, params.request_id, envelope)
  end
  if type(params.on_complete) == "function" then
    pcall(params.on_complete, envelope)
  end
  require("neph.internal.review_queue").on_complete(params.request_id)
end

--- Active popup state (single-popup constraint matches single-active-review).
---@type {win: integer?, buf: integer?, params: table?}
local active = { win = nil, buf = nil, params = nil }

--- Close the popup window/buffer if present. Idempotent.
local function close_popup()
  if active.win and vim.api.nvim_win_is_valid(active.win) then
    pcall(vim.api.nvim_win_close, active.win, true)
  end
  if active.buf and vim.api.nvim_buf_is_valid(active.buf) then
    pcall(vim.api.nvim_buf_delete, active.buf, { force = true })
  end
  active.win = nil
  active.buf = nil
  active.params = nil
end

--- Fall back to vim.ui.select when snacks isn't available. Maps the user's
--- selection back to accept/reject/view/later semantics.
---@param params table
local function open_via_ui_select(params)
  local options = { "Accept", "Reject", "View diff", "Later" }
  local prompt =
    string.format("%s wants to write %s", params.agent or "agent", vim.fn.fnamemodify(params.path or "?", ":~:."))
  vim.ui.select(options, { prompt = prompt }, function(choice)
    if choice == "Accept" then
      resolve("accept", params, "popup-accept")
    elseif choice == "Reject" then
      resolve("reject", params, "popup-reject")
    elseif choice == "View diff" then
      require("neph.api.review")._open_immediate(params)
    end
    -- Nil / "Later" → leave queue entry active.
  end)
end

--- Open the popup for *params*. Caller is review_queue.set_open_fn after
--- gate handling and review_provider gating.
---@param params table  Canonical review-queue request shape
function M.open(params)
  -- Compute hunks from disk vs proposed content
  local old_lines = read_file_lines(params.path)
  local new_lines = params.content and vim.split(params.content, "\n", { plain = true }) or {}
  -- Trim trailing empty line that vim.split(., "\n") leaves when content
  -- ends with \n — otherwise the diff sees a phantom extra line.
  if #new_lines > 0 and new_lines[#new_lines] == "" then
    table.remove(new_lines)
  end

  local hunks = engine.compute_hunks(old_lines, new_lines)
  local body_lines, plus_count, minus_count = render_hunks(old_lines, new_lines, hunks, 24)

  -- Build the popup buffer content: header + separator + hunks + footer
  local rel_path = vim.fn.fnamemodify(params.path or "?", ":~:.")
  local lines = {
    string.format("%s → write file", params.agent or "agent"),
    string.format(
      "  %s    +%d / -%d   %d hunk%s",
      rel_path,
      plus_count,
      minus_count,
      #hunks,
      #hunks == 1 and "" or "s"
    ),
    "",
  }
  if #body_lines == 0 then
    table.insert(lines, "  (no changes)")
  else
    for _, l in ipairs(body_lines) do
      table.insert(lines, l)
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  [a] accept   [r] reject   [v] view full diff   [q]/[esc] later")

  -- Close any prior popup (shouldn't happen, but be defensive).
  close_popup()

  -- Open a native floating window. If nvim_open_win fails (e.g. headless with
  -- no UI attached or some incompatible config), fall through to vim.ui.select.
  local create_ok, buf = pcall(vim.api.nvim_create_buf, false, true)
  if not create_ok or not buf then
    log.debug("review.popup", "nvim_create_buf failed — falling back to vim.ui.select")
    open_via_ui_select(params)
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "diff")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

  -- Compute reasonable popup size
  local width = math.min(100, math.max(40, vim.o.columns - 4))
  local height = math.min(#lines + 2, math.max(8, math.floor(vim.o.lines * 0.5)))

  local open_ok, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Neph review ",
    title_pos = "center",
  })
  if not open_ok or not win then
    log.debug("review.popup", "nvim_open_win failed (%s) — falling back to vim.ui.select", tostring(win))
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    open_via_ui_select(params)
    return
  end
  pcall(vim.api.nvim_win_set_option, win, "wrap", false)

  active.win = win
  active.buf = buf
  active.params = params

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  map("a", function()
    close_popup()
    resolve("accept", params, "popup-accept")
  end, "Neph: accept proposed change")

  map("r", function()
    close_popup()
    resolve("reject", params, "popup-reject")
  end, "Neph: reject proposed change")

  map("v", function()
    close_popup()
    require("neph.api.review")._open_immediate(params)
  end, "Neph: view full diff in vimdiff tab")

  map("q", function()
    close_popup()
  end, "Neph: defer review (stays in queue)")
  map("<Esc>", function()
    close_popup()
  end, "Neph: defer review (stays in queue)")
end

--- Reset internal state (test aid).
function M._reset()
  close_popup()
end

--- Whether a popup is currently visible (test aid).
function M._is_open()
  return active.win ~= nil and vim.api.nvim_win_is_valid(active.win)
end

return M
