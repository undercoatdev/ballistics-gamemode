-- TAB scoreboard model. No GMod calls.
-- Series text comes from the round snapshot; K/D clears once per match.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Scoreboard = BALLISTICS.Scoreboard or {}

local S = BALLISTICS.Scoreboard

-- NW2 fallback when bal_round_sync has not filled RoundHud yet.
S.NWRound = "bal_round"
S.NWGood = "bal_score_good"
S.NWBad = "bal_score_bad"

local function color(r, g, b, a)
	if Color then return Color(r, g, b, a or 255) end
	return { r = r, g = g, b = b, a = a or 255 }
end

local function finite(n)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

local function whole(n, fallback)
	local v = finite(n)
	if v == nil then return fallback end
	v = math.floor(v)
	if v < 0 then v = 0 end
	return v
end

local function hasChannels(c)
	return type(c) == "table" and tonumber(c.r) and tonumber(c.g) and tonumber(c.b)
end

-- Team colours from sh_teams. The literals are only used when that table is missing.
function S.TeamColor(teamId)
	local known = BALLISTICS.TeamColor and BALLISTICS.TeamColor[teamId]
	if hasChannels(known) then return known end
	if teamId == (TEAM_BAD or 2) then return color(210, 70, 70) end
	if teamId == (TEAM_GOOD or 1) then return color(80, 140, 220) end
	return color(180, 180, 180)
end

-- printName is team.GetName / the team PrintName. "BLUE" / "RED" are the fallback.
function S.ColumnName(teamId, printName)
	if type(printName) == "string" then
		local name = printName:match("^%s*(.-)%s*$")
		if name and name ~= "" and name ~= tostring(teamId) then return name end
	end
	local known = BALLISTICS.TeamName and BALLISTICS.TeamName[teamId]
	if type(known) == "string" and known ~= "" then return known end
	if teamId == (TEAM_GOOD or 1) then return "BLUE" end
	if teamId == (TEAM_BAD or 2) then return "RED" end
	return "TEAM"
end

-- roundsToWin 0 (and anything below 1) is an endless series.
function S.Header(round, roundsToWin, scoreGood, scoreBad)
	local cap = finite(roundsToWin)
	local capText = "∞"
	if cap ~= nil and cap >= 1 then capText = tostring(math.floor(cap)) end
	return {
		roundLine = "Round " .. tostring(whole(round, 0)) .. " / " .. capText,
		scoreLeft = whole(scoreGood, 0),
		scoreRight = whole(scoreBad, 0),
	}
end

-- Snapshot wins once a real bal_round_sync has stored the series score.
-- A phase-only RoundHud update (seen, but no scores) leaves NW2 in place.
-- roundsToWin is always the config value, not a networked field.
function S.MatchFrom(snapshot, nwRound, nwGood, nwBad, roundsToWin)
	local round = whole(nwRound, 0)
	local good = whole(nwGood, 0)
	local bad = whole(nwBad, 0)
	if type(snapshot) == "table" and snapshot.seen == true then
		local full = snapshot.scoreGood ~= nil or snapshot.scoreBad ~= nil
		if full and snapshot.round ~= nil then round = whole(snapshot.round, round) end
		if snapshot.scoreGood ~= nil then good = whole(snapshot.scoreGood, good) end
		if snapshot.scoreBad ~= nil then bad = whole(snapshot.scoreBad, bad) end
	end
	return S.Header(round, roundsToWin, good, bad)
end

local function isPly(ply)
	local t = type(ply)
	return t == "table" or t == "userdata" or t == "Player" or t == "Entity"
end

function S.PlayerName(ply)
	if not isPly(ply) then return "" end
	local methods = { "Nick", "Name", "GetName" }
	for i = 1, #methods do
		local fn = ply[methods[i]]
		if type(fn) == "function" then
			local ok, n = pcall(fn, ply)
			if ok and type(n) == "string" and n ~= "" then return n end
		end
	end
	if type(ply.name) == "string" and ply.name ~= "" then return ply.name end
	if type(ply.nick) == "string" and ply.nick ~= "" then return ply.nick end
	return ""
end

function S.FragCount(ply)
	if not isPly(ply) then return 0 end
	if type(ply.Frags) == "function" then
		local ok, n = pcall(ply.Frags, ply)
		local v = ok and finite(n) or nil
		if v ~= nil then return math.floor(v) end
	end
	if ply.frags ~= nil then
		local v = finite(ply.frags)
		if v ~= nil then return math.floor(v) end
	end
	if ply.kills ~= nil then
		local v = finite(ply.kills)
		if v ~= nil then return math.floor(v) end
	end
	return 0
end

local function stat(ply, method, field)
	if not isPly(ply) then return 0 end
	if type(ply[method]) == "function" then
		local ok, n = pcall(ply[method], ply)
		local v = ok and finite(n) or nil
		if v ~= nil then
			if v < 0 then v = 0 end
			return math.floor(v)
		end
	end
	if type(ply) == "table" and ply[field] ~= nil then
		local v = finite(ply[field])
		if v ~= nil then
			if v < 0 then v = 0 end
			return math.floor(v)
		end
	end
	return 0
end

function S.Row(ply)
	local alive = true
	if isPly(ply) then
		if type(ply.Alive) == "function" then
			local ok, v = pcall(ply.Alive, ply)
			if ok then alive = v == true end
		elseif type(ply) == "table" and ply.alive ~= nil then
			alive = ply.alive == true
		end
	end
	return {
		name = S.PlayerName(ply),
		kills = S.FragCount(ply),
		deaths = stat(ply, "Deaths", "deaths"),
		ping = stat(ply, "Ping", "ping"),
		alive = alive,
		ply = ply,
	}
end

-- Highest kills first. Equal kills fall back to name, then original order.
function S.SortPlayers(list)
	local out = {}
	if type(list) ~= "table" then return out end
	local rows = {}
	for i = 1, #list do
		local ply = list[i]
		rows[#rows + 1] = {
			ply = ply,
			i = i,
			frags = S.FragCount(ply),
			name = S.PlayerName(ply),
		}
	end
	table.sort(rows, function(a, b)
		if a.frags ~= b.frags then return a.frags > b.frags end
		if a.name ~= b.name then return a.name < b.name end
		return a.i < b.i
	end)
	for i = 1, #rows do
		out[i] = rows[i].ply
	end
	return out
end

function S.SpectatorLine(names)
	local parts = {}
	if type(names) == "table" then
		for i = 1, #names do
			if type(names[i]) == "string" and names[i] ~= "" then
				parts[#parts + 1] = names[i]
			end
		end
	end
	if #parts == 0 then return "Spectators: —" end
	return "Spectators: " .. table.concat(parts, ", ")
end

-- True only when a new match starts: lobby (or a blank phase) into the first
-- buy/live, or the transition that just zeroed the series score (State:_enterBuy
-- matchStart). buy↔live↔post and an admin end into the lobby do not qualify.
function S.ShouldResetFrags(oldPhase, newPhase, scoreJustZeroed)
	if newPhase ~= "buy" and newPhase ~= "live" then return false end
	if scoreJustZeroed == true then return true end
	if oldPhase == nil or oldPhase == "" or oldPhase == "lobby" then return true end
	return false
end
