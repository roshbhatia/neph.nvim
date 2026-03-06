local M = {}

---@class HunkRange
---@field start_line integer
---@field end_line integer

---@class HunkDecision
---@field index integer
---@field decision "accept" | "reject"
---@field reason string?

---@class ReviewEnvelope
---@field schema "review/v1"
---@field decision "accept" | "reject" | "partial"
---@field content string
---@field hunks HunkDecision[]
---@field reason string?

---@param old_lines string[]
---@param new_lines string[]
---@return HunkRange[]
function M.compute_hunks(old_lines, new_lines)
  local old_str = table.concat(old_lines, "\n")
  local new_str = table.concat(new_lines, "\n")

  -- Ensure trailing newline consistency for vim.diff if lines are non-empty
  if #old_lines > 0 then
    old_str = old_str .. "\n"
  end
  if #new_lines > 0 then
    new_str = new_str .. "\n"
  end

  local ok, diff_result = pcall(vim.diff, old_str, new_str, {
    result_type = "indices",
  })

  if not ok or not diff_result then
    return {}
  end

  local ranges = {}
  for _, hunk in ipairs(diff_result) do
    -- hunk format: {start_a, count_a, start_b, count_b}
    local start_a, count_a, _, _ = unpack(hunk)

    -- In nvim.diff indices, if count is 0, start_a points to the line AFTER
    -- where the insertion happens (or the end of file + 1).
    -- For our UI purposes, we want a valid line number if possible.
    local display_start = start_a
    if count_a == 0 then
      -- It's a pure addition.
      -- If start_a is > #old_lines, it's at the end.
      if display_start > #old_lines then
        display_start = math.max(1, #old_lines)
      end
    end

    table.insert(ranges, {
      start_line = display_start,
      end_line = math.max(display_start, display_start + count_a - 1),
    })
  end

  return ranges
end

---@param old_lines string[]
---@param new_lines string[]
---@param decisions HunkDecision[]
---@return string
function M.apply_decisions(old_lines, new_lines, decisions)
  local old_str = table.concat(old_lines, "\n")
  local new_str = table.concat(new_lines, "\n")

  if #old_lines > 0 then
    old_str = old_str .. "\n"
  end
  if #new_lines > 0 then
    new_str = new_str .. "\n"
  end

  local ok, diff_result = pcall(vim.diff, old_str, new_str, {
    result_type = "indices",
  })

  if not ok or not diff_result then
    return table.concat(old_lines, "\n")
  end

  local result_lines = vim.deepcopy(old_lines)
  local offset = 0

  for i, hunk in ipairs(diff_result) do
    local decision = decisions[i]
    if decision and decision.decision == "accept" then
      local start_a, count_a, start_b, count_b = unpack(hunk)

      local new_hunk_lines = {}
      for j = start_b, start_b + count_b - 1 do
        table.insert(new_hunk_lines, new_lines[j])
      end

      local replace_start = start_a + offset

      -- Remove count_a lines
      for _ = 1, count_a do
        if replace_start <= #result_lines then
          table.remove(result_lines, replace_start)
        end
      end

      -- Insert count_b lines
      for j = #new_hunk_lines, 1, -1 do
        table.insert(result_lines, replace_start, new_hunk_lines[j])
      end

      offset = offset + (count_b - count_a)
    end
  end

  return table.concat(result_lines, "\n")
end

---@param decisions HunkDecision[]
---@param content string
---@return ReviewEnvelope
function M.build_envelope(decisions, content)
  local accepted = vim.tbl_filter(function(h)
    return h.decision == "accept"
  end, decisions)
  local rejected = vim.tbl_filter(function(h)
    return h.decision == "reject"
  end, decisions)

  local decision
  if #rejected == 0 and #decisions > 0 then
    decision = "accept"
  elseif #accepted == 0 and #decisions > 0 then
    decision = "reject"
    content = ""
  elseif #decisions == 0 then
    decision = "accept" -- No changes
  else
    decision = "partial"
  end

  local reasons = {}
  for _, h in ipairs(rejected) do
    if h.reason and h.reason ~= "" then
      table.insert(reasons, h.reason)
    end
  end

  return {
    schema = "review/v1",
    decision = decision,
    content = content,
    hunks = decisions,
    reason = #reasons > 0 and table.concat(reasons, "; ") or nil,
  }
end

-- State machine session
function M.create_session(old_lines, new_lines)
  local hunk_ranges = M.compute_hunks(old_lines, new_lines)
  local decisions = {}
  local current_idx = 1

  local self = {}

  function self.get_current_hunk()
    return hunk_ranges[current_idx], current_idx
  end

  function self.get_total_hunks()
    return #hunk_ranges
  end

  function self.accept()
    if current_idx > #hunk_ranges then
      return false
    end
    table.insert(decisions, { index = current_idx, decision = "accept" })
    current_idx = current_idx + 1
    return true
  end

  function self.reject(reason)
    if current_idx > #hunk_ranges then
      return false
    end
    table.insert(decisions, { index = current_idx, decision = "reject", reason = reason })
    current_idx = current_idx + 1
    return true
  end

  function self.accept_all()
    while current_idx <= #hunk_ranges do
      self.accept()
    end
  end

  function self.reject_all(reason)
    while current_idx <= #hunk_ranges do
      self.reject(reason)
      reason = nil
    end
  end

  function self.is_done()
    return current_idx > #hunk_ranges
  end

  function self.finalize()
    local content = M.apply_decisions(old_lines, new_lines, decisions)
    return M.build_envelope(decisions, content)
  end

  return self
end

return M
