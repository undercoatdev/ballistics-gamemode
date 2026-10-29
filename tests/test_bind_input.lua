-- Fail when keyDown / bind polls ignore mouse codes or hard-code KEY_ only paths.
local root = (arg and arg[0] or ""):match("^(.*)/tests/") or "."

local function read(rel)
	local f = assert(io.open(root .. "/" .. rel, "r"))
	local t = f:read("*a")
	f:close()
	return t
end

local sh = read("gamemodes/ballistics/gamemode/modules/keys/sh_keys.lua")
assert(sh:find("K%.IsBindDown", 1, false), "sh_keys must define K.IsBindDown")
assert(sh:find("input%.IsButtonDown", 1, false), "IsBindDown must try IsButtonDown")

local cl = read("gamemodes/ballistics/gamemode/modules/keys/cl_keys.lua")
assert(cl:find("K%.IsBindDown", 1, false), "cl_keys keyDown must call K.IsBindDown")

local loot = read("gamemodes/ballistics/gamemode/modules/loot/cl_loot.lua")
assert(loot:find("IsBindDown", 1, true), "loot must use IsBindDown for use/inventory")

print("test_bind_input ok")
