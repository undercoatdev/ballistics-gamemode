-- Survivors on either team keep gear (win, loss, draw). The dead reset.
-- Run: luajit tests/test_gear.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
dofile("gamemodes/ballistics/gamemode/modules/gear/sh_gear.lua")

local K = BALLISTICS.Gear.Keeps
check("alive good winner keeps", K({ winner = "good", team = 1, alive = true }) == true)
check("string team good keeps", K({ winner = "good", team = "good", alive = true }) == true)
check("bad winner on bad keeps", K({ winner = "bad", team = 2, alive = true }) == true)
check("string team bad keeps", K({ winner = "bad", team = "bad", alive = true }) == true)
check("alive loser keeps", K({ winner = "good", team = 2, alive = true }) == true)
check("alive survivor of a draw keeps", K({ winner = "draw", team = 1, alive = true }) == true)
check("spectator never keeps", K({ team = 3, alive = true }) == false)
check("dead winner does not keep", K({ winner = "good", team = 1, alive = false }) == false)
check("missing alive does not keep", K({ winner = "good", team = "good" }) == false)
check("match start resets", K({ winner = "good", team = "good", alive = true, matchStart = true }) == false)
check("empty context resets", K(nil) == false)

local spent = 0
BALLISTICS.GiveMed = function(ply, id, n)
	ply.pbMed.counts[id] = (ply.pbMed.counts[id] or 0) + n
	if ply.pbMed.counts[id] < 0 then ply.pbMed.counts[id] = 0 end
	return true
end
BALLISTICS.Money = { Spend = function() spent = spent + 1 end }

local winner = {
	sid = "w",
	alive = true,
	pbMed = { counts = { 2, 0, 1, 0 } },
	ammoNow = { pistol = 21 },
}
local loser = {
	sid = "l",
	alive = true,
	pbMed = { counts = { 3, 1, 0, 0 } },
	ammoNow = {},
}
function winner:Alive() return self.alive end
function winner:IsValid() return true end
function loser:Alive() return self.alive end
function loser:IsValid() return true end

local function makeGun(class, att, clip)
	local wep = {
		class = class,
		ArcticTacRP = true,
		Attachments = { [1] = { Installed = att } },
		clip1 = clip,
	}
	function wep:IsValid() return true end
	function wep:GetClass() return class end
	function wep:Clip1() return self.clip1 end
	function wep:Clip2() return 0 end
	function wep:Detach(slot)
		self.detached = slot
		self.Attachments[slot].Installed = nil
	end
	function wep:SetClip1(n) self.clip1 = n end
	function wep:SetClip2(n) self.clip2 = n end
	wep.BallisticsAttOriginal = function(self, slot, installed)
		self.sawRestore = self.BallisticsAttRestore == true
		self.Attachments[slot].Installed = installed
	end
	function wep:Attach(slot, installed)
		self.BallisticsAttOriginal(self, slot, installed)
		if self.BallisticsAttRestore ~= true then spent = spent + 1 end
	end
	return wep
end

local keptGun = makeGun("tacrp_ex_m1911", "optic_kept", 4)
local knife = makeGun("tacrp_knife", nil, 0)
knife.Attachments[1].Installed = nil
winner.weapons = { knife, keptGun }
function winner:GetWeapons() return self.weapons end
function winner:GetAmmo() return self.ammoNow end
function winner:SetAmmo(n, name) self.ammoNow[name] = n end
function winner:Give(class, noAmmo)
	self.noAmmo = noAmmo
	local wep = makeGun(class, "irons", 0)
	self.given = wep
	self.ammoNow.ar2 = 10
	return wep
end
function loser:GetWeapons() return {} end
function loser:GetAmmo() return {} end

BALLISTICS.PlayerId = function(ply) return ply.sid end
BALLISTICS.Slots = {
	Members = function(team)
		if team == TEAM_GOOD then return { "w" } end
		if team == TEAM_BAD then return { "l" } end
		return {}
	end,
	Player = function(id)
		if id == "w" then return winner end
		if id == "l" then return loser end
	end,
	TeamOf = function(id)
		if id == "w" then return TEAM_GOOD, 1 end
		if id == "l" then return TEAM_BAD, 1 end
	end,
}

dofile("gamemodes/ballistics/gamemode/modules/gear/sv_gear.lua")

hook.Run("Ballistics_RoundEnd", "good", "elimination")
check("winner will keep", BALLISTICS.Gear.WillKeep(winner) == true)
check("alive player on the losing team keeps", BALLISTICS.Gear.WillKeep(loser) == true)
hook.Run("Ballistics_RoundEnd", "good", "elimination")
loser.alive = false
check("dead player does not keep", BALLISTICS.Gear.WillKeep(loser) == false)
loser.alive = true
winner.pbMed.counts = { 0, 0, 0, 0 }
winner.weapons = {}
BALLISTICS.Gear.ApplySpawn(winner)
check("kept gun was given without default ammo", winner.noAmmo == true and winner.given ~= nil)
check("attachment restored without a charge", winner.given.Attachments[1].Installed == "optic_kept" and spent == 0)
check("irons were detached first", winner.given.detached == 1)
check("clip restored after attach", winner.given.clip1 == 4)
check("reserve ammo restored", winner.ammoNow.pistol == 21)
check("ammo injected by Give is cleared", winner.ammoNow.ar2 == 0)
check("meds restored to the snapshot", winner.pbMed.counts[1] == 2 and winner.pbMed.counts[3] == 1)
BALLISTICS.Gear.ClearMeds(loser)
check("loser meds cleared", loser.pbMed.counts[1] == 0 and loser.pbMed.counts[2] == 0)

