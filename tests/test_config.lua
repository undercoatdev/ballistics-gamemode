-- Config defaults, Get/Set, clamp, unknown keys, ResetSection.
-- Run: luajit tests/test_config.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")

local C = BALLISTICS.Config
local r = 2 / 0.01905

check("StartMoney is 1000", C.StartMoney == 1000)
check("SlotsPerTeam is 5", C.SlotsPerTeam == 5)
check("MinPerTeam is 1", C.MinPerTeam == 1)
check("BuyTime is 10", C.BuyTime == 10)
check("RoundTime is 600", C.RoundTime == 600)
check("PostRoundTime is 5", C.PostRoundTime == 5)
check("RoundsToWin is 0 (endless)", C.RoundsToWin == 0)
check("TimeoutWinner is draw", C.TimeoutWinner == "draw")
check("FreezeInBuy is true", C.FreezeInBuy == true)
check("HealthMode is realistic", C.HealthMode == "realistic")
check("Good model is combine soldier", C.ModelGood == "models/player/combine_soldier.mdl")
check("Bad model is combine super soldier", C.ModelBad == "models/player/combine_super_soldier.mdl")
check("ObjectiveRadius is 2 m in Hammer units", math.abs(C.ObjectiveRadius - r) < 1e-9)
check("CustomizeRadius matches ObjectiveRadius", math.abs(C.CustomizeRadius - r) < 1e-9)
check("CaptureTimeOne is 20", C.CaptureTimeOne == 20)
check("CaptureTimeTwo is 10", C.CaptureTimeTwo == 10)
check("CaptureMaxCounted is 2", C.CaptureMaxCounted == 2)
check("CaptureDecay is on", C.CaptureDecay == true)
check("CaptureDecayRate is 1", C.CaptureDecayRate == 1)
check("CaptureContestedFreeze is on", C.CaptureContestedFreeze == true)
check("TickRate is 0.1", C.TickRate == 0.1)
check("BuyAmmoMags is 3", C.BuyAmmoMags == 3)
check("MaxMoney is 0 (no cap)", C.MaxMoney == 0)
check("AttRefundOnDetach is false", C.AttRefundOnDetach == false)
check("AdminSuperOnly is false", C.AdminSuperOnly == false)

check("weapon costs", C.Costs.tacrp_ex_m1911 == 100 and C.Costs.tacrp_mr96 == 500 and C.Costs.tacrp_skorpion == 500 and C.Costs.tacrp_mp5 == 600 and C.Costs.tacrp_ex_ak47 == 900 and C.Costs.tacrp_hk417 == 1000 and C.Costs.tacrp_tgs12 == 900 and C.Costs.tacrp_spr == 700)
check("nade costs", C.Costs.nade_frag == 500 and C.Costs.nade_smoke == 200 and C.Costs.nade_thermite == 700 and C.Costs.nade_flashbang == 250)
check("med costs", C.Costs.med_pills == 50 and C.Costs.med_small == 80 and C.Costs.med_trauma == 100 and C.Costs.med_resus == 500)
check("att costs", C.AttCosts.optic == 250 and C.AttCosts.bolt == 100 and C.AttCosts.muzzle == 100 and C.AttCosts.trigger == 200 and C.AttCosts.tactical == 300 and C.AttCosts.ammo == 400 and C.AttCosts.accessory == 200 and C.AttCosts.perk == 700)
check("gains", C.Gains.kill == 500 and C.Gains.round_win == 1000 and C.Gains.round_loss == 500 and C.Gains.draw == 500)
check("buy limits unlimited", C.BuyLimits.weapon_per_round == 0 and C.BuyLimits.nade_each == 0)

check("Get StartMoney", C.Get("StartMoney") == 1000)
check("Get nested cost", C.Get("Costs.tacrp_mp5") == 600)

local ok, val = C.Set("StartMoney", 1200)
check("Set StartMoney", ok == true and val == 1200 and C.StartMoney == 1200)

ok, val = C.Set("StartMoney", -50)
check("negative money clamps to 0", ok == true and val == 0 and C.StartMoney == 0)

ok, val = C.Set("BuyTime", 0)
check("time below 1 clamps to 1", ok == true and val == 1 and C.BuyTime == 1)

ok, val = C.Set("BuyTime", 9999)
check("time above 3600 clamps to 3600", ok == true and val == 3600 and C.BuyTime == 3600)

ok, val = C.Set("ObjectiveRadius", 5)
check("radius below 16 clamps to 16", ok == true and val == 16 and C.ObjectiveRadius == 16)

