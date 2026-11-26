const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const src = fs.readFileSync(process.argv[2], 'utf8');
const test = fs.readFileSync(process.argv[3], 'utf8');
lua.lua_pushstring(L, to_luastring(src)); lua.lua_setglobal(L, to_luastring('SRC'));
// extra sources: argv[4..] become SRC2, SRC3, ... (an existing file path is read; anything else is used as literal source)
for (let i = 4; i < process.argv.length; i++) {
  const a = process.argv[i];
  const text = (a.length < 400 && fs.existsSync(a)) ? fs.readFileSync(a, 'utf8') : a;
  lua.lua_pushstring(L, to_luastring(text)); lua.lua_setglobal(L, to_luastring('SRC' + (i - 2)));
}
if (process.argv.length < 5) { lua.lua_pushstring(L, to_luastring('')); lua.lua_setglobal(L, to_luastring('SRC2')); }
const r = lauxlib.luaL_dostring(L, to_luastring(test));
if (r !== lua.LUA_OK) { console.log('LUA ERROR:', lua.lua_tojsstring(L, -1)); process.exit(1); }
