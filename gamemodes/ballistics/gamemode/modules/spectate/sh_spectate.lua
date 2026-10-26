-- Death spectate: helmet cam on a living teammate. Knocked out counts as
-- alive. No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spectate = BALLISTICS.Spectate or {}
local S = BALLISTICS.Spectate

-- Phases where a dead player follows a teammate (lobby keeps free cam).
function S.PhaseFollows(phase)
	return phase == "buy" or phase == "live" or phase == "post" or phase == "squad"
end

-- mates: ordered list of living teammates. dir 1 = next, -1 = previous.
-- Keeps current when it is still in the list and dir is 0.
function S.Pick(mates, current, dir)
	local n = #(mates or {})
	if n == 0 then return nil end
	local at = 0
	for i = 1, n do
		if mates[i] == current then at = i break end
	end
	dir = tonumber(dir) or 0
	if at == 0 then return mates[dir < 0 and n or 1] end
	if dir == 0 then return mates[at] end
	return mates[((at - 1 + (dir < 0 and -1 or 1)) % n) + 1]
end

-- Helmet cam: up and to the right of the head, a touch forward.
S.CAM_UP = 7
S.CAM_RIGHT = 5
S.CAM_FORWARD = 3
S.FOV_ADD = 12
S.SMOOTH = 12 -- higher = snappier

-- Exponential smoothing factor for this frame.
function S.Blend(dt)
	dt = tonumber(dt) or 0
	if dt <= 0 then return 0 end
	local k = 1 - math.exp(-S.SMOOTH * dt)
	if k > 1 then k = 1 end
	return k
end

function S.Label(name)
	if type(name) ~= "string" or name == "" then return nil end
	return "Spectating: " .. name
end
