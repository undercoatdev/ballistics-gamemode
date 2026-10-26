-- Round and match end lines. No GMod calls.
-- The client keeps one line for a few seconds. A game win replaces the round line.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Banner = BALLISTICS.Banner or {}

local B = BALLISTICS.Banner

B.HOLD = 5

local current = nil

local function copyColor(col, fallback)
	fallback = fallback or { r = 230, g = 230, b = 230 }
	if type(col) ~= "table" then
		return { r = fallback.r, g = fallback.g, b = fallback.b, a = 255 }
	end
	return {
		r = col.r or fallback.r,
		g = col.g or fallback.g,
		b = col.b or fallback.b,
		a = col.a or 255,
	}
end

local function sideOf(winner)
	if winner == "good" or winner == 1 then return "good" end
	if winner == "bad" or winner == 2 then return "bad" end
	return nil
end

local function teamId(side)
	if side == "bad" then return TEAM_BAD or 2 end
	return TEAM_GOOD or 1
end

local function teamName(side)
	local id = teamId(side)
	local name = BALLISTICS.TeamName and BALLISTICS.TeamName[id]
	if type(name) ~= "string" or name == "" then
		name = side == "bad" and "Bad" or "Good"
	end
	return string.upper(name)
end

local function teamColor(side)
	local id = teamId(side)
	local col = BALLISTICS.TeamColor and BALLISTICS.TeamColor[id]
	if side == "bad" then return copyColor(col, { r = 220, g = 50, b = 50 }) end
	return copyColor(col, { r = 70, g = 140, b = 255 })
end

function B.Line(kind, winner)
	if kind == "round" then
		if winner == "draw" then
			return "DRAW", { r = 230, g = 230, b = 230, a = 255 }
		end
		local side = sideOf(winner)
		if not side then return nil end
		return teamName(side) .. " WINS THE ROUND", teamColor(side)
	end
	if kind == "game" then
		local side = sideOf(winner)
		if not side then return nil end
		return teamName(side) .. " WINS THE GAME", teamColor(side)
	end
	return nil
end

function B.Show(kind, winner, at)
	local text, col = B.Line(kind, winner)
	if not text then
		current = nil
		return nil
	end
	current = {
		text = text,
		color = col,
		kind = kind,
		untilAt = (tonumber(at) or 0) + (B.HOLD or 5),
	}
	return text
end

function B.Current(at)
	if not current then return nil end
	if (tonumber(at) or 0) >= current.untilAt then return nil end
	return current.text, current.color
end

function B.Clear()
	current = nil
end
