-- Round machine: every transition, timeouts, draw, min players, and the server
-- driver (spawn, freeze, knife, models, elimination, money commit).
-- Run: luajit tests/test_state.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_state.lua")

local function cfg(over)
	local base = {
		MinPerTeam = 1,
		BuyTime = 10,
		RoundTime = 600,
		PostRoundTime = 5,
		RoundsToWin = 0,
		TimeoutWinner = "draw",
	}
	if over then
		for k, v in pairs(over) do base[k] = v end
	end
	return base
end

local function start(st, now, good, bad)
	return st:Transition({ type = "start", good = good or 1, bad = bad or 1, flags = true }, now or 0)
end

local State = BALLISTICS.State

local st = State.new(cfg())
check("match opens in lobby with no clock", st:Phase() == "lobby" and st:Round() == 0 and st:EndsAt() == nil)
check("lobby tick does nothing", #st:Tick(100000) == 0 and st:Phase() == "lobby")

local events, err = st:Transition({ type = "start", good = 1, bad = 0, flags = true }, 0)
check("start needs both teams", events == nil and err == "min players" and st:Phase() == "lobby")

events, err = st:Transition({ type = "start", good = 0, bad = 0, flags = true }, 0)
check("start with nobody is min players", events == nil and err == "min players")

events, err = st:Transition({ type = "start", good = 1, bad = 1, flags = false }, 0)
check("start needs both flags", events == nil and err == "flags" and st:Phase() == "lobby")

events, err = st:Transition({ type = "start", good = 1, bad = 1 }, 0)
check("missing flags are not treated as ready", events == nil and err == "flags")

local needTwo = State.new(cfg({ MinPerTeam = 2 }))
events, err = needTwo:Transition({ type = "start", good = 2, bad = 1, flags = true }, 0)
check("min players is per team", events == nil and err == "min players")
events = needTwo:Transition({ type = "start", good = 2, bad = 2, flags = true }, 0)
check("min players allows an even match", events and events[1].new == "buy")

st:SetReady(1, 1, false)
events, err = st:Transition("start", 0)
check("SetReady without flags refuses start", events == nil and err == "flags" and st:Phase() == "lobby")

st:SetReady(0, 0, false)
events = st:Transition({ type = "start", good = 1, bad = 1, flags = true }, 0)
check("event fields override SetReady", events and events[1].new == "buy" and events[1].old == "lobby" and events[1].matchStart == true and events[1].round == 1)
check("buy has a 10s clock", st:Phase() == "buy" and st:Round() == 1 and st:EndsAt() == 10 and st:TimeLeft(0) == 10)

events, err = st:Transition({ type = "start", good = 1, bad = 1, flags = true }, 1)
check("start during buy is refused", events == nil and err == "not lobby" and st:Phase() == "buy" and st:Round() == 1)

events, err = st:Transition({ type = "end", winner = "good", reason = "capture" }, 1)
check("end during buy is refused", events == nil and err == "not live" and st:Phase() == "buy" and st:Score().good == 0)

check("tick before the buy clock stays in buy", #st:Tick(9.999) == 0 and st:Phase() == "buy")
events = st:Tick(10)
check("buy ends into live", events and events[1].type == "phase" and events[1].old == "buy" and events[1].new == "live" and st:Phase() == "live" and st:EndsAt() == 610)

events, err = st:Transition("end", 11)
check("end without a winner is refused", events == nil and err == "bad winner" and st:Phase() == "live")

events, err = st:Transition({ type = "end", winner = "green", reason = "capture" }, 11)
check("unknown winner is refused", events == nil and err == "bad winner" and st:Score().good == 0)

check("early live tick does not end the round", #st:Tick(609.999) == 0 and st:Phase() == "live")
events = st:Tick(610)
check("10 min timeout is a draw", events and events[1].type == "round_end" and events[1].winner == "draw" and events[1].reason == "timeout" and events[1].scoreGood == 0 and events[1].scoreBad == 0)
check("draw does not change the score", st:Phase() == "post" and st:Score().good == 0 and st:Score().bad == 0 and st:Winner() == "draw")
check("post lasts 5s", st:EndsAt() == 615 and events[2].new == "post")

events, err = st:Transition({ type = "end", winner = "good", reason = "capture" }, 611)
check("end during post is refused", events == nil and err == "not live" and st:Phase() == "post")

events = st:Tick(615)
check("post returns to buy for the next round", events and events[1].new == "buy" and events[1].matchStart == false and st:Round() == 2 and st:Phase() == "buy" and st:EndsAt() == 625)
check("score survives into the next round", st:Score().good == 0 and st:Score().bad == 0)

-- A late tick advances one boundary and starts that phase's clock from now.
local late = State.new(cfg())
start(late, 0)
local jumped = late:Tick(99999)
check("one tick does not skip live", #jumped == 1 and late:Phase() == "live" and late:EndsAt() == 99999 + 600)

-- Capture / elimination end the live round and credit the winner.
local played = State.new(cfg())
start(played, 0)
played:Tick(10)
events = played:Transition({ type = "end", winner = "good", reason = "capture" }, 40)
check("capture ends live and scores", events and events[1].type == "round_end" and events[1].winner == "good" and events[1].reason == "capture" and events[1].scoreGood == 1 and played:Phase() == "post")
played:Tick(45)
played:Tick(55)
events = played:Transition({ type = "end", winner = "draw", reason = "elimination" }, 80)
check("elimination draw does not score", events and events[1].winner == "draw" and events[1].reason == "elimination" and played:Score().good == 1 and played:Score().bad == 0)

-- TimeoutWinner is read when the clock fires, and a bad timeout scores.
local biased = State.new(cfg({ TimeoutWinner = "bad", RoundTime = 600 }))
start(biased, 0)
biased:Tick(10)
biased.cfg.TimeoutWinner = "good"
events = biased:Tick(610)
check("timeout winner is read live from config", events[1].winner == "good" and events[1].reason == "timeout" and biased:Score().good == 1 and biased:Score().bad == 0)

-- Endless match (RoundsToWin 0) keeps cycling after wins.
local endless = State.new(cfg({ RoundsToWin = 0 }))
start(endless, 0)
endless:Tick(10)
endless:Transition({ type = "end", winner = "good", reason = "elimination" }, 20)
events = endless:Tick(25)
check("endless match returns to buy", events[1].new == "buy" and endless:Phase() == "buy" and endless:MatchWinner() == nil)

-- First to 2: win, play another, win, return to lobby.
local match = State.new(cfg({ RoundsToWin = 2, BuyTime = 10, RoundTime = 600, PostRoundTime = 5 }))
start(match, 0)
match:Tick(10)
match:Transition({ type = "end", winner = "bad", reason = "elimination" }, 30)
check("first win does not end the match", match:MatchWinner() == nil and match:Score().bad == 1)
events = match:Tick(35)
check("series continues into the next buy", events[1].new == "buy" and match:Phase() == "buy" and match:Round() == 2)
match:Tick(45)
events = match:Transition({ type = "end", winner = "bad", reason = "capture" }, 50)
check("reaching RoundsToWin records the match winner", events[1].scoreBad == 2 and match:MatchWinner() == "bad" and match:Phase() == "post")
events = match:Tick(55)
check("finished match returns to lobby", events[1].type == "phase" and events[1].old == "post" and events[1].new == "lobby" and events[2].type == "match_end" and events[2].winner == "bad")
check("lobby has no countdown after the match", match:Phase() == "lobby" and match:EndsAt() == nil and match:Score().bad == 2)
events = match:Transition({ type = "start", good = 1, bad = 1, flags = true }, 80)
check("a new match resets the score and round", events[1].matchStart == true and match:Round() == 1 and match:Score().good == 0 and match:Score().bad == 0 and match:Phase() == "buy")

-- First to 1 ends after a single win, not after a draw.
local quick = State.new(cfg({ RoundsToWin = 1 }))
start(quick, 0)
quick:Tick(10)
quick:Tick(610)
events = quick:Tick(615)
check("a draw does not satisfy RoundsToWin", events[1].new == "buy" and quick:Phase() == "buy")
quick:Tick(625)
quick:Transition({ type = "end", winner = "good", reason = "elimination" }, 700)
events = quick:Tick(705)
check("one win can end the match", events[2].type == "match_end" and events[2].winner == "good" and quick:Phase() == "lobby")

events, err = State.new(cfg()):Transition("nope", 0)
check("unknown event", events == nil and err == "unknown event")

local elim = State.Elimination
local winner, reason = elim(1, 1)
check("both sides alive is not an elimination", winner == nil and reason == nil)
winner, reason = elim(0, 2)
check("a dead side loses", winner == "bad" and reason == "elimination")
winner, reason = elim(3, 0)
check("the living side wins", winner == "good" and reason == "elimination")
winner, reason = elim(0, 0)
check("both sides dead is a draw", winner == "draw" and reason == "elimination")
check("a knocked-out player still counts as alive for the caller", elim(1, 1) == nil)

-- Server driver. concommand must exist before sv_round loads.
local cmds = {}
concommand = {
	Add = function(name, fn)
		cmds[name] = fn
	end,
}
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_deps.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_ledger.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_money.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_player.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_round.lua")

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
		for i = 1, #batch do batch[i]() end
	end
end

local function fake(id, opts)
	opts = opts or {}
	local ply = {
		id = id,
		alive = opts.alive ~= false,
		teamId = TEAM_SPEC,
		frozen = false,
		movetype = MOVETYPE_WALK or 2,
		model = nil,
		weapons = {},
		admin = opts.admin == true,
		nw = {},
		pos = nil,
		spec = nil,
		specTarget = nil,
		pbDown = false,
	}
	function ply:SteamID64() return self.id end
	function ply:Alive() return self.alive end
	function ply:IsAdmin() return self.admin end
	function ply:IsSuperAdmin() return false end
	function ply:SetTeam(teamId) self.teamId = teamId end
	function ply:Team() return self.teamId end
	function ply:Nick() return self.id end
	function ply:Freeze(on) self.frozen = on and true or false end
	function ply:SetMoveType(mode) self.movetype = mode end
	function ply:SetModel(model) self.model = model end
	function ply:StripWeapons() self.weapons = {} end
	function ply:StripAmmo() end
	function ply:RemoveAllAmmo() end
	function ply:Give(class)
		self.weapons[#self.weapons + 1] = class
	end
	function ply:SelectWeapon() end
	function ply:SetHealth() end
	function ply:SetArmor() end
	function ply:KillSilent() self.alive = false end
	function ply:Spectate(mode) self.spec = mode end
	function ply:SpectateEntity(ent) self.specTarget = ent end
	function ply:UnSpectate()
		self.spec = nil
		self.specTarget = nil
	end
	function ply:SetPos(pos) self.pos = pos end
	function ply:SetEyeAngles() end
	function ply:SetNoTarget() end
	function ply:SetNW2Int(key, value) self.nw[key] = value end
	function ply:ChatPrint() end
	function ply:Spawn()
		self.alive = true
		if GM and GM.PlayerSpawn then GM:PlayerSpawn(self) end
	end
	return ply
end

check("debug command is registered", type(cmds.bal_debug_start) == "function")

local admin = fake("admin", { admin = true, alive = false })
local user = fake("user", { admin = false, alive = false })
local good = fake("good")
local bad = fake("bad")
local mate = fake("mate")

good.weapons = { "weapon_crowbar" }
good.alive = true
GM:PlayerInitialSpawn(good)
GM:PlayerSpawn(good)
check("joining does not give a knife", #good.weapons == 1 and good.weapons[1] == "weapon_crowbar")
flush()
check("joining becomes a spectator", good.alive == false and good.teamId == TEAM_SPEC and #good.weapons == 0)
check("death think never respawns", GM:PlayerDeathThink(good) == false)
check("death drops nothing", GM:ShouldDropWeapon(good, {}) == false)

BALLISTICS.Slots.ClearAll()
BALLISTICS.Slots.Take(good, TEAM_GOOD, 1)
BALLISTICS.Slots.Take(mate, TEAM_GOOD, 2)
mate.alive = true
good.alive = true
good.weapons = { "tacrp_knife", "tacrp_ex_ak47" }
local medCalls = {}
PLAYER_BALLISTICS = {
	GiveMed = function(_, id, n)
		medCalls[#medCalls + 1] = { id = id, n = n }
		return true
	end,
}
GM:DoPlayerDeath(good, bad, {})
good.alive = false
GM:PlayerDeath(good, nil, bad)
flush()
local meds = {}
for i = 1, #medCalls do
	if medCalls[i].n == -99 then meds[medCalls[i].id] = true end
end
check("death strips weapons and ammo", #good.weapons == 0)
check("death zeros every med", meds[1] and meds[2] and meds[3] and meds[4])
check("dead player stays slotted", BALLISTICS.Slots.TeamOf(good) == TEAM_GOOD)
check("dead player spectates a living teammate", good.spec == (OBS_MODE_CHASE or 5) and good.specTarget == mate)
check("dead player cannot pick weapons up", GM:PlayerCanPickupWeapon(good, {}) == false)
check("living player can pick a dropped gun up", GM:PlayerCanPickupWeapon(mate, {}) == true)
PLAYER_BALLISTICS = nil
check("wipe without player ballistics still strips", (function()
	mate.weapons = { "tacrp_mp5" }
	BALLISTICS.Player.Wipe(mate)
	return #mate.weapons == 0
end)())

BALLISTICS.Slots.ClearAll()
local ok, why = cmds.bal_debug_start(nil)
check("console start with one team is min players", ok == false and why == "min players" and BALLISTICS.Round.Phase() == "lobby")

BALLISTICS.Slots.Take(good, TEAM_GOOD, 1)
BALLISTICS.Slots.Take(bad, TEAM_BAD, 1)
BALLISTICS.Spawns = { HasBoth = function() return false end }
ok, why = BALLISTICS.StartMatch(admin)
check("start without flags is refused", ok == false and why == "flags" and BALLISTICS.Round.Phase() == "lobby")
BALLISTICS.Spawns = nil

ok, why = cmds.bal_debug_start(user)
check("non-admin cannot start", ok == false and why == "admin" and BALLISTICS.Round.Phase() == "lobby")

local phases = {}
hook.Add("Ballistics_PhaseChanged", "state", function(old, new)
	phases[#phases + 1] = old .. ">" .. new
end)
local endings = {}
hook.Add("Ballistics_RoundEnd", "state", function(winner, reason)
	endings[#endings + 1] = winner .. ":" .. reason
end)

good.weapons = { "weapon_crowbar", "weapon_pistol" }
bad.weapons = { "weapon_crowbar" }
ok, why = cmds.bal_debug_start(admin)
check("admin debug start with 1v1 enters buy", ok == true and why == nil and BALLISTICS.Round.Phase() == "buy" and BALLISTICS.Round.Number() == 1)

check("buy spawns the knife only", #good.weapons == 1 and good.weapons[1] == "tacrp_knife" and #bad.weapons == 1 and bad.weapons[1] == "tacrp_knife")
check("buy forces combine models", good.model == "models/player/combine_soldier.mdl" and bad.model == "models/player/combine_super_soldier.mdl")
check("buy freezes both sides", good.frozen == true and bad.frozen == true and good.movetype == (MOVETYPE_NONE or 0) and bad.movetype == (MOVETYPE_NONE or 0))
check("buy puts them on a ring around their flag", good.pos and bad.pos and math.abs(good.pos.x - 40) < 1e-6 and math.abs((bad.pos.x - good.pos.x) - 256) < 1e-6)
check("spawned players are on their teams and alive", good.alive == true and good.teamId == TEAM_GOOD and bad.teamId == TEAM_BAD)

local gbal, gpend = BALLISTICS.Money.Get(good)
local bbal = BALLISTICS.Money.Get(bad)
check("match start resets money", gbal == 1000 and gpend == 0 and bbal == 1000 and good.nw.bal_money == 1000)

check("second start is refused", BALLISTICS.StartMatch(admin) == false)

local spent = BALLISTICS.Money.Spend(good, 100)
local broke = BALLISTICS.Money.Spend(good, 99999)
gbal = BALLISTICS.Money.Get(good)
check("spend during buy", spent == true and broke == false and gbal == 900)
BALLISTICS.Money.Earn(good, "bonus", 200)
gbal, gpend = BALLISTICS.Money.Get(good)
check("earn during buy stays pending", gbal == 900 and gpend == 200)

BALLISTICS.Round.Tick(5)
check("mid buy stays buy", BALLISTICS.Round.Phase() == "buy" and good.frozen == true)

good.pbDown = true
bad.pbDown = true
BALLISTICS.Round.Tick(10)
check("buy advances to live and unfreezes", BALLISTICS.Round.Phase() == "live" and good.frozen == false and bad.frozen == false and good.movetype == (MOVETYPE_WALK or 2))
BALLISTICS.Round.Tick(10.5)
check("a team of only knocked-out players does not lose", BALLISTICS.Round.Phase() == "live" and good.pbDown == true and good.alive == true and bad.pbDown == true)

BALLISTICS.Round.Tick(610)
local snap = BALLISTICS.Round.Snapshot(610)
check("round ends in a draw at 10 min", BALLISTICS.Round.Phase() == "post" and snap.winner == "draw" and snap.reason == "timeout" and snap.round == 1)
gbal, gpend = BALLISTICS.Money.Get(good)
local _, bpend = BALLISTICS.Money.Get(bad)
check("a draw pays Gains.draw to everyone", gbal == 900 and gpend == 700 and bpend == 500 and endings[1] == "draw:timeout")

BALLISTICS.Round.Tick(615)
gbal, gpend = BALLISTICS.Money.Get(good)
bbal = BALLISTICS.Money.Get(bad)
check("next round is buy and commits pending", BALLISTICS.Round.Phase() == "buy" and BALLISTICS.Round.Number() == 2 and gbal == 1600 and gpend == 0 and bbal == 1500 and good.nw.bal_pending == 0)
check("the next buy freezes and re-kits", good.frozen == true and #good.weapons == 1 and good.weapons[1] == "tacrp_knife" and good.alive == true)

check("phase order is lobby buy live post buy", phases[1] == "lobby>buy" and phases[2] == "buy>live" and phases[3] == "live>post" and phases[4] == "post>buy")

BALLISTICS.Round.Tick(625)
check("second live unfreezes", BALLISTICS.Round.Phase() == "live" and good.frozen == false)

good.weapons = { "tacrp_knife", "tacrp_spr" }
good.alive = false
bad.alive = true
bad.pbDown = true
medCalls = {}
PLAYER_BALLISTICS = {
	GiveMed = function(_, id, n)
		medCalls[#medCalls + 1] = { id = id, n = n }
		return true
	end,
}
GM:DoPlayerDeath(good, bad, {})
GM:PlayerDeath(good, nil, bad)
flush()
check("live death wipes the inventory again", #good.weapons == 0 and medCalls[1] and medCalls[1].n == -99)
check("last living teammate is gone so they roam", good.spec == (OBS_MODE_ROAMING or 6))
check("they are still slotted until the next buy", BALLISTICS.Slots.TeamOf(good) == TEAM_GOOD and good.alive == false)

BALLISTICS.Round.Tick(625.2)
local score = BALLISTICS.Round.Score()
snap = BALLISTICS.Round.Snapshot(625.2)
check("a knocked-out side wins when the other side is dead", BALLISTICS.Round.Phase() == "post" and snap.winner == "bad" and snap.reason == "elimination" and score.good == 0 and score.bad == 1)
gbal, gpend = BALLISTICS.Money.Get(good)
local _, bpend = BALLISTICS.Money.Get(bad)
check("round rewards wait in pending", gpend == 500 and bpend == 1000 and gbal == 1600 and endings[2] == "bad:elimination")

if failed then os.exit(1) end
