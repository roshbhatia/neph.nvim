-- .luacheckrc — luacheck configuration for neph.nvim
-- https://luacheck.readthedocs.io/en/stable/config.html

globals = { "vim", "Snacks", "unpack" }
std = "lua54"

-- Test files use intentional stubs, monkey-patches, and callbacks whose
-- signatures are mandated by the framework (unused args, shadowed locals, etc.)
files["tests/"] = {
  ignore = {
    "112", -- accessing undefined global (e.g. captured upvalues in closures)
    "122", -- setting read-only field of a global (monkey-patching os/math)
    "211", -- unused variable
    "212", -- unused variable in loop
    "213", -- unused argument
    "214", -- unused argument (self)
    "221", -- unused function (local function defined but not called)
    "311", -- value assigned to variable is unused
    "312", -- value of a field is unused
  },
}
