-- HUD hidden while TacRP customize is open. Run: luajit tests/test_hudhide.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end
dofile("tests/support/gmod_stub.lua")
BALLISTICS = BALLISTICS or {}
dofile("gamemodes/ballistics/gamemode/modules/hudhide/sh_hudhide.lua")
local H = BALLISTICS.HudHide
check("PB med row hidden", H.ShouldHide("PlayerBallistics_MedHud"))
check("BD status hidden", H.ShouldHide("BodyDamage_Status"))
check("our keybinds hidden", H.ShouldHide("Ballistics_Keys"))
check("banner kept", not H.ShouldHide("Ballistics_Banner"))
check("squad countdown kept", not H.ShouldHide("Ballistics_SquadFreeze"))
check("TacRP own hud kept", not H.ShouldHide("TacRP_HUD"))
local wep = { ArcticTacRP = true, on = false }
function wep:GetCustomize() return self.on end
check("closed menu", H.Customizing(wep) == false)
wep.on = true
check("open menu", H.Customizing(wep) == true)
check("non TacRP weapon", H.Customizing({}) == false and H.Customizing(nil) == false)

-- client wrap
CLIENT = true
local events = { HUDPaint = {} }
local realAdd = hook.Add
hook.Add = function(e, n, f) events[e] = events[e] or {}; events[e][n] = f; realAdd(e, n, f) end
hook.GetTable = function() return events end
local drawn = 0
hook.Add("HUDPaint", "PlayerBallistics_Hud", function() drawn = drawn + 1 end)
IsValid = function(x) return x ~= nil end
local ply = {}
function ply:GetActiveWeapon() return wep end
LocalPlayer = function() return ply end
dofile("gamemodes/ballistics/gamemode/modules/hudhide/cl_hudhide.lua")
H.Wrap()
wep.on = true
events.HUDPaint.PlayerBallistics_Hud()
check("hidden while customizing", drawn == 0)
wep.on = false
events.HUDPaint.PlayerBallistics_Hud()
check("back instantly on close", drawn == 1)
H.Wrap()
events.HUDPaint.PlayerBallistics_Hud()
check("no double wrap", drawn == 2)
if failed then os.exit(1) end
