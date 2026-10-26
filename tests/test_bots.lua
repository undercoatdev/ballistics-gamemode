-- Test bots: slot choice, fill plan, admin gate, and that a bot counts
-- for elimination, capture, and kill money.
-- Run: luajit tests/test_bots.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_deps.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_state.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_ledger.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_tabs.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_gains.lua")
dofile("gamemodes/ballistics/gamemode/modules/objective/sh_capture.lua")
dofile("gamemodes/ballistics/gamemode/modules/bots/sh_bots.lua")

local B = BALLISTICS.Bots
local GOOD = TEAM_GOOD
local BAD = TEAM_BAD
local SHARED = "90071996842377216"

check("message name", B.Message() == "bal_bots")
check("the player cap is ten", B.MaxPlayers() == 10)
check("first free slot is 1", B.FirstFree({}, 5) == 1)
check("first free skips occupied slots", B.FirstFree({ [1] = "a", [2] = "b" }, 5) == 3)
check("a hole is used before the end", B.FirstFree({ [1] = "a", [3] = "c" }, 5) == 2)
check("a full side has no slot", B.FirstFree({ "a", "b", "c", "d", "e" }, 5) == nil)
check("a zero limit still searches one slot", B.FirstFree({}, 0) == 1)
check("slots past the limit are ignored", B.FirstFree({ [6] = "a" }, 5) == 1)

