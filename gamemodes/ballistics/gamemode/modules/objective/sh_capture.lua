-- Pure capture. No game API.
-- Each flag has its own progress. Good's bar fills when Bad stands in Good's
-- circle, and the other way around. A full bar is a win for the attackers.
-- Knocked-out players are omitted by the caller (alive and conscious).
-- n = 1 fills in CaptureTimeOne. n >= 2 fills in CaptureTimeTwo, and n is
-- capped at CaptureMaxCounted before that choice. A conscious defender
-- freezes the bar when CaptureContestedFreeze is set. An empty circle
-- decays at CaptureDecayRate times the one-player rate.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Capture = BALLISTICS.Capture or {}

local C = BALLISTICS.Capture

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function coords(v)
	if v == nil then return nil end
	local kind = type(v)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Vector" then return nil end
	local x = tonumber(v.x)
	local y = tonumber(v.y)
	local z = tonumber(v.z)
	if x == nil then x = tonumber(v[1]) end
	if y == nil then y = tonumber(v[2]) end
	if z == nil then z = tonumber(v[3]) end
	if not finite(x) or not finite(y) or not finite(z) then return nil end
	return x, y, z
end

function C.Side(team)
	if team == GOOD or team == "good" or team == "Good" then return "good" end
	if team == BAD or team == "bad" or team == "Bad" then return "bad" end
	return nil
end

local function other(side)
	if side == "good" then return "bad" end
	if side == "bad" then return "good" end
	return nil
end

local function flagPos(flag)
	if flag == nil then return nil end
	if type(flag) == "table" and flag.pos ~= nil then return flag.pos end
	return flag
end

local function inside(pos, flag, radius)
	local r = tonumber(radius)
	if not finite(r) or r < 0 then return false end
	local x, y, z = coords(pos)
	local fx, fy, fz = coords(flagPos(flag))
	if not x or not fx then return false end
	local dx = x - fx
	local dy = y - fy
	local dz = z - fz
	return dx * dx + dy * dy + dz * dz <= r * r
end

local function cfgOf(world)
	if type(world) == "table" and type(world.cfg) == "table" then return world.cfg end
	if type(BALLISTICS.Config) == "table" then return BALLISTICS.Config end
	return {}
end

local function num(cfg, key, default)
	local n = tonumber(cfg[key])
	if not finite(n) then return default end
	return n
end

local function radiusOf(cfg)
	local r = num(cfg, "ObjectiveRadius", 2 / 0.01905)
	if r < 0 then return 0 end
	return r
end

local function positive(cfg, key, default)
	local n = num(cfg, key, default)
	if n <= 0 then return default end
	return n
end

function C.new()
	return { good = 0, bad = 0 }
end

-- Raw counts, before CaptureMaxCounted. Only alive and conscious players
-- inside the circle are counted. The owner side defends; the other side attacks.
function C.Counts(players, flag, owner, radius)
	local attackers, defenders = 0, 0
	local side = C.Side(owner)
	local enemy = other(side)
	if not side or type(players) ~= "table" then return 0, 0 end
	for i = 1, #players do
		local ply = players[i]
		if type(ply) == "table" and ply.alive == true and ply.conscious == true then
			if inside(ply.pos, flag, radius) then
				local who = C.Side(ply.team)
				if who == side then
					defenders = defenders + 1
				elseif who == enemy then
					attackers = attackers + 1
				end
			end
		end
	end
	return attackers, defenders
end

local function counted(attackers, cfg)
	local n = math.floor(tonumber(attackers) or 0)
	if n < 0 then n = 0 end
	local cap = math.floor(num(cfg, "CaptureMaxCounted", 2))
	if cap < 1 then cap = 1 end
	if n > cap then n = cap end
	return n
end

