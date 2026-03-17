-- E2E test: neph-cli review → Neovim RPC → vimdiff → programmatic decision → stdout
--
-- Exercises the real flow end-to-end inside headless Neovim.

--- Find the buffer with review keymaps and call a keymap callback by lhs.
local function call_review_keymap(lhs)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local maps = vim.api.nvim_buf_get_keymap(bufnr, "n")
    for _, m in ipairs(maps) do
      if m.lhs == lhs and m.callback then
        -- Switch to this buffer's window first
        for _, win in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_buf(win) == bufnr then
            vim.api.nvim_set_current_win(win)
            break
          end
        end
        m.callback()
        return true
      end
    end
  end
  return false
end

--- Spawn neph-cli review as a job and return a handle for checking results.
local function spawn_review(neph_cli, nvim_socket, stdin_json, extra_env)
  local state = { stdout = {}, stderr = {}, exited = false, code = nil }
  local env = { NVIM = "", NVIM_SOCKET_PATH = nvim_socket, PATH = os.getenv("PATH") }
  if extra_env then
    for k, v in pairs(extra_env) do
      env[k] = v
    end
  end

  local job_id = vim.fn.jobstart({ "npx", "tsx", neph_cli, "review" }, {
    env = env,
    on_stdout = function(_, data)
      for _, l in ipairs(data) do
        if l ~= "" then
          table.insert(state.stdout, l)
        end
      end
    end,
    on_stderr = function(_, data)
      for _, l in ipairs(data) do
        if l ~= "" then
          table.insert(state.stderr, l)
        end
      end
    end,
    on_exit = function(_, c)
      state.code = c
      state.exited = true
    end,
  })
  vim.fn.chansend(job_id, stdin_json)
  vim.fn.chanclose(job_id, "stdin")
  state.job_id = job_id
  return state
end

return function(t)
  local plugin_root = vim.fn.getcwd()
  local neph_cli = plugin_root .. "/tools/neph-cli/src/index.ts"
  if vim.fn.executable("npx") ~= 1 then
    t.skip("review e2e", "npx not available on PATH")
    return
  end
  if vim.fn.filereadable(neph_cli) ~= 1 then
    t.skip("review e2e", "neph-cli source not found")
    return
  end

  local nvim_socket = vim.v.servername
  if not nvim_socket or nvim_socket == "" then
    nvim_socket = vim.fn.serverstart(vim.fn.tempname())
  end
  if nvim_socket and nvim_socket ~= "" then
    vim.wait(1000, function()
      return vim.uv.fs_stat(nvim_socket) ~= nil
    end)
  end
  if not nvim_socket or nvim_socket == "" then
    t.skip("review e2e", "no Neovim server socket")
    return
  end

  -- Set up neph with stub backend
  require("neph").setup({
    agents = {},
    backend = {
      setup = function() end,
      open = function()
        return {}
      end,
      focus = function()
        return true
      end,
      hide = function() end,
      is_visible = function()
        return false
      end,
      kill = function() end,
      cleanup_all = function() end,
    },
    review_provider = require("neph.reviewers.vimdiff"),
  })

  t.describe("neph-cli review e2e", function()
    t.it("no-changes: auto-accepts when content matches disk", function()
      local test_file = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "same_content" }, test_file)

      local state = spawn_review(neph_cli, nvim_socket, vim.json.encode({ path = test_file, content = "same_content" }))

      t.wait_for(function()
        return state.exited
      end, 5000, "should auto-accept (no changes)")
      t.assert_eq(state.code, 0, "exit code should be 0")

      local parsed = vim.json.decode(table.concat(state.stdout, ""))
      t.assert_eq(parsed.decision, "accept", "decision should be accept")
      vim.fn.delete(test_file)
    end)

    t.it("accept flow: programmatic gA + gs returns accept", function()
      local test_file = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "line1", "line2", "line3" }, test_file)

      local state = spawn_review(
        neph_cli,
        nvim_socket,
        vim.json.encode({ path = test_file, content = "line1\nline2_CHANGED\nline3" })
      )

      t.wait_for(function()
        return vim.fn.tabpagenr("$") > 1
      end, 5000, "review tab should open")

      -- Accept all hunks then submit
      vim.schedule(function()
        call_review_keymap("gA")
        vim.schedule(function()
          call_review_keymap("gs")
        end)
      end)

      t.wait_for(function()
        return state.exited
      end, 10000, "neph-cli should exit after accept")
      t.assert_eq(state.code, 0, "exit code should be 0 (accept)")

      local parsed = vim.json.decode(table.concat(state.stdout, ""))
      t.assert_eq(parsed.decision, "accept", "decision should be accept")
      t.assert_truthy(parsed.content:find("line2_CHANGED"), "content should contain accepted change")
      t.assert_eq(parsed.hookSpecificOutput, nil, "no agent-specific fields")

      vim.fn.delete(test_file)
    end)

    t.it("reject flow: pressing q rejects all undecided hunks", function()
      local test_file = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "old_content" }, test_file)

      local state = spawn_review(neph_cli, nvim_socket, vim.json.encode({ path = test_file, content = "new_content" }))

      t.wait_for(function()
        return vim.fn.tabpagenr("$") > 1
      end, 5000, "review tab should open")

      -- Quit = reject all undecided
      vim.schedule(function()
        call_review_keymap("q")
      end)

      t.wait_for(function()
        return state.exited
      end, 10000, "neph-cli should exit after reject")
      t.assert_eq(state.code, 2, "exit code should be 2 (reject)")

      local parsed = vim.json.decode(table.concat(state.stdout, ""))
      t.assert_eq(parsed.decision, "reject", "decision should be reject")

      vim.fn.delete(test_file)
    end)

    t.it("dry-run: auto-accepts without Neovim review", function()
      local state = spawn_review(
        neph_cli,
        nvim_socket,
        vim.json.encode({ path = "/tmp/doesnt_matter.lua", content = "anything" }),
        { NEPH_DRY_RUN = "1" }
      )

      t.wait_for(function()
        return state.exited
      end, 5000, "dry-run should complete quickly")
      t.assert_eq(state.code, 0, "exit code should be 0")

      local parsed = vim.json.decode(table.concat(state.stdout, ""))
      t.assert_eq(parsed.decision, "accept", "dry-run should accept")
    end)

    t.it("protocol: stdout is always { decision, content }", function()
      local test_file = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "hello" }, test_file)

      local state = spawn_review(neph_cli, nvim_socket, vim.json.encode({ path = test_file, content = "hello" }))

      t.wait_for(function()
        return state.exited
      end, 5000, "should auto-accept")

      local stdout = table.concat(state.stdout, "")
      local parsed = vim.json.decode(stdout)
      t.assert_truthy(parsed.decision, "must have decision field")
      t.assert_truthy(parsed.content ~= nil, "must have content field")
      -- No agent-specific fields
      t.assert_eq(parsed.hookSpecificOutput, nil, "no hookSpecificOutput")
      t.assert_eq(parsed.permissionDecision, nil, "no permissionDecision")

      vim.fn.delete(test_file)
    end)
  end)
end
