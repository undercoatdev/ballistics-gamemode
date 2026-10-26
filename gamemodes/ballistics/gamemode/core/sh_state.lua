-- Pure round state machine. No GMod calls.
-- Phases: lobby → buy → live → post → buy … until RoundsToWin (0 = endless).
-- A decided match (one team reaches RoundsToWin) always leaves post for the
-- firing squad, then the lobby. A deciding tie (equal score on the line, or a
-- draw when one more win would clinch) leaves post for an untimed showdown in
-- the same phase. Showdown names a winner before the lobby. An endless match
-- never enters squad. Post never returns straight to the lobby.
--
-- state:Transition(evt, now) → events, or nil, err
-- state:Tick(now) → events (one phase boundary per call; empty if nothing fired)
-- evt is "start" / "end" or { type = "start"|"end", good, bad, flags, winner, reason }
-- "start" needs ≥ MinPerTeam on both teams and flags == true.
-- A live clock expiry ends the round as TimeoutWinner (default "draw").

BALLISTICS = BALLISTICS or {}

local State = {}
State.__index = State

local PHASE_LOBBY = "lobby"
local PHASE_BUY = "buy"
local PHASE_LIVE = "live"
local PHASE_POST = "post"
local PHASE_SQUAD = "squad"

local function duration(self, key, default)
	local n = tonumber(self.cfg[key])
	if not n or n ~= n or n <= 0 then return default end
	return n
end

local function whole(self, key, default)
	local n = tonumber(self.cfg[key])
	if not n or n ~= n then return default end
	return math.floor(n)
end

local function timeoutWinner(self)
	local w = self.cfg.TimeoutWinner
	if w == "good" or w == "bad" or w == "draw" then return w end
	return "draw"
end

local function roundsToWin(self)
	local n = whole(self, "RoundsToWin", 0)
	if n < 0 then return 0 end
	return n
end

local function squadDuration(self)
	local n = tonumber(self.cfg.FiringSquadDuration)
	if not n or n ~= n or n <= 0 then return 30 end
	return n
end

function State.new(cfg)
	if type(cfg) ~= "table" then cfg = {} end
	return setmetatable({
		cfg = cfg,
		phase = PHASE_LOBBY,
		round = 0,
		score = { good = 0, bad = 0 },
		enteredAt = 0,
		endsAt = nil,
		winner = nil,
		reason = nil,
		matchWinner = nil,
		squadMode = nil,
		ready = nil,
	}, State)
end

function State:Phase()
	return self.phase
end

function State:Round()
	return self.round
end

function State:Score()
	return { good = self.score.good, bad = self.score.bad }
end

function State:EndsAt()
	return self.endsAt
end

function State:Winner()
	return self.winner, self.reason
end

function State:MatchWinner()
	return self.matchWinner
end

function State:SquadMode()
	return self.squadMode
end

function State:TimeLeft(now)
	if not self.endsAt then return nil end
	now = tonumber(now) or 0
	local left = self.endsAt - now
	if left < 0 then return 0 end
	return left
end

function State:Snapshot(now)
	now = tonumber(now) or 0
	local left = self:TimeLeft(now) or 0
	return {
		phase = self.phase,
		round = self.round,
		enteredAt = self.enteredAt,
		endsAt = self.endsAt or 0,
		timeLeft = left,
		scoreGood = self.score.good,
		scoreBad = self.score.bad,
		winner = self.winner or "",
		reason = self.reason or "",
		matchWinner = self.matchWinner or "",
		squadMode = self.squadMode or "",
	}
end

-- Remembered by a bare Transition("start", now). Explicit event fields win.
function State:SetReady(good, bad, flags)
	self.ready = {
		good = tonumber(good) or 0,
		bad = tonumber(bad) or 0,
		flags = flags == true,
	}
end

function State:CanStart(good, bad, flags)
	if self.phase ~= PHASE_LOBBY then return false, "not lobby" end
	local min = whole(self, "MinPerTeam", 1)
	if min < 0 then min = 0 end
	if (tonumber(good) or 0) < min or (tonumber(bad) or 0) < min then
		return false, "min players"
	end
	if flags ~= true then return false, "flags" end
	return true
end

-- Knocked-out-but-alive players are still alive. Callers pass Alive() counts,
-- not consciousness. Zero living players on a side eliminates that side.
-- Both sides at once is a draw.
function State.Elimination(goodAlive, badAlive)
	goodAlive = tonumber(goodAlive) or 0
	badAlive = tonumber(badAlive) or 0
	local goodOut = goodAlive <= 0
	local badOut = badAlive <= 0
	if not goodOut and not badOut then return nil end
	if goodOut and badOut then return "draw", "elimination" end
	if goodOut then return "bad", "elimination" end
	return "good", "elimination"
