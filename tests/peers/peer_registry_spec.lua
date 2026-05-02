---@diagnostic disable: undefined-global
-- peer_registry_spec.lua – tests for neph.peers registry and adapter contract

describe("neph.peers", function()
  local peers

  before_each(function()
    package.loaded["neph.peers"] = nil
    package.loaded["neph.peers.claudecode"] = nil
    package.loaded["neph.peers.opencode"] = nil
    -- Make sure stale claudecode/opencode shims from previous tests don't bleed in.
    package.loaded["claudecode"] = nil
    package.loaded["opencode"] = nil
    peers = require("neph.peers")
  end)

  it("resolve('') returns nil", function()
    assert.is_nil(peers.resolve(""))
  end)

  it("resolve(nil) returns nil", function()
    assert.is_nil(peers.resolve(nil))
  end)

  it("resolve('claudecode') returns the adapter table", function()
    local adapter = peers.resolve("claudecode")
    assert.is_table(adapter, "claudecode adapter must load even when peer plugin is absent")
    assert.is_function(adapter.is_available, "adapter must expose is_available()")
    assert.is_function(adapter.open, "adapter must expose open()")
    assert.is_function(adapter.send, "adapter must expose send()")
    assert.is_function(adapter.kill, "adapter must expose kill()")
  end)

  it("claudecode adapter reports unavailable when claudecode plugin is missing", function()
    local adapter = peers.resolve("claudecode")
    local ok, reason = adapter.is_available()
    assert.is_false(ok, "claudecode is not installed in the test env")
    assert.is_string(reason, "is_available must return a reason string")
  end)

  it("opencode adapter reports unavailable when opencode plugin is missing", function()
    local adapter = peers.resolve("opencode")
    local ok, reason = adapter.is_available()
    assert.is_false(ok)
    assert.is_string(reason)
  end)

  it("resolve caches results across calls", function()
    local first = peers.resolve("claudecode")
    local second = peers.resolve("claudecode")
    assert.are.equal(first, second, "registry should return the same module instance")
  end)

  it("resolve returns nil for an unknown kind", function()
    assert.is_nil(peers.resolve("definitely-not-a-real-peer"))
  end)
end)

describe("contracts.validate_agent — peer type", function()
  local contracts
  before_each(function()
    package.loaded["neph.internal.contracts"] = nil
    contracts = require("neph.internal.contracts")
  end)

  it("accepts a peer agent with peer.kind", function()
    local def = {
      name = "claude-peer-test",
      label = "Claude (peer)",
      icon = "C",
      cmd = "claude",
      type = "peer",
      peer = { kind = "claudecode" },
    }
    assert.has_no.errors(function()
      contracts.validate_agent(def)
    end)
  end)

  it("rejects a peer agent missing peer table", function()
    local def = {
      name = "broken",
      label = "broken",
      icon = "x",
      cmd = "x",
      type = "peer",
    }
    assert.has_error(function()
      contracts.validate_agent(def)
    end)
  end)

  it("rejects a peer agent missing peer.kind", function()
    local def = {
      name = "broken",
      label = "broken",
      icon = "x",
      cmd = "x",
      type = "peer",
      peer = {},
    }
    assert.has_error(function()
      contracts.validate_agent(def)
    end)
  end)

  it("still accepts hook/terminal/extension types", function()
    for _, t in ipairs({ "hook", "terminal", "extension" }) do
      local def = { name = "x" .. t, label = "x", icon = "y", cmd = "z", type = t }
      assert.has_no.errors(function()
        contracts.validate_agent(def)
      end)
    end
  end)
end)
