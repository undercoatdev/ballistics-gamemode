-- Capture rates, decay, contest, unconscious players, and elimination.
-- Run: luajit tests/test_capture.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

local function near(a, b)
	return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6
end

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_deps.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_state.lua")
dofile("gamemodes/ballistics/gamemode/modules/objective/sh_capture.lua")

local pure = readAll("gamemodes/ballistics/gamemode/modules/objective/sh_capture.lua")
check("capture logic does not touch the game", not pure:find("hook.Add", 1, true)
	and not pure:find("net.Start", 1, true)
	and not pure:find("ents.Create", 1, true)
	and not pure:find("LocalPlayer", 1, true)
	and not pure:find("IsConscious", 1, true))

local C = BALLISTICS.Capture
local GOOD = TEAM_GOOD
local BAD = TEAM_BAD

local cfg = {
	ObjectiveRadius = 100,
	CaptureTimeOne = 20,
	CaptureTimeTwo = 10,
	CaptureMaxCounted = 2,
	CaptureDecay = true,
	CaptureDecayRate = 1,
	CaptureContestedFreeze = true,
}

local flags = {
	good = { pos = { x = 0, y = 0, z = 0 } },
	bad = { pos = { x = 2000, y = 0, z = 0 } },
}

local function person(team, x, opts)
	opts = opts or {}
	return {
		team = team,
		pos = { x = x, y = opts.y or 0, z = opts.z or 0 },
		alive = opts.alive ~= false,
		conscious = opts.conscious ~= false,
	}
end

local function world(players, over)
	local use = cfg
	if over then
		use = {}
		for k, v in pairs(cfg) do use[k] = v end
		for k, v in pairs(over) do use[k] = v end
	end
	return { players = players, flags = flags, cfg = use }
end

local function run(state, players, n, over)
	local last
	for _ = 1, n do
		last = C.Tick(state, world(players, over), 0.1)
	end
	return last
end

local function fresh()
	return C.new()
end

-- One attacker on Bad's flag. Good is the attacking side.
local lone = { person(GOOD, 2000) }
local state = fresh()
local before = run(state, lone, 199)
check("one attacker has not won one tick early", before.winner == nil and state.bad < 1 and near(state.bad, 0.995))
local won = C.Tick(state, world(lone), 0.1)
check("one attacker takes the flag in 20s", won.winner == "good" and won.reason == "capture" and state.bad == 1 and state.good == 0)

local two = { person(GOOD, 2000), person(GOOD, 2000, { y = 10 }) }
state = fresh()
before = run(state, two, 99)
check("two attackers have not won one tick early", before.winner == nil and state.bad < 1 and near(state.bad, 0.99))
won = C.Tick(state, world(two), 0.1)
check("two attackers take the flag in 10s", won.winner == "good" and won.reason == "capture" and state.bad == 1)

local three = { person(GOOD, 2000), person(GOOD, 2050), person(GOOD, 2000, { z = 40 }) }
state = fresh()
local twoState = fresh()
run(state, three, 50)
run(twoState, two, 50)
check("three attackers are capped at the two-player rate", near(state.bad, twoState.bad) and near(state.bad, 0.5))
won = run(state, three, 50)
check("three attackers still take the flag in 10s", won.winner == "good" and state.bad == 1)

state = fresh()
won = run(state, three, 200, { CaptureMaxCounted = 1 })
check("a cap of one keeps three attackers on the slow rate", won.winner == "good" and state.bad == 1)
state = fresh()
before = run(state, three, 100, { CaptureMaxCounted = 1 })
check("a cap of one is not the fast rate at 10s", before.winner == nil and near(state.bad, 0.5))

local atk, def = C.Counts(three, flags.bad, "bad", 100)
check("three living attackers are all inside before the cap", atk == 3 and def == 0)

-- Decay uses the one-player rate, including after a two-player fill.
state = fresh()
run(state, two, 100)
check("two attackers fill the bar before the decay check", state.bad == 1)
before = run(state, {}, 199)
check("decay has not emptied the bar one tick early", before.winner == nil and state.bad > 0 and near(state.bad, 0.005))
won = C.Tick(state, world({}), 0.1)
check("an empty circle drains a full bar in 20s", state.bad == 0 and won.winner == nil)

state = fresh()
state.bad = 0.5
run(state, {}, 100)
check("half a bar drains in 10s at the one-player rate", state.bad == 0)

state = fresh()
state.bad = 1
run(state, {}, 100, { CaptureDecayRate = 2 })
check("double decay empties a full bar in 10s", state.bad == 0)

state = fresh()
run(state, lone, 100)
run(state, {}, 50, { CaptureDecay = false })
check("decay off holds whatever was captured", near(state.bad, 0.5))

-- Contested freeze: a conscious defender pauses the bar, attackers or not.
state = fresh()
run(state, lone, 40)
local held = state.bad
local contest = { person(GOOD, 2000), person(BAD, 2000) }
run(state, contest, 200)
check("a defender freezes capture", near(state.bad, held) and held > 0)
run(state, { person(BAD, 2000) }, 100)
check("defenders alone also freeze, so the bar does not decay", near(state.bad, held))

