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
check("zero magazines is infinite", A.WantInfinite(0) == true and A.WantInfinite(nil) == true and A.WantInfinite(-1) == true and A.WritesReserve(0) == false)
check("positive magazines are finite", A.WantInfinite(3) == false and A.WritesReserve(3) == true)
check("no count forces infinite ammo on", A.ForcedValue() == "1" and A.ForcedValue(0) == "1")
check("three magazines forces the convar off", A.ForcedValue(3) == "0")
check("squad reads the firing squad magazine count", A.ActiveMags({ BuyAmmoMags = 3, FiringSquadMags = 0 }, "squad") == 0 and A.ActiveMags({ BuyAmmoMags = 3, FiringSquadMags = 0 }, "live") == 3)

local values = { tacrp_infiniteammo = "0" }
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
check("arming remembers 0 and forces infinite on", values.tacrp_infiniteammo == "1")
values.tacrp_infiniteammo = "0"
callbacks.tacrp_infiniteammo("tacrp_infiniteammo", "1", "0")
check("a change while infinite is forced back to 1", values.tacrp_infiniteammo == "1")
BALLISTICS.Config = { BuyAmmoMags = 3, FiringSquadMags = 0 }
BALLISTICS.Round = { Phase = function() return "live" end }
hook.Run("Ballistics_PhaseChanged")
check("three magazines forces finite ammo", values.tacrp_infiniteammo == "0")
values.tacrp_infiniteammo = "1"
callbacks.tacrp_infiniteammo("tacrp_infiniteammo", "0", "1")
check("a change while finite is forced back to 0", values.tacrp_infiniteammo == "0")
BALLISTICS.Round.Phase = function() return "squad" end
hook.Run("Ballistics_PhaseChanged")
check("squad with 0 magazines turns infinite ammo back on", values.tacrp_infiniteammo == "1")
hook.Run("InitPostEntity")
check("InitPostEntity does not replace the remembered 0", values.tacrp_infiniteammo == "1")
values.tacrp_infiniteammo = "1"
hook.Run("ShutDown")
check("shutdown restores the remembered value", values.tacrp_infiniteammo == "0")
values.tacrp_infiniteammo = "1"
hook.Run("ShutDown")
check("a second shutdown does not invent a value", values.tacrp_infiniteammo == "1")

if failed then os.exit(1) end