ok, val = C.Set("ObjectiveRadius", 5000)
check("radius above 1000 clamps to 1000", ok == true and val == 1000 and C.ObjectiveRadius == 1000)

ok = C.Set("NotAKey", 1)
check("unknown top-level key refused", ok == false)

ok = C.Set("Costs.not_a_gun", 10)
check("unknown cost key refused", ok == false)

ok, val = C.Set("Costs.tacrp_mp5", 650)
check("nested cost set", ok == true and val == 650 and C.Costs.tacrp_mp5 == 650)

ok, val = C.Set("HealthMode", "ARCADE")
check("HealthMode normalises to lowercase", ok == true and val == "arcade" and C.HealthMode == "arcade")

ok = C.Set("HealthMode", "hardcore")
check("invalid HealthMode refused", ok == false and C.HealthMode == "arcade")

C.Apply({
	foo = 123,
	StartMoney = 400,
	Costs = { tacrp_mp5 = 50, nade_gas = 99, tacrp_ak47 = 1 },
	Gains = { kill = -20 },
})
check("Apply ignores unknown top-level key", C.foo == nil)
check("Apply sets known key", C.StartMoney == 400)
check("Apply nested known cost", C.Costs.tacrp_mp5 == 50)
check("Apply ignores unknown cost keys", C.Costs.nade_gas == nil and C.Costs.tacrp_ak47 == nil)
check("Apply clamps nested negative gain", C.Gains.kill == 0)

C.ResetSection("gains")
check("ResetSection gains restores kill", C.Gains.kill == 500 and C.Gains.round_win == 1000)
check("ResetSection gains leaves StartMoney", C.StartMoney == 400)

C.ResetSection("weapons")
check("ResetSection weapons restores gun prices only", C.Costs.tacrp_mp5 == 600 and C.Costs.nade_frag == 500)

C.ResetSection("General")
check("ResetSection General restores StartMoney and radii", C.StartMoney == 1000 and math.abs(C.ObjectiveRadius - r) < 1e-9 and C.BuyTime == 10 and C.HealthMode == "realistic")

C.Set("SlotsPerTeam", 8)
C.ResetSection("teams")
check("ResetSection teams", C.SlotsPerTeam == 5 and C.MinPerTeam == 1)

C.Set("AttCosts.perk", 1)
C.ResetSection("attachments")
check("ResetSection attachments", C.AttCosts.perk == 700 and C.AttRefundOnDetach == false)

local exported = C.Export()
check("Export has StartMoney and no Get function", exported.StartMoney == 1000 and exported.Get == nil and exported.Set == nil)
check("Export copies nested tables", exported.Costs ~= C.Costs and exported.Costs.tacrp_spr == 700)

C.Set("StartMoney", 1)
C.Reset()
check("Reset restores every default", C.StartMoney == 1000 and C.Costs.tacrp_mp5 == 600 and C.HealthMode == "realistic")

local admin = { IsAdmin = function() return true end, IsSuperAdmin = function() return false end }
local super = { IsAdmin = function() return true end, IsSuperAdmin = function() return true end }
local user = { IsAdmin = function() return false end, IsSuperAdmin = function() return false end }
check("IsAdmin accepts admins", BALLISTICS.IsAdmin(admin) == true)
check("IsAdmin rejects players", BALLISTICS.IsAdmin(user) == false)
C.Set("AdminSuperOnly", true)
check("AdminSuperOnly requires superadmin", BALLISTICS.IsAdmin(admin) == false and BALLISTICS.IsAdmin(super) == true)
C.Set("AdminSuperOnly", false)

-- Load the rest of core so syntax errors fail this test.
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_deps.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_config.lua")
check("TEAM_GOOD and TEAM_BAD", TEAM_GOOD == 1 and TEAM_BAD == 2)
check("Net registry exists", BALLISTICS.Net and type(BALLISTICS.Net.Register) == "function")
check("SaveConfig exists on server stub", type(BALLISTICS.SaveConfig) == "function")
check("buy menu disabled without TacRP", BALLISTICS.BuyDisabled == true)
check("IsConscious of a living player", BALLISTICS.IsConscious({ Alive = function() return true end }) == true)
check("IsConscious of a dead player", BALLISTICS.IsConscious({ Alive = function() return false end }) == false)
check("IsConscious of a knocked-out player", BALLISTICS.IsConscious({ Alive = function() return true end, pbDown = true }) == false)

if failed then os.exit(1) end
