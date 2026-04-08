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
    "211", -- unused local variable
    "212", -- unused argument
    "213", -- unused loop variable
    "221", -- local variable is accessed but never set
    "311", -- value assigned to a local variable is never used
    "312", -- value of an argument is never used
  },
}
