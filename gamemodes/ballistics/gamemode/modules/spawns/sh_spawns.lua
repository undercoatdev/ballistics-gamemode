-- Pure spawn records: JSON, defaults fallback, ring offsets, overhead pan.
-- No GMod calls. sv_spawns.lua and cl_spawns_editor.lua are the glue.

BALLISTICS = BALLISTICS or {}
BALLISTICS.SpawnData = BALLISTICS.SpawnData or {}

local D = BALLISTICS.SpawnData

D.RING = 40
D.MIN_SEPARATION = 64
D.OP_PLACE = 1
D.OP_SAVE = 2
D.OP_RESET = 3
D.OP_BOX = 4

-- Oriented box. pos is the geometric centre. Height is fixed and not saved.
D.BOX_HEIGHT = 128
D.BOX_LENGTH = 768
D.BOX_WIDTH = 384
D.BOX_MIN = 128
D.BOX_MAX = 8192

-- Team markers at the capture centres. They are not solid and cannot be moved.
D.FLAG_MODEL_GOOD = "models/props_c17/cashregister01a.mdl"
D.FLAG_MODEL_BAD = "models/combine_helicopter/helicopter_bomb01.mdl"
-- Flag props are lifted this many units (1 ft) so they sit on the floor, not in it.
D.FLAG_LIFT = 12

function D.flagModel(team)
	if team == "bad" or team == 2 then return D.FLAG_MODEL_BAD end
	return D.FLAG_MODEL_GOOD
end

function D.flagProps()
	return {
		good = D.FLAG_MODEL_GOOD,
		bad = D.FLAG_MODEL_BAD,
		solid = "none",
		pickup = false,
		damage = false,
	}
end

-- Closest placed flag to a point, for an editor that can no longer trace the prop.
function D.nearestSide(state, pos, maxDist)
	if type(state) ~= "table" or type(pos) ~= "table" then return nil end
	local function ok(n)
		return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
	end
	if not ok(pos.x) or not ok(pos.y) or not ok(pos.z) then return nil end
	maxDist = tonumber(maxDist) or 96
	local best, bestD = nil, nil
	for _, side in ipairs({ "good", "bad" }) do
		local flag = state[side]
		if type(flag) == "table" and type(flag.pos) == "table" then
			local dx = (flag.pos.x or 0) - pos.x
			local dy = (flag.pos.y or 0) - pos.y
			local dz = (flag.pos.z or 0) - pos.z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d <= maxDist and (bestD == nil or d < bestD) then
				best, bestD = side, d
			end
		end
	end
	return best
end

local LIMIT = 200000

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function wrapYaw(y)
	y = y % 360
	if y < 0 then y = y + 360 end
	if y >= 360 then y = 0 end
	return y
end

function D.side(team)
	if team == 1 or team == "good" or team == "Good" then return "good" end
	if team == 2 or team == "bad" or team == "Bad" then return "bad" end
	return nil
end

function D.mapFile(map)
	if type(map) ~= "string" then return nil end
	if not map:match("^[%w_%-]+$") then return nil end
	if #map > 64 then return nil end
	return "ballistics/spawns/" .. map .. ".json"
end

local function cleanPos(p)
	if type(p) ~= "table" then return nil end
	local x = tonumber(p.x)
	local y = tonumber(p.y)
	local z = tonumber(p.z)
	if x == nil then x = tonumber(p[1]) end
	if y == nil then y = tonumber(p[2]) end
	if z == nil then z = tonumber(p[3]) end
	if not finite(x) or not finite(y) or not finite(z) then return nil end
	if math.abs(x) > LIMIT or math.abs(y) > LIMIT or math.abs(z) > LIMIT then return nil end
	return { x = x, y = y, z = z }
end

