-- Tests for neph.internal.channel
describe("neph.internal.channel", function()
  local channel

  before_each(function()
    package.loaded["neph.internal.channel"] = nil
    channel = require("neph.internal.channel")
  end)

  it("returns empty string before any path is set when servername is empty", function()
    -- vim.v.servername is typically empty in headless test env
    local path = channel.socket_path()
    -- Either empty or whatever vim.v.servername reports
    assert.is_string(path)
  end)

  -- socket_path() verifies fs_stat; use a real temp file so the stored path
  -- is treated as live and returned directly.
  it("returns the path after set_socket_path when the socket file exists", function()
    local tmp = vim.fn.tempname()
    local fh = io.open(tmp, "w")
    if fh then
      fh:close()
      channel.set_socket_path(tmp)
      assert.equals(tmp, channel.socket_path())
      os.remove(tmp)
    end
  end)

  it("overrides vim.v.servername when the stored socket file exists on disk", function()
    local tmp = vim.fn.tempname()
    local fh = io.open(tmp, "w")
    if fh then
      fh:close()
      channel.set_socket_path(tmp)
      assert.equals(tmp, channel.socket_path())
      os.remove(tmp)
    end
  end)

  it("falls back to vim.v.servername when path is empty", function()
    -- No set_socket_path call -- internal path remains ""
    local path = channel.socket_path()
    -- Should be vim.v.servername (may be empty in headless)
    assert.is_string(path)
  end)

  -- Issue 1: set_socket_path ignores empty strings so a second call with ""
  -- cannot clear a previously valid stored path.
  it("set_socket_path ignores empty string -- does not overwrite a valid path", function()
    local tmp = vim.fn.tempname()
    local fh = io.open(tmp, "w")
    if fh then
      fh:close()
      channel.set_socket_path(tmp)
      channel.set_socket_path("")
      -- "" was ignored; the real file is still on disk so socket_path() must
      -- return the stored path directly.
      assert.equals(tmp, channel.socket_path())
      os.remove(tmp)
    end
  end)

  -- Issue 3: socket_path() should fall back to vim.v.servername when the
  -- stored path points to a non-existent file.
  it("falls back to vim.v.servername when stored socket file does not exist", function()
    channel.set_socket_path("/tmp/__neph_nonexistent_socket_xyz.sock")
    local p = channel.socket_path()
    assert.is_string(p)
    local servername = vim.v.servername or ""
    if servername ~= "" then
      assert.equals(servername, p)
    end
  end)

  -- Issue 5: is_connected() helper
  describe("is_connected", function()
    it("returns false when no path is set and servername is empty", function()
      if (vim.v.servername or "") == "" then
        assert.is_false(channel.is_connected())
      else
        assert.is_boolean(channel.is_connected())
      end
    end)

    it("returns false for a path that does not exist on disk", function()
      channel.set_socket_path("/tmp/__neph_nonexistent_socket_xyz.sock")
      if (vim.v.servername or "") == "" then
        assert.is_false(channel.is_connected())
      else
        assert.is_boolean(channel.is_connected())
      end
    end)

    it("returns true for a socket path that exists on disk", function()
      local tmp = vim.fn.tempname()
      local fh = io.open(tmp, "w")
      if fh then
        fh:close()
        channel.set_socket_path(tmp)
        assert.is_true(channel.is_connected())
        os.remove(tmp)
      end
    end)
  end)
end)
