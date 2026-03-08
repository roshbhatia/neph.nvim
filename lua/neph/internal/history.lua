---@mod neph.history Prompt history management
---@brief [[
--- Persists sent prompts per agent as JSON files under stdpath("data")
--- and exposes a vim.ui.select picker to browse/copy them.
---@brief ]]

local M = {}

local history_dir = vim.fn.stdpath("data")

---@type table<string,string>
local history_files = {}
---@type table<string,integer>
local current_index = {}

--- Return the history-file path for *termname*.
---@param termname string
---@return string
function M.get_history_file(termname)
  if not history_files[termname] then
    history_files[termname] = string.format("%s/neph_history_%s.json", history_dir, termname)
  end
  return history_files[termname]
end

--- Append *prompt* to the history file for *termname*.
---@param termname string
---@param prompt   string
function M.save(termname, prompt)
  if not prompt or prompt == "" then
    return
  end
  local entries = M.load(termname)
  table.insert(entries, { timestamp = os.date("%Y-%m-%d %H:%M:%S"), prompt = prompt })
  local path = M.get_history_file(termname)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile({ vim.json.encode(entries) }, path)
end

-- Keep old name as alias for backward compat
M.save_to_history = M.save

--- Load all history entries for *termname*.
---@param termname string
---@return {timestamp:string, prompt:string}[]
function M.load(termname)
  local path = M.get_history_file(termname)
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  local content = vim.fn.readfile(path)
  if not content or #content == 0 then
    return {}
  end
  local ok, entries = pcall(vim.json.decode, table.concat(content, "\n"))
  if ok and type(entries) == "table" then
    return entries
  end
  return {}
end

M.load_history = M.load

--- Show a picker with history for *termname* (or all agents when nil).
--- Selected entry is copied to the + register.
---@param termname? string
function M.pick(termname)
  local data = {}

  local function load_for(name)
    for _, e in ipairs(M.load(name)) do
      table.insert(data, {
        text = string.format("[%s] %s: %s", name, e.timestamp, e.prompt),
        prompt = e.prompt,
        terminal = name,
        timestamp = e.timestamp,
      })
    end
  end

  if termname then
    load_for(termname)
  else
    for _, agent in ipairs(require("neph.internal.agents").get_all()) do
      load_for(agent.name)
    end
    table.sort(data, function(a, b)
      return a.timestamp > b.timestamp
    end)
  end

  if #data == 0 then
    vim.notify("Neph: no history entries", vim.log.levels.INFO)
    return
  end

  vim.ui.select(data, {
    prompt = termname and (termname .. " History") or "Neph – AI History",
    format_item = function(item)
      return item.text
    end,
  }, function(item)
    if item then
      vim.fn.setreg("+", item.prompt)
      vim.notify("Copied: " .. item.prompt:sub(1, 60), vim.log.levels.INFO)
    end
  end)
end

M.create_history_picker = M.pick

function M.get_current_history_index()
  return current_index
end
function M.set_current_history_index(termname, idx)
  current_index[termname] = idx
end

return M