winner.alive = false
hook.Run("Ballistics_RoundEnd", "good", "elimination")
check("a winner who died before spawn does not keep", BALLISTICS.Gear.WillKeep(winner) == false)

winner.alive = true
hook.Run("Ballistics_RoundEnd", "draw", "timeout")
check("a draw survivor keeps", BALLISTICS.Gear.WillKeep(winner) == true)

hook.Run("Ballistics_RoundEnd", "good", "elimination")
BALLISTICS.Gear.Reset()
check("match start drops the snapshot", BALLISTICS.Gear.WillKeep(winner) == false)

-- Gear never outlives the game.
winner.alive = true
hook.Run("Ballistics_RoundEnd", "good", "elimination")
check("survivor snapshot before game end", BALLISTICS.Gear.WillKeep(winner) == true)
hook.Run("Ballistics_MatchEnd", "good")
check("game end drops carried gear", BALLISTICS.Gear.WillKeep(winner) == false)
hook.Run("Ballistics_RoundEnd", "good", "elimination")
hook.Run("Ballistics_PhaseChanged", "post", "squad")
check("firing squad drops carried gear", BALLISTICS.Gear.WillKeep(winner) == false)
hook.Run("Ballistics_RoundEnd", "good", "elimination")
hook.Run("Ballistics_PhaseChanged", "squad", "lobby")
check("lobby drops carried gear", BALLISTICS.Gear.WillKeep(winner) == false)

-- Carried guns come back in the order they occupied, not GetWeapons order.
do
	dofile("gamemodes/ballistics/gamemode/modules/loadout/sh_loadout.lua")
	dofile("gamemodes/ballistics/gamemode/modules/loadout/sv_loadout.lua")
	local ak = makeGun("tacrp_ex_ak47", "optic_ak", 10)
	local pistol = makeGun("tacrp_ex_m1911", "optic_pistol", 3)
	winner.alive = true
	winner.weapons = { knife }
	BALLISTICS.Loadout.Reset(winner, "tacrp_knife")
	BALLISTICS.Loadout.NoteGun(winner, "tacrp_ex_ak47")
	winner.weapons = { knife, ak }
	BALLISTICS.Loadout.NoteGun(winner, "tacrp_ex_m1911")
	winner.weapons = { pistol, knife, ak }
	hook.Run("Ballistics_RoundEnd", "good", "elimination")
	local order = {}
	local prevGive = winner.Give
	function winner:Give(class, noAmmo)
		order[#order + 1] = class
		local wep = prevGive(self, class, noAmmo)
		self.weapons[#self.weapons + 1] = wep
		return wep
	end
	winner.weapons = {}
	BALLISTICS.Gear.ApplySpawn(winner)
	check("kept guns restore in slot order", order[1] == "tacrp_ex_ak47" and order[2] == "tacrp_ex_m1911" and #order == 2)
	local guns = BALLISTICS.Loadout.Guns(winner)
	check("restored guns keep that slot order", guns[1] == "tacrp_ex_ak47" and guns[2] == "tacrp_ex_m1911")
end

do
	local pistolA = makeGun("tacrp_ex_m1911", "optic_live", 4)
	winner.alive = true
	winner.weapons = { knife, pistolA }
	BALLISTICS.Loadout.Reset(winner, "tacrp_knife")
	BALLISTICS.Loadout.NoteGun(winner, "tacrp_ex_m1911")
	BALLISTICS.Loadout.SetTwin(winner, {
		class = "tacrp_ex_m1911",
		clip1 = 9,
		attachments = { { slot = 1, att = "optic_twin" } },
	})
	BALLISTICS.Loadout.NoteGun(winner, "tacrp_ex_m1911")
	BALLISTICS.Loadout.SetLiveSlot(winner, 1)
	hook.Run("Ballistics_RoundEnd", "good", "elimination")
	winner.weapons = {}
	local given = {}
	function winner:Give(class, noAmmo)
		given[#given + 1] = class
		local wep = makeGun(class, "irons", 0)
		self.weapons[#self.weapons + 1] = wep
		self.given = wep
		return wep
	end
	BALLISTICS.Gear.ApplySpawn(winner)
	check("a twin is given once", #given == 1 and given[1] == "tacrp_ex_m1911")
	check("the live copy is restored onto the entity", winner.given.clip1 == 4 and winner.given.Attachments[1].Installed == "optic_live")
	local twin = BALLISTICS.Loadout.Twin(winner)
	check("the stored twin is restored", twin ~= nil and twin.clip1 == 9 and twin.attachments[1].att == "optic_twin")
	check("twin slots survive carry-over", BALLISTICS.Loadout.ClassFor(winner, 1) == "tacrp_ex_m1911" and BALLISTICS.Loadout.ClassFor(winner, 2) == "tacrp_ex_m1911")
end

-- TacRP autosave forced off on the client so bought guns start bare.
do
	local val = 1
	local cvar = { GetInt = function() return val end }
	GetConVar = function(n) if n == "tacrp_autosave" then return cvar end end
	RunConsoleCommand = function(n, v) if n == "tacrp_autosave" then val = tonumber(v) end end
	CLIENT = true
	dofile("gamemodes/ballistics/gamemode/modules/customize/cl_noautosave.lua")
	check("tacrp_autosave forced off", val == 0)
	BALLISTICS.NoAutosave.Restore()
	check("tacrp_autosave restored on shutdown", val == 1)
	CLIENT = nil
end

if failed then os.exit(1) end
