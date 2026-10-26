-- Firing squad finale: lineup on the box, kits, freeze label, admin rows.
-- No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Squad = BALLISTICS.Squad or {}

local S = BALLISTICS.Squad

S.INSET = 48
S.KNIFE = "tacrp_knife"
S.DEFAULT_WEAPON = "tacrp_ex_ak47"

local ROWS = {
	{
		path = "FiringSquadEnabled",
		label = "Enabled",
		kind = "bool",
		blurb = "When a team reaches Rounds to win, line both teams up before the lobby. Off, or a draw, goes straight to the lobby. Rounds to win 0 never ends the match.",
	},
	{
		path = "FiringSquadDuration",
		label = "Duration (seconds)",
		kind = "number",
		min = 5,
		max = 300,
		decimals = 0,
		blurb = "How long the firing squad lasts before everyone returns to the lobby.",
	},
	{
		path = "FiringSquadFreeze",
		label = "Freeze time (seconds)",
		kind = "int",
		min = 0,
		max = 120,
		decimals = 0,
		blurb = "Losers stay frozen but can still be shot. 0 lets them move immediately.",
	},
	{
		path = "FiringSquadWeapon",
		label = "Winner weapon",
		kind = "string",
		blurb = "Weapon class given to the winners. Everything else is stripped.",
	},
	{
		path = "FiringSquadMags",
		label = "Magazines",
		kind = "int",
		min = 0,
		max = 30,
		decimals = 0,
		blurb = "Full magazines of that weapon's own clip, given as reserve ammo.",
	},
	{
		path = "FiringSquadLoserKnife",
		label = "Loser knife",
		kind = "bool",
		blurb = "Give the losers a knife. Off leaves them unarmed.",
	},
}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function wrapYaw(y)
	y = y % 360
	if y < 0 then y = y + 360 end
	-- A tiny negative angle modulo 360 lands on 360, which is the same as 0.
	if y >= 360 then y = 0 end
	return y
end

local function whole(n, fallback)
	n = tonumber(n)
	if not n or n ~= n then return fallback end
	return math.floor(n)
end

function S.ValidClass(class)
	if type(class) ~= "string" or class == "" or #class > 64 then return false end
	return string.match(class, "^[%w_]+$") ~= nil
end

function S.Settings(cfg)
	cfg = type(cfg) == "table" and cfg or {}
	local duration = tonumber(cfg.FiringSquadDuration)
	if not duration or duration ~= duration then duration = 30 end
	if duration < 5 then duration = 5 end
	if duration > 300 then duration = 300 end
	local freeze = whole(cfg.FiringSquadFreeze, 10)
	if freeze < 0 then freeze = 0 end
	if freeze > 120 then freeze = 120 end
	local weapon = cfg.FiringSquadWeapon
	if not S.ValidClass(weapon) then weapon = S.DEFAULT_WEAPON end
	local mags = whole(cfg.FiringSquadMags, 4)
	if mags < 0 then mags = 0 end
	if mags > 30 then mags = 30 end
	return {
		enabled = cfg.FiringSquadEnabled == true,
		duration = duration,
		freeze = freeze,
		weapon = weapon,
		mags = mags,
		loserKnife = cfg.FiringSquadLoserKnife == true,
	}
end

function S.Role(team, winner)
	if winner ~= "good" and winner ~= "bad" then return nil end
	local side = nil
	if team == "good" or team == 1 then side = "good" end
	if team == "bad" or team == 2 then side = "bad" end
	if not side then return nil end
	if side == winner then return "winner" end
	return "loser"
end

function S.Kit(role, cfg)
	local settings = S.Settings(cfg)
	if role == "winner" then
		return { weapon = settings.weapon, mags = settings.mags, knife = false, freeze = 0 }
	end
	if role == "loser" then
		return { weapon = nil, mags = 0, knife = settings.loserKnife, freeze = settings.freeze }
	end
	return nil
end

-- Clip size and reserve for the winner's weapon. Reuses the buy ammo helpers.
function S.Reserve(wep, mags)
	local ammo, clip = nil, nil
	if BALLISTICS.Buy and type(BALLISTICS.Buy.WeaponAmmo) == "function" then
		ammo, clip = BALLISTICS.Buy.WeaponAmmo(wep)
	end
	local rounds = 0
	if BALLISTICS.Buy and type(BALLISTICS.Buy.AmmoRounds) == "function" then
		rounds = BALLISTICS.Buy.AmmoRounds(clip, mags) or 0
	end
	return ammo, clip, rounds
end

function S.FreezeLabel(remaining)
	local n = tonumber(remaining)
	if not n or n ~= n or n <= 0 then return nil end
	local s = math.ceil(n - 1e-9)
	if s < 1 then return nil end
	return "FROZEN " .. tostring(s)
end