state = fresh()
run(state, contest, 100, { CaptureContestedFreeze = false })
check("with freeze off, defenders do not stop the attackers", near(state.bad, 0.5))

-- Unconscious bodies sit in the circle and still do not count.
local ko = person(GOOD, 2000, { conscious = false })
local koDef = person(BAD, 2000, { conscious = false })
atk, def = C.Counts({ ko, koDef, person(GOOD, 2000) }, flags.bad, BAD, 100)
check("an unconscious body inside the circle is not counted", atk == 1 and def == 0)

state = fresh()
run(state, { ko }, 200)
check("a knocked-out attacker never fills the bar", state.bad == 0 and state.good == 0)

state = fresh()
run(state, { person(GOOD, 2000), koDef }, 100)
check("a knocked-out defender does not contest", near(state.bad, 0.5))

local dead = person(GOOD, 2000, { alive = false, conscious = true })
state = fresh()
run(state, { dead }, 200)
check("a dead player inside the circle does not capture", state.bad == 0)

atk = C.Counts({ person(GOOD, 2100), person(GOOD, 2200) }, flags.bad, "bad", 100)
check("the circle boundary counts and past it does not", atk == 1)
atk = C.Counts({ person(GOOD, 2000, { z = 150 }) }, flags.bad, "bad", 100)
check("height above the circle does not count", atk == 0)

state = fresh()
run(state, { person(GOOD, 0) }, 200)
check("standing on your own flag does not capture it", state.good == 0 and state.bad == 0)

-- Both flags filling on the same tick is a capture draw, not a team win.
local both = { person(GOOD, 2000), person(BAD, 0) }
state = fresh()
before = run(state, both, 199)
check("a simultaneous capture has not resolved early", before.winner == nil and state.good < 1 and state.bad < 1)
won = C.Tick(state, world(both), 0.1)
check("both flags filling together is a capture draw", won.winner == "draw" and won.reason == "capture" and state.good == 1 and state.bad == 1)

local uneven = { person(GOOD, 2000), person(GOOD, 2040), person(BAD, 0) }
state = fresh()
won = run(state, uneven, 100)
check("the faster flag wins before the other one fills", won.winner == "good" and won.reason == "capture" and state.bad == 1 and near(state.good, 0.5))

-- Elimination uses Alive(), not consciousness. The same knocked-out player
-- who failed to capture is still alive, so that team is not eliminated.
local down = {
	Alive = function() return true end,
	pbDown = true,
}
check("a knocked-out player is not conscious", BALLISTICS.IsConscious(down) == false)
local koBody = {
	team = GOOD,
	pos = { x = 2000, y = 0, z = 0 },
	alive = down:Alive(),
	conscious = BALLISTICS.IsConscious(down),
}
state = fresh()
run(state, { koBody }, 200)
check("the knocked-out player's body does not capture", state.bad == 0 and koBody.alive == true and koBody.conscious == false)

local function aliveCount(list, team)
	local n = 0
	for i = 1, #list do
		if list[i].team == team and list[i].alive == true then n = n + 1 end
	end
	return n
end

local sides = { koBody, { team = BAD, alive = false, conscious = false, pos = { x = 0, y = 0, z = 0 } } }
local elimW, elimR = BALLISTICS.State.Elimination(aliveCount(sides, GOOD), aliveCount(sides, BAD))
check("a team that is only knocked out is not eliminated", elimW == "good" and elimR == "elimination" and aliveCount(sides, GOOD) == 1)

local bothUp = {
	{ team = GOOD, alive = true, conscious = false },
	{ team = BAD, alive = true, conscious = false },
}
elimW = BALLISTICS.State.Elimination(aliveCount(bothUp, GOOD), aliveCount(bothUp, BAD))
check("two knocked-out teams stay in the round", elimW == nil)

local bothDead = {
	{ team = GOOD, alive = false, conscious = false },
	{ team = BAD, alive = false, conscious = false },
}
elimW, elimR = BALLISTICS.State.Elimination(aliveCount(bothDead, GOOD), aliveCount(bothDead, BAD))
check("both teams dying together is an elimination draw", elimW == "draw" and elimR == "elimination")

