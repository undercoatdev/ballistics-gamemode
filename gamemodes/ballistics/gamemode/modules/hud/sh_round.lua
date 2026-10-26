-- Round HUD model. No GMod calls.
-- A small phase line at the top centre. When capture bars are up, the line
-- moves below them so the two never share pixels.

BALLISTICS = BALLISTICS or {}
BALLISTICS.RoundHud = BALLISTICS.RoundHud or {}

local H = BALLISTICS.RoundHud

local NAMES = {
	lobby = "LOBBY",
	buy = "BUY",
	live = "LIVE",
	post = "POST",
}

local CHIP_W = 220
local CHIP_H = 16
local CHIP_TOP = 6
local CHIP_GAP = 4

local snap = {
	phase = "",
	endsAt = 0,
	round = 0,
	winner = "",
	seen = false,
}

function H.Clock(seconds)
	local n = tonumber(seconds) or 0
	if n ~= n or n == math.huge or n < 0 then n = 0 end
	local s = math.ceil(n - 1e-9)
	if s < 0 then s = 0 end
	local minutes = math.floor(s / 60)
	local remain = s - minutes * 60
	return string.format("%d:%02d", minutes, remain)
end

-- Lobby has no countdown. A missing clock shows the phase alone.
function H.Label(phase, timeLeft)
	local name = NAMES[phase]
	if not name then return nil end
	if phase == "lobby" or timeLeft == nil then return name end
	return name .. "  " .. H.Clock(timeLeft)
end

function H.Apply(payload)
	if type(payload) ~= "table" then return false end
	local phase = payload.phase
	if type(phase) == "string" and NAMES[phase] then
		snap.phase = phase
		snap.seen = true
	end
	if payload.endsAt ~= nil then
		local ends = tonumber(payload.endsAt)
		if ends and ends == ends and ends ~= math.huge and ends ~= -math.huge then
			snap.endsAt = ends
		else
			snap.endsAt = 0
		end
	end
	if payload.round ~= nil then
		snap.round = math.floor(tonumber(payload.round) or 0)
	end
	if type(payload.winner) == "string" then snap.winner = payload.winner end
	return snap.seen == true
end

function H.Seen()
	return snap.seen == true
end

function H.Snapshot()
	return {
		phase = snap.phase,
		endsAt = snap.endsAt,
		round = snap.round,
		winner = snap.winner,
		seen = snap.seen == true,
	}
end

function H.TimeLeft(now)
	if not snap.seen then return nil end
	if snap.phase == "lobby" or snap.phase == "" then return nil end
	local ends = tonumber(snap.endsAt) or 0
	if ends <= 0 then return nil end
	now = tonumber(now) or 0
	local left = ends - now
	if left < 0 then return 0 end
	return left
end

function H.Line(now)
	if not snap.seen then return nil end
	return H.Label(snap.phase, H.TimeLeft(now))
end

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function barsFor(screenW, barCount)
	local cap = BALLISTICS.Capture
	if not cap or type(cap.BarRects) ~= "function" then return {} end
	local rects = cap.BarRects(screenW, barCount)
	if type(rects) ~= "table" then return {} end
	return rects
end

-- barCount is how many capture bars are on screen (0, 1, or 2).
function H.Place(screenW, barCount)
	local sw = tonumber(screenW) or 0
	if sw < 0 then sw = 0 end
	local w = CHIP_W
	if sw > 0 and w > sw then w = sw end
	local x = math.floor((sw - w) / 2)
	if x < 0 then x = 0 end
	local rect = { x = x, y = CHIP_TOP, w = w, h = CHIP_H }
	local bars = barsFor(sw, barCount)
	local function hit(r)
		for i = 1, #bars do
			if overlaps(r, bars[i]) then return true end
		end
		return false
	end
	if hit(rect) then
		local bottom = 0
		for i = 1, #bars do
			local yb = bars[i].y + bars[i].h
			if yb > bottom then bottom = yb end
		end
		rect.y = bottom + CHIP_GAP
	end
	return rect
end
