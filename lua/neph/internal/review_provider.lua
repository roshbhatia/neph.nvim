---@mod neph.internal.review_provider Review provider resolution

local M = {}

local noop = require("neph.reviewers.noop")
local vimdiff = require("neph.reviewers.vimdiff")

local providers = {
  noop = noop,
  vimdiff = vimdiff,
}

---@return neph.ReviewProvider
function M.resolve()
  local config = require("neph.config").current
  local provider = config.review_provider
  if type(provider) == "table" and provider.name then
    return provider
  end
  if type(provider) == "string" and providers[provider] then
    return providers[provider]
  end
  return noop
end

---@return boolean
function M.is_enabled()
  local provider = M.resolve()
  return provider.name ~= "noop"
end

return M