end

-- "good", "bad", "showdown", or nil when the series continues.
-- A deciding tie is an equal score already on the rounds-to-win line, or a
-- draw while the scores are level and one more win would clinch. RoundsToWin
-- 0 never closes. Knocked-out players are not an input here.
function State.MatchCall(good, bad, roundWinner, roundsToWin)
	good = math.floor(tonumber(good) or 0)
	bad = math.floor(tonumber(bad) or 0)
	if good < 0 then good = 0 end
	if bad < 0 then bad = 0 end
	local need = math.floor(tonumber(roundsToWin) or 0)
	if need <= 0 then return nil end
	local goodHit = good >= need
	local badHit = bad >= need
	if goodHit and badHit then return "showdown" end
	if goodHit then return "good" end
	if badHit then return "bad" end
	if roundWinner == "draw" and good == bad and good + 1 >= need then
		return "showdown"
	end
	return nil
end

-- Alive counts are Alive(), so knocked-out players are still in. Slot counts
-- are how many players are on the team. nil means the fight continues.
-- "lobby" means nobody is slotted. A simultaneous wipe is Good's win.
function State.ShowdownCall(goodAlive, badAlive, goodSlots, badSlots)
	goodSlots = math.floor(tonumber(goodSlots) or 0)
	badSlots = math.floor(tonumber(badSlots) or 0)
	if goodSlots < 0 then goodSlots = 0 end
	if badSlots < 0 then badSlots = 0 end
	if goodSlots <= 0 and badSlots <= 0 then return "lobby" end
	if goodSlots <= 0 then return "bad" end
	if badSlots <= 0 then return "good" end
	goodAlive = math.floor(tonumber(goodAlive) or 0)
	badAlive = math.floor(tonumber(badAlive) or 0)
	if goodAlive > 0 and badAlive > 0 then return nil end
	if goodAlive <= 0 and badAlive <= 0 then return "good" end
	if goodAlive <= 0 then return "bad" end
	return "good"
end

local function phaseEvent(old, new, round, matchStart)
	return {
		type = "phase",
		old = old,
		new = new,
		round = round,
		matchStart = matchStart and true or false,
	}
end

function State:_enterBuy(now, matchStart)
	local prev = self.phase
	if matchStart then
		self.score.good = 0
		self.score.bad = 0
		self.matchWinner = nil
		self.round = 1
	else
		self.round = self.round + 1
	end
	self.squadMode = nil
	self.phase = PHASE_BUY
	self.enteredAt = now
	self.endsAt = now + duration(self, "BuyTime", 20)
	self.winner = nil
	self.reason = nil
	return { phaseEvent(prev, PHASE_BUY, self.round, matchStart) }
end

function State:_enterLive(now)
	local prev = self.phase
	self.phase = PHASE_LIVE
	self.squadMode = nil
	self.enteredAt = now
	self.endsAt = now + duration(self, "RoundTime", 600)
	return { phaseEvent(prev, PHASE_LIVE, self.round, false) }
end

function State:_enterPost(now, winner, reason)
	local prev = self.phase
	self.phase = PHASE_POST
	self.enteredAt = now
	self.endsAt = now + duration(self, "PostRoundTime", 5)
	self.winner = winner
	self.reason = reason
	if winner == "good" then
		self.score.good = self.score.good + 1
	elseif winner == "bad" then
		self.score.bad = self.score.bad + 1
	end
	local call = State.MatchCall(self.score.good, self.score.bad, winner, roundsToWin(self))
	if call == "good" or call == "bad" then
		self.matchWinner = call
		self.squadMode = "finale"
	elseif call == "showdown" then
		self.matchWinner = nil
		self.squadMode = "showdown"
	else
		self.squadMode = nil
	end
	return {
		{
			type = "round_end",
			winner = winner,
			reason = reason,
			round = self.round,
			scoreGood = self.score.good,
			scoreBad = self.score.bad,
		},
		phaseEvent(prev, PHASE_POST, self.round, false),
	}
end

function State:_enterSquad(now)
	local prev = self.phase
	self.phase = PHASE_SQUAD
	self.squadMode = "finale"
	self.enteredAt = now
	self.endsAt = now + squadDuration(self)
	return {
		phaseEvent(prev, PHASE_SQUAD, self.round, false),
		{ type = "match_end", winner = self.matchWinner, round = self.round },
	}
end

