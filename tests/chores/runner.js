const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const src = fs.readFileSync(process.argv[2], 'utf8');
const test = fs.readFileSync(process.argv[3], 'utf8');
lua.lua_pushstring(L, to_luastring(src)); lua.lua_setglobal(L, to_luastring('SRC'));
lua.lua_pushstring(L, to_luastring(process.argv[4] || '')); lua.lua_setglobal(L, to_luastring('SRC2'));
const r = lauxlib.luaL_dostring(L, to_luastring(test));
if (r !== lua.LUA_OK) { console.log('LUA ERROR:', lua.lua_tojsstring(L, -1)); process.exit(1); }
