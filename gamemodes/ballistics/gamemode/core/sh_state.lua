-- Pure round state machine. No GMod calls.
-- Phases: lobby → buy → live → post → buy … until RoundsToWin (0 = endless),
-- then post returns to lobby.
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
	local need = roundsToWin(self)
	if need > 0 and self.matchWinner == nil then
		if self.score.good >= need then
			self.matchWinner = "good"
		elseif self.score.bad >= need then
			self.matchWinner = "bad"
		end
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

function State:_enterLobby(now)
	local prev = self.phase
	local winner = self.matchWinner
	self.phase = PHASE_LOBBY
	self.enteredAt = now
	self.endsAt = nil
	return {
		phaseEvent(prev, PHASE_LOBBY, self.round, false),
		{ type = "match_end", winner = winner, round = self.round },
	}
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
		if self.matchWinner then return self:_enterLobby(now) end
		return self:_enterBuy(now, false)
	end
	return {}
end

BALLISTICS.State = State
