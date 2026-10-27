-- Clears K/D once per match and mirrors the series score onto NW2.
-- State:_enterBuy(now, true) zeros score.good/bad and marks the phase event
-- matchStart. sv_round then runs Ballistics_PhaseChanged. That is the only
-- transition that may wipe frags; buy↔live↔post must not.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Scoreboard = BALLISTICS.Scoreboard or {}

local S = BALLISTICS.Scoreboard

local function isEnt(ply)
	local t = type(ply)
	return t == "table" or t == "userdata"
end

local function eachPlayer(fn)
	if BALLISTICS.Player and type(BALLISTICS.Player.Each) == "function" then
		BALLISTICS.Player.Each(fn)
		return
	end
	if player and type(player.GetAll) == "function" then
		local all = player.GetAll()
		if type(all) ~= "table" then return end
		for i = 1, #all do fn(all[i]) end
	end
end

function S.ResetFrags()
	eachPlayer(function(ply)
		if not isEnt(ply) then return end
		if type(ply.SetFrags) == "function" then pcall(ply.SetFrags, ply, 0) end
		if type(ply.SetDeaths) == "function" then pcall(ply.SetDeaths, ply, 0) end
	end)
end

local function series()
	local round, good, bad = 0, 0, 0
	local r = BALLISTICS.Round
	if type(r) == "table" then
		if type(r.Number) == "function" then round = tonumber(r.Number()) or 0 end
		if type(r.Score) == "function" then
			local s = r.Score()
			if type(s) == "table" then
				good = tonumber(s.good) or 0
				bad = tonumber(s.bad) or 0
			end
		end
	end
	if round < 0 then round = 0 end
	if good < 0 then good = 0 end
	if bad < 0 then bad = 0 end
	return math.floor(round), math.floor(good), math.floor(bad)
end

function S.Publish(target)
	local round, good, bad = series()
	local function one(ply)
		if not isEnt(ply) or type(ply.SetNW2Int) ~= "function" then return end
		pcall(ply.SetNW2Int, ply, S.NWRound or "bal_round", round)
		pcall(ply.SetNW2Int, ply, S.NWGood or "bal_score_good", good)
		pcall(ply.SetNW2Int, ply, S.NWBad or "bal_score_bad", bad)
	end
	if target ~= nil then
		one(target)
		return
	end
	eachPlayer(one)
end

if hook and hook.Add then
	hook.Add("Ballistics_PhaseChanged", "Ballistics_Scoreboard", function(old, new, event)
		local zeroed = type(event) == "table" and event.matchStart == true
		if type(S.ShouldResetFrags) == "function" and S.ShouldResetFrags(old, new, zeroed) then
			S.ResetFrags()
		end
		S.Publish()
	end)
	hook.Add("Ballistics_RoundEnd", "Ballistics_Scoreboard", function()
		S.Publish()
	end)
	hook.Add("PlayerInitialSpawn", "Ballistics_Scoreboard", function(ply)
		S.Publish(ply)
	end)
end
