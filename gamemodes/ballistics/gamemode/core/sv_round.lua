-- Drives the pure round machine: buy spawn, live elimination, timeout draw.
-- BALLISTICS.StartMatch(ply) is what the lobby Start button calls.
-- bal_debug_start is the admin/console concommand.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2
local state = BALLISTICS.State.new(BALLISTICS.Config or {})

local function isValid(ent)
	if ent == nil or ent == false then return false end
	if type(ent) == "table" and type(ent.IsValid) == "function" then
		return ent:IsValid() == true
	end
	if type(ent) ~= "table" and IsValid then return IsValid(ent) end
	return type(ent) == "table"
end

-- modules/spawns sets BALLISTICS.Spawns.HasBoth. With that module absent there
-- are no flags, so the match cannot start.
function BALLISTICS.HasBothFlags()
	local spawns = BALLISTICS.Spawns
	if type(spawns) == "table" and type(spawns.HasBoth) == "function" then
		return spawns.HasBoth() == true
	end
	return false
end

-- modules/spawns sets HasBox. With that module absent, or no box saved,
-- the match cannot start.
function BALLISTICS.HasSquadBox()
	local spawns = BALLISTICS.Spawns
	if type(spawns) == "table" and type(spawns.HasBox) == "function" then
		return spawns.HasBox() == true
	end
	return false
end

local function broadcast(target)
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	local now = (CurTime and CurTime()) or 0
	BALLISTICS.Net.Send("bal_round_sync", target, state:Snapshot(now))
end

local function eachSlotted(fn)
	if not (BALLISTICS.Slots and BALLISTICS.Slots.Members) then return end
	for _, teamId in ipairs({ GOOD, BAD }) do
		local members = BALLISTICS.Slots.Members(teamId)
		for i = 1, #members do
			local ply = BALLISTICS.Slots.Player(members[i])
			if ply then fn(ply, teamId, members[i]) end
		end
	end
end

local function spawnSlotted()
	if not (BALLISTICS.Player and BALLISTICS.Player.SpawnInRound) then return end
	eachSlotted(function(ply)
		BALLISTICS.Player.SpawnInRound(ply)
	end)
end

local function unfreezeSlotted()
	if not (BALLISTICS.Player and BALLISTICS.Player.SetFrozen) then return end
	eachSlotted(function(ply)
		if not ply.Alive or ply:Alive() then
			BALLISTICS.Player.SetFrozen(ply, false)
		end
	end)
end

local function spectateAll()
	if not (BALLISTICS.Player and BALLISTICS.Player.Each and BALLISTICS.Player.MakeSpectator) then return end
	BALLISTICS.Player.Each(function(ply)
		BALLISTICS.Player.MakeSpectator(ply)
	end)
end

local function handle(events)
	if type(events) ~= "table" then return end
	for i = 1, #events do
		local event = events[i]
		if event.type == "phase" then
			if event.new == "buy" then
				if BALLISTICS.Slots and BALLISTICS.Slots.ApplyQueued then
					BALLISTICS.Slots.ApplyQueued()
				end
				if event.matchStart then
					if BALLISTICS.Money and BALLISTICS.Money.Reset then
						BALLISTICS.Money.Reset()
					end
					if BALLISTICS.Gear and BALLISTICS.Gear.Reset then BALLISTICS.Gear.Reset() end
					if BALLISTICS.Organs and BALLISTICS.Organs.Reset then BALLISTICS.Organs.Reset() end
					-- Same transition that State:_enterBuy uses to zero the series score.
					if BALLISTICS.Scoreboard and BALLISTICS.Scoreboard.ResetFrags then
						BALLISTICS.Scoreboard.ResetFrags()
					end
				else
					if BALLISTICS.Money and BALLISTICS.Money.CommitAll then
						BALLISTICS.Money.CommitAll()
					end
					-- Organ hp is read before corpses (and their records) are removed.
					if BALLISTICS.Organs and BALLISTICS.Organs.Capture then BALLISTICS.Organs.Capture() end
				end
				if BALLISTICS.Cleanup and BALLISTICS.Cleanup.Round then BALLISTICS.Cleanup.Round() end
				spawnSlotted()
			elseif event.new == "live" then
				unfreezeSlotted()
			elseif event.new == "lobby" then
				spectateAll()
			end
			broadcast()
			if hook and hook.Run then
				hook.Run("Ballistics_PhaseChanged", event.old, event.new, event)
			end
		elseif event.type == "round_end" then
			broadcast()
			if hook and hook.Run then
				hook.Run("Ballistics_RoundEnd", event.winner, event.reason, event)
			end
		elseif event.type == "match_end" then
			if hook and hook.Run then
				hook.Run("Ballistics_MatchEnd", event.winner, event)
			end
		end
	end