local plan = B.FillPlan({
	[GOOD] = { [1] = "human" },
	[BAD] = {},
}, 2, 1)
check("fill lists empty slots good then bad", #plan == 3 and plan[1].team == GOOD and plan[1].slot == 2 and plan[1].name == "Bot Good 2" and plan[2].team == BAD and plan[2].slot == 1 and plan[3].slot == 2 and plan[3].name == "Bot Bad 2")

local nine = B.FillPlan({ [GOOD] = {}, [BAD] = {} }, 5, 9)
check("nine players leave room for one bot", #nine == 1 and nine[1].team == GOOD and nine[1].slot == 1 and nine[1].name == "Bot Good 1")
check("ten players leave no room", #B.FillPlan({ [GOOD] = {}, [BAD] = {} }, 5, 10) == 0)
check("slots per team caps the plan under ten", #B.FillPlan({ [GOOD] = {}, [BAD] = {} }, 2, 0) == 4)
check("a lower server cap beats the ten ceiling", #B.FillPlan({ [GOOD] = {}, [BAD] = {} }, 5, 0, 8) == 8)
check("a cap above ten is clamped", #B.FillPlan({ [GOOD] = {}, [BAD] = {} }, 5, 0, 100) == 10)

local add, err = B.ValidateAdd({ team = GOOD, taken = {}, limit = 5, playerCount = 0 })
check("add takes good slot 1", add and add.team == GOOD and add.slot == 1 and add.name == "Bot Good 1")
add, err = B.ValidateAdd({ team = BAD, taken = { [1] = "a" }, limit = 5, playerCount = 1 })
check("add takes the first free bad slot", add and add.slot == 2 and add.name == "Bot Bad 2")
add, err = B.ValidateAdd({ team = 9, taken = {}, limit = 5, playerCount = 0 })
check("add rejects an unknown team", add == nil and err == "team")
add, err = B.ValidateAdd({ team = "nope", limit = 5, playerCount = 0 })
check("add rejects a text team", add == nil and err == "team")
add, err = B.ValidateAdd({
	team = GOOD,
	taken = { "a", "b", "c", "d", "e" },
	limit = 5,
	playerCount = 10,
})
check("a full team is refused before the player cap", add == nil and err == "full")
add, err = B.ValidateAdd({ team = GOOD, taken = {}, limit = 5, playerCount = 10 })
check("the tenth player blocks another bot", add == nil and err == "players")
add, err = B.ValidateAdd({ team = GOOD, taken = { [1] = "a", [2] = "b" }, limit = 2, playerCount = 2 })
check("slots per team blocks a third on that side", add == nil and err == "full")
add, err = B.ValidateAdd({ team = BAD, sides = { [BAD] = { [1] = "a" } }, limit = 5, playerCount = 3 })
check("add reads the side out of the grid", add and add.slot == 2)
check("a bad context is refused", B.ValidateAdd(nil) == nil)

local decision, why = B.Admit(false, "add", { team = GOOD, taken = {}, limit = 5, playerCount = 0 })
check("a non-admin add is refused", decision == nil and why == "admin")
decision, why = B.Admit(nil, "remove", {})
check("a missing admin is refused", decision == nil and why == "admin")
decision, why = B.Admit(true, "nope", {})
check("an unknown action is refused", decision == nil and why == "action")
decision = B.Admit(true, "remove", nil)
check("an admin can remove", decision and decision.action == "remove")
decision = B.Admit(true, "fill", { sides = { [GOOD] = {}, [BAD] = {} }, limit = 5, playerCount = 10 })
check("fill at the cap is an empty plan", decision and decision.action == "fill" and #decision.plan == 0)
decision = B.Admit(true, "add", { team = GOOD, taken = { [2] = "x" }, limit = 5, playerCount = 1 })
check("an admin add keeps the free slot", decision and decision.action == "add" and decision.slot == 1 and decision.name == "Bot Good 1")

check("lobby and buy take a slot now", B.JoinsNow("lobby") == true and B.JoinsNow("buy") == true and B.JoinsNow(nil) == true)
check("live and post wait for the next buy", B.JoinsNow("live") == false and B.JoinsNow("post") == false)
check("squad waits for the lobby", B.JoinsNow("squad") == false)
check("only buy spawns immediately", B.SpawnNow("buy") == true and B.SpawnNow("lobby") == false and B.SpawnNow("live") == false and B.SpawnNow("post") == false)

local tab = BALLISTICS.AdminTabs.Find("bots")
check("Test Bots is on the admin tree", tab and tab.title == "Test Bots" and tab.implemented == true)
check("Test Bots does not reset config", BALLISTICS.AdminTabs.ResetRequest(tab) == nil)
check("the tab is not added twice", BALLISTICS.AdminTabs.Add({ id = "bots", title = "Test Bots", implemented = true }) == false)

-- Server: unique bot ids, admin gate, queue, idle input.
local handlers = {}
function net.Receive(name, fn)
	handlers[name] = fn
end
local wire = { action = "", team = 0 }
function net.ReadString()
	return wire.action
end
function net.ReadUInt()
	return wire.team
end

local clock = 100
function CurTime()
	return clock
end

local pending = {}
function timer.Simple(_, fn)
	pending[#pending + 1] = fn
end
local function flush()
	local guard = 0
	while #pending > 0 and guard < 8 do
		guard = guard + 1
		local batch = pending
		pending = {}
		for i = 1, #batch do
			batch[i]()
		end
	end
end

dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_money.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_player.lua")
dofile("gamemodes/ballistics/gamemode/modules/objective/sv_objective.lua")

local roster = {}
local nextUid = 10
local nextEnt = 2
local created = 0

local function methods(ply)
	function ply:IsBot()
		return self.bot == true
	end
	function ply:IsPlayer()
		return true
	end
	function ply:IsAdmin()
		return self.admin == true
	end
	function ply:IsSuperAdmin()
		return false
	end
	function ply:SteamID64()
		return self.steam
	end
	function ply:UserID()
		return self.uid
	end
	function ply:EntIndex()
		return self.ent
	end
	function ply:Nick()
		return self.name
	end
	function ply:Alive()
		return self.alive == true
	end
	function ply:SetTeam(teamId)
		self.teamId = teamId
	end
	function ply:Team()
		return self.teamId
	end
	function ply:KillSilent()
		self.alive = false
	end
	function ply:Spawn()
		self.alive = true
		self.spawns = (self.spawns or 0) + 1
		if GM and GM.PlayerSpawn then GM:PlayerSpawn(self) end
	end
	function ply:IsValid()
		return self.kicked ~= true
	end
	function ply:Kick()
		self.kicked = true
		self.alive = false
		for i = 1, #roster do
			if roster[i] == self then
				table.remove(roster, i)
				break
			end
		end
		if hook and hook.Run then hook.Run("PlayerDisconnected", self) end
	end
	function ply:Spectate(mode)
		self.spec = mode
	end
	function ply:SpectateEntity(ent)
		self.specTarget = ent
	end
	function ply:UnSpectate()
		self.spec = nil
		self.specTarget = nil
	end
	function ply:SetNoTarget() end
	function ply:SetPos(pos)
		self.pos = pos
	end
	function ply:GetPos()
		return self.pos or { x = 0, y = 0, z = 0 }
	end
	function ply:SetEyeAngles(ang)
		self.ang = ang
	end
	function ply:EyeAngles()
		return self.ang or { p = 0, y = 90, r = 0 }
	end
	function ply:StripWeapons()
		self.weapons = {}
	end
	function ply:StripAmmo() end
	function ply:RemoveAllAmmo() end
	function ply:Give(class)
		self.weapons = self.weapons or {}
		self.weapons[#self.weapons + 1] = class
	end
	function ply:SelectWeapon() end
	function ply:SetHealth() end
	function ply:GetMaxHealth()
		return 100
	end
	function ply:SetArmor() end
	function ply:SetModel(model)
		self.model = model
	end
	function ply:Freeze(on)
		self.frozen = on and true or false
	end
	function ply:SetMoveType(mode)
		self.movetype = mode
	end
	function ply:SetNW2Int(key, value)
		self.nw[key] = value
	end
	function ply:ChatPrint() end
end

local function make(opts)
	opts = opts or {}
	local ply = {
		bot = opts.bot == true,
		admin = opts.admin == true,
		steam = opts.steam or SHARED,
		uid = opts.uid,
		ent = opts.ent or nextEnt,
		name = opts.name or "p",
		alive = opts.alive ~= false,
		teamId = TEAM_SPEC,
		weapons = {},
		nw = {},
		pos = opts.pos,
	}
	nextEnt = nextEnt + 1
	methods(ply)
	return ply
end

function player.GetAll()
	return roster
end
function player.GetBots()
	local list = {}
	for i = 1, #roster do
		if roster[i].bot then list[#list + 1] = roster[i] end
	end
	return list
end
function player.GetCount()
	return #roster
end
function player.CreateNextBot(name)
	created = created + 1
	nextUid = nextUid + 1
	local ply = make({
		bot = true,
		name = name,
		uid = nextUid,
		steam = SHARED,
		alive = true,
	})
	roster[#roster + 1] = ply
	if GM and GM.PlayerInitialSpawn then GM:PlayerInitialSpawn(ply) end
	if GM and GM.PlayerSpawn then GM:PlayerSpawn(ply) end
	return ply
end

local phase = "lobby"
BALLISTICS.Round = {
	Phase = function()
		return phase
	end,
	SpawnTransform = function()
		return { x = 40, y = 0, z = 16 }, { p = 0, y = 15, r = 0 }
	end,
}

local createsBefore = created
dofile("gamemodes/ballistics/gamemode/modules/bots/sv_bots.lua")
check("loading the module creates no bots", created == createsBefore)
check("the bot net message is registered", handlers[B.Message()] ~= nil)

local human = make({ bot = false, steam = "76561198000000001", uid = 1, name = "host" })
local mirror = make({ bot = true, steam = "76561198000000001", uid = 4, name = "copy" })
local zero = make({ bot = true, steam = "0", uid = 0, ent = 8, name = "zero" })
check("a human keeps the steam id", BALLISTICS.PlayerId(human) == "76561198000000001")
check("a bot does not use the host steam id", BALLISTICS.PlayerId(mirror) == "bot:4")
check("a bot with no user id uses its entity index", BALLISTICS.PlayerId(zero) == "bot:8")

BALLISTICS.Slots.ClearAll()
BALLISTICS.Slots.Take(human, GOOD, 1)
BALLISTICS.Slots.Take(mirror, BAD, 1)
check("a bot with the host steam id does not take the host slot", BALLISTICS.Slots.TeamOf(human) == GOOD and BALLISTICS.Slots.SlotOf(human) == 1 and BALLISTICS.Slots.Player("76561198000000001") == human)
check("the copied bot has its own slot", BALLISTICS.Slots.TeamOf(mirror) == BAD and BALLISTICS.Slots.Player("bot:4") == mirror)

local twin = make({ bot = true, steam = SHARED, uid = 5, name = "twin", pos = { x = 0, y = 0, z = 0 } })
local mate = make({ bot = true, steam = SHARED, uid = 6, name = "mate", pos = { x = 5000, y = 0, z = 0 } })
BALLISTICS.Slots.Take(twin, BAD, 2)
BALLISTICS.Slots.Take(mate, GOOD, 2)
check("two bots that share a steam id both count", BALLISTICS.PlayerId(twin) ~= BALLISTICS.PlayerId(mate) and BALLISTICS.Slots.Count(BAD) == 2 and BALLISTICS.Slots.Count(GOOD) == 2)

local function aliveOn(teamId)
	local n = 0
	local members = BALLISTICS.Slots.Members(teamId)
	for i = 1, #members do
		local ply = BALLISTICS.Slots.Player(members[i])
		if ply and ply.Alive and ply:Alive() then n = n + 1 end
	end
	return n
end

phase = "live"
check("living bots keep both sides in the round", BALLISTICS.State.Elimination(aliveOn(GOOD), aliveOn(BAD)) == nil)
human.alive = false
mate.alive = false
local win, reason = BALLISTICS.State.Elimination(aliveOn(GOOD), aliveOn(BAD))
check("a living bot side wins the elimination", win == "bad" and reason == "elimination" and aliveOn(BAD) == 2 and aliveOn(GOOD) == 0)
twin.alive = false
mirror.alive = false
win, reason = BALLISTICS.State.Elimination(aliveOn(GOOD), aliveOn(BAD))
check("dead bots eliminate their side", win == "draw" and reason == "elimination")
human.alive = true
mate.alive = true
twin.alive = true
mirror.alive = true

check("a living bot is conscious", BALLISTICS.IsConscious(twin) == true)
BALLISTICS.Spawns = {
	Snapshot = function()
		return {
			good = { pos = { x = 0, y = 0, z = 0 } },
			bad = { pos = { x = 5000, y = 0, z = 0 } },
		}
	end,
}
-- Everyone else stands well outside both circles. The bad bot is on Good's flag.
human.pos = { x = 8000, y = 0, z = 0 }
mate.pos = { x = 8000, y = 100, z = 0 }
mirror.pos = { x = 8000, y = 200, z = 0 }
twin.pos = { x = 0, y = 0, z = 0 }
local captured = BALLISTICS.Objective.Tick(20)
check("a bot on the flag counts as a capture", captured and captured.winner == "bad" and captured.reason == "capture")

local reward = BALLISTICS.Gains.KillReward({
	phase = "live",
	suicide = false,
	attackerIsPlayer = twin:IsPlayer(),
	victimTeam = BALLISTICS.Slots.TeamOf(human),
	attackerTeam = BALLISTICS.Slots.TeamOf(twin),
})
check("the kill rule treats a bot as a player", reward == "kill")
local same = BALLISTICS.Gains.KillReward({
	phase = "live",
	suicide = false,
	attackerIsPlayer = twin:IsPlayer(),
	victimTeam = BALLISTICS.Slots.TeamOf(mirror),
	attackerTeam = BALLISTICS.Slots.TeamOf(twin),
})
check("a bot teamkill still pays nothing", same == nil)
check("a bot teamkill does not touch the ledger", BALLISTICS.Money.OnDeath(mirror, twin) == false)
local paid = BALLISTICS.Money.OnDeath(human, twin)
local _, pend = BALLISTICS.Money.Get(twin)
local _, otherPend = BALLISTICS.Money.Get(mirror)
check("a bot kill pays that bot's pending", paid == true and pend == 500 and otherPend == 0)

-- Handle path runs as a multiplayer server (the stub defaults to singleplayer).
function game.SinglePlayer()
	return false
end

-- Handle path. The humans above are not in the roster, so the cap sees bots we add.
BALLISTICS.Slots.ClearAll()
roster = {}
phase = "lobby"
local admin = make({ bot = false, admin = true, steam = "76561198000000099", uid = 2, name = "admin" })
local user = make({ bot = false, admin = false, steam = "76561198000000098", uid = 3, name = "user" })
roster[#roster + 1] = admin

local calls = 0
local inner = BALLISTICS.Bots.Handle
BALLISTICS.Bots.Handle = function(...)
	calls = calls + 1
	return inner(...)
end

local function drive(ply, action, team)
	wire.action = action
	wire.team = team or 0
	handlers[B.Message()](0, ply)
end

local before = created
local ok, why = inner(user, { action = "add", team = GOOD })
check("Handle refuses a non-admin", ok == false and why == "admin" and created == before)
drive(user, "add", GOOD)
drive(nil, "add", GOOD)
check("the net message refuses a non-admin", calls == 0 and created == before)

ok, why = inner(admin, { action = "add", team = 7 })
check("the server rejects a bad team", ok == false and why == "team" and created == before)

clock = 200
drive(admin, "add", GOOD)
flush()
check("an admin add in the lobby slots one bot", calls == 1 and BALLISTICS.Bots.Count() == 1 and BALLISTICS.Slots.Count(GOOD) == 1)
local lobbyBot = player.GetBots()[1]
check("a lobby bot waits and is not spawned", lobbyBot and lobbyBot:Alive() == false and (lobbyBot.spawns or 0) == 0 and lobbyBot:Nick() == "Bot Good 1" and BALLISTICS.Slots.TeamOf(lobbyBot) == GOOD)

phase = "live"
clock = 201
local liveBefore = BALLISTICS.Slots.Count(BAD)
drive(admin, "add", BAD)
flush()
local liveBot = nil
for i = 1, #player.GetBots() do
	if player.GetBots()[i]:Nick() == "Bot Bad 1" then liveBot = player.GetBots()[i] end
end
local queued = BALLISTICS.Slots.NetPayload().queue
local queuedSlot = nil
for i = 1, #queued do
	if queued[i].id == BALLISTICS.PlayerId(liveBot) then queuedSlot = queued[i].slot end
end
check("a live add waits for the next buy", liveBot and liveBot:Alive() == false and (liveBot.spawns or 0) == 0 and BALLISTICS.Slots.TeamOf(liveBot) == nil and BALLISTICS.Slots.Count(BAD) == liveBefore and queuedSlot == 1)
check("a queued bot is not alive for elimination", aliveOn(BAD) == 0)
drive(admin, "add", BAD)
local queuedSlots = {}
queued = BALLISTICS.Slots.NetPayload().queue
for i = 1, #queued do
	queuedSlots[queued[i].slot] = true
end
check("the next live add takes the next free slot", queuedSlots[1] == true and queuedSlots[2] == true)

BALLISTICS.Slots.ApplyQueued()
check("the next buy claims the queued slot", BALLISTICS.Slots.TeamOf(liveBot) == BAD and liveBot:Alive() == false)
phase = "buy"
BALLISTICS.Player.SpawnInRound(liveBot)
flush()
check("the buy spawn puts the bot on the flag", liveBot:Alive() == true and liveBot.pos and liveBot.pos.x == 40 and liveBot.frozen == true and liveBot.weapons and liveBot.weapons[1] == "tacrp_knife")

phase = "buy"
clock = 202
local buyBots = BALLISTICS.Bots.Count()
drive(admin, "add", BAD)
flush()
local buyBot = nil
for i = 1, #player.GetBots() do
	local ply = player.GetBots()[i]
	if ply:Nick() == "Bot Bad 3" then buyBot = ply end
end
check("a buy add spawns immediately and stays spawned", BALLISTICS.Bots.Count() == buyBots + 1 and buyBot and buyBot:Alive() == true and buyBot.pos and buyBot.pos.x == 40 and BALLISTICS.Slots.TeamOf(buyBot) == BAD and BALLISTICS.Slots.SlotOf(buyBot) == 3)

phase = "lobby"
clock = 203
local removed
ok, removed = inner(admin, { action = "remove" })
check("remove frees bot slots and kicks them", ok == true and removed.removed >= 1 and BALLISTICS.Bots.Count() == 0 and BALLISTICS.Slots.Count(GOOD) == 0 and BALLISTICS.Slots.Count(BAD) == 0)
check("remove does not kick the admin", admin.kicked ~= true)

phase = "lobby"
clock = 204
roster = { admin }
BALLISTICS.Slots.ClearAll()
BALLISTICS.Slots.Take(admin, GOOD, 1)
ok, removed = inner(admin, { action = "fill" })
flush()
check("fill stops at the ten player cap", ok == true and removed.added == 9 and BALLISTICS.Bots.Count() == 9 and player.GetCount() == 10)
check("fill leaves the admin's slot and fills the rest", BALLISTICS.Slots.TeamOf(admin) == GOOD and BALLISTICS.Slots.SlotOf(admin) == 1 and BALLISTICS.Slots.Count(GOOD) == 5 and BALLISTICS.Slots.Count(BAD) == 5)

ok, removed = inner(admin, { action = "remove" })
BALLISTICS.Slots.ClearAll()
roster = { admin }

local countNow = player.GetCount
player.GetCount = function()
	return 10
end
local createdHeld = created
ok, why = inner(admin, { action = "add", team = GOOD })
check("a full server refuses another bot", ok == false and why == "players" and created == createdHeld)
player.GetCount = countNow

BALLISTICS.Config.Set("SlotsPerTeam", 1)
BALLISTICS.Slots.ClearAll()
roster = { admin }
BALLISTICS.Slots.Take(admin, GOOD, 1)
ok, why = inner(admin, { action = "add", team = GOOD })
check("slots per team refuses a second good bot", ok == false and why == "full")
BALLISTICS.Config.Set("SlotsPerTeam", 5)
BALLISTICS.Slots.ClearAll()

function game.SinglePlayer()
	return true
end
function game.MaxPlayers()
	return 1
end
roster = { admin }
local spBefore = created
ok, why = inner(admin, { action = "add", team = GOOD })
check("singleplayer refuses a bot add with a notice", ok == false and why == "singleplayer" and created == spBefore and BALLISTICS.Bots.Count() == 0)
ok, why = inner(admin, { action = "fill" })
check("singleplayer refuses fill without calling CreateNextBot", ok == false and why == "singleplayer" and created == spBefore)
ok = inner(admin, { action = "remove" })
check("singleplayer still allows remove", ok == true)
BALLISTICS.Slots.ClearAll()
roster = { admin }

function game.SinglePlayer()
	return false
end
function game.MaxPlayers()
	return 2
end
-- admin is already one player, so one bot fills a dedicated cap of 2.
ok, removed = inner(admin, { action = "fill" })
check("a dedicated server cap limits the fill", ok == true and removed.added == 1 and player.GetCount() == 2)
inner(admin, { action = "remove" })
BALLISTICS.Slots.ClearAll()
roster = { admin }

function game.MaxPlayers()
	return 32
end
-- CreateNextBot returning nil (server full) or erroring must not throw or spam.
local realCreate = player.CreateNextBot
player.CreateNextBot = function() return nil end
ok, why = inner(admin, { action = "add", team = GOOD })
check("a nil CreateNextBot is a friendly refusal", ok == false and why == "create")
player.CreateNextBot = function() error("Cannot create a player bot in singleplayer!") end
local okCall, res = pcall(inner, admin, { action = "fill" })
check("an erroring CreateNextBot does not throw and fill stops", okCall == true and res == true and BALLISTICS.Bots.Count() == 0)
player.CreateNextBot = realCreate
BALLISTICS.Slots.ClearAll()
roster = { admin }

clock = 300
local burst = created
for i = 1, 5 do
	drive(admin, "add", GOOD)
end
local afterBurst = created
drive(admin, "add", GOOD)
check("bot commands are rate limited", afterBurst == burst + 5 and created == afterBurst)
clock = 301
drive(admin, "add", BAD)
check("the limit opens on the next second", created == afterBurst + 1)

local function command()
	return {
		buttons = false,
		move = false,
		ang = nil,
		ClearButtons = function(self)
			self.buttons = true
		end,
		ClearMovement = function(self)
			self.move = true
		end,
		SetViewAngles = function(self, ang)
			self.ang = ang
		end,
	}
end

phase = "buy"
local humanCmd = command()
hook.Run("StartCommand", human, humanCmd)
check("a human keeps their buttons", humanCmd.buttons == false)
local botCmd = command()
mirror.ang = { p = 0, y = 90, r = 0 }
local look = mirror:EyeAngles()
hook.Run("StartCommand", mirror, botCmd)
check("a bot command is cleared and the view stays", botCmd.buttons == true and botCmd.move == true and botCmd.ang == look and look.y == 90)
local speeds = { f = nil, s = nil, u = nil, b = nil }
local mv = {
	SetForwardSpeed = function(_, v) speeds.f = v end,
	SetSideSpeed = function(_, v) speeds.s = v end,
	SetUpSpeed = function(_, v) speeds.u = v end,
	SetButtons = function(_, v) speeds.b = v end,
	SetMaxClientSpeed = function() end,
	SetMaxSpeed = function() end,
}
local moveCmd = command()
hook.Run("SetupMove", mirror, mv, moveCmd)
check("setup move stops a bot", moveCmd.buttons == true and moveCmd.move == true and speeds.f == 0 and speeds.s == 0 and speeds.u == 0 and speeds.b == 0)
local humanMv = { SetForwardSpeed = function() speeds.f = 9 end }
speeds.f = nil
hook.Run("SetupMove", human, humanMv, command())
check("setup move leaves a human alone", speeds.f == nil)

if failed then os.exit(1) end
