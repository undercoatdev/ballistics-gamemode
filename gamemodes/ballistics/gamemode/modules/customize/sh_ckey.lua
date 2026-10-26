-- Pure C-key decisions. No game API.
-- TacRP treats customize as a level on the usercmd, so a tap that rises and
-- falls between two commands is lost. Callers feed a rising edge only.
-- Press then applies a short debounce. Permission is separate from the edge.

BALLISTICS = BALLISTICS or {}
BALLISTICS.CKey = BALLISTICS.CKey or {}

local C = BALLISTICS.CKey

C.DEBOUNCE = 0.25

local REASONS = {
	dead = "You are not alive.",
	weapon = "Hold a weapon to customize it.",
	zone = "Only at your objective",
	phase = "Only at your objective",
}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

function C.ReasonText(err)
	if type(err) ~= "string" then return nil end
	return REASONS[err]
end

-- pressed must be exactly true. A release or a held repeat is not an edge.
-- A second edge sooner than DEBOUNCE seconds is dropped. state.last is the
-- time of the last accepted edge.
function C.Press(state, now, pressed)
	if type(state) ~= "table" then state = {} end
	if pressed ~= true then return false, state end
	if not finite(now) then return false, state end
	local last = state.last
	if finite(last) and (now - last) < C.DEBOUNCE then
		return false, state
	end
	state.last = now
	return true, state
end

function C.NextOpen(open)
	return open ~= true
end

-- BUY swaps the wheel and the attachment menu. Closing attachments reopens
-- the wheel; opening attachments hides it. The wheel has no other close.
function C.BuySwap(attOpen)
	if attOpen == true then return true, false end
	return false, true
end

-- Opening needs a living player, an active TacRP weapon, and either BUY
-- (anywhere) or LIVE inside the own-flag radius. Closing is always allowed.
function C.Allow(ctx)
	if type(ctx) ~= "table" then return false, "phase" end
	if ctx.want ~= true then return true end
	if ctx.alive ~= true then return false, "dead" end
	if ctx.hasWeapon ~= true then return false, "weapon" end
	if ctx.phase == "buy" then return true end
	if ctx.phase == "live" then
		if ctx.inZone == true then return true end
		return false, "zone"
	end
	return false, "phase"
end

-- Steady-state: the menu cannot stay open. A phase change is separate
-- (PhaseCloses) so leaving BUY closes even if the player is standing on
-- their flag when LIVE starts.
function C.MustClose(ctx)
	if type(ctx) ~= "table" or ctx.open ~= true then return false end
	if ctx.alive ~= true then return true, "dead" end
	if ctx.weaponChanged == true then return true, "switch" end
	if ctx.hasWeapon ~= true then return true, "weapon" end
	if ctx.phase == "buy" then return false end
	if ctx.phase == "live" then
		if ctx.inZone == true then return false end
		return true, "zone"
	end
	return true, "phase"
end

function C.PhaseCloses(oldPhase, newPhase, open)
	if open ~= true then return false end
	if type(oldPhase) ~= "string" or type(newPhase) ~= "string" then return false end
	return oldPhase ~= newPhase
end

-- Coordinates accept a plain {x,y,z} or a Vector (fields or slots).
function C.Coords(v)
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

function C.DistSqr(a, b)
	local ax, ay, az = C.Coords(a)
	local bx, by, bz = C.Coords(b)
	if not ax or not bx then return nil end
	local dx = ax - bx
	local dy = ay - by
	local dz = az - bz
	return dx * dx + dy * dy + dz * dz
end

-- Boundary counts as inside. Distance is 3D: height counts.
function C.InRadius(pos, flagPos, radius)
	local r = tonumber(radius)
	if not finite(r) or r < 0 then return false end
	local dist = C.DistSqr(pos, flagPos)
	if dist == nil then return false end
	return dist <= r * r
end

function C.FlagPos(snapshot, teamId)
	if type(snapshot) ~= "table" then return nil end
	local side
	if teamId == 1 or teamId == "good" or teamId == "Good" then
		side = "good"
	elseif teamId == 2 or teamId == "bad" or teamId == "Bad" then
		side = "bad"
	end
	if side == nil then return nil end
	local flag = snapshot[side]
	if type(flag) ~= "table" then return nil end
	local pos = flag.pos or flag
	if C.Coords(pos) == nil then return nil end
	return pos
end