function State:_enterShowdown(now)
	local prev = self.phase
	self.phase = PHASE_SQUAD
	self.squadMode = "showdown"
	self.matchWinner = nil
	self.enteredAt = now
	self.endsAt = nil
	return { phaseEvent(prev, PHASE_SQUAD, self.round, false) }
end

function State:_enterLobby(now)
	local prev = self.phase
	local winner = self.matchWinner
	self.phase = PHASE_LOBBY
	self.squadMode = nil
	self.enteredAt = now
	self.endsAt = nil
	local events = {
		phaseEvent(prev, PHASE_LOBBY, self.round, false),
	}
	-- Squad already announced the match win on the way in.
	if prev ~= PHASE_SQUAD then
		events[#events + 1] = { type = "match_end", winner = winner, round = self.round }
	end
	return events
end

local function startFields(self, data)
	local ready = self.ready or {}
	local good = ready.good or 0
	local bad = ready.bad or 0
	local flags = ready.flags == true
	if data.good ~= nil then good = data.good end
	if data.bad ~= nil then bad = data.bad end
	if data.flags ~= nil then flags = data.flags == true end
	return good, bad, flags
end

function State:_start(data, now)
	local good, bad, flags = startFields(self, data)
	local ok, err = self:CanStart(good, bad, flags)
	if not ok then return nil, err end
	return self:_enterBuy(now, true)
end

function State:_end(data, now)
	if self.phase ~= PHASE_LIVE then return nil, "not live" end
	local winner = data.winner
	if winner ~= "good" and winner ~= "bad" and winner ~= "draw" then
		return nil, "bad winner"
	end
	local reason = data.reason
	if type(reason) ~= "string" or reason == "" then reason = "unknown" end
	return self:_enterPost(now, winner, reason)
end

function State:Transition(evt, now)
	now = tonumber(now) or 0
	local kind = evt
	local data = {}
	if type(evt) == "table" then
		kind = evt.type or evt[1]
		data = evt
	end
	if kind == "start" then return self:_start(data, now) end
	if kind == "end" then return self:_end(data, now) end
	return nil, "unknown event"
end

function State:Tick(now)
	now = tonumber(now) or 0
	if self.phase == PHASE_LOBBY or not self.endsAt or now < self.endsAt then
		return {}
	end
	if self.phase == PHASE_BUY then return self:_enterLive(now) end
	if self.phase == PHASE_LIVE then
		return self:_enterPost(now, timeoutWinner(self), "timeout")
	end
	if self.phase == PHASE_POST then
		-- A tie must not fall through to the lobby without a side.
		if self.squadMode == "showdown" then return self:_enterShowdown(now) end
		if self.matchWinner and self.matchWinner ~= "good" and self.matchWinner ~= "bad" then
			return self:_enterShowdown(now)
		end
		if self.matchWinner == "good" or self.matchWinner == "bad" or self.squadMode == "finale" then
			return self:_enterSquad(now)
		end
		return self:_enterBuy(now, false)
	end
	if self.phase == PHASE_SQUAD then
		if self.squadMode == "showdown" then return {} end
		return self:_enterLobby(now)
	end
	return {}
end

function State:FinishShowdown(now, winner)
	if self.phase ~= PHASE_SQUAD or self.squadMode ~= "showdown" then return nil, "not showdown" end
	if winner ~= "good" and winner ~= "bad" then return nil, "bad winner" end
	now = tonumber(now) or 0
	self.matchWinner = winner
	local prev = self.phase
	self.phase = PHASE_LOBBY
	self.squadMode = nil
	self.enteredAt = now
	self.endsAt = nil
	return {
		{ type = "match_end", winner = winner, round = self.round },
		phaseEvent(prev, PHASE_LOBBY, self.round, false),
	}
end

function State:AbandonShowdown(now)
	if self.phase ~= PHASE_SQUAD or self.squadMode ~= "showdown" then return nil, "not showdown" end
	now = tonumber(now) or 0
	self.matchWinner = nil
	local prev = self.phase
	self.phase = PHASE_LOBBY
	self.squadMode = nil
	self.enteredAt = now
	self.endsAt = nil
	return { phaseEvent(prev, PHASE_LOBBY, self.round, false) }
end

function State:ConsiderShowdown(now, goodAlive, badAlive, goodSlots, badSlots)
	if self.phase ~= PHASE_SQUAD or self.squadMode ~= "showdown" then return {} end
	local call = State.ShowdownCall(goodAlive, badAlive, goodSlots, badSlots)
	if call == "good" or call == "bad" then
		return self:FinishShowdown(now, call) or {}
	end
	if call == "lobby" then
		return self:AbandonShowdown(now) or {}
	end
	return {}
end

BALLISTICS.State = State
