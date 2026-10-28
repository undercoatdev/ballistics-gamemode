-- Firing squad: lineup, phase, config, banners, and the server spawn.
-- Run: luajit tests/test_squad.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

local function near(a, b, eps)
	return math.abs((a or 0) - (b or 0)) < (eps or 1e-4)
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_state.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_tabs.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_rules.lua")
dofile("gamemodes/ballistics/gamemode/modules/buy/sh_buy.lua")
dofile("gamemodes/ballistics/gamemode/modules/spawns/sh_spawns.lua")
dofile("gamemodes/ballistics/gamemode/modules/squad/sh_squad.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_banner.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_gains.lua")
dofile("gamemodes/ballistics/gamemode/modules/godmode/sh_godmode.lua")

local S = BALLISTICS.Squad
local State = BALLISTICS.State

local function cfg(over)
	local base = {
		MinPerTeam = 1,
		BuyTime = 10,
		RoundTime = 600,
		PostRoundTime = 5,
		RoundsToWin = 1,
		TimeoutWinner = "draw",
	}
	if over then
		for k, v in pairs(over) do base[k] = v end
	end
	return base
end

local function start(st)
	return st:Transition({ type = "start", good = 1, bad = 1, flags = true }, 0)
end

local function play(over, winner)
	local st = State.new(cfg(over))
	start(st)
	st:Tick(10)
	st:Transition({ type = "end", winner = winner or "good", reason = "elimination" }, 20)
	local events = st:Tick(25)
	return st, events
end

local decided, events = play({}, "bad")
check("a decided match always enters the firing squad", events[1].new == "squad" and events[2].type == "match_end" and events[2].winner == "bad" and decided:Phase() == "squad" and decided:SquadMode() == "finale")

local ignored = play({ FiringSquadEnabled = false }, "good")
check("the removed enabled flag does not skip the squad", ignored:Phase() == "squad" and ignored:MatchWinner() == "good" and ignored:SquadMode() == "finale")

local drawn, drawEvents = play({}, "draw")
local drawAnnounced = false
for i = 1, #drawEvents do
	if drawEvents[i].type == "match_end" then drawAnnounced = true end