end

-- Slotted and Alive(). Knocked out is still alive, so a team of only KO'd
-- players is not eliminated.
local function aliveCount(teamId)
	if not (BALLISTICS.Slots and BALLISTICS.Slots.Members) then return 0 end
	local members = BALLISTICS.Slots.Members(teamId)
	local n = 0
	for i = 1, #members do
		local ply = BALLISTICS.Slots.Player(members[i])
		if ply and ply.Alive and ply:Alive() then n = n + 1 end
	end
	return n
end

local function normalizeWinner(winner)
	if winner == "good" or winner == GOOD then return "good" end
	if winner == "bad" or winner == BAD then return "bad" end
	if winner == "draw" then return "draw" end
	return nil
end

BALLISTICS.Round = {}

function BALLISTICS.Round.Phase()
	return state:Phase()
end

function BALLISTICS.Round.Number()
	return state:Round()
end

function BALLISTICS.Round.Score()
	return state:Score()
end

function BALLISTICS.Round.Snapshot(now)
	return state:Snapshot(now or ((CurTime and CurTime()) or 0))
end

function BALLISTICS.Round.Broadcast(ply)
	broadcast(ply)
end

-- Slotted players stand on a ring around that team's flag. The origin ring
-- below is only for a round driver loaded without the spawns module. A loaded
-- module that has no flag for this team returns nil — never the origin.
function BALLISTICS.Round.SpawnTransform(teamId, slot)
	local spawns = BALLISTICS.Spawns
	if type(spawns) == "table" and type(spawns.PlayerSpawn) == "function" then
		local pos, ang = spawns.PlayerSpawn(teamId, slot)
		return pos, ang
	end
	local per = 5
	if BALLISTICS.Slots and BALLISTICS.Slots.Limit then per = BALLISTICS.Slots.Limit() end
	if not per or per < 1 then per = 1 end
	slot = tonumber(slot) or 1
	local theta = (slot - 1) * (2 * math.pi / per)
	local x = math.cos(theta) * 40
	local y = math.sin(theta) * 40
	if teamId == BAD then x = x + 256 end
	local yaw = math.deg(theta)
	local pos = Vector and Vector(x, y, 16) or { x = x, y = y, z = 16 }
	local ang = Angle and Angle(0, yaw, 0) or { p = 0, y = yaw, r = 0 }
	return pos, ang
end

function BALLISTICS.Round.End(winner, reason)
	winner = normalizeWinner(winner)
	if not winner then return false, "bad winner" end
	local now = (CurTime and CurTime()) or 0
	local events, err = state:Transition({ type = "end", winner = winner, reason = reason }, now)
	if not events then return false, err end
	handle(events)
	return true
end

function BALLISTICS.Round.CheckElimination()
	if state:Phase() ~= "live" then return nil end
	local winner, reason = BALLISTICS.State.Elimination(aliveCount(GOOD), aliveCount(BAD))
	if not winner then return nil end
	local ok, err = BALLISTICS.Round.End(winner, reason)
	if not ok then return nil, err end
	return winner, reason
end

local function slotCount(teamId)
	if BALLISTICS.Slots and BALLISTICS.Slots.Count then
		return tonumber(BALLISTICS.Slots.Count(teamId)) or 0
	end
	return 0
end

local function considerShowdown(now)
	if state:Phase() ~= "squad" then return nil end
	local snap = state:Snapshot(now)
	if snap.squadMode ~= "showdown" then return nil end
	local events = state:ConsiderShowdown(now, aliveCount(GOOD), aliveCount(BAD), slotCount(GOOD), slotCount(BAD))
	if type(events) ~= "table" or #events == 0 then return nil end
	return events
end

function BALLISTICS.Round.Tick(now)
	if now == nil then now = (CurTime and CurTime()) or 0 end
	if state:Phase() == "live" then
		local winner, reason = BALLISTICS.State.Elimination(aliveCount(GOOD), aliveCount(BAD))
		if winner then
			local events = state:Transition({ type = "end", winner = winner, reason = reason }, now)
			if events then
				handle(events)
				return events
			end
		end
	end
	if state:Phase() == "squad" then
		local events = considerShowdown(now)
		if events then
			handle(events)
			return events
		end
	end
	local events = state:Tick(now)
	handle(events)
	local extra = considerShowdown(now)
	if extra then
		handle(extra)
		return extra
	end
	return events
end

