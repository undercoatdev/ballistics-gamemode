-- Rules view model: sections, minute/metre conversion, reset scope, admin gate.
-- Run: luajit tests/test_rules.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_tabs.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_rules.lua")

local C = BALLISTICS.Config
local V = BALLISTICS.RulesView
local radius = 2 / 0.01905

local function rowMap(section)
	local map = {}
	local rows = V.Rows(section)
	for i = 1, #rows do
		map[rows[i].path] = rows[i]
	end
	return map, rows
end

check("ten minutes is 600 seconds", V.FromMinutes(10) == 600 and V.ToMinutes(600) == 10)
check("one and a half minutes is 90 seconds", V.FromMinutes(1.5) == 90 and V.ToMinutes(90) == 1.5)
check("minutes round-trip", V.FromMinutes(V.ToMinutes(600)) == 600)
check("two metres is the shipped radius", math.abs(V.FromMetres(2) - radius) < 1e-9)
check("the shipped radius is two metres", math.abs(V.ToMetres(radius) - 2) < 1e-6)
check("metres round-trip", math.abs(V.FromMetres(V.ToMetres(radius)) - radius) < 1e-6)

local editors = V.Editors()
check("six editors", #editors == 6)
local editorSet = {}
for i = 1, #editors do
	editorSet[editors[i]] = true
	local req = V.ResetPayload(editors[i])
	local rows = V.Rows(editors[i])
	if not (req and req.reset == true and req.section == editors[i] and #rows > 0) then
		editorSet[editors[i]] = false
	end
end
check("each editor resets only its own section and has rows", editorSet.weapons and editorSet.throwables and editorSet.meds and editorSet.attachments and editorSet.gains and editorSet.general)

local rulesReq = V.ResetPayload("rules")
local costsReq = V.ResetPayload("costs")
check("rules and costs parents reset their own sections", rulesReq and rulesReq.section == "rules" and costsReq and costsReq.section == "costs")
check("parent tabs have no direct fields", #V.Rows("rules") == 0 and #V.Rows("costs") == 0 and #V.Rows("nope") == 0)
check("an unknown tab has no reset", V.ResetPayload("nope") == nil)
check("spawns reset is not a config section", V.ResetPayload("spawns").kind == "spawns" and V.ResetPayload("spawns").section == nil)

local weapons = V.Rows("weapons")
local throwables = V.Rows("throwables")
local meds = V.Rows("meds")
local atts = V.Rows("attachments")
local gains = V.Rows("gains")
check("weapon rows use catalog names", #weapons == 8 and weapons[1].label == "Colt M1911" and weapons[1].path == "Costs.tacrp_ex_m1911" and weapons[1].display == 100)
check("throwable rows use catalog names", #throwables == 4 and throwables[1].label == "Frag grenade" and throwables[1].path == "Costs.nade_frag")
check("med rows use catalog names", #meds == 4 and meds[1].label == "Pills" and meds[4].label == "Resuscitation kit" and meds[4].path == "Costs.med_resus")
check("attachment rows use price keys", #atts == 11 and atts[9].label == "Technique" and atts[9].display == 300 and atts[10].display == 500 and atts[11].label == "Boost" and atts[11].display == 500 and atts[1].label == "Optic" and atts[1].path == "AttCosts.optic" and atts[8].label == "Perk" and atts[8].display == 700)
check("gain rows", #gains == 4 and gains[1].path == "Gains.kill" and gains[1].display == 500 and gains[2].label == "Round win" and gains[2].display == 1000 and gains[3].path == "Gains.round_loss" and gains[4].path == "Gains.draw")

local generalMap, general = rowMap("general")
local generalPaths = {
	"RoundTime", "BuyTime", "PostRoundTime", "StartMoney", "MaxMoney",
	"HealedUpOrgans",
	"CaptureTimeOne", "CaptureTimeTwo", "CaptureDecay", "CaptureContestedFreeze",
	"ObjectiveRadius", "CustomizeRadius", "BuyAmmoMags",
}
local generalOk = #general == #generalPaths
for i = 1, #generalPaths do
	if not general[i] or general[i].path ~= generalPaths[i] then generalOk = false end
end
check("general fields are the rules list, in order", generalOk)
check("general hides models, tick rate, and admin flag", generalMap.ModelGood == nil and generalMap.TickRate == nil and generalMap.AdminSuperOnly == nil and generalMap.TimeoutWinner == nil)
check("general no longer holds rounds-to-win or health mode", generalMap.RoundsToWin == nil and generalMap.HealthMode == nil)
check("round length is shown in minutes", generalMap.RoundTime.kind == "minutes" and generalMap.RoundTime.display == 10 and generalMap.RoundTime.unit == "min" and generalMap.RoundTime.max == 60)
check("buy time stays in seconds", generalMap.BuyTime.display == 20 and generalMap.BuyTime.unit == "s" and generalMap.BuyTime.kind == "number")
check("radii are shown in metres", generalMap.ObjectiveRadius.kind == "metres" and generalMap.ObjectiveRadius.unit == "m" and math.abs(generalMap.ObjectiveRadius.display - 2) < 1e-6 and math.abs(generalMap.CustomizeRadius.display - 2) < 1e-6)
check("capture flags are booleans", generalMap.CaptureDecay.kind == "bool" and generalMap.CaptureDecay.display == true and generalMap.CaptureContestedFreeze.display == true)
check("magazines per gun", generalMap.BuyAmmoMags.label == "Magazines per gun" and generalMap.BuyAmmoMags.display == 0 and generalMap.BuyAmmoMags.blurb == "0 = infinite ammo.")
local organBlurb = "At each new round every organ heals this many units (capped at max). Destroyed organs always come back working, just weak."
check("healed organs row", generalMap.HealedUpOrgans.label == "Healed up organs" and generalMap.HealedUpOrgans.kind == "int" and generalMap.HealedUpOrgans.display == 10 and generalMap.HealedUpOrgans.min == 0 and generalMap.HealedUpOrgans.max == 100 and generalMap.HealedUpOrgans.blurb == organBlurb)

local settingsMap, settings = rowMap("settings")
check("Admin Settings holds rounds to win then health mode", #settings == 3 and settings[1].path == "RoundsToWin" and settings[2].path == "HealthMode" and settings[3].path == "BulletPushForce" and settingsMap.BulletPushForce.display == 0.5)
check("rounds to win row", settingsMap.RoundsToWin.label == "Rounds to win (0 = endless)" and settingsMap.RoundsToWin.kind == "int" and settingsMap.RoundsToWin.display == 3 and settingsMap.RoundsToWin.min == 0 and settingsMap.RoundsToWin.max == 1000)
check("health mode is a realistic/arcade switch", settingsMap.HealthMode.kind == "enum" and settingsMap.HealthMode.display == "realistic" and settingsMap.HealthMode.values[1].id == "realistic" and settingsMap.HealthMode.values[2].label == "Arcade")
check("Admin Settings reset is its own section", V.ResetPayload("settings") and V.ResetPayload("settings").section == "settings")

local committed = V.Commit(generalMap.RoundTime, 12)
check("committing minutes stores seconds", committed and committed.key == "RoundTime" and committed.value == 720)
committed = V.Commit(generalMap.ObjectiveRadius, 3)
check("committing metres stores hammer units", committed and committed.key == "ObjectiveRadius" and math.abs(committed.value - V.FromMetres(3)) < 1e-9)
committed = V.Commit(settingsMap.HealthMode, "Arcade")
check("health mode commit normalises case", committed and committed.value == "arcade")
check("an unknown health mode is refused", V.Commit(settingsMap.HealthMode, "hardcore") == nil)
committed = V.Commit(generalMap.CaptureDecay, false)
check("bool commit", committed and committed.key == "CaptureDecay" and committed.value == false)
committed = V.Commit(gains[1], 10.9)
check("gain commit floors", committed and committed.key == "Gains.kill" and committed.value == 10)
check("a bad number is refused", V.Commit(gains[1], "abc") == nil)

C.Set("RoundTime", 90)
C.Set("ObjectiveRadius", V.FromMetres(4))
local edited = rowMap("general")
check("rows follow the live config", edited.RoundTime.display == 1.5 and math.abs(edited.ObjectiveRadius.display - 4) < 1e-6)
check("same display is not a new edit", V.Same(10, 10) and V.Same(10, 10.0001) and V.Same("10", 10) and not V.Same(10, 10.01) and not V.Same(true, false))

local function dirty()
	C.Reset()
	C.Set("Costs.tacrp_mp5", 11)
	C.Set("Costs.nade_frag", 12)
	C.Set("Costs.med_pills", 13)
	C.Set("AttCosts.perk", 14)
	C.Set("AttRefundOnDetach", true)
	C.Set("Gains.kill", 15)
	C.Set("Gains.round_win", 16)
	C.Set("StartMoney", 17)
	C.Set("RoundTime", 120)
	C.Set("HealthMode", "arcade")
	C.Set("ObjectiveRadius", 200)
	C.Set("CustomizeRadius", 180)
	C.Set("SlotsPerTeam", 8)
	C.Set("BuyLimits.weapon_per_round", 2)
	C.Set("CaptureDecay", false)
	C.Set("BuyTime", 30)
	C.Set("HealedUpOrgans", 33)
	C.Set("BuyAmmoMags", 9)
end

local function nearRadius()
	return math.abs(C.ObjectiveRadius - radius) < 1e-6 and math.abs(C.CustomizeRadius - radius) < 1e-6
end

dirty()
C.ResetSection(V.ResetPayload("weapons").section)
check("weapons reset restores guns only", C.Costs.tacrp_mp5 == 600 and C.Costs.nade_frag == 12 and C.Costs.med_pills == 13 and C.AttCosts.perk == 14 and C.Gains.kill == 15 and C.StartMoney == 17 and C.SlotsPerTeam == 8)

dirty()
C.ResetSection(V.ResetPayload("throwables").section)
check("throwables reset restores nades only", C.Costs.nade_frag == 500 and C.Costs.tacrp_mp5 == 11 and C.Costs.med_pills == 13)

dirty()
C.ResetSection(V.ResetPayload("meds").section)
check("meds reset restores meds only", C.Costs.med_pills == 50 and C.Costs.nade_frag == 12 and C.Costs.tacrp_mp5 == 11)

dirty()
C.ResetSection(V.ResetPayload("attachments").section)
check("attachments reset restores att prices only", C.AttCosts.perk == 700 and C.AttRefundOnDetach == false and C.Costs.tacrp_mp5 == 11)

dirty()
C.ResetSection(V.ResetPayload("gains").section)
check("gains reset restores gains only", C.Gains.kill == 500 and C.Gains.round_win == 1000 and C.StartMoney == 17 and C.Costs.tacrp_mp5 == 11)

dirty()
C.ResetSection(V.ResetPayload("general").section)
check("general reset restores general only", C.StartMoney == 1000 and C.RoundTime == 600 and C.BuyTime == 20 and C.CaptureDecay == true and nearRadius() and C.Gains.kill == 15 and C.Costs.tacrp_mp5 == 11 and C.AttCosts.perk == 14 and C.SlotsPerTeam == 8 and C.BuyLimits.weapon_per_round == 2 and C.HealedUpOrgans == 10 and C.BuyAmmoMags == 0)
check("general reset leaves Admin Settings keys", C.HealthMode == "arcade" and C.RoundsToWin == 3)

dirty()
C.Set("RoundsToWin", 7)
C.ResetSection(V.ResetPayload("settings").section)
check("settings reset restores rounds and health only", C.RoundsToWin == 3 and C.HealthMode == "realistic" and C.StartMoney == 17 and C.RoundTime == 120)

dirty()
C.ResetSection(V.ResetPayload("costs").section)
check("costs reset restores every item price and not attachments", C.Costs.tacrp_mp5 == 600 and C.Costs.nade_frag == 500 and C.Costs.med_pills == 50 and C.AttCosts.perk == 14 and C.AttRefundOnDetach == true and C.Gains.kill == 15)

dirty()
C.ResetSection(V.ResetPayload("rules").section)
check("rules reset restores rules and leaves teams and buy limits", C.Costs.tacrp_mp5 == 600 and C.Costs.nade_frag == 500 and C.Costs.med_pills == 50 and C.AttCosts.perk == 700 and C.AttRefundOnDetach == false and C.Gains.kill == 500 and C.Gains.round_win == 1000 and C.StartMoney == 1000 and C.RoundTime == 600 and C.HealthMode == "arcade" and C.CaptureDecay == true and nearRadius() and C.SlotsPerTeam == 8 and C.BuyLimits.weapon_per_round == 2 and C.HealedUpOrgans == 10 and C.BuyAmmoMags == 0)

dirty()
local unknownOk = C.ResetSection("nope")
check("an unknown section does not reset", unknownOk == false and C.Costs.tacrp_mp5 == 11 and C.StartMoney == 17)

local sneaky = { key = "StartMoney", value = 1, SlotsPerTeam = 9, reset = false }
local clean = V.PayloadFor(true, sneaky)
check("an admin edit keeps one key", clean and clean.key == "StartMoney" and clean.value == 1 and clean.SlotsPerTeam == nil and clean.reset == nil)
local resetClean = V.PayloadFor(true, { reset = true, section = "weapons", key = "StartMoney", value = 0 })
check("a reset payload stays a reset", resetClean and resetClean.reset == true and resetClean.section == "weapons" and resetClean.key == nil)
check("a non-admin edit is dropped", V.PayloadFor(false, sneaky) == nil and V.PayloadFor(nil, sneaky) == nil and V.PayloadFor(true, { reset = true }) == nil and V.PayloadFor(true, "nope") == nil)

-- Server gate: bal_config_set is admin-only and the schema clamps it.
local clock = 0
CurTime = function() return clock end
local nextPayload = {}
function net.ReadTable()
	return nextPayload
end
local handlers = {}
function net.Receive(name, fn)
	handlers[name] = fn
end
dofile("gamemodes/ballistics/gamemode/core/sv_config.lua")

local function person(admin, super)
	return {
		IsAdmin = function() return admin == true end,
		IsSuperAdmin = function() return super == true end,
	}
end

local admin = person(true, false)
local user = person(false, false)
local super = person(true, true)

local function drive(ply, payload)
	clock = clock + 1
	nextPayload = payload
	handlers["bal_config_set"](0, ply)
end

check("config set is registered", handlers["bal_config_set"] ~= nil)

C.Set("StartMoney", 42)
drive(nil, { key = "StartMoney", value = 1 })
drive(user, { key = "StartMoney", value = 1 })
drive(user, { reset = true, section = "general" })
drive(user, { StartMoney = 1 })
drive({}, { key = "StartMoney", value = 1 })
check("non-admins cannot change config", C.StartMoney == 42)

drive(admin, { key = "StartMoney", value = 77 })
check("an admin edit is saved", C.StartMoney == 77)
drive(admin, { key = "RoundTime", value = 99999 })
check("the schema clamps round time", C.RoundTime == 3600)
drive(admin, { key = "ObjectiveRadius", value = 1 })
check("the schema clamps radius", C.ObjectiveRadius == 16)
drive(admin, { key = "Costs.nade_frag", value = -5 })
check("the schema clamps a negative cost", C.Costs.nade_frag == 0)
drive(admin, { key = "HealthMode", value = "Arcade" })
check("the schema normalises health mode", C.HealthMode == "arcade")
drive(admin, { key = "NotAKey", value = 5 })
check("an unknown key is ignored", C.NotAKey == nil and C.StartMoney == 77)

C.Set("Costs.tacrp_mp5", 11)
C.Set("Costs.nade_frag", 12)
drive(user, { reset = true, section = "weapons" })
check("a non-admin cannot reset", C.Costs.tacrp_mp5 == 11)
drive(admin, { reset = true, section = "weapons" })
check("an admin weapons reset leaves throwables", C.Costs.tacrp_mp5 == 600 and C.Costs.nade_frag == 12)

local minuteRow = rowMap("general").RoundTime
local minuteEdit = V.Commit(minuteRow, 12)
drive(admin, V.PayloadFor(true, minuteEdit))
check("the admin path stores minutes as seconds", C.RoundTime == 720)
local metreRow = rowMap("general").ObjectiveRadius
drive(admin, V.PayloadFor(true, V.Commit(metreRow, 3)))
check("the admin path stores metres as units", math.abs(C.ObjectiveRadius - V.FromMetres(3)) < 1e-6)

C.Set("SlotsPerTeam", 8)
C.Set("StartMoney", 17)
drive(admin, { reset = true, section = "rules" })
check("an admin rules reset leaves team size", C.StartMoney == 1000 and C.SlotsPerTeam == 8 and C.RoundTime == 600)

C.Set("AdminSuperOnly", true)
C.Set("BuyTime", 30)
drive(admin, { key = "BuyTime", value = 40 })
check("AdminSuperOnly blocks a normal admin", C.BuyTime == 30)
drive(super, { key = "BuyTime", value = 40 })
check("a superadmin can edit when required", C.BuyTime == 40)
C.Set("AdminSuperOnly", false)

if failed then os.exit(1) end
