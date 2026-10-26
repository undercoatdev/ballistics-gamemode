-- Drive capture during LIVE and end the round through BALLISTICS.Round.End.
-- Progress resets when the phase becomes BUY or the match returns to the lobby.
-- The ground circles are the spawn module's; this file only counts players.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Objective = BALLISTICS.Objective or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local progress = BALLISTICS.Capture.new()
local sentGood, sentBad

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function validEnt(ent)
	if ent == nil or ent == false then return false end
	local kind = type(ent)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Player" and kind ~= "Entity" then
		return false
	end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	if kind ~= "table" and IsValid then return IsValid(ent) end
	return kind == "table"
end

local function phaseOf()
	if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
		local p = BALLISTICS.Round.Phase()
		if type(p) == "string" and p ~= "" then return p end
	end
	return "lobby"
end

local function tickRate()
	local n = BALLISTICS.Config and tonumber(BALLISTICS.Config.TickRate)
	if not finite(n) or n <= 0 then return 0.1 end
	if n > 5 then return 5 end
	return n
end

local function publish(target, force)
	local good = progress.good or 0
	local bad = progress.bad or 0
	if not force and target == nil and good == sentGood and bad == sentBad then return end
	if target == nil then
		sentGood = good
		sentBad = bad
	end
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	BALLISTICS.Net.Send("bal_capture_sync", target, { good = good, bad = bad })
end

function BALLISTICS.Objective.Progress()
	return progress.good or 0, progress.bad or 0
end

function BALLISTICS.Objective.Reset()
	BALLISTICS.Capture.Reset(progress)
	publish(nil, true)
end

function BALLISTICS.Objective.Sync(ply)
	publish(ply, true)
end

local function sample()
	local list = {}
	local slots = BALLISTICS.Slots
	if not slots or type(slots.Members) ~= "function" or type(slots.Player) ~= "function" then
		return list
	end
	for _, teamId in ipairs({ GOOD, BAD }) do
		local members = slots.Members(teamId)
		if type(members) == "table" then
			for i = 1, #members do
				local ply = slots.Player(members[i])
				if validEnt(ply) and type(ply.GetPos) == "function" then
					local alive = type(ply.Alive) == "function" and ply:Alive() == true
					local conscious = false
					if type(BALLISTICS.IsConscious) == "function" then
						conscious = BALLISTICS.IsConscious(ply) == true
					end
					list[#list + 1] = {
						team = teamId,
						pos = ply:GetPos(),
						alive = alive,
						conscious = conscious,
					}
				end
			end
		end
	end
	return list
end

local function flags()
	local snap
	if BALLISTICS.Spawns and type(BALLISTICS.Spawns.Snapshot) == "function" then
		snap = BALLISTICS.Spawns.Snapshot()
	end
	if type(snap) ~= "table" then return {} end
	return { good = snap.good, bad = snap.bad }
end

function BALLISTICS.Objective.Tick(dt)
	if phaseOf() ~= "live" then return nil end
	dt = tonumber(dt)
	if not finite(dt) or dt <= 0 then dt = tickRate() end
	local result = BALLISTICS.Capture.Tick(progress, {
		players = sample(),
		flags = flags(),
	}, dt)
	publish(nil, false)
	if result.winner and BALLISTICS.Round and type(BALLISTICS.Round.End) == "function" then
		BALLISTICS.Round.End(result.winner, result.reason or "capture")
	end
	return result
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	-- bal_capture_sync: float goodProgress, float badProgress.
	-- goodProgress is how far Bad has taken Good's flag.
	BALLISTICS.Net.Register("bal_capture_sync", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteFloat(tonumber(payload.good) or 0)
			net.WriteFloat(tonumber(payload.bad) or 0)
		end,
	})
end

if hook and hook.Add then
	hook.Add("Ballistics_PhaseChanged", "Ballistics_CaptureReset", function(_, newPhase)
		if newPhase == "buy" or newPhase == "lobby" then
			BALLISTICS.Objective.Reset()
		end
	end)

	hook.Add("PlayerInitialSpawn", "Ballistics_CaptureSync", function(ply)
		publish(ply, true)
	end)

	local nextAt = 0
	local lastAt = nil
	hook.Add("Think", "Ballistics_Objective", function()
		local now = (CurTime and CurTime()) or 0
		if now < nextAt then return end
		local rate = tickRate()
		nextAt = now + rate
		local dt = rate
		if lastAt ~= nil then
			dt = now - lastAt
			if not finite(dt) or dt <= 0 or dt > 1 then dt = rate end
		end
		lastAt = now
		BALLISTICS.Objective.Tick(dt)
	end)
end
