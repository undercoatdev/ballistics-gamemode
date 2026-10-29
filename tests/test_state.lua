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

local soloState = State.new(cfg())
events, err = soloState:Transition({ type = "start", good = 1, bad = 0, flags = true, solo = true }, 0)
check("singleplayer start allows one occupied team", events and events[1].new == "buy" and soloState:Phase() == "buy")
events, err = State.new(cfg()):Transition({ type = "start", good = 0, bad = 0, flags = true, solo = true }, 0)
check("singleplayer start with nobody is still min players", events == nil and err == "min players")

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
check("reaching RoundsToWin records the match winner", events[1].scoreBad == 2 and match:MatchWinner() == "bad" and match:Phase() == "post" and match:SquadMode() == "finale")
events = match:Tick(55)
check("a decided match enters the firing squad", events[1].type == "phase" and events[1].old == "post" and events[1].new == "squad" and events[2].type == "match_end" and events[2].winner == "bad" and match:Phase() == "squad" and match:SquadMode() == "finale")
check("the squad keeps the score and lasts 30 seconds", match:Score().bad == 2 and match:EndsAt() == 85)
events = match:Tick(85)
check("the squad returns to the lobby without a second match end", #events == 1 and events[1].new == "lobby" and match:Phase() == "lobby" and match:EndsAt() == nil)
events = match:Transition({ type = "start", good = 1, bad = 1, flags = true }, 90)
check("a new match resets the score and round", events[1].matchStart == true and match:Round() == 1 and match:Score().good == 0 and match:Score().bad == 0 and match:Phase() == "buy")

-- A draw before the deciding round continues. A deciding draw is a showdown.
local series = State.new(cfg({ RoundsToWin = 3 }))
start(series, 0)
series:Tick(10)
series:Tick(610)
events = series:Tick(615)
check("a draw before the deciding round returns to buy", events[1].new == "buy" and series:Phase() == "buy" and series:MatchWinner() == nil and series:SquadMode() == nil)

local quick = State.new(cfg({ RoundsToWin = 1 }))
start(quick, 0)
quick:Tick(10)
quick:Tick(610)
events = quick:Tick(615)
local quickEnd = false
for i = 1, #events do
	if events[i].type == "match_end" then quickEnd = true end
end
check("a deciding draw enters showdown without a winner", events[1].new == "squad" and quick:Phase() == "squad" and quick:SquadMode() == "showdown" and quick:MatchWinner() == nil and quick:EndsAt() == nil and quickEnd == false)
check("showdown has no clock", #quick:Tick(99999) == 0 and quick:Phase() == "squad" and quick:MatchWinner() == nil)

local one = State.new(cfg({ RoundsToWin = 1 }))
start(one, 0)
one:Tick(10)
one:Transition({ type = "end", winner = "good", reason = "elimination" }, 20)
events = one:Tick(25)
check("one win enters the firing squad and names the winner", events[1].new == "squad" and events[2].type == "match_end" and events[2].winner == "good" and one:SquadMode() == "finale")
events = one:Tick(55)
check("the firing squad then returns to the lobby", #events == 1 and events[1].new == "lobby" and one:Phase() == "lobby")

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

local call = State.MatchCall
check("endless never closes", call(9, 9, "draw", 0) == nil and call(3, 1, "good", 0) == nil)
check("a unique reach is that side", call(3, 1, "good", 3) == "good" and call(1, 3, "bad", 3) == "bad")
check("both sides on the line is a showdown", call(3, 3, "good", 3) == "showdown" and call(2, 2, "draw", 3) == "showdown")
check("a non-deciding draw continues", call(0, 0, "draw", 3) == nil and call(1, 1, "draw", 3) == nil)
check("a deciding draw is a showdown", call(0, 0, "draw", 1) == "showdown" and call(2, 2, "draw", 3) == "showdown")

local show = State.ShowdownCall
check("both sides alive keeps the showdown going", show(1, 1, 1, 1) == nil and show(2, 1, 3, 1) == nil)
check("only dead players are out", show(0, 1, 1, 1) == "bad" and show(1, 0, 1, 1) == "good")
check("both teams dying picks Good", show(0, 0, 1, 1) == "good" and show(0, 0, 4, 2) == "good")
check("an empty team loses to the team that has players", show(0, 0, 0, 2) == "bad" and show(0, 0, 3, 0) == "good")
check("nobody slotted leaves for the lobby", show(0, 0, 0, 0) == "lobby" and show(1, 1, 0, 0) == "lobby")

local function enterShowdown()
	local st = State.new(cfg({ RoundsToWin = 1 }))
	start(st, 0)
	st:Tick(10)
	st:Tick(610)
	st:Tick(615)
	return st
end

local liveShow = enterShowdown()
check("showdown waits while anyone is alive", #liveShow:ConsiderShowdown(700, 1, 1, 1, 1) == 0 and liveShow:Phase() == "squad")
check("knocked-out players do not end the showdown", #liveShow:ConsiderShowdown(701, 1, 1, 2, 2) == 0 and liveShow:Phase() == "squad")
local wiped = liveShow:ConsiderShowdown(702, 1, 0, 2, 2)
check("wiping a side wins the game then the lobby", wiped[1].type == "match_end" and wiped[1].winner == "good" and wiped[2].new == "lobby" and liveShow:Phase() == "lobby" and liveShow:MatchWinner() == "good")

local bothDead = enterShowdown()
local bothEv = bothDead:ConsiderShowdown(1, 0, 0, 1, 1)
check("a simultaneous wipe still names Good", bothEv[1].type == "match_end" and bothEv[1].winner == "good" and bothDead:Phase() == "lobby")

local emptySide = enterShowdown()
local emptyEv = emptySide:ConsiderShowdown(1, 0, 0, 0, 3)
check("a team with no players loses the showdown", emptyEv[1].winner == "bad" and emptySide:MatchWinner() == "bad" and emptySide:Phase() == "lobby")

local nobody = enterShowdown()
local noneEv = nobody:ConsiderShowdown(3, 0, 0, 0, 0)
check("nobody slotted does not invent a winner", noneEv[1].new == "lobby" and noneEv[2] == nil and nobody:MatchWinner() == nil and nobody:Phase() == "lobby")
local refused, refuseErr = nobody:FinishShowdown(4, "good")
check("a finished showdown cannot be finished again", refused == nil and refuseErr == "not showdown")

local stray = State.new(cfg({ RoundsToWin = 3 }))
start(stray, 0)
stray:Tick(10)
stray:Transition({ type = "end", winner = "draw", reason = "timeout" }, 20)
stray.matchWinner = "draw"
events = stray:Tick(25)
local strayEnd = false
for i = 1, #events do
	if events[i].type == "match_end" then strayEnd = true end
end
check("a stray draw winner becomes a showdown", events[1].new == "squad" and stray:SquadMode() == "showdown" and stray:Phase() == "squad" and strayEnd == false and stray:MatchWinner() == nil)

local badCall = enterShowdown()
local badEv, badErr = badCall:FinishShowdown(5, "draw")
check("showdown refuses a draw as the game winner", badEv == nil and badErr == "bad winner" and badCall:Phase() == "squad")

local idle = State.new(cfg())
check("EndMatch in lobby is a no-op", #idle:EndMatch(0) == 0 and idle:Phase() == "lobby" and idle:Round() == 0)

local cut = State.new(cfg({ RoundsToWin = 2 }))
start(cut, 0)
local cutEv = cut:EndMatch(3)
local cutSquad = false
for i = 1, #cutEv do
	if cutEv[i].new == "squad" then cutSquad = true end
end
check("EndMatch from buy returns to lobby without a squad", cutEv[1].new == "lobby" and cutEv[1].old == "buy" and cut:Phase() == "lobby" and cutSquad == false)
check("EndMatch resets the series", cut:Round() == 0 and cut:Score().good == 0 and cut:Score().bad == 0 and cut:MatchWinner() == nil and cut:EndsAt() == nil)

start(cut, 10)
cut:Tick(20)
cut:Transition({ type = "end", winner = "good", reason = "elimination" }, 30)
check("a live win still scores before EndMatch", cut:Phase() == "post" and cut:Score().good == 1)
cutEv = cut:EndMatch(31)
check("EndMatch from post skips the firing squad", cut:Phase() == "lobby" and cut:Round() == 0 and cut:Score().good == 0 and cut:SquadMode() == nil)
local namedEnd = false
for i = 1, #cutEv do
	if cutEv[i].type == "match_end" and cutEv[i].winner == "good" then namedEnd = true end
end
check("EndMatch does not name a match winner", namedEnd == false)

local fromSquad = State.new(cfg({ RoundsToWin = 1 }))
start(fromSquad, 0)
fromSquad:Tick(10)
fromSquad:Transition({ type = "end", winner = "bad", reason = "elimination" }, 20)
fromSquad:Tick(25)
check("setup is in the firing squad", fromSquad:Phase() == "squad")
fromSquad:EndMatch(26)
check("EndMatch from squad returns to a fresh lobby", fromSquad:Phase() == "lobby" and fromSquad:Round() == 0 and fromSquad:Score().bad == 0 and fromSquad:SquadMode() == nil)

-- Server driver. concommand must exist before sv_round loads.
local cmds = {}
concommand = {
	Add = function(name, fn)
		cmds[name] = fn
	end,
}
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
-- Money-flow cases use round numbers; pin StartMoney (shipped default is 100).
BALLISTICS.Config.Set("StartMoney", 1000)
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
check("dead player spectates a living teammate", good.spec == (OBS_MODE_IN_EYE or 4) and good.specTarget == mate)
check("dead player cannot pick weapons up", GM:PlayerCanPickupWeapon(good, {}) == false)
check("living player can pick a dropped gun up", GM:PlayerCanPickupWeapon(mate, {}) == true)
check("the dropper cannot pick their gun up during grace", GM:PlayerCanPickupWeapon(mate, { BallisticsDropOwner = mate, BallisticsDropUntil = 10 }) == false)
check("someone else can pick a fresh drop up", GM:PlayerCanPickupWeapon(mate, { BallisticsDropOwner = good, BallisticsDropUntil = 10 }) == true)
check("grace expiry lets the dropper pick it up", GM:PlayerCanPickupWeapon(mate, { BallisticsDropOwner = mate, BallisticsDropUntil = -1 }) == true)
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
BALLISTICS.Spawns = { HasBoth = function() return true end, HasBox = function() return false end }
ok, why = BALLISTICS.StartMatch(admin)
check("start without the firing squad box is refused", ok == false and why == "box" and BALLISTICS.Round.Phase() == "lobby")
BALLISTICS.Spawns = { HasBoth = function() return true end, HasBox = function() return true end }

ok, why = cmds.bal_debug_start(user)
check("non-admin cannot start", ok == false and why == "admin" and BALLISTICS.Round.Phase() == "lobby")

local watcher = fake("watcher", { alive = false })
GM:PlayerInitialSpawn(watcher)
GM:PlayerSpawn(watcher)
flush()

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

ents = {
	Create = function()
		local ent = { spawned = false }
		function ent:SetPos(p) self.pos = p end
		function ent:GetPos() return self.pos end
		function ent:SetAngles(a) self.ang = a end
		function ent:Spawn() self.spawned = true end
		function ent:IsValid() return true end
		return ent
	end,
}
good.balNextSpawn = true
local spot = GM:PlayerSelectSpawn(good)
check("a slotted spawn selects the flag ring, not a map start", spot and spot:GetPos() and math.abs(spot:GetPos().x - 40) < 1e-6 and math.abs((spot:GetPos().y or 0) - (good.pos.y or 0)) < 1e-6)
good.balNextSpawn = false
ents = nil
check("spawned players are on their teams and alive", good.alive == true and good.teamId == TEAM_GOOD and bad.teamId == TEAM_BAD)
check("an unslotted player stays a free-cam spectator", watcher.alive == false and watcher.teamId == TEAM_SPEC and watcher.spec == (OBS_MODE_ROAMING or 6))

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
BALLISTICS.Round.Tick(20)
check("buy advances to live and unfreezes", BALLISTICS.Round.Phase() == "live" and good.frozen == false and bad.frozen == false and good.movetype == (MOVETYPE_WALK or 2))
BALLISTICS.Round.Tick(20.5)
check("a team of only knocked-out players does not lose", BALLISTICS.Round.Phase() == "live" and good.pbDown == true and good.alive == true and bad.pbDown == true)

BALLISTICS.Round.Tick(620)
local snap = BALLISTICS.Round.Snapshot(620)
check("round ends in a draw at 10 min", BALLISTICS.Round.Phase() == "post" and snap.winner == "draw" and snap.reason == "timeout" and snap.round == 1)
gbal, gpend = BALLISTICS.Money.Get(good)
local _, bpend = BALLISTICS.Money.Get(bad)
check("a draw pays Gains.draw to everyone", gbal == 900 and gpend == 700 and bpend == 500 and endings[1] == "draw:timeout")

BALLISTICS.Round.Tick(625)
gbal, gpend = BALLISTICS.Money.Get(good)
bbal = BALLISTICS.Money.Get(bad)
check("next round is buy and commits pending", BALLISTICS.Round.Phase() == "buy" and BALLISTICS.Round.Number() == 2 and gbal == 1600 and gpend == 0 and bbal == 1500 and good.nw.bal_pending == 0)
check("the next buy freezes and re-kits", good.frozen == true and #good.weapons == 1 and good.weapons[1] == "tacrp_knife" and good.alive == true)

check("phase order is lobby buy live post buy", phases[1] == "lobby>buy" and phases[2] == "buy>live" and phases[3] == "live>post" and phases[4] == "post>buy")

BALLISTICS.Round.Tick(645)
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
check("last living teammate is gone: fixed, no free roam", good.spec == (OBS_MODE_FIXED or 2))
check("they are still slotted until the next buy", BALLISTICS.Slots.TeamOf(good) == TEAM_GOOD and good.alive == false)

BALLISTICS.Round.Tick(645.2)
local score = BALLISTICS.Round.Score()
snap = BALLISTICS.Round.Snapshot(625.2)
check("a knocked-out side wins when the other side is dead", BALLISTICS.Round.Phase() == "post" and snap.winner == "bad" and snap.reason == "elimination" and score.good == 0 and score.bad == 1)
gbal, gpend = BALLISTICS.Money.Get(good)
local _, bpend = BALLISTICS.Money.Get(bad)
check("round rewards wait in pending", gpend == 500 and bpend == 900 and gbal == 1600 and endings[2] == "bad:elimination")

-- Lobby free cam: unfreezing a spectator must not set walk movetype.
do
	local spec = { movetype = 10, alive = false, obs = 6 }
	function spec:Alive() return self.alive end
	function spec:GetObserverMode() return self.obs end
	function spec:Freeze(on) self.frozen = on end
	function spec:SetMoveType(m) self.movetype = m end
	BALLISTICS.Player.SetFrozen(spec, false)
	check("unfreeze keeps a spectator's free cam", spec.movetype == 10 and spec.frozen == false)
	spec.alive, spec.obs = true, 0
	BALLISTICS.Player.SetFrozen(spec, false)
	check("unfreeze still walks a living player", spec.movetype == 2)
end

local gearReset, organReset, squadEnded = false, false, false
BALLISTICS.Gear = { Reset = function() gearReset = true end }
BALLISTICS.Organs = { Reset = function() organReset = true end }
BALLISTICS.Squad = { End = function() squadEnded = true end }
local moneyBefore = BALLISTICS.Money.Get(good)
local ended = BALLISTICS.Round.EndMatch()
check("EndMatch from post returns to the lobby", ended == true and BALLISTICS.Round.Phase() == "lobby")
check("EndMatch resets round and score", BALLISTICS.Round.Number() == 0 and BALLISTICS.Round.Score().good == 0 and BALLISTICS.Round.Score().bad == 0)
check("EndMatch wipes gear, organs, and an active squad", gearReset and organReset and squadEnded)
check("EndMatch leaves money until the next start", BALLISTICS.Money.Get(good) == moneyBefore)
check("EndMatch spectates everyone", good.spec == (OBS_MODE_ROAMING or 6) and bad.spec == (OBS_MODE_ROAMING or 6))
flush()
check("EndMatch in lobby is a no-op", BALLISTICS.Round.EndMatch() == true and BALLISTICS.Round.Phase() == "lobby")

check("noclip cannot be turned on", GM:PlayerNoClip(good, true) == false and GM:PlayerNoClip(good, false) == true)

BALLISTICS.Spawns = { HasBoth = function() return true end, HasBox = function() return true end }
local wasSingle = game.SinglePlayer
function game.SinglePlayer() return false end
BALLISTICS.Slots.ClearAll()
BALLISTICS.Slots.Take(good, TEAM_GOOD, 1)
good.alive = true
local soloOk, soloWhy = BALLISTICS.StartMatch(nil)
check("multiplayer still needs both teams", soloOk == false and soloWhy == "min players" and BALLISTICS.Round.Phase() == "lobby")
function game.SinglePlayer() return true end
BALLISTICS.Slots.ClearAll()
soloOk, soloWhy = BALLISTICS.Round.BootSinglePlayer(good)
check("singleplayer boot slots Good and starts", soloOk == true and soloWhy == nil and BALLISTICS.Round.Phase() == "buy" and BALLISTICS.Slots.TeamOf(good) == TEAM_GOOD)
local againOk, againWhy = BALLISTICS.Round.BootSinglePlayer(good)
check("singleplayer boot runs once", againOk == false and againWhy == "once" and BALLISTICS.Round.Phase() == "buy")
BALLISTICS.Round.Tick(20)
check("singleplayer buy still becomes live", BALLISTICS.Round.Phase() == "live")
BALLISTICS.Round.Tick(20.1)
check("an empty team does not end the singleplayer round", BALLISTICS.Round.Phase() == "live")
function game.SinglePlayer() return false end
BALLISTICS.Round.Tick(20.2)
check("multiplayer still eliminates an empty side", BALLISTICS.Round.Phase() == "post")
game.SinglePlayer = wasSingle

if failed then os.exit(1) end
