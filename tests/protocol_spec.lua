-- tests/protocol_spec.lua
-- Ensures protocol.json stays in sync with the dispatch table in lua/neph/rpc.lua.
-- Parses rpc.lua source directly (dispatch is local, not exported) so no source
-- changes are required. Checks both directions: no phantom documented methods and
-- no undocumented dispatch entries.

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    error("Could not open file: " .. path)
  end
  local contents = f:read("*a")
  f:close()
  return contents
end

-- Extract the ["method.name"] keys from the local dispatch table in rpc.lua.
-- Matches lines of the form:   ["review.open"] = function
local function parse_dispatch_keys(source)
  local keys = {}
  -- Only scan within the dispatch block: from "local dispatch = {" to the
  -- closing "}" that ends the block.  We find the block boundaries first, then
  -- match keys inside that slice to avoid false positives elsewhere.
  local dispatch_start = source:find("local dispatch = {", 1, true)
  if not dispatch_start then
    error("Could not locate 'local dispatch = {' in rpc.lua")
  end
  -- Walk forward to find the matching closing brace.
  local depth = 0
  local dispatch_end = dispatch_start
  for i = dispatch_start, #source do
    local ch = source:sub(i, i)
    if ch == "{" then
      depth = depth + 1
    elseif ch == "}" then
      depth = depth - 1
      if depth == 0 then
        dispatch_end = i
        break
      end
    end
  end
  local block = source:sub(dispatch_start, dispatch_end)
  for key in block:gmatch('%["([a-z][a-z0-9._%-]*)"%]%s*=%s*function') do
    keys[key] = true
  end
  return keys
end

-- Extract the method names from protocol.json.
local function parse_protocol_keys(source)
  local decoded = vim.json.decode(source)
  if not decoded or not decoded.methods then
    error("protocol.json is missing top-level 'methods' key")
  end
  local keys = {}
  for method in pairs(decoded.methods) do
    keys[method] = true
  end
  return keys
end

describe("protocol.json <-> rpc.lua sync", function()
  local rpc_source = read_file("lua/neph/rpc.lua")
  local protocol_source = read_file("protocol.json")

  local dispatch_keys = parse_dispatch_keys(rpc_source)
  local protocol_keys = parse_protocol_keys(protocol_source)

  it("every method in protocol.json exists in rpc.lua dispatch (no phantom docs)", function()
    local phantoms = {}
    for method in pairs(protocol_keys) do
      if not dispatch_keys[method] then
        table.insert(phantoms, method)
      end
    end
    table.sort(phantoms)
    assert.are.equal(
      0,
      #phantoms,
      "Methods in protocol.json but missing from rpc.lua dispatch:\n  " .. table.concat(phantoms, "\n  ")
    )
  end)

  it("every method in rpc.lua dispatch exists in protocol.json (no undocumented methods)", function()
    local undocumented = {}
    for method in pairs(dispatch_keys) do
      if not protocol_keys[method] then
        table.insert(undocumented, method)
      end
    end
    table.sort(undocumented)
    assert.are.equal(
      0,
      #undocumented,
      "Methods in rpc.lua dispatch but missing from protocol.json:\n  " .. table.concat(undocumented, "\n  ")
    )
  end)

  it("dispatch key count matches protocol.json method count", function()
    local dispatch_count = 0
    for _ in pairs(dispatch_keys) do
      dispatch_count = dispatch_count + 1
    end
    local protocol_count = 0
    for _ in pairs(protocol_keys) do
      protocol_count = protocol_count + 1
    end
    assert.are.equal(
      protocol_count,
      dispatch_count,
      string.format(
        "Count mismatch: protocol.json has %d methods, rpc.lua dispatch has %d",
        protocol_count,
        dispatch_count
      )
    )
  end)
end)