end
check("a deciding draw enters showdown", drawEvents[1].new == "squad" and drawn:Phase() == "squad" and drawn:SquadMode() == "showdown" and drawn:MatchWinner() == nil and drawn:EndsAt() == nil and drawAnnounced == false)
check("showdown does not time out", #drawn:Tick(100000) == 0 and drawn:Phase() == "squad")
local named = drawn:FinishShowdown(30, "bad")
check("showdown names a winner then the lobby", named[1].type == "match_end" and named[1].winner == "bad" and named[2].new == "lobby" and drawn:Phase() == "lobby")

local endless, endlessEvents = play({ RoundsToWin = 0 }, "good")
check("rounds to win 0 never starts the firing squad", endlessEvents[1].new == "buy" and endless:MatchWinner() == nil and endless:Phase() == "buy")

local squad, squadEvents = play({ FiringSquadDuration = 12 }, "good")
check("a winning match enters squad and announces the match once", squad:Phase() == "squad" and squadEvents[1].old == "post" and squadEvents[1].new == "squad" and squadEvents[2].type == "match_end" and squadEvents[2].winner == "good")
check("one tick does not skip the squad into the lobby", #squadEvents == 2 and squad:EndsAt() == 37)
check("squad waits out its clock", #squad:Tick(36.9) == 0 and squad:Phase() == "squad")
local back = squad:Tick(37)
check("squad then returns to the lobby without a second match end", back and #back == 1 and back[1].type == "phase" and back[1].new == "lobby" and squad:Phase() == "lobby" and squad:EndsAt() == nil)

local timed = play({}, "bad")
check("a missing duration lasts 30 seconds", timed:Phase() == "squad" and timed:EndsAt() == 55)
local zero = play({ FiringSquadDuration = 0 }, "good")
check("a non-positive duration lasts 30 seconds", zero:Phase() == "squad" and zero:EndsAt() == 55)

local box = { pos = { x = 0, y = 0, z = 64 }, yaw = 0, sx = 768, sy = 384 }
local line = S.Line(box, { 1 }, { 1 })
check("one good stands on the negative long side", line and near(line.good[1].pos.x, 0) and near(line.good[1].pos.y, -144) and near(line.good[1].pos.z, 0) and near(line.good[1].yaw, 90))
check("one bad stands opposite and faces back", line and near(line.bad[1].pos.x, 0) and near(line.bad[1].pos.y, 144) and near(line.bad[1].pos.z, 0) and near(line.bad[1].yaw, 270))
check("the two lines face each other", line and near((line.good[1].yaw - line.bad[1].yaw) % 360, 180))

local pair = S.Line(box, { 3, 1 }, {})
check("occupied slots are spaced along the long side in slot order", pair and pair.good[1].slot == 1 and pair.good[2].slot == 3 and near(pair.good[1].pos.x, -168) and near(pair.good[2].pos.x, 168) and near(pair.good[1].pos.y, -144))

local turned = S.Line({ pos = { x = 0, y = 0, z = 64 }, yaw = 90, sx = 768, sy = 384 }, { 1 }, { 1 })
check("yaw 90 turns the lines across world X", turned and near(turned.good[1].pos.x, 144) and near(turned.good[1].pos.y, 0) and near(turned.good[1].yaw, 180))
check("yaw 90 bad stands on the other side facing back", turned and near(turned.bad[1].pos.x, -144) and near(turned.bad[1].pos.y, 0) and near(turned.bad[1].yaw, 0))
check("a bad box has no lineup", S.Line(nil, { 1 }, { 1 }) == nil)

check("winner and loser roles follow the match", S.Role(1, "good") == "winner" and S.Role("bad", "good") == "loser" and S.Role(2, "bad") == "winner" and S.Role("good", "draw") == nil and S.Role(1, "showdown") == "showdown" and S.Role(2, "showdown") == "showdown")
local winners = S.Kit("winner", { FiringSquadWeapon = "tacrp_ex_ak47", FiringSquadMags = 4, FiringSquadFreeze = 10 })
local losers = S.Kit("loser", { FiringSquadWeapon = "tacrp_ex_ak47", FiringSquadMags = 4, FiringSquadFreeze = 10 })
local both = S.Kit("showdown", { FiringSquadWeapon = "tacrp_ex_ak47", FiringSquadMags = 0, FiringSquadFreeze = 10 })
check("winners get the gun and no knife", winners and winners.weapon == "tacrp_ex_ak47" and winners.mags == 4 and winners.knife == false and winners.freeze == 0)
check("losers are frozen and unarmed", losers and losers.weapon == nil and losers.knife == false and losers.mags == 0 and losers.freeze == 10)
check("showdown arms both sides and freezes nobody", both and both.weapon == "tacrp_ex_ak47" and both.mags == 0 and both.knife == false and both.freeze == 0)
check("freeze text counts down", S.FreezeLabel(10) == "FROZEN 10" and S.FreezeLabel(9.1) == "FROZEN 10" and S.FreezeLabel(0.2) == "FROZEN 1" and S.FreezeLabel(0) == nil and S.FreezeLabel(-1) == nil)

local wep = {
	Primary = { Ammo = "ar2", ClipSize = 30 },
	GetMaxClip1 = function() return 30 end,
}
local ammo, clip, rounds = S.Reserve(wep, 4)
check("four magazines use the weapon clip", ammo == "ar2" and clip == 30 and rounds == 120)
check("a class name is a token", S.ValidClass("tacrp_ex_ak47") == true and S.ValidClass("") == false and S.ValidClass("bad class") == false and S.ValidClass("models/a.mdl") == false)

local C = BALLISTICS.Config
check("firing squad defaults", C.FiringSquadDuration == 30 and C.FiringSquadFreeze == 10 and C.FiringSquadWeapon == "tacrp_ex_ak47" and C.FiringSquadMags == 0 and C.FiringSquadEnabled == nil and C.FiringSquadLoserKnife == nil)
local enabledSet, enabledErr = C.Set("FiringSquadEnabled", true)
local knifeSet = C.Set("FiringSquadLoserKnife", true)
check("removed firing squad toggles are unknown", enabledSet == false and enabledErr == "unknown key" and knifeSet == false)
check("an empty weapon class is refused", C.Set("FiringSquadWeapon", "") == false)
check("a weapon class with a space is refused", C.Set("FiringSquadWeapon", "bad class") == false)
local modelOk = C.Set("ModelGood", "models/player/combine_soldier.mdl")
check("model paths are still accepted", modelOk == true and C.ModelGood == "models/player/combine_soldier.mdl")
local _, dur = C.Set("FiringSquadDuration", 1)
check("duration clamps to the schema", dur == 5)
_, dur = C.Set("FiringSquadDuration", 999)
check("duration clamps high", dur == 300)
local _, freeze = C.Set("FiringSquadFreeze", -1)
check("freeze clamps low", freeze == 0)
_, freeze = C.Set("FiringSquadFreeze", 200)
check("freeze clamps high", freeze == 120)
local _, mags = C.Set("FiringSquadMags", 40)
check("magazines clamp high", mags == 30)
C.Set("FiringSquadWeapon", "tacrp_ex_m1911")
C.ResetSection("general")
check("resetting general leaves the firing squad weapon", C.FiringSquadWeapon == "tacrp_ex_m1911" and C.BuyTime == 20 and C.RoundsToWin == 5)
C.ResetSection("firing_squad")
check("resetting the firing squad restores its defaults", C.FiringSquadWeapon == "tacrp_ex_ak47" and C.FiringSquadFreeze == 10 and C.FiringSquadMags == 0 and C.FiringSquadDuration == 30)

local rows = S.Rows("firing_squad")
check("the firing squad tab has four rows", #rows == 4)
local blurbs = true
local weaponRow, magRow, enabledRow = nil, nil, nil
for i = 1, #rows do
	if type(rows[i].blurb) ~= "string" or rows[i].blurb == "" then blurbs = false end
	if rows[i].path == "FiringSquadWeapon" then weaponRow = rows[i] end
	if rows[i].path == "FiringSquadMags" then magRow = rows[i] end
	if rows[i].path == "FiringSquadEnabled" or rows[i].path == "FiringSquadLoserKnife" then enabledRow = rows[i] end
end
check("every firing squad row has a blurb", blurbs and weaponRow and weaponRow.kind == "string" and magRow and magRow.kind == "int" and string.find(magRow.blurb, "0 = infinite ammo", 1, true) and enabledRow == nil)
local committed = S.Commit(weaponRow, "  tacrp_mp5 ")
check("a weapon class is trimmed and committed", committed and committed.key == "FiringSquadWeapon" and committed.value == "tacrp_mp5")
check("a bad weapon class is not committed", S.Commit(weaponRow, "bad class") == nil)
local magCommit = S.Commit(magRow, 0)
check("zero magazines commits", magCommit and magCommit.key == "FiringSquadMags" and magCommit.value == 0)
check("a non-admin cannot send the row", S.PayloadFor(false, committed) == nil and S.PayloadFor(true, committed).key == "FiringSquadWeapon")

local general = BALLISTICS.RulesView.Rows("general")
local leaked = false
for i = 1, #general do
	if string.find(general[i].path, "FiringSquad", 1, true) then leaked = true end
end
check("firing squad is not under Rules > General", leaked == false)

local tab = BALLISTICS.AdminTabs.Find("firing_squad")
local reset = BALLISTICS.AdminTabs.ResetRequest(tab)
check("firing squad is its own admin tab", tab and tab.title == "Firing Squad" and reset and reset.reset == true and reset.section == "firing_squad")

local Banner = BALLISTICS.Banner
local text, col = Banner.Line("round", "good")
check("good wins the round in the team colour", text == "GOOD WINS THE ROUND" and col.r == 70 and col.g == 140 and col.b == 255)
col.r = 0
local _, again = Banner.Line("round", "good")
check("banner colour is a copy", again.r == 70 and BALLISTICS.TeamColor[TEAM_GOOD].r == 70)
check("bad wins the round", Banner.Line("round", "bad") == "BAD WINS THE ROUND")
local drawText, drawCol = Banner.Line("round", "draw")
check("a draw is its own line", drawText == "DRAW" and drawCol.r == 230)
check("good wins the game", Banner.Line("game", "good") == "GOOD WINS THE GAME")
check("a draw is not a game win", Banner.Line("game", "draw") == nil and Banner.Line("round", nil) == nil)
check("the game line replaces the round line", Banner.Show("round", "bad", 0) == "BAD WINS THE ROUND" and Banner.Show("game", "good", 1) == "GOOD WINS THE GAME" and Banner.Current(1) == "GOOD WINS THE GAME")
check("the banner expires", Banner.Current(6) == nil)
check("squad is not protected and pays nothing", BALLISTICS.GodMode.Active("squad") == false and BALLISTICS.GodMode.Protects("squad", true) == false and BALLISTICS.Gains.KillReward({ phase = "squad", attackerIsPlayer = true, suicide = false, victimTeam = TEAM_GOOD, attackerTeam = TEAM_BAD }) == nil)

local gearCalls, organCalls, spawnCalls, moneyCalls = 0, 0, 0, 0
BALLISTICS.Gear = { ApplySpawn = function() gearCalls = gearCalls + 1 end, WillKeep = function() return true end }
BALLISTICS.Organs = { ApplySpawn = function() organCalls = organCalls + 1 end }
BALLISTICS.Money = { Earn = function() moneyCalls = moneyCalls + 1 end }
BALLISTICS.Player = {
	Wipe = function(ply)
		ply.wiped = (ply.wiped or 0) + 1
		ply.weapons = {}
		ply.ammo = {}
		ply.setAmmo = nil
	end,
	SetFrozen = function(ply, on)
		ply.frozen = on and true or false
	end,
	SpawnInRound = function()
		spawnCalls = spawnCalls + 1
	end,
}

local function person(teamId, slot)
	local ply = {
		teamId = teamId,
		slot = slot,
		alive = false,
		weapons = { "tacrp_mp5" },
		ammo = { ar2 = 9 },
		money = 40,
	}
	function ply:Spawn()
		self.spawned = (self.spawned or 0) + 1
		self.alive = true
		self.weapons = { "tacrp_knife" }
	end
	function ply:Give(class, skipAmmo)
		self.weapons[#self.weapons + 1] = class
		self.lastSkip = skipAmmo
		local gun = { class = class, Primary = { Ammo = "ar2", ClipSize = 30 } }
		function gun:GetMaxClip1() return 30 end
		function gun:SetClip1(n) self.clip = n end
		self.wep = gun
		return gun
	end
	function ply:SetAmmo(n, kind)
		self.ammo[kind] = n
		self.setAmmo = true
	end
	function ply:SetPos(p) self.pos = p end
	function ply:SetEyeAngles(a) self.ang = a end
	function ply:SetTeam(t) self.teamId = t end
	function ply:Alive() return self.alive == true end
	function ply:SelectWeapon(class) self.selected = class end
	return ply
end

local good = person(TEAM_GOOD, 1)
local goodLate = person(TEAM_GOOD, 3)
local bad = person(TEAM_BAD, 1)
local byId = { g = good, g3 = goodLate, b = bad }
BALLISTICS.Slots = {
	Members = function(teamId)
		if teamId == TEAM_GOOD then return { "g3", "g" } end
		if teamId == TEAM_BAD then return { "b" } end
		return {}
	end,
	Player = function(id) return byId[id] end,
	TeamOf = function(ply) return ply.teamId, ply.slot end,
}
BALLISTICS.Spawns = {
	SquadBox = function()
		return { pos = { x = 0, y = 0, z = 64 }, yaw = 0, sx = 768, sy = 384 }
	end,
}
local phase = "squad"
BALLISTICS.Round = {
	Phase = function() return phase end,
	Snapshot = function() return { matchWinner = "good", phase = phase } end,
}
local clock = 0
function CurTime() return clock end

dofile("gamemodes/ballistics/gamemode/modules/ammo/sh_ammo.lua")
dofile("gamemodes/ballistics/gamemode/modules/squad/sv_squad.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sv_banner.lua")

hook.Run("Ballistics_PhaseChanged", "post", "squad")
check("squad spawns slotted players who were dead", good.spawned == 1 and good.alive == true and bad.spawned == 1 and goodLate.spawned == 1)
check("winners are stripped to the squad weapon and infinite ammo writes no reserve", #good.weapons == 1 and good.weapons[1] == "tacrp_ex_ak47" and good.lastSkip == true and good.setAmmo ~= true and good.wep.clip == 30 and good.selected == "tacrp_ex_ak47" and good.frozen == false)
check("losers are stripped, unarmed, and frozen", #bad.weapons == 0 and bad.frozen == true and bad.balSquadUntil == 10 and bad.selected == nil)
check("the lineup uses the box, feet lifted by 2", near(good.pos.x, -168) and near(good.pos.y, -144) and near(good.pos.z, 2) and near(good.ang.y, 90))
check("the later good slot stands further along the same side", near(goodLate.pos.x, 168) and near(goodLate.pos.y, -144) and near(goodLate.ang.y, 90))
check("the loser faces the winners", near(bad.pos.x, 0) and near(bad.pos.y, 144) and near(bad.pos.z, 2) and near(bad.ang.y, 270))
check("squad spawn does not keep gear, organs, or pay", gearCalls == 0 and organCalls == 0 and spawnCalls == 0 and moneyCalls == 0 and good.money == 40 and bad.money == 40)
check("SpawnInRound was not used", spawnCalls == 0 and good.wiped == 1)

bad.alive = false
hook.Run("Think")
check("a player who dies during the squad is not respawned", bad.spawned == 1 and bad.alive == false)
bad.alive = true
clock = 9
hook.Run("Think")
check("losers stay frozen until the count ends", bad.frozen == true and bad.balSquadUntil == 10)
clock = 10
hook.Run("Think")
check("losers unfreeze when the count ends", bad.frozen == false and bad.balSquadUntil == nil)

BALLISTICS.Config.FiringSquadMags = 4
hook.Run("Ballistics_PhaseChanged", "post", "squad")
check("finite magazines write a reserve", good.setAmmo == true and good.ammo.ar2 == 120 and good.wep.clip == 30 and bad.frozen == true)
BALLISTICS.Config.FiringSquadMags = 0

BALLISTICS.Round.Snapshot = function()
	return { matchWinner = "", squadMode = "showdown", phase = phase }
end
hook.Run("Ballistics_PhaseChanged", "post", "squad")
check("showdown arms both teams and freezes nobody", good.weapons[1] == "tacrp_ex_ak47" and bad.weapons[1] == "tacrp_ex_ak47" and good.frozen == false and bad.frozen == false and good.balSquadUntil == nil and bad.balSquadUntil == nil and good.setAmmo ~= true)

phase = "lobby"
hook.Run("Ballistics_PhaseChanged", "squad", "lobby")
check("leaving squad clears the finale", BALLISTICS.Squad.Active() == false and good.balSquadRole == nil)
bad.frozen = true
phase = "buy"
hook.Run("Ballistics_PhaseChanged", "lobby", "buy")
check("a buy freeze is not cleared when the phase is not leaving squad", bad.frozen == true)

local sent = {}
local netSend = BALLISTICS.Net.Send
BALLISTICS.Net.Send = function(name, ply, payload)
	sent[#sent + 1] = payload
	return netSend(name, ply, payload)
end
hook.Run("Ballistics_RoundEnd", "bad", "elimination", {})
hook.Run("Ballistics_MatchEnd", "good", {})
hook.Run("Ballistics_MatchEnd", "draw", {})
local rounds, games, draws = 0, 0, 0
for i = 1, #sent do
	if sent[i] and sent[i].kind == "round" and sent[i].winner == "bad" then rounds = rounds + 1 end
	if sent[i] and sent[i].kind == "game" and sent[i].winner == "good" then games = games + 1 end
	if sent[i] and sent[i].kind == "game" and sent[i].winner == "draw" then draws = draws + 1 end
end
check("the server sends a round banner and a game banner, not a draw game", rounds == 1 and games == 1 and draws == 0)

local editor = loadfile("gamemodes/ballistics/gamemode/modules/spawns/cl_spawns_editor.lua")
local squadCl = loadfile("gamemodes/ballistics/gamemode/modules/squad/cl_squad.lua")
local squadTab = loadfile("gamemodes/ballistics/gamemode/modules/squad/cl_tab_squad.lua")
local bannerCl = loadfile("gamemodes/ballistics/gamemode/modules/hud/cl_banner.lua")
local rulesCl = loadfile("gamemodes/ballistics/gamemode/modules/admin/cl_tab_rules.lua")
check("squad, banner, and editor clients compile", editor ~= nil and squadCl ~= nil and squadTab ~= nil and bannerCl ~= nil and rulesCl ~= nil)

if failed then os.exit(1) end
