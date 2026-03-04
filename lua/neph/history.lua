---@mod neph.history Prompt history management
---@brief [[
--- Persists sent prompts per agent to simple flat files under /tmp and
--- exposes a Snacks picker to browse/copy them.
---@brief ]]

local M = {}

local history_dir = "/tmp"

---@type table<string,string>
local history_files = {}
---@type table<string,integer>
local current_index = {}

--- Return the history-file path for *termname*.
---@param termname string
---@return string
function M.get_history_file(termname)
  if not history_files[termname] then
    history_files[termname] = string.format("%s/neph-history-%s.txt", history_dir, termname)
  end
  return history_files[termname]
end

--- Append *prompt* to the history file for *termname*.
---@param termname string
---@param prompt   string
function M.save(termname, prompt)
  if not prompt or prompt == "" then return end
  local f = io.open(M.get_history_file(termname), "a")
  if f then
    f:write(string.format("%s|%s\n", os.date("%Y-%m-%d %H:%M:%S"), prompt))
    f:close()
  end
end

-- Keep old name as alias for backward compat
M.save_to_history = M.save

--- Load all history entries for *termname*.
---@param termname string
---@return {timestamp:string, prompt:string}[]
function M.load(termname)
  local entries = {}
  local f = io.open(M.get_history_file(termname), "r")
  if f then
    for line in f:lines() do
      local ts, prompt = line:match("^(.-)|(.*)")
      if ts and prompt then
        table.insert(entries, { timestamp = ts, prompt = prompt })
      end
    end
    f:close()
  end
  return entries
end

M.load_history = M.load

--- Show a Snacks picker with history for *termname* (or all agents when nil).
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
    for _, agent in ipairs(require("neph.agents").get_all()) do
      load_for(agent.name)
    end
    table.sort(data, function(a, b) return a.timestamp > b.timestamp end)
  end

  Snacks.picker.pick({
    prompt = termname and (termname .. " History") or "Neph – AI History",
    items = data,
    format = "text",
    layout = "default",
    preview = false,
    confirm = function(_, item)
      if item then
        vim.fn.setreg("+", item.prompt)
        vim.notify("Copied: " .. item.prompt:sub(1, 60), vim.log.levels.INFO)
      end
    end,
  })
end

M.create_history_picker = M.pick

function M.get_current_history_index() return current_index end
function M.set_current_history_index(termname, idx) current_index[termname] = idx end

return M
