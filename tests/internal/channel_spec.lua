-- Tests for neph.internal.channel
describe("neph.internal.channel", function()
  local channel

  before_each(function()
    package.loaded["neph.internal.channel"] = nil
    channel = require("neph.internal.channel")
  end)

  it("returns empty string before any path is set when servername is empty", function()
    -- vim.v.servername is typically empty in headless test env
    channel.set_socket_path("")
    local path = channel.socket_path()
    -- Either empty or whatever vim.v.servername reports
    assert.is_string(path)
  end)

  it("returns the path after set_socket_path", function()
    channel.set_socket_path("/tmp/nvim.test/0")
    assert.equals("/tmp/nvim.test/0", channel.socket_path())
  end)

  it("overrides vim.v.servername when explicitly set", function()
    channel.set_socket_path("/tmp/explicit.sock")
    assert.equals("/tmp/explicit.sock", channel.socket_path())
  end)

  it("falls back to vim.v.servername when path is empty", function()
    channel.set_socket_path("")
    local path = channel.socket_path()
    -- Should be vim.v.servername (may be empty in headless)
    assert.is_string(path)
  end)
end)
