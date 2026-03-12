---@diagnostic disable: undefined-global
-- init_spec.lua – tests for review graceful exit and force_cleanup

describe("neph.api.review graceful exit", function()
  local review

  before_each(function()
    package.loaded["neph.api.review"] = nil
    package.loaded["neph.api.review.engine"] = nil
    package.loaded["neph.api.review.ui"] = nil
    package.loaded["neph.internal.review_queue"] = nil
    review = require("neph.api.review")
  end)

  describe("force_cleanup", function()
    it("is a no-op when no active review", function()
      -- Should not error
      review.force_cleanup("claude")
    end)

    it("is a no-op when agent does not match", function()
      -- No active review, different agent
      review.force_cleanup("goose")
    end)
  end)

  describe("write_result", function()
    it("handles nil path gracefully", function()
      -- Should not error
      review.write_result(nil, nil, "test-req", { decision = "accept" })
    end)

    it("handles nil channel_id gracefully", function()
      review.write_result(nil, nil, "test-req", { decision = "reject" })
    end)

    it("handles channel_id 0 gracefully", function()
      review.write_result(nil, 0, "test-req", { decision = "accept" })
    end)
  end)
end)
