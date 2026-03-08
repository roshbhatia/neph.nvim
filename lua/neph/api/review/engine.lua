local M = {}

---@class HunkRange
---@field start_a integer  Start line in old file (1-indexed)
---@field end_a   integer  End line in old file (inclusive)
---@field start_b integer  Start line in new file (1-indexed)
---@field end_b   integer  End line in new file (inclusive)

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
    local start_a, count_a, start_b, count_b = unpack(hunk)

    -- For pure insertions (count_a == 0), start_a is the line AFTER which
    -- the insertion happens. Clamp to valid range for UI display.
    local display_a = start_a
    if count_a == 0 and display_a > #old_lines then
      display_a = math.max(1, #old_lines)
    end

    -- For pure deletions (count_b == 0), start_b is the line AFTER which
    -- the deletion point sits. Clamp similarly.
    local display_b = start_b
    if count_b == 0 and display_b > #new_lines then
      display_b = math.max(1, #new_lines)
    end

    table.insert(ranges, {
      start_a = display_a,
      end_a = math.max(display_a, display_a + count_a - 1),
      start_b = display_b,
      end_b = math.max(display_b, display_b + count_b - 1),
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

      -- For pure insertions (count_a == 0), start_a is the line after which
      -- to insert, so we insert at start_a + 1. For replacements/deletions,
      -- start_a is the first line to replace.
      local replace_start = start_a + offset
      if count_a == 0 then
        replace_start = replace_start + 1
      end

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