-- Flags stand upright. A missing angle is 0. A present but non-numeric angle is rejected.
local function cleanAng(a)
	if a == nil then return { p = 0, y = 0, r = 0 } end
	if type(a) ~= "table" then return nil end
	local y = tonumber(a.y)
	if y == nil then y = tonumber(a.yaw) end
	if y == nil then y = tonumber(a[2]) end
	if y == nil then y = 0 end
	if not finite(y) then return nil end
	local p = tonumber(a.p)
	if p == nil then p = tonumber(a[1]) end
	if p ~= nil and not finite(p) then return nil end
	local r = tonumber(a.r)
	if r == nil then r = tonumber(a[3]) end
	if r ~= nil and not finite(r) then return nil end
	return { p = 0, y = wrapYaw(y), r = 0 }
end

local function copyFlag(flag)
	if not flag then return nil end
	return {
		pos = { x = flag.pos.x, y = flag.pos.y, z = flag.pos.z },
		ang = { p = flag.ang.p, y = flag.ang.y, r = flag.ang.r },
	}
end

local function normalizeFlag(raw)
	if type(raw) ~= "table" then return nil, "flag" end
	local pos = cleanPos(raw.pos)
	if not pos then return nil, "pos" end
	local ang = cleanAng(raw.ang)
	if not ang then return nil, "ang" end
	return { pos = pos, ang = ang }
end

local function clampSize(n)
	n = math.abs(n)
	if n < D.BOX_MIN then n = D.BOX_MIN end
	if n > D.BOX_MAX then n = D.BOX_MAX end
	return n
end

-- A bad box is dropped. Callers keep the flags.
local function normalizeBox(raw)
	if type(raw) ~= "table" then return nil end
	local pos = cleanPos(raw.pos)
	if not pos then return nil end
	local yaw = tonumber(raw.yaw)
	if yaw == nil and type(raw.ang) == "table" then
		yaw = tonumber(raw.ang.y) or tonumber(raw.ang.yaw)
	end
	if yaw == nil then yaw = 0 end
	if not finite(yaw) then return nil end
	local sx = tonumber(raw.sx)
	local sy = tonumber(raw.sy)
	if not finite(sx) or not finite(sy) then return nil end
	return { pos = pos, yaw = wrapYaw(yaw), sx = clampSize(sx), sy = clampSize(sy) }
end

local function copyBox(box)
	if type(box) ~= "table" or type(box.pos) ~= "table" then return nil end
	return {
		pos = { x = box.pos.x, y = box.pos.y, z = box.pos.z },
		yaw = box.yaw or 0,
		sx = box.sx,
		sy = box.sy,
	}
end

function D.decode(tbl)
	if type(tbl) ~= "table" then return nil, "json" end
	local state = { good = nil, bad = nil, box = nil, source = "file", map = "", dirty = false }
	local any = false
	for _, side in ipairs({ "good", "bad" }) do
		if tbl[side] ~= nil then
			local flag, err = normalizeFlag(tbl[side])
			if not flag then return nil, err end
			state[side] = flag
			any = true
		end
	end
	-- A missing or invalid box does not throw away saved flags.
	if tbl.box ~= nil then
		local box = normalizeBox(tbl.box)
		if box then
			state.box = box
			any = true
		end
	end
	if not any then return nil, "empty" end
	return state
end

function D.copy(state)
	state = state or {}
	return {
		good = copyFlag(state.good),
		bad = copyFlag(state.bad),
		box = copyBox(state.box),
		source = state.source or "none",
		map = state.map or "",
		dirty = state.dirty == true,
	}
end

function D.hasBoth(state)
	if type(state) ~= "table" then return false end
	local function ok(flag)
		return type(flag) == "table" and type(flag.pos) == "table" and finite(flag.pos.x) and finite(flag.pos.y) and finite(flag.pos.z)
	end
	return ok(state.good) and ok(state.bad)
end

function D.hasBox(state)
	if type(state) ~= "table" or type(state.box) ~= "table" or type(state.box.pos) ~= "table" then
		return false
	end
	local box = state.box
	return finite(box.pos.x) and finite(box.pos.y) and finite(box.pos.z) and finite(box.sx) and finite(box.sy)
end

