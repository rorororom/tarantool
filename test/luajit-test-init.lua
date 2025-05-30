-- Disable strict for Tarantool.
require("strict").off()

local ffi = require('ffi')
local alloc = require('internal.alloc')
local loaders = require('internal.loaders')

-- XXX: lua-Harness test suite uses it's own tap.lua module
-- that conflicts with the Tarantool's one.
package.loaded.tap = nil
loaders.builtin.tap = nil
-- XXX: lua-Harness test suite checks that utf8 module presents
-- only in Lua5.3 or moonjit.
utf8 = nil

-- There are some tests launching Lua interpreter, so strict need
-- to be disabled for the child tests too. Hence `strict.off()` is
-- added to `progname` command used in these tests.
-- Unlike LuaJIT, Tarantool doesn't store the given CLI flags in
-- `arg`, so the table has the following layout:
-- * arg[-1] -- the binary name
-- * arg[0]  -- the script name
-- * arg[N]  -- the script argument for all N in [1, #arg]
-- The former one can be used to adjust the command to be used in
-- child tests.
-- XXX: Quotes types are important.
-- XXX: luacheck thinks that `arg` is read-only global variable.
-- luacheck: no global
arg[-1] = arg[-1]..' -e "require[[strict]].off()"'

-- XXX: PUC Rio Lua 5.1 test suite checks that global variable
-- `_loadfile()` exists and uses it for code loading from test
-- files. If the variable is not defined then suite uses
-- `loadfile()` as default. Same for the `_dofile()`.

-- XXX: Some tests in PUC Rio Lua 5.1 test suite clean `arg`
-- variable, so evaluate this once and use later.
local path_to_sources = arg[0]:gsub("[^/]+$", "")

-- luacheck: no global
function _loadfile(filename)
  return loadfile(path_to_sources..filename)
end

-- luacheck: no global
function _dofile(filename)
  return dofile(path_to_sources..filename)
end

-- Tarantool has its own print() function.
--
-- There are tests, which check something around a Lua/C function
-- and use print() as a well known example of such function. The
-- easiest way to mitigate problems in the tests is to replace
-- print() back to the original one.
--
-- Our own print() is a simple wrapper around the original print()
-- and performs some extra actions only in the interactive mode.
-- It seems more or less safe to skip testing of the wrapper on
-- LuaJIT's test suites.
--
-- Examples from LuaJIT test suites that fail with tarantool's
-- print() function:
--
--  | PUC-Rio-Lua-5.1-tests/db.lua
--  | ----------------------------
--  | local a = debug.getinfo(print)
--  | assert(a.what == "C" and a.short_src == "[C]")
--  | -- In tarantool: a.what == "Lua"
--  | -- In tarantool: a.short_src == "builtin/internal.print.lua"
--
--  | lua-Harness-tests/301-basic.t
--  | -----------------------------
--  | setfenv(print, {})
--  | -- Expected error: 'setfenv' cannot change environment of
--  | -- given object.
--  | -- In tarantool: success.
--
--  | lua-Harness-tests/304-string.t
--  | ------------------------------
--  | string.dump(print)
--  | -- Expected error: unable to dump given function.
--  | -- In tarantool: success.
--
--  | lua-Harness-tests/304-string.t
--  | ------------------------------
--  | tostring(print)
--  | Expected: 'function: builtin#29' (or similar).
--  | In tarantool: 'function: 0x40e88018' (or similar).
local print_M = require('internal.print')
rawset(_G, 'print', print_M.raw_print)
assert(print ~= nil)
assert(type(print) == 'function')

-- Tarantool has its own pairs() function.
--
-- There is a test (PUC-Rio-Lua-5.1-tests/db.lua) in LuaJIT regression suite,
-- that become broken with patched version of pairs().
-- Here we replace patched version by original one.
local pairs_M = require('internal.pairs')
rawset(_G, 'pairs', pairs_M.builtin_pairs)
assert(pairs ~= nil)
assert(type(pairs) == 'function')

-- Disable the override loader.
--
-- If the override loader is enabled at least one test in the
-- LuaJIT submodule fails: PUC-Rio-Lua-5.1-tests/attrib.lua.
--
-- A sketchy description of the test case of the question is the
-- following.
--
-- There is a directory:
--
--  | + libs/
--  | +- foo.lua
--  | +- bar.lua
--
-- And the Lua code:
--
--  | package.path = 'libs/?.lua;libs/bar.lua'
--  | local foo = require('foo')
--
-- The test case expects that `foo` contains a return value of
-- libs/foo.lua.
--
-- However, when the override loader is enabled, the following
-- occurs. The override loader attempts to find `override.foo`: it
-- tries `libs/?.lua` first -- it means `libs/override/foo.lua`
-- and there is no such file. Then the loader tries `libs/bar.lua`
-- and succeeds.
--
-- So `foo` contains a return value of `libs/bar.lua`.
--
-- Unlikely there is a valid user scenario for a package.path
-- entry without the interrogation mark. We consider this override
-- loader behavior as valid. The loader is disabled to pass the
-- test suite, but likely it would be more correct to discard the
-- test case.
loaders.override_builtin_disable()

-- Increase the default Lua memory limit.
--
-- Some tests in the tarantool-tests suite of LuaJIT assume that
-- for the GC64 build we have more than 4 GB of Lua memory.
-- Increase the limit to 128 TiB (LuaJIT maximum for GC64 mode).
if ffi.abi('gc64') then
  alloc.setlimit(128 * 1024 * 1024 * 1024 * 1024)
end

-- This is workaround introduced for flaky macosx tests reported by
-- https://github.com/tarantool/tarantool/issues/7058
collectgarbage('collect')
