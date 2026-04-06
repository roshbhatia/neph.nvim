-- .luacheckrc — luacheck configuration for neph.nvim
-- https://luacheck.readthedocs.io/en/stable/config.html

globals = { "vim", "Snacks" }
std = "lua54"

-- Test files use intentional stubs with unused args and local helpers
-- that are never called directly (e.g. `local function close_tab() end`
-- set up for later use, or callbacks with signature-mandated params).
files["tests/"] = {
  ignore = {
    "211", -- unused variable
    "212", -- unused variable in loop
    "213", -- unused argument
    "214", -- unused argument (self)
    "221", -- unused function (local function defined but not called)
  },
}