-- Seconds of progress per second. Negative means decay. Zero means hold.
local function rateOf(attackers, defenders, cfg)
	if defenders > 0 and cfg.CaptureContestedFreeze ~= false then return 0 end
	local n = counted(attackers, cfg)
	local one = positive(cfg, "CaptureTimeOne", 20)
	local two = positive(cfg, "CaptureTimeTwo", 10)
	if n <= 0 then
		if cfg.CaptureDecay == false then return 0 end
		local decay = num(cfg, "CaptureDecayRate", 1)
		if decay < 0 then decay = 0 end
		return -decay / one
	end
	if n == 1 then return 1 / one end
	return 1 / two
end

local function clamp01(p)
	p = tonumber(p) or 0
	if not finite(p) or p <= 0 then return 0 end
	if p >= 1 then return 1 end
	return p
end

local function step(progress, attackers, defenders, cfg, dt)
	progress = clamp01(progress)
	local rate = rateOf(attackers, defenders, cfg)
	if rate == 0 or not finite(dt) or dt <= 0 then return progress, false end
	local nextp = progress + rate * dt
	if nextp >= 1 then nextp = 1 end
	if nextp < 1e-8 then nextp = 0 end
	return nextp, progress < 1 and nextp >= 1
end

-- Mutates state. Winner is the attacking side, or "draw" when both bars
-- fill on the same tick. reason is "capture" only when somebody won.
function C.Tick(state, world, dt)
	if type(state) ~= "table" then state = C.new() end
	world = type(world) == "table" and world or {}
	local cfg = cfgOf(world)
	local radius = radiusOf(cfg)
	local flags = type(world.flags) == "table" and world.flags or {}
	local players = world.players
	local goodAtk, goodDef = C.Counts(players, flags.good, "good", radius)
	local badAtk, badDef = C.Counts(players, flags.bad, "bad", radius)
	local good, goodWin = step(state.good, goodAtk, goodDef, cfg, dt)
	local bad, badWin = step(state.bad, badAtk, badDef, cfg, dt)
	state.good = good
	state.bad = bad
	local winner
	if goodWin and badWin then
		winner = "draw"
	elseif goodWin then
		winner = "bad"
	elseif badWin then
		winner = "good"
	end
	return {
		good = good,
		bad = bad,
		winner = winner,
		reason = winner and "capture" or nil,
	}
end

function C.Reset(state)
	if type(state) ~= "table" then return C.new() end
	state.good = 0
	state.bad = 0
	return state
end

local function flagText(side)
	local id = side == "bad" and BAD or GOOD
	local name = BALLISTICS.TeamName and BALLISTICS.TeamName[id]
	if type(name) ~= "string" or name == "" then
		name = side == "bad" and "Bad" or "Good"
	end
	return name .. " flag"
end

-- HUD rows. A side is omitted at 0, so the bar stays hidden until somebody
-- has stood in a circle. team is the flag owner's id, for that side's colour.
function C.Bars(good, bad)
	local list = {}
	local function add(side, value, team)
		value = tonumber(value) or 0
		if not finite(value) or value <= 0 then return end
		if value > 1 then value = 1 end
		list[#list + 1] = {
			side = side,
			team = team,
			progress = value,
			text = flagText(side),
		}
	end
	add("good", good, GOOD)
	add("bad", bad, BAD)
	return list
end

-- Screen geometry for the top-middle bars. The round HUD reads this so its
-- phase line can sit clear of the bars. cl_capture_bar paints these rects.
C.BAR_W = 300
C.BAR_H = 18
C.BAR_GAP = 6
C.BAR_TOP = 8

function C.BarRects(screenW, barCount)
	local count = math.floor(tonumber(barCount) or 0)
	if count < 0 then count = 0 end
	local sw = tonumber(screenW) or 0
	local x = math.floor((sw - C.BAR_W) / 2)
	if x < 0 then x = 0 end
	local y = C.BAR_TOP
	local rects = {}
	for i = 1, count do
		rects[i] = { x = x, y = y, w = C.BAR_W, h = C.BAR_H }
		y = y + C.BAR_H + C.BAR_GAP
	end
	return rects
end
