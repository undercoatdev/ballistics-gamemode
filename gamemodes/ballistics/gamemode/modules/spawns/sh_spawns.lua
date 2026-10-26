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

local LIMIT = 200000

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function wrapYaw(y)
	y = y % 360
	if y < 0 then y = y + 360 end
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

function D.decode(tbl)
	if type(tbl) ~= "table" then return nil, "json" end
	local state = { good = nil, bad = nil, source = "file", map = "", dirty = false }
	local any = false
	for _, side in ipairs({ "good", "bad" }) do
		if tbl[side] ~= nil then
			local flag, err = normalizeFlag(tbl[side])
			if not flag then return nil, err end
			state[side] = flag
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

function D.reasonText(err)
	if err == "team" then return "Pick Good or Bad." end
	if err == "pos" or err == "flag" then return "That point is not on the map." end
	if err == "ang" then return "That angle is not valid." end
	if err == "close" then return "Flags must be at least 64 units apart." end
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
	if D.hasBoth(state) then
		if state and state.dirty then
			return "Both flags are placed. Save to keep them on this map."
		end
		return "Both flags are placed."
	end
	return "Both flags must be placed before the round can start."
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

function D.toJSON(state)
	if type(state) ~= "table" or (not state.good and not state.bad) then
		return nil, "empty"
	end
	return '{"good":' .. flagJSON(state.good) .. ',"bad":' .. flagJSON(state.bad) .. '}'
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
	return { good = nil, bad = nil, source = "none", map = map, dirty = false }
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
		return { x = 0, y = 0, z = 4096, yaw = 0, halfH = 2048, halfW = 2048 * aspect, ortho = true }
	end
	if maxx < minx then minx, maxx = maxx, minx end
	if maxy < miny then miny, maxy = maxy, miny end
	if maxz < minz then minz, maxz = maxz, minz end
	local spanX = maxx - minx
	local spanY = maxy - miny
	if spanX < 64 or spanY < 64 then
		return { x = 0, y = 0, z = 4096, yaw = 0, halfH = 2048, halfW = 2048 * aspect, ortho = true }
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
		ortho = true,
		groundZ = minz,
	}
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
