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

  -- Collect accepted patches, then apply in reverse order so indices stay valid
  -- without needing an offset accumulator. This also avoids O(n²) shifting from
  -- repeated table.remove in forward order.
  local patches = {}
  for i, hunk in ipairs(diff_result) do
    local decision = decisions[i]
    if decision and decision.decision == "accept" then
      local start_a, count_a, start_b, count_b = unpack(hunk)
      local lines = {}
      for j = start_b, math.min(start_b + count_b - 1, #new_lines) do
        lines[#lines + 1] = new_lines[j]
      end
      patches[#patches + 1] = { start_a = start_a, count_a = count_a, lines = lines }
    end
  end

  local result_lines = vim.deepcopy(old_lines)
  for i = #patches, 1, -1 do
    local p = patches[i]
    local pos = p.start_a
    if p.count_a == 0 then
      pos = pos + 1
    end
    for _ = 1, p.count_a do
      if pos <= #result_lines then
        table.remove(result_lines, pos)
      end
    end
    for j = #p.lines, 1, -1 do
      table.insert(result_lines, pos, p.lines[j])
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
  -- Random-access decisions array: nil = undecided, table = decided
  local decisions_by_idx = {}
  local current_idx = 1

  local self = {}

  function self.get_hunk_ranges()
    return hunk_ranges
  end

  function self.get_current_hunk()
    return hunk_ranges[current_idx], current_idx
  end

  function self.get_total_hunks()
    return #hunk_ranges
  end

  -- Random-access methods
  function self.accept_at(idx)
    if idx < 1 or idx > #hunk_ranges then
      return false
    end
    decisions_by_idx[idx] = { index = idx, decision = "accept" }
    return true
  end

  function self.reject_at(idx, reason)
    if idx < 1 or idx > #hunk_ranges then
      return false
    end
    decisions_by_idx[idx] = { index = idx, decision = "reject", reason = reason }
    return true
  end

  function self.get_decision(idx)
    return decisions_by_idx[idx]
  end

  function self.is_complete()
    for i = 1, #hunk_ranges do
      if not decisions_by_idx[i] then
        return false
      end
    end
    return true
  end

  function self.next_undecided(from)
    from = from or 1
    for i = from, #hunk_ranges do
      if not decisions_by_idx[i] then
        return i
      end
    end
    -- Wrap around
    for i = 1, from - 1 do
      if not decisions_by_idx[i] then
        return i
      end
    end
    return nil
  end

  function self.clear_at(idx)
    if idx < 1 or idx > #hunk_ranges then
      return false
    end
    decisions_by_idx[idx] = nil
    return true
  end

  function self.get_tally()
    local accepted, rejected, undecided = 0, 0, 0
    for i = 1, #hunk_ranges do
      local d = decisions_by_idx[i]
      if not d then
        undecided = undecided + 1
      elseif d.decision == "accept" then
        accepted = accepted + 1
      elseif d.decision == "reject" then
        rejected = rejected + 1
      end
    end
    return { accepted = accepted, rejected = rejected, undecided = undecided }
  end

  function self.accept_all_remaining()
    for i = 1, #hunk_ranges do
      if not decisions_by_idx[i] then
        decisions_by_idx[i] = { index = i, decision = "accept" }
      end
    end
  end

  function self.reject_all_remaining(reason)
    for i = 1, #hunk_ranges do
      if not decisions_by_idx[i] then
        decisions_by_idx[i] = { index = i, decision = "reject", reason = reason }
      end
    end
  end

  -- Sequential methods (backward compat, delegate to random-access)
  function self.accept()
    if current_idx > #hunk_ranges then
      return false
    end
    self.accept_at(current_idx)
    current_idx = current_idx + 1
    return true
  end

  function self.reject(reason)
    if current_idx > #hunk_ranges then
      return false
    end
    self.reject_at(current_idx, reason)
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
    -- Treat undecided hunks as rejected (safety)
    for i = 1, #hunk_ranges do
      if not decisions_by_idx[i] then
        decisions_by_idx[i] = { index = i, decision = "reject", reason = "Undecided" }
      end
    end
    -- Build ordered decisions array for apply_decisions
    local decisions = {}
    for i = 1, #hunk_ranges do
      decisions[i] = decisions_by_idx[i]
    end
    local content = M.apply_decisions(old_lines, new_lines, decisions)
    return M.build_envelope(decisions, content)
  end

  return self
end

return M
