---@diagnostic disable: undefined-global
-- Tests that the opencode peer's `permission.asked` listener applies the
-- unified diff asynchronously (no synchronous vim.fn.system in the autocmd
-- handler — that was the freeze risk we hardened against).

describe("opencode peer async patch application", function()
  local peer

  before_each(function()
    package.loaded["neph.peers.opencode"] = nil
    package.loaded["opencode"] = nil
    package.loaded["opencode.server"] = nil
    package.loaded["opencode"] = {
      start = function() end,
      toggle = function() end,
    }
    package.loaded["opencode.server"] = {
      new = function(_)
        return {
          next = function(_, fn)
            fn({ permit = function() end })
          end,
        }
      end,
    }
    peer = require("neph.peers.opencode")
    if peer._reset then
      peer._reset()
    end
    require("neph.internal.review_queue")._reset()
    require("neph.internal.review_queue").set_open_fn(function() end)
    vim.g.opencode_opts = nil
  end)

  after_each(function()
    pcall(vim.api.nvim_create_augroup, "NephOpencodePerm", { clear = true })
    require("neph.internal.review_queue")._reset()
    if peer and peer._reset then
      peer._reset()
    end
  end)

  it("does NOT call vim.fn.system synchronously in permission.asked handler", function()
    -- Stub vim.fn.system with a sentinel so we can detect any sync subprocess.
    local sync_calls = {}
    local orig_system = vim.fn.system
    vim.fn.system = function(cmd, ...)
      table.insert(sync_calls, cmd)
      return orig_system(cmd, ...)
    end

    -- Create a real file we can patch against.
    local f = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "hello" }, f)
    local diff = table.concat({
      "--- a/file",
      "+++ b/file",
      "@@ -1 +1 @@",
      "-hello",
      "+world",
      "",
    }, "\n")

    peer.open("opencode", { peer = { intercept_permissions = true } }, "/tmp")
    vim.wait(50, function()
      return #vim.api.nvim_get_autocmds({ group = "NephOpencodePerm", event = "User" }) >= 1
    end)

    -- Fire the event and immediately measure that the autocmd returned without
    -- a sync patch invocation. The async on_exit will fire on the next tick.
    local before_count = #sync_calls
    vim.api.nvim_exec_autocmds("User", {
      pattern = "OpencodeEvent:permission.asked",
      data = {
        port = 4711,
        event = {
          type = "permission.asked",
          properties = {
            id = "p-async",
            permission = "edit",
            metadata = { filepath = f, diff = diff },
          },
        },
      },
    })
    local after_count = #sync_calls

    -- The handler must NOT have invoked any synchronous subprocess.
    -- (Specifically: no `patch` call inline.)
    for i = before_count + 1, after_count do
      local cmd = sync_calls[i]
      if type(cmd) == "table" then
        for _, arg in ipairs(cmd) do
          if type(arg) == "string" and arg:find("patch") then
            assert.is_nil(arg, "found sync patch invocation in autocmd handler: " .. arg)
          end
        end
      elseif type(cmd) == "string" then
        assert.is_falsy(cmd:find("^patch ") or cmd:find(" patch "), "sync patch invocation: " .. cmd)
      end
    end

    vim.fn.system = orig_system
    vim.fn.delete(f)
  end)
end)
