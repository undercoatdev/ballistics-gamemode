-- Kill-gain decision, and the server glue that pays it into pending.
-- Round win, loss, and draw stay on the round-end hook.
-- Run: luajit tests/test_gains.lua
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
-- Money-flow cases use round numbers; pin StartMoney (shipped default is 100).
BALLISTICS.Config.Set("StartMoney", 1000)
BALLISTICS.Config.Set("Gains.round_win", 1000)
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_gains.lua")

local G = BALLISTICS.Gains
local GOOD = TEAM_GOOD
local BAD = TEAM_BAD

local function ctx(over)
	local base = {
		phase = "live",
		suicide = false,
		attackerIsPlayer = true,
		victimTeam = GOOD,
		attackerTeam = BAD,
	}
	for k, v in pairs(over or {}) do
		base[k] = v
	end
	return base
end

check("an enemy kill during live pays", G.KillReward(ctx()) == "kill")
check("the other direction also pays", G.KillReward(ctx({ victimTeam = BAD, attackerTeam = GOOD })) == "kill")
check("a teamkill pays nothing", G.KillReward(ctx({ attackerTeam = GOOD })) == nil)
check("a suicide pays nothing", G.KillReward(ctx({ suicide = true, attackerTeam = GOOD })) == nil)
check("a world death pays nothing", G.KillReward(ctx({ attackerIsPlayer = false })) == nil)
check("a missing attacker pays nothing", G.KillReward({
	phase = "live",
	suicide = false,
	victimTeam = GOOD,
	attackerTeam = BAD,
}) == nil)
check("buy pays nothing", G.KillReward(ctx({ phase = "buy" })) == nil)
check("lobby pays nothing", G.KillReward(ctx({ phase = "lobby" })) == nil)
check("post pays nothing", G.KillReward(ctx({ phase = "post" })) == nil)
check("squad pays nothing", G.KillReward(ctx({ phase = "squad" })) == nil)
check("phase match is exact", G.KillReward(ctx({ phase = "LIVE" })) == nil)
check("an unslotted victim pays nothing", G.KillReward({
	phase = "live",
	suicide = false,
	attackerIsPlayer = true,
	attackerTeam = BAD,
}) == nil)
check("an unslotted attacker pays nothing", G.KillReward({
	phase = "live",
	suicide = false,
	attackerIsPlayer = true,
	victimTeam = GOOD,
}) == nil)
check("a spectator attacker pays nothing", G.KillReward(ctx({ attackerTeam = TEAM_SPEC })) == nil)
check("a spectator victim pays nothing", G.KillReward(ctx({ victimTeam = TEAM_SPEC })) == nil)
check("a bad context pays nothing", G.KillReward(nil) == nil and G.KillReward("live") == nil and G.KillReward({}) == nil)

dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_ledger.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_money.lua")

local phase = "live"
BALLISTICS.Round = {
	Phase = function() return phase end,
}

local function player(id)
	local ud = newproxy(true)
	local nw = {}
	getmetatable(ud).__index = {
		SteamID64 = function() return id end,
		SetNW2Int = function(_, k, v) nw[k] = v end,
		GetNW2Int = function(_, k) return nw[k] end,
		IsPlayer = function() return true end,
		IsAdmin = function() return false end,
		Nick = function() return id end,
	}
	return ud, nw
end

local function world()
	local ud = newproxy(true)
	getmetatable(ud).__index = {
		IsPlayer = function() return false end,
	}
	return ud
end

local good, goodNw = player("GOOD")
local bad, badNw = player("BAD")
local mate = player("MATE")
local env = world()

BALLISTICS.Slots.Take(good, GOOD, 1)
BALLISTICS.Slots.Take(bad, BAD, 1)
BALLISTICS.Slots.Take(mate, GOOD, 2)

local function pending(ply)
	local _, p = BALLISTICS.Money.Get(ply)
	return p
end

local function balance(ply)
	local b = BALLISTICS.Money.Get(ply)
	return b
end

check("enemy kill during live earns into pending", BALLISTICS.Money.OnDeath(bad, good) == true and pending(good) == 500 and balance(good) == 1000 and goodNw.bal_pending == 500)
check("the victim is not paid", pending(bad) == 0)
check("a second kill stacks in pending", BALLISTICS.Money.OnDeath(bad, good) == true and pending(good) == 1000 and balance(good) == 1000)

local held = pending(good)
check("a teamkill does not pay", BALLISTICS.Money.OnDeath(mate, good) == false and pending(good) == held and pending(mate) == 0)
check("a suicide does not pay", BALLISTICS.Money.OnDeath(good, good) == false and pending(good) == held)
check("a world death does not pay", BALLISTICS.Money.OnDeath(good, env) == false and pending(good) == held)
check("a nil attacker does not pay", BALLISTICS.Money.OnDeath(good, nil) == false and pending(good) == held)

phase = "buy"
check("a buy-phase kill does not pay", BALLISTICS.Money.OnDeath(bad, good) == false and pending(good) == held)
phase = "lobby"
check("a lobby kill does not pay", BALLISTICS.Money.OnDeath(bad, good) == false and pending(good) == held)
phase = "post"
check("a post-round kill does not pay", BALLISTICS.Money.OnDeath(bad, good) == false and pending(good) == held)
phase = "live"

BALLISTICS.Config.Set("Gains.kill", 250)
check("the next kill uses the live gain", BALLISTICS.Money.OnDeath(good, bad) == true and pending(bad) == 250 and badNw.bal_pending == 250)
BALLISTICS.Config.Set("Gains.kill", 500)

local beforeGood = pending(good)
local beforeBad = pending(bad)
hook.Run("PlayerDeath", good, env, bad)
check("the death hook pays the attacker, not the inflictor", pending(bad) == beforeBad + 500 and pending(good) == beforeGood)

beforeGood = pending(good)
beforeBad = pending(bad)
hook.Run("Ballistics_RoundEnd", "draw")
check("a draw still pays everyone", pending(good) == beforeGood + 500 and pending(bad) == beforeBad + 500)

beforeGood = pending(good)
beforeBad = pending(bad)
hook.Run("Ballistics_RoundEnd", "good")
check("a win still pays win and loss", pending(good) == beforeGood + 1000 and pending(bad) == beforeBad + 500)

beforeGood = pending(good)
beforeBad = pending(bad)
hook.Run("Ballistics_RoundEnd", "bad")
check("the other win still pays win and loss", pending(bad) == beforeBad + 1000 and pending(good) == beforeGood + 500)

if failed then os.exit(1) end
