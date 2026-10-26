-- Which slot a test bot fills, and whether the request is allowed.
-- No GMod calls. The server module creates the NextBots.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Bots = BALLISTICS.Bots or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2
local MAX_PLAYERS = 10

local ACTIONS = { add = true, fill = true, remove = true }

local function whole(n, fallback)
	n = tonumber(n)
	if not n or n ~= n then return fallback end
	return math.floor(n)
end

function BALLISTICS.Bots.Message()
	return "bal_bots"
end

function BALLISTICS.Bots.MaxPlayers()
	return MAX_PLAYERS
end

function BALLISTICS.Bots.Limit(perTeam)
	local n = whole(perTeam, 5)
	if n < 1 then n = 1 end
	if n > 16 then n = 16 end
	return n
end

function BALLISTICS.Bots.PlayingTeam(teamId)
	teamId = tonumber(teamId)
	if teamId == GOOD or teamId == BAD then return true, teamId end
	return false
end

-- Lobby and buy take a slot immediately. Live and post wait for the next buy.
function BALLISTICS.Bots.JoinsNow(phase)
	return phase ~= "live" and phase ~= "post"
end

-- Buy puts a new bot on the flag. Lobby waits for the match. Live and post
-- wait until the following buy, the same as a human who was not yet spawned.
function BALLISTICS.Bots.SpawnNow(phase)
	return phase == "buy"
end

local function sideName(teamId)
	if tonumber(teamId) == BAD then return "Bad" end
	return "Good"
end

function BALLISTICS.Bots.Name(teamId, slot)
	slot = whole(slot, 1)
	if slot < 1 then slot = 1 end
	return "Bot " .. sideName(teamId) .. " " .. tostring(slot)
end

local function occupied(taken, slot)
	if type(taken) ~= "table" then return false end
	local occ = taken[slot]
	return occ ~= nil and occ ~= false and occ ~= ""
end

function BALLISTICS.Bots.FirstFree(taken, limit)
	local n = BALLISTICS.Bots.Limit(limit)
	for slot = 1, n do
		if not occupied(taken, slot) then return slot end
	end
	return nil
end

-- Room left under the 10-player cap and under SlotsPerTeam on both sides.
function BALLISTICS.Bots.Room(playerCount, limit, maxPlayers)
	local per = BALLISTICS.Bots.Limit(limit)
	local cap = per * 2
	local maxP = whole(maxPlayers, MAX_PLAYERS)
	if maxP < 1 then maxP = MAX_PLAYERS end
	if maxP > MAX_PLAYERS then maxP = MAX_PLAYERS end
	if maxP > cap then maxP = cap end
	local count = whole(playerCount, 0)
	if count < 0 then count = 0 end
	local room = maxP - count
	if room < 0 then return 0 end
	return room
end

function BALLISTICS.Bots.FillPlan(sides, limit, playerCount, maxPlayers)
	local per = BALLISTICS.Bots.Limit(limit)
	local room = BALLISTICS.Bots.Room(playerCount, per, maxPlayers)
	local plan = {}
	sides = type(sides) == "table" and sides or {}
	for _, teamId in ipairs({ GOOD, BAD }) do
		local taken = sides[teamId]
		for slot = 1, per do
			if room <= 0 then return plan end
			if not occupied(taken, slot) then
				plan[#plan + 1] = {
					team = teamId,
					slot = slot,
					name = BALLISTICS.Bots.Name(teamId, slot),
				}
				room = room - 1
			end
		end
	end
	return plan
end

function BALLISTICS.Bots.ValidateAdd(ctx)
	if type(ctx) ~= "table" then return nil, "payload" end
	local ok, teamId = BALLISTICS.Bots.PlayingTeam(ctx.team)
	if not ok then return nil, "team" end
	local per = BALLISTICS.Bots.Limit(ctx.limit)
	local taken = ctx.taken
	if taken == nil and type(ctx.sides) == "table" then
		taken = ctx.sides[teamId]
	end
	local slot = BALLISTICS.Bots.FirstFree(taken, per)
	if not slot then return nil, "full" end
	if BALLISTICS.Bots.Room(ctx.playerCount, per, ctx.maxPlayers) < 1 then
		return nil, "players"
	end
	return {
		team = teamId,
		slot = slot,
		name = BALLISTICS.Bots.Name(teamId, slot),
	}
end

function BALLISTICS.Bots.Admit(isAdmin, action, ctx)
	if isAdmin ~= true then return nil, "admin" end
	if type(action) ~= "string" or not ACTIONS[action] then return nil, "action" end
	if action == "remove" then
		return { action = "remove" }
	end
	if type(ctx) ~= "table" then return nil, "payload" end
	if action == "fill" then
		local plan = BALLISTICS.Bots.FillPlan(ctx.sides, ctx.limit, ctx.playerCount, ctx.maxPlayers)
		return { action = "fill", plan = plan }
	end
	local row, err = BALLISTICS.Bots.ValidateAdd(ctx)
	if not row then return nil, err end
	row.action = "add"
	return row
end

if BALLISTICS.AdminTabs and type(BALLISTICS.AdminTabs.Add) == "function" then
	BALLISTICS.AdminTabs.Add({
		id = "bots",
		title = "Test Bots",
		implemented = true,
		reset = { enabled = false },
	})
end
