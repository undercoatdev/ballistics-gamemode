-- Finite ammo reserve: N magazines of this gun, not TacRP's injected default.
-- Run: luajit tests/test_ammo.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/modules/buy/sh_buy.lua")
dofile("gamemodes/ballistics/gamemode/modules/ammo/sh_ammo.lua")

local A = BALLISTICS.Ammo
check("three mags on an empty gun", A.ReserveTarget(0, 30, 3) == 90)
check("reserve adds to ammo already held", A.ReserveTarget(90, 30, 3) == 180)
check("zero mags leaves the previous reserve", A.ReserveTarget(40, 30, 0) == 40)
check("negative before counts as empty", A.ReserveTarget(-5, 10, 2) == 20)
check("injected default is ignored", A.ReserveAfterGive(0, 60, 30, 3) == 90)
check("shared ammo ignores the injection too", A.ReserveAfterGive(90, 150, 30, 3) == 180)
check("forced convar value is 0", A.ForcedValue() == "0")

local values = { tacrp_infiniteammo = "1" }
local callbacks = {}
function GetConVar(name)
	return {
		GetString = function() return values[name] end,
		SetString = function(_, v) values[name] = tostring(v) end,
		SetInt = function(_, v) values[name] = tostring(v) end,
	}
end
cvars = {
	AddChangeCallback = function(name, fn, id)
		callbacks[name] = fn
		callbacks[id] = fn
	end,
}
dofile("gamemodes/ballistics/gamemode/modules/ammo/sv_ammo.lua")
check("arming remembers 1 and forces 0", values.tacrp_infiniteammo == "0")
values.tacrp_infiniteammo = "1"
callbacks.tacrp_infiniteammo("tacrp_infiniteammo", "0", "1")
check("a change while running is forced back to 0", values.tacrp_infiniteammo == "0")
hook.Run("InitPostEntity")
check("InitPostEntity does not remember the forced 0", values.tacrp_infiniteammo == "0")
hook.Run("ShutDown")
check("shutdown restores the remembered value", values.tacrp_infiniteammo == "1")
values.tacrp_infiniteammo = "0"
hook.Run("ShutDown")
check("a second shutdown does not invent a value", values.tacrp_infiniteammo == "0")

if failed then os.exit(1) end
