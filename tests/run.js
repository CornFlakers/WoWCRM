// Runs the offline Lua tests. Usage: cd tests && npm install && npm test
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

process.chdir(path.join(__dirname, ".."));
let failed = false;
for (const file of ["tests/test_logic.lua", "tests/test_smoke.lua"]) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  // This Lua VM has no file-reading library, so hand the TOC text to the tests.
  lua.lua_pushstring(L, to_luastring(require("fs").readFileSync("WoWCRM.toc", "utf8")));
  lua.lua_setglobal(L, to_luastring("TOC_TEXT"));
  if (lauxlib.luaL_dofile(L, to_luastring(file)) !== lua.LUA_OK) {
    console.error("FAIL " + file + "\n  " + lua.lua_tojsstring(L, -1));
    failed = true;
  }
}
process.exit(failed ? 1 : 0);