local function dist2d(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

function D.place(state, team, pos, ang)
	local side = D.side(team)
	if not side then return nil, "team" end
	local flag, err = normalizeFlag({ pos = pos, ang = ang })
	if not flag then return nil, err or "pos" end
	local otherName = side == "good" and "bad" or "good"
	local other = state and state[otherName]
	if other and other.pos and dist2d(other.pos, flag.pos) < D.MIN_SEPARATION then
		return nil, "close"
	end
	local out = D.copy(state)
	out[side] = flag
	out.dirty = true
	return out
end

function D.placeBox(state, pos, yaw, sx, sy)
	if type(yaw) == "table" then
		yaw = tonumber(yaw.y) or tonumber(yaw.yaw)
	end
	local box = normalizeBox({ pos = pos, yaw = yaw, sx = sx, sy = sy })
	if not box then return nil, "box" end
	local out = D.copy(state)
	out.box = box
	out.dirty = true
	return out
end

function D.reasonText(err)
	if err == "team" then return "Pick Good or Bad." end
	if err == "pos" or err == "flag" then return "That point is not on the map." end
	if err == "ang" then return "That angle is not valid." end
	if err == "close" then return "Flags must be at least 64 units apart." end
	if err == "box" then return "That firing squad box is not valid." end
	if err == "empty" then return "Place a flag first." end
	if err == "admin" then return "Only an admin can edit spawns." end
	return "Could not update spawns."
end

function D.statusText(state)
	if type(state) ~= "table" then return "No flags" end
	local base = "No flags"
	if state.source == "file" then
		base = "Saved for this map"
	elseif state.source == "defaults" then
		base = "Built-in defaults"
	end
	if state.dirty then return base .. " (unsaved)" end
	return base
end

function D.readiness(state)
	if not D.hasBoth(state) then
		return "Both flags must be placed before the round can start."
	end
	if not D.hasBox(state) then
		return "Both flags are placed. Place the firing squad box in Admin > Spawns."
	end
	if state and state.dirty then
		return "Both flags are placed. Save to keep them on this map."
	end
	return "Both flags are placed."
end

-- JSON subset: objects, arrays, numbers, strings, true/false/null. No comments.
local NULL = {}

local function parseJSON(s)
	local i = 1
	local n = #s
	local function ws()
		while i <= n do
			local c = s:byte(i)
			if c ~= 32 and c ~= 9 and c ~= 10 and c ~= 13 then break end
			i = i + 1
		end
	end
	local parseValue
	local function fail(err)
		return nil, err
	end
	local function parseString()
		i = i + 1
		local out = {}
		while i <= n do
			local c = s:byte(i)
			if c == 34 then
				i = i + 1
				return table.concat(out)
			elseif c == 92 then
				i = i + 1
				if i > n then return fail("string") end
				local e = s:byte(i)
				if e == 34 or e == 92 or e == 47 then
					out[#out + 1] = string.char(e)
				elseif e == 110 then
					out[#out + 1] = "\n"
				elseif e == 114 then
					out[#out + 1] = "\r"
				elseif e == 116 then
					out[#out + 1] = "\t"
				elseif e == 98 then
					out[#out + 1] = "\b"
				elseif e == 102 then
					out[#out + 1] = "\f"
				elseif e == 117 then
					local hex = s:sub(i + 1, i + 4)
					if #hex < 4 or not hex:match("^%x%x%x%x$") then return fail("string") end
					local code = tonumber(hex, 16)
					if code < 128 then
						out[#out + 1] = string.char(code)
					elseif code < 2048 then
						out[#out + 1] = string.char(192 + math.floor(code / 64), 128 + (code % 64))
					else
						out[#out + 1] = string.char(
							224 + math.floor(code / 4096),
							128 + (math.floor(code / 64) % 64),
							128 + (code % 64)
						)
					end
					i = i + 4
				else
					return fail("string")
				end
				i = i + 1
			elseif c < 32 then
				return fail("string")
			else
				out[#out + 1] = string.char(c)
				i = i + 1
			end
		end
		return fail("string")
	end
	local function parseNumber()
		local start = i
		if s:byte(i) == 45 then i = i + 1 end
		if i > n or s:byte(i) < 48 or s:byte(i) > 57 then return fail("number") end
		if s:byte(i) == 48 then
			i = i + 1
		else
			while i <= n and s:byte(i) >= 48 and s:byte(i) <= 57 do i = i + 1 end
		end
		if i <= n and s:byte(i) == 46 then
			i = i + 1
			if i > n or s:byte(i) < 48 or s:byte(i) > 57 then return fail("number") end
			while i <= n and s:byte(i) >= 48 and s:byte(i) <= 57 do i = i + 1 end
		end
		if i <= n and (s:byte(i) == 101 or s:byte(i) == 69) then
			i = i + 1
			if i <= n and (s:byte(i) == 43 or s:byte(i) == 45) then i = i + 1 end
			if i > n or s:byte(i) < 48 or s:byte(i) > 57 then return fail("number") end
			while i <= n and s:byte(i) >= 48 and s:byte(i) <= 57 do i = i + 1 end
		end
		local num = tonumber(s:sub(start, i - 1))
		if not finite(num) then return fail("number") end
		return num
	end
	local function parseObject()
		i = i + 1
		local obj = {}
		ws()
		if i <= n and s:byte(i) == 125 then
			i = i + 1
			return obj
		end
		while true do
			ws()
			if i > n or s:byte(i) ~= 34 then return fail("key") end
			local key, err = parseString()
			if err then return nil, err end
			ws()
			if i > n or s:byte(i) ~= 58 then return fail("colon") end
			i = i + 1
			local val, verr = parseValue()
			if verr then return nil, verr end
			if val ~= NULL then obj[key] = val end
			ws()
			if i > n then return fail("object") end
			local c = s:byte(i)
			if c == 44 then
				i = i + 1
			elseif c == 125 then
				i = i + 1
				return obj
			else
				return fail("object")
			end
		end
	end
	local function parseArray()
		i = i + 1
		local arr = {}
		ws()
		if i <= n and s:byte(i) == 93 then
			i = i + 1
			return arr
		end
		while true do
			local val, err = parseValue()
			if err then return nil, err end
			arr[#arr + 1] = val ~= NULL and val or nil
			ws()
			if i > n then return fail("array") end
			local c = s:byte(i)
			if c == 44 then
				i = i + 1
			elseif c == 93 then
				i = i + 1
				return arr
			else
				return fail("array")
			end
		end
	end
	parseValue = function()
		ws()
		if i > n then return fail("value") end
		local c = s:byte(i)
		if c == 123 then
			return parseObject()
		elseif c == 91 then
			return parseArray()
		elseif c == 34 then
			return parseString()
		elseif c == 116 and s:sub(i, i + 3) == "true" then
			i = i + 4
			return true
		elseif c == 102 and s:sub(i, i + 4) == "false" then
			i = i + 5
			return false
		elseif c == 110 and s:sub(i, i + 3) == "null" then
			i = i + 4
			return NULL
		else
			return parseNumber()
		end
	end
	local value, err = parseValue()
	if err then return nil, err end
	ws()
	if i <= n then return nil, "trailing" end
	return value
end

function D.fromJSON(s)
	if type(s) ~= "string" then return nil, "json" end
	local value, err = parseJSON(s)
	if err then return nil, err end
	return D.decode(value)
end

local function num(n)
	if not finite(n) then return "0.000000" end
	return string.format("%.6f", n)
end

local function flagJSON(flag)
	if not flag then return "null" end
	return string.format(
		'{"pos":{"x":%s,"y":%s,"z":%s},"ang":{"p":%s,"y":%s,"r":%s}}',
		num(flag.pos.x), num(flag.pos.y), num(flag.pos.z),
		num(flag.ang.p), num(flag.ang.y), num(flag.ang.r)
	)
end

local function boxJSON(box)
	if not box or not box.pos then return "null" end
	return string.format(
		'{"pos":{"x":%s,"y":%s,"z":%s},"yaw":%s,"sx":%s,"sy":%s}',
		num(box.pos.x), num(box.pos.y), num(box.pos.z),
		num(box.yaw), num(box.sx), num(box.sy)
	)
end

function D.toJSON(state)
	local hasBox = type(state) == "table" and type(state.box) == "table" and type(state.box.pos) == "table"
	if type(state) ~= "table" or (not state.good and not state.bad and not hasBox) then
		return nil, "empty"
	end
	return '{"good":' .. flagJSON(state.good) .. ',"bad":' .. flagJSON(state.bad) .. ',"box":' .. boxJSON(state.box) .. '}'
end

-- saved: JSON string, table, or nil. A bad file falls through to defaults, then none.
function D.resolve(saved, defaults, map)
	map = map or ""
	local parsed
	if type(saved) == "string" and saved ~= "" then
		parsed = D.fromJSON(saved)
	elseif type(saved) == "table" then
		parsed = D.decode(saved)
	end
	if parsed then
		parsed.source = "file"
		parsed.map = map
		parsed.dirty = false
		return parsed
	end
	local def = type(defaults) == "table" and defaults[map] or nil
	if type(def) == "table" then
		local state = D.decode(def)
		if state then
			state.source = "defaults"
			state.map = map
			state.dirty = false
			return state
		end
	end
	return { good = nil, bad = nil, box = nil, source = "none", map = map, dirty = false }
end

-- Eight corners, bottom ring then top ring. Local +X/+Y follow the box yaw.
D.BOX_EDGES = {
	{ 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
	{ 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
	{ 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

function D.boxCorners(box)
	if type(box) ~= "table" or type(box.pos) ~= "table" then return nil end
	local sx = tonumber(box.sx)
	local sy = tonumber(box.sy)
	local yaw = tonumber(box.yaw) or 0
	if not finite(sx) or not finite(sy) or not finite(yaw) then return nil end
	if not finite(box.pos.x) or not finite(box.pos.y) or not finite(box.pos.z) then return nil end
	local hx = sx * 0.5
	local hy = sy * 0.5
	local hz = D.BOX_HEIGHT * 0.5
	local rad = math.rad(yaw)
	local c = math.cos(rad)
	local s = math.sin(rad)
	local function world(lx, ly, lz)
		return {
			x = box.pos.x + lx * c - ly * s,
			y = box.pos.y + lx * s + ly * c,
			z = box.pos.z + lz,
		}
	end
	local signs = {
		{ -1, -1, -1 }, { 1, -1, -1 }, { 1, 1, -1 }, { -1, 1, -1 },
		{ -1, -1, 1 }, { 1, -1, 1 }, { 1, 1, 1 }, { -1, 1, 1 },
	}
	local corners = {}
	for i = 1, #signs do
		local sg = signs[i]
		corners[i] = world(sg[1] * hx, sg[2] * hy, sg[3] * hz)
	end
	return corners
end

function D.screenAxes(yaw)
	local rad = math.rad(yaw or 0)
	local cy = math.cos(rad)
	local sy = math.sin(rad)
	-- Pitch 90, roll 0: screen up and screen right on the ground plane.
	return { x = cy, y = sy }, { x = sy, y = -cy }
end

function D.pan(yaw, keys, speed)
	keys = keys or {}
	speed = tonumber(speed) or 0
	local up, right = D.screenAxes(yaw)
	local x, y = 0, 0
	if keys.w then x = x + up.x y = y + up.y end
	if keys.s then x = x - up.x y = y - up.y end
	if keys.d then x = x + right.x y = y + right.y end
	if keys.a then x = x - right.x y = y - right.y end
	local len = math.sqrt(x * x + y * y)
	if len > 0 and speed ~= 0 then
		x = x / len * speed
		y = y / len * speed
	else
		x, y = 0, 0
	end
	return x, y
end

-- Ortho window centered on the camera. (0,0) is the top-left of the screen.
function D.groundPoint(mx, my, sw, sh, cam)
	if type(cam) ~= "table" then return nil end
	sw = tonumber(sw) or 0
	sh = tonumber(sh) or 0
	if sw <= 0 or sh <= 0 then return nil end
	local halfW = cam.halfW or 1
	local halfH = cam.halfH or 1
	local left = cam.left or -halfW
	local right = cam.right or halfW
	local top = cam.top or -halfH
	local bottom = cam.bottom or halfH
	local u = (tonumber(mx) or 0) / sw
	local v = (tonumber(my) or 0) / sh
	local rightAmount = left + (right - left) * u
	local vertAmount = top + (bottom - top) * v
	local up, rightv = D.screenAxes(cam.yaw or 0)
	return {
		x = (cam.x or 0) + rightv.x * rightAmount + up.x * (-vertAmount),
		y = (cam.y or 0) + rightv.y * rightAmount + up.y * (-vertAmount),
	}
end

-- Screen ray for the overhead camera. fov is horizontal, matching util.AimVector
-- and CalcView. (0,0) is the top-left. Pitch 90 aims the centre straight down.
function D.AimDir(angles, fov, mx, my, sw, sh)
	local at = type(angles)
	if at ~= "table" and at ~= "Angle" and at ~= "userdata" then return nil end
	sw, sh = tonumber(sw), tonumber(sh)
	if not sw or not sh or sw <= 0 or sh <= 0 then return nil end
	mx, my = tonumber(mx) or 0, tonumber(my) or 0
	local function comp(v)
		v = tonumber(v)
		if not finite(v) then return 0 end
		return v
	end
	local pitch = comp(angles.p ~= nil and angles.p or angles[1])
	local yaw = comp(angles.y ~= nil and angles.y or angles[2])
	local roll = comp(angles.r ~= nil and angles.r or angles[3])
	fov = tonumber(fov)
	if not finite(fov) then fov = 90 end
	local sp, cp = math.sin(math.rad(pitch)), math.cos(math.rad(pitch))
	local syaw, cyaw = math.sin(math.rad(yaw)), math.cos(math.rad(yaw))
	local sr, cr = math.sin(math.rad(roll)), math.cos(math.rad(roll))
	local fx, fy, fz = cp * cyaw, cp * syaw, -sp
	local rx = -sr * sp * cyaw + cr * syaw
	local ry = -sr * sp * syaw - cr * cyaw
	local rz = -sr * cp
	local ux = cr * sp * cyaw + sr * syaw
	local uy = cr * sp * syaw - sr * cyaw
	local uz = cr * cp
	local tanHalf = math.tan(math.rad(fov) * 0.5)
	if not finite(tanHalf) then return nil end
	local aspect = sw / sh
	local nx = (mx / sw) * 2 - 1
	local ny = 1 - (my / sh) * 2
	local sx = nx * tanHalf
	local sy = ny * tanHalf / aspect
	local x = fx + rx * sx + ux * sy
	local y = fy + ry * sx + uy * sy
	local z = fz + rz * sx + uz * sy
	local len2 = x * x + y * y + z * z
	if len2 < 1e-12 then return nil end
	local inv = 1 / math.sqrt(len2)
	return Vector(x * inv, y * inv, z * inv)
end

function D.covers(cam, x, y)
	if type(cam) ~= "table" then return false end
	local up, right = D.screenAxes(cam.yaw or 0)
	local dx = x - (cam.x or 0)
	local dy = y - (cam.y or 0)
	local a = right.x
	local b = -up.x
	local c = right.y
	local d = -up.y
	local det = a * d - b * c
	if math.abs(det) < 1e-8 then return false end
	local rightAmount = (dx * d - b * dy) / det
	local vertAmount = (a * dy - dx * c) / det
	local halfW = cam.halfW or 0
	local halfH = cam.halfH or 0
	return math.abs(rightAmount) <= halfW + 1e-4 and math.abs(vertAmount) <= halfH + 1e-4
end

function D.fitDistance(halfH, fov)
	halfH = tonumber(halfH) or 0
	local tanHalf = math.tan(math.rad((tonumber(fov) or 90) * 0.5))
	if tanHalf < 0.05 then tanHalf = 1 end
	return halfH / tanHalf
end

function D.zoom(halfH, direction, aspect)
	aspect = tonumber(aspect) or (16 / 9)
	if aspect < 0.2 then aspect = 0.2 end
	if aspect > 5 then aspect = 5 end
	local factor = (tonumber(direction) or 0) > 0 and 0.85 or 1.18
	halfH = (tonumber(halfH) or 1024) * factor
	if halfH < 64 then halfH = 64 end
	if halfH > 100000 then halfH = 100000 end
	return halfH, halfH * aspect
end

-- Frame the whole XY bounds. At yaw 0, screen-up is +X and screen-right is -Y.
function D.overview(mins, maxs, fov, aspect)
	aspect = tonumber(aspect) or (16 / 9)
	if aspect < 0.2 then aspect = 0.2 end
	fov = tonumber(fov) or 90
	local function comp(v, key)
		if type(v) ~= "table" then return nil end
		return tonumber(v[key])
	end
	local minx, miny, minz = comp(mins, "x"), comp(mins, "y"), comp(mins, "z")
	local maxx, maxy, maxz = comp(maxs, "x"), comp(maxs, "y"), comp(maxs, "z")
	if not (minx and miny and minz and maxx and maxy and maxz) then
		return { x = 0, y = 0, z = 4096, yaw = 0, halfH = 2048, halfW = 2048 * aspect, ortho = false }
	end
	if maxx < minx then minx, maxx = maxx, minx end
	if maxy < miny then miny, maxy = maxy, miny end
	if maxz < minz then minz, maxz = maxz, minz end
	local spanX = maxx - minx
	local spanY = maxy - miny
	if spanX < 64 or spanY < 64 then
		return { x = 0, y = 0, z = 4096, yaw = 0, halfH = 2048, halfW = 2048 * aspect, ortho = false }
	end
	local needH = spanX * 0.5 * 1.08
	local needW = spanY * 0.5 * 1.08
	local halfH = math.max(needH, needW / aspect)
	local halfW = halfH * aspect
	local midZ = (minz + maxz) * 0.5
	local z = math.max(maxz + 128, midZ + D.fitDistance(halfH, fov))
	return {
		x = (minx + maxx) * 0.5,
		y = (miny + maxy) * 0.5,
		z = z,
		yaw = 0,
		halfH = halfH,
		halfW = halfW,
		ortho = false,
		groundZ = minz,
	}
end

-- Overhead slice. The top value means no cut. Callers fall back when this is nil.
local function compZ(v)
	if type(v) ~= "table" then return nil end
	local z = tonumber(v.z)
	if z == nil then z = tonumber(v[3]) end
	if not finite(z) then return nil end
	return z
end

function D.SliceBounds(mins, maxs)
	local a, b = compZ(mins), compZ(maxs)
	if not a or not b then return nil end
	if b < a then a, b = b, a end
	return a, b
end

function D.ClampSlice(slice, bottom, top)
	local lo, hi = tonumber(bottom), tonumber(top)
	if not finite(lo) or not finite(hi) then return nil end
	if hi < lo then lo, hi = hi, lo end
	slice = tonumber(slice)
	if not finite(slice) then return hi end
	if slice < lo then return lo end
	if slice > hi then return hi end
	return slice
end

-- Trace start at min(current z, slice) so a roof above the cut is not hit.
function D.SliceStart(z, slice)
	z = tonumber(z)
	if not finite(z) then return nil end
	slice = tonumber(slice)
	if not finite(slice) then return z end
	if slice < z then return slice end
	return z
end

-- 8-unit steps. Missing or flat world bounds fall back to a full map around ground.
D.SLICE_STEP = 8
D.SLICE_FALLBACK = 16384

local function snapStepDown(v)
	return math.floor(v / D.SLICE_STEP + 1e-9) * D.SLICE_STEP
end

local function snapStepUp(v)
	return math.ceil(v / D.SLICE_STEP - 1e-9) * D.SLICE_STEP
end

-- Absolute window. World Z is shifted by ground and snapped out to the step
-- so tunnels under the floor stay on the slider. The top value is "no cut".
function D.SliceRange(ground, worldBottom, worldTop)
	ground = tonumber(ground)
	if not finite(ground) then ground = 0 end
	local function fallback()
		return ground - D.SLICE_FALLBACK, ground + D.SLICE_FALLBACK
	end
	local lo, hi = tonumber(worldBottom), tonumber(worldTop)
	if not finite(lo) or not finite(hi) then return fallback() end
	if hi < lo then lo, hi = hi, lo end
	if hi - lo < 1 then return fallback() end
	local relLo = snapStepDown(lo - ground)
	local relHi = snapStepUp(hi - ground)
	if relLo > 0 then relLo = 0 end
	if relHi < 0 then relHi = 0 end
	if relHi <= relLo then return fallback() end
	return ground + relLo, ground + relHi
end

function D.SliceSnap(v, lo, hi)
	v = tonumber(v)
	lo, hi = tonumber(lo), tonumber(hi)
	if not finite(lo) or not finite(hi) then return nil end
	if hi < lo then lo, hi = hi, lo end
	if not finite(v) then return hi end
	v = lo + math.floor((v - lo) / D.SLICE_STEP + 0.5) * D.SLICE_STEP
	if v < lo then v = lo end
	if v > hi then v = hi end
	return v
end

function D.SliceLabel(v, ground)
	v, ground = tonumber(v), tonumber(ground) or 0
	if not finite(v) then return "No cut" end
	local d = math.floor(v - ground + 0.5)
	if d > 0 then return "+" .. d end
	return tostring(d)
end

local function clampCount(n, fallback)
	n = math.floor(tonumber(n) or fallback)
	if n < 1 then n = 1 end
	return n
end

function D.ringCandidates(slot, per, radius)
	per = clampCount(per, 5)
	if per > 16 then per = 16 end
	slot = math.floor(tonumber(slot) or 1)
	if slot < 1 then slot = 1 end
	slot = ((slot - 1) % per) + 1
	radius = tonumber(radius) or D.RING
	if radius < 8 then radius = 8 end
	local base = (slot - 1) * (2 * math.pi / per)
	local nudges = {
		{ a = 0, r = radius },
		{ a = 0, r = radius + 32 },
		{ a = 0, r = radius + 64 },
		{ a = 0.35, r = radius },
		{ a = -0.35, r = radius },
		{ a = 0.7, r = radius + 32 },
		{ a = -0.7, r = radius + 32 },
	}
	local list = {}
	for i = 1, #nudges do
		local theta = base + nudges[i].a
		local rad = nudges[i].r
		list[i] = {
			x = math.cos(theta) * rad,
			y = math.sin(theta) * rad,
			z = 0,
			yaw = wrapYaw(math.deg(theta)),
		}
	end
	return list
end

function D.chooseCandidate(slot, per, radius, blocked)
	local list = D.ringCandidates(slot, per, radius)
	for i = 1, #list do
		if not blocked or not blocked(list[i], i) then
			return list[i], i
		end
	end
	return list[#list], #list
end

function D.playerPoint(flag, slot, per, blocked)
	if type(flag) ~= "table" or type(flag.pos) ~= "table" then return nil end
	local c = D.chooseCandidate(slot, per, D.RING, blocked)
	return {
		x = flag.pos.x + c.x,
		y = flag.pos.y + c.y,
		z = flag.pos.z + (c.z or 0),
	}, { p = 0, y = c.yaw, r = 0 }
end

if SERVER and AddCSLuaFile then
	AddCSLuaFile(((GM and GM.FolderName) or "ballistics") .. "/gamemode/modules/spawns/defaults.lua")
end
if include then
	include(((GM and GM.FolderName) or "ballistics") .. "/gamemode/modules/spawns/defaults.lua")
end