local none = C.Bars(0, 0)
local oneBar = C.Bars(0.4, 0)
local otherBar = C.Bars(0, 0.2)
local twoBars = C.Bars(0.4, 1)
check("the bar stays hidden at zero", #none == 0)
check("a partial good flag names that flag", #oneBar == 1 and oneBar[1].text == "Good flag" and oneBar[1].team == GOOD and near(oneBar[1].progress, 0.4))
check("a partial bad flag names that flag", #otherBar == 1 and otherBar[1].text == "Bad flag" and otherBar[1].team == BAD)
check("both flags with progress draw two bars", #twoBars == 2 and twoBars[1].side == "good" and twoBars[2].side == "bad")

-- Server driver: LIVE ticks, IsConscious, Round.End, reset at BUY.
local phaseName = "live"
local ended = nil
BALLISTICS.Round = {
	Phase = function() return phaseName end,
	End = function(winner, reason)
		ended = { winner = winner, reason = reason }
		phaseName = "post"
		return true
	end,
}

local goodPly = { alive = true, pbDown = false, pos = { x = 2000, y = 0, z = 0 }, teamId = GOOD }
local badPly = { alive = true, pbDown = false, pos = { x = 9000, y = 0, z = 0 }, teamId = BAD }
function goodPly:IsValid() return true end
function goodPly:Alive() return self.alive == true end
function goodPly:GetPos() return self.pos end
function badPly:IsValid() return true end
function badPly:Alive() return self.alive == true end
function badPly:GetPos() return self.pos end

BALLISTICS.Slots = {
	Members = function(team)
		if team == GOOD then return { "good" } end
		if team == BAD then return { "bad" } end
		return {}
	end,
	Player = function(id)
		if id == "good" then return goodPly end
		if id == "bad" then return badPly end
		return nil
	end,
}
BALLISTICS.Spawns = {
	Snapshot = function()
		return {
			good = { pos = { x = 0, y = 0, z = 0 } },
			bad = { pos = { x = 2000, y = 0, z = 0 } },
		}
	end,
}
BALLISTICS.Config.ObjectiveRadius = 100

dofile("gamemodes/ballistics/gamemode/modules/objective/sv_objective.lua")

phaseName = "buy"
BALLISTICS.Objective.Tick(0.1)
local gProg, bProg = BALLISTICS.Objective.Progress()
check("capture does not move outside live", gProg == 0 and bProg == 0 and ended == nil)

phaseName = "live"
for _ = 1, 199 do
	BALLISTICS.Objective.Tick(0.1)
end
gProg, bProg = BALLISTICS.Objective.Progress()
check("the driver has not ended the round early", ended == nil and bProg < 1)
BALLISTICS.Objective.Tick(0.1)
gProg, bProg = BALLISTICS.Objective.Progress()
check("the driver ends the round by capture", ended and ended.winner == "good" and ended.reason == "capture" and bProg == 1 and phaseName == "post")

ended = nil
phaseName = "live"
goodPly.pbDown = true
hook.Run("Ballistics_PhaseChanged", "post", "buy")
gProg, bProg = BALLISTICS.Objective.Progress()
check("entering buy clears the bar", gProg == 0 and bProg == 0)
phaseName = "live"
for _ = 1, 200 do
	BALLISTICS.Objective.Tick(0.1)
end
gProg, bProg = BALLISTICS.Objective.Progress()
check("the driver ignores a knocked-out body on the flag", gProg == 0 and bProg == 0 and ended == nil and BALLISTICS.IsConscious(goodPly) == false)

goodPly.pbDown = false
goodPly.pos = { x = 2000, y = 0, z = 0 }
badPly.pos = { x = 0, y = 0, z = 0 }
for _ = 1, 200 do
	if phaseName == "live" then BALLISTICS.Objective.Tick(0.1) end
end
check("the driver calls a capture draw when both flags fill", ended and ended.winner == "draw" and ended.reason == "capture")

local serverSrc = readAll("gamemodes/ballistics/gamemode/modules/objective/sv_objective.lua")
local clientSrc = readAll("gamemodes/ballistics/gamemode/modules/objective/cl_objective.lua")
local barSrc = readAll("gamemodes/ballistics/gamemode/modules/hud/cl_capture_bar.lua")
check("the server ends through the round API", serverSrc:find("Round.End", 1, true) ~= nil)
check("the server syncs bal_capture_sync", serverSrc:find("bal_capture_sync", 1, true) ~= nil)
check("the server asks IsConscious", serverSrc:find("IsConscious", 1, true) ~= nil)
check("the server does not spawn a circle", not serverSrc:find("ents.Create", 1, true))
check("the client reads the capture sync", clientSrc:find("bal_capture_sync", 1, true) ~= nil and clientSrc:find("ReadFloat", 1, true) ~= nil)
check("the bar does not draw its own circle", not barSrc:find("DrawWireframeSphere", 1, true) and not barSrc:find("DrawLine", 1, true))
check("client capture files compile", loadfile("gamemodes/ballistics/gamemode/modules/objective/cl_objective.lua") ~= nil
	and loadfile("gamemodes/ballistics/gamemode/modules/hud/cl_capture_bar.lua") ~= nil)

CLIENT = true
dofile("gamemodes/ballistics/gamemode/modules/objective/cl_objective.lua")
BALLISTICS.Capture.SetView(0.25, -1)
local viewGood, viewBad = BALLISTICS.Capture.View()
local shown = BALLISTICS.Capture.Bars(viewGood, viewBad)
check("the client keeps partial progress and drops a negative", near(viewGood, 0.25) and viewBad == 0 and #shown == 1 and shown[1].text == "Good flag")
BALLISTICS.Capture.SetView(0, 0)
viewGood, viewBad = BALLISTICS.Capture.View()
check("the client hides the bar at zero", #BALLISTICS.Capture.Bars(viewGood, viewBad) == 0)

if failed then os.exit(1) end
