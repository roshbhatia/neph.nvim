## Module Layout

```
lua/neph/
├── internal/
│   └── git.lua          NEW  pure git utilities (diff_lines, merge_base, in_git_repo)
├── api/
│   └── diff.lua         NEW  review(scope, opts) + picker(scope)
└── api.lua              +    diff_review(scope, opts), diff_picker(scope)
```

## `neph/internal/git.lua`

Direct port of `sysinit/utils/diff_review/git.lua` with no semantic changes. Exposes:

```lua
M.in_git_repo(cwd?)          → boolean
M.git_lines(args, opts?)     → string[]|nil, string|nil
M.merge_base(opts?)          → string|nil, string|nil
M.diff_lines(scope, opts?)   → string[]|nil, string|nil
```

`diff_lines` scope values: `"head"`, `"staged"`, `"branch"`, `"file"`.
Hunk-scope diff is handled separately in `api/diff.lua` (requires gitsigns, not pure git).

## `neph/api/diff.lua`

```lua
-- Build the prompt message: structured diff block with preamble
local function build_message(prompt, lines) → string

-- Get hunk lines at cursor position via gitsigns (pcall-guarded)
local function current_hunk_lines() → string[]|nil, string|nil

-- Resolve prompt text from config or fallback
local function resolve_prompt(scope) → string

-- Core: get diff for scope, build message, send to active agent
M.review(scope, opts)
  -- scope: "head"|"staged"|"branch"|"file"|"hunk"
  -- opts: { prompt?, cwd?, file?, merge_base_targets?, branch_fallback?, submit? }
  -- returns: boolean, string|nil (success, error)

-- Open snacks git diff picker (pcall-guarded)
M.picker(scope)
  -- scope: "head"|"staged"|"branch"
  -- returns: boolean, string|nil
```

**No provider registry.** The only "provider" is `require("neph.internal.session").ensure_active_and_send(message)`. If no agent is active, the session module already notifies the user — no special handling needed in diff.

## Config Schema (`neph/config.lua`)

```lua
diff = {
  prompts = {
    review = "Review this diff carefully. Identify any bugs, logic errors, "
          .. "security issues, missing edge-cases, or places where the intent "
          .. "of the change is unclear. Be concise and specific — cite line "
          .. "numbers where relevant.",
    hunk   = "Review this specific hunk. What does it change, is the change "
          .. "correct, and are there any issues?",
  },
  branch_fallback = "HEAD~1",  -- used when merge-base resolution fails
}
```

All fields optional; defaults apply when absent.

## Public API (`neph/api.lua`)

```lua
--- Send a git diff to the active agent.
--- scope: "head"|"staged"|"branch"|"file"|"hunk"
function M.diff_review(scope, opts)

--- Open a snacks.nvim git diff picker.
--- scope: "head"|"staged"|"branch"
function M.diff_picker(scope)
```

These are thin wrappers: validate scope, delegate to `neph.api.diff`.

## Keymap Layout (sysinit/plugins/neph.lua)

```lua
-- Pickers (browse, no agent send)
{ "<leader>drr", function() api.diff_picker("head")    end, desc = "Diff: browse HEAD" },
{ "<leader>drs", function() api.diff_picker("staged")  end, desc = "Diff: browse staged" },
{ "<leader>drf", function() api.diff_picker("branch")  end, desc = "Diff: browse branch" },

-- AI review (send to active agent)
{ "<leader>dra", function() api.diff_review("head")    end, desc = "Diff: review HEAD" },
{ "<leader>drS", function() api.diff_review("staged")  end, desc = "Diff: review staged" },
{ "<leader>drb", function() api.diff_review("branch")  end, desc = "Diff: review branch" },
{ "<leader>drF", function() api.diff_review("file")    end, desc = "Diff: review file" },
{ "<leader>drh", function() api.diff_review("hunk")    end, desc = "Diff: review hunk" },
```

## Dependency Notes

- **gitsigns**: Used only for hunk review. Loaded via `pcall`; graceful error if absent.
- **snacks**: Used only for picker functions. Loaded via `pcall`; graceful error if absent.
- Neither is a hard dependency of neph.

## What Gets Deleted

- `~/.config/nvim/lua/sysinit/plugins/diff-review.lua` — entire file
- `~/.config/nvim/lua/sysinit/utils/diff_review/init.lua` — entire file
- `~/.config/nvim/lua/sysinit/utils/diff_review/git.lua` — entire file
- `~/.config/nvim/lua/sysinit/utils/diff_review/` — directory

## Complexity Delta

```
Before:  ~470 lines across 3 files (provider registry, git utils, plugin spec)
After:   ~200 lines across 2 new files + small additions to api.lua/config.lua
```

The provider abstraction layer disappears entirely. Hunk review is inline rather than split.