-- Two lines on the long sides, inset from the edge, facing each other.
-- goodSlots and badSlots are occupied slot numbers. Index is sorted slot order.
function S.Line(box, goodSlots, badSlots)
	if type(box) ~= "table" or type(box.pos) ~= "table" then return nil end
	local sx = tonumber(box.sx)
	local sy = tonumber(box.sy)
	local yaw = tonumber(box.yaw) or 0
	if not finite(sx) or not finite(sy) or not finite(yaw) then return nil end
	if sx <= 0 or sy <= 0 then return nil end
	if not finite(box.pos.x) or not finite(box.pos.y) or not finite(box.pos.z) then return nil end

	local longAxis = "x"
	local longLen = sx
	local shortLen = sy
	if sy > sx then
		longAxis = "y"
		longLen = sy
		shortLen = sx
	end

	local inset = S.INSET
	local across = shortLen * 0.5 - inset
	if across < 24 then across = math.max(8, shortLen * 0.25) end
	local inner = longLen - 2 * inset
	if inner < 0 then inner = 0 end

	local height = 128
	if BALLISTICS.SpawnData and type(BALLISTICS.SpawnData.BOX_HEIGHT) == "number" then
		height = BALLISTICS.SpawnData.BOX_HEIGHT
	end
	local feetZ = box.pos.z - height * 0.5
	local rad = math.rad(yaw)
	local c = math.cos(rad)
	local s = math.sin(rad)

	local function world(lx, ly)
		return {
			x = box.pos.x + lx * c - ly * s,
			y = box.pos.y + lx * s + ly * c,
			z = feetZ,
		}
	end

	local function face(lx, ly, tx, ty)
		local dx = tx - lx
		local dy = ty - ly
		local wx = dx * c - dy * s
		local wy = dx * s + dy * c
		return wrapYaw(math.deg(math.atan2(wy, wx)))
	end

	local function idsOf(slots)
		local ids = {}
		if type(slots) ~= "table" then return ids end
		for i = 1, #slots do
			local n = tonumber(slots[i])
			if n then ids[#ids + 1] = math.floor(n) end
		end
		table.sort(ids)
		return ids
	end

	local function sideList(slots, sign)
		local ids = idsOf(slots)
		local count = #ids
		local list = {}
		for i = 1, count do
			local along = 0
			if count > 1 then
				local step = inner / count
				along = -inner * 0.5 + step * (i - 0.5)
			end
			local lx, ly
			if longAxis == "x" then
				lx = along
				ly = sign * across
			else
				lx = sign * across
				ly = along
			end
			local tx, ty
			if longAxis == "x" then
				tx = along
				ty = -sign * across
			else
				tx = -sign * across
				ty = along
			end
			list[i] = {
				slot = ids[i],
				pos = world(lx, ly),
				yaw = face(lx, ly, tx, ty),
			}
		end
		return list
	end

	return {
		good = sideList(goodSlots, -1),
		bad = sideList(badSlots, 1),
	}
end

local function read(path)
	local cfg = BALLISTICS.Config
	if type(cfg) ~= "table" then return nil end
	if type(cfg.Get) == "function" then return cfg.Get(path) end
	return cfg[path]
end

function S.Rows(section)
	if section ~= nil and section ~= "firing_squad" then return {} end
	local rows = {}
	for i = 1, #ROWS do
		local spec = ROWS[i]
		local value = read(spec.path)
		rows[i] = {
			path = spec.path,
			label = spec.label,
			kind = spec.kind,
			value = value,
			display = value,
			min = spec.min,
			max = spec.max,
			decimals = spec.decimals,
			blurb = spec.blurb,
		}
	end
	return rows
end

function S.Same(a, b)
	local view = BALLISTICS.RulesView
	if view and type(view.Same) == "function" then return view.Same(a, b) end
	return a == b
end

function S.Commit(row, display)
	if type(row) ~= "table" or type(row.path) ~= "string" or row.path == "" then
		return nil, "field"
	end
	if row.kind == "string" then
		if type(display) ~= "string" then return nil, "invalid" end
		local class = string.match(display, "^%s*(.-)%s*$")
		if not S.ValidClass(class) then return nil, "invalid" end
		return { key = row.path, value = class }
	end
	local view = BALLISTICS.RulesView
	if view and type(view.Commit) == "function" then
		return view.Commit(row, display)
	end
	return nil, "view"
end

function S.PayloadFor(isAdmin, payload)
	local view = BALLISTICS.RulesView
	if view and type(view.PayloadFor) == "function" then
		return view.PayloadFor(isAdmin, payload)
	end
	return nil
end

BALLISTICS.SquadView = S

if BALLISTICS.AdminTabs and type(BALLISTICS.AdminTabs.Add) == "function" then
	BALLISTICS.AdminTabs.Add({
		id = "firing_squad",
		title = "Firing Squad",
		implemented = true,
		reset = { enabled = true, section = "firing_squad" },
	})
end