local function sideCounts()
	local good, bad = 0, 0
	if BALLISTICS.Slots and BALLISTICS.Slots.Count then
		good = BALLISTICS.Slots.Count(GOOD)
		bad = BALLISTICS.Slots.Count(BAD)
	end
	return good, bad
end

function BALLISTICS.Round.CanStart(ply)
	if ply ~= nil and not BALLISTICS.IsAdmin(ply) then return false, "admin" end
	local good, bad = sideCounts()
	local ok, err = state:CanStart(good, bad, BALLISTICS.HasBothFlags())
	if not ok then return false, err end
	if not BALLISTICS.HasSquadBox() then return false, "box" end
	return true
end

function BALLISTICS.StartMatch(ply)
	local ok, err = BALLISTICS.Round.CanStart(ply)
	if not ok then return false, err end
	local good, bad = sideCounts()
	local now = (CurTime and CurTime()) or 0
	local events
	events, err = state:Transition({
		type = "start",
		good = good,
		bad = bad,
		flags = BALLISTICS.HasBothFlags(),
	}, now)
	if not events then return false, err end
	handle(events)
	return true
end

-- Admin End Game. No firing squad. Gear, organs, and an active squad are
-- wiped here; money waits for the next match start, as a normal end does.
function BALLISTICS.Round.EndMatch()
	local now = (CurTime and CurTime()) or 0
	local events = state:EndMatch(now)
	if type(events) ~= "table" or #events == 0 then return true end
	if BALLISTICS.Gear and type(BALLISTICS.Gear.Reset) == "function" then
		BALLISTICS.Gear.Reset()
	end
	if BALLISTICS.Organs and type(BALLISTICS.Organs.Reset) == "function" then
		BALLISTICS.Organs.Reset()
	end
	if BALLISTICS.Squad and type(BALLISTICS.Squad.End) == "function" then
		BALLISTICS.Squad.End()
	end
	handle(events)
	return true
end

local function tell(ply, msg)
	print(msg)
	if BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply) and ply.ChatPrint then ply:ChatPrint(msg) end
end

local function startReason(err)
	local view = BALLISTICS.LobbyView
	local minPer = BALLISTICS.Config and BALLISTICS.Config.MinPerTeam
	if view and type(view.ReasonText) == "function" then
		local text = view.ReasonText(err, minPer)
		if type(text) == "string" and text ~= "" then return text end
	end
	return tostring(err)
end

function BALLISTICS.DebugStart(ply)
	local actor = nil
	if isValid(ply) then actor = ply end
	if actor and not BALLISTICS.IsAdmin(actor) then
		tell(actor, "Ballistics: admin only")
		return false, "admin"
	end
	local ok, err = BALLISTICS.StartMatch(actor)
	if ok then
		tell(actor, "Ballistics: match started")
	else
		tell(actor, "Ballistics: cannot start (" .. startReason(err) .. ")")
	end
	return ok, err
end

if concommand and concommand.Add then
	concommand.Add("bal_debug_start", function(ply)
		return BALLISTICS.DebugStart(ply)
	end, nil, "Start the ballistics match (admin)")
end

local function startTimer()
	if not (timer and timer.Create) then return end
	local rate = 0.1
	if BALLISTICS.Config and type(BALLISTICS.Config.TickRate) == "number" and BALLISTICS.Config.TickRate > 0 then
		rate = BALLISTICS.Config.TickRate
	end
	timer.Create("Ballistics_Round", rate, 0, function()
		BALLISTICS.Round.Tick((CurTime and CurTime()) or 0)
	end)
end

startTimer()

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_match_end", function(ply)
		if not (BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply)) then return end
		BALLISTICS.Round.EndMatch()
	end, { admin = true, rate = 2 })

	-- bal_round_sync: string phase, uint16 round, float endsAt, float enteredAt,
	-- uint16 scoreGood, uint16 scoreBad, string winner, string reason,
	-- string matchWinner.
	BALLISTICS.Net.Register("bal_round_sync", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteString(payload.phase or "")
			net.WriteUInt(payload.round or 0, 16)
			net.WriteFloat(payload.endsAt or 0)
			net.WriteFloat(payload.enteredAt or 0)
			net.WriteUInt(payload.scoreGood or 0, 16)
			net.WriteUInt(payload.scoreBad or 0, 16)
			net.WriteString(payload.winner or "")
			net.WriteString(payload.reason or "")
			net.WriteString(payload.matchWinner or "")
		end,
	})
end

if hook and hook.Add then
	hook.Add("PlayerInitialSpawn", "Ballistics_RoundSync", function(ply)
		broadcast(ply)
	end)
end
