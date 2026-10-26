-- Shared config: defaults, Get/Set, clamp/validation. No GMod calls.
-- Live values sit in BALLISTICS.Config so PrintTable shows them. API is on a
-- metatable so pairs/Export/PrintTable never see Get/Set/ResetSection.

BALLISTICS = BALLISTICS or {}

local DEFAULTS = {
	SlotsPerTeam = 5,
	MinPerTeam = 1,
	BuyTime = 10,
	RoundTime = 600,
	PostRoundTime = 5,
	RoundsToWin = 0,
	TimeoutWinner = "draw",
	FreezeInBuy = true,
	HealthMode = "realistic",
	ModelGood = "models/player/combine_soldier.mdl",
	ModelBad = "models/player/combine_super_soldier.mdl",
	ObjectiveRadius = 2 / 0.01905, -- 2 m in Hammer units
	CustomizeRadius = 2 / 0.01905,
	CaptureTimeOne = 20,
	CaptureTimeTwo = 10,
	CaptureMaxCounted = 2,
	CaptureDecay = true,
	CaptureDecayRate = 1.0,
	CaptureContestedFreeze = true,
	TickRate = 0.1,
	BuyAmmoMags = 3,
	StartMoney = 800,
	MaxMoney = 0,
	Costs = {
		tacrp_ex_m1911 = 100,
		tacrp_mr96 = 500,
		tacrp_skorpion = 500,
		tacrp_mp5 = 600,
		tacrp_ex_ak47 = 900,
		tacrp_hk417 = 1000,
		tacrp_tgs12 = 900,
		tacrp_spr = 700,
		nade_frag = 500,
		nade_smoke = 200,
		nade_thermite = 700,
		nade_flashbang = 250,
		med_pills = 50,
		med_small = 80,
		med_trauma = 100,
		med_resus = 500,
	},
	AttCosts = {
		optic = 250,
		bolt = 100,
		muzzle = 100,
		trigger = 200,
		tactical = 300,
		ammo = 400,
		accessory = 200,
		perk = 700,
	},
	AttRefundOnDetach = false,
	Gains = {
		kill = 500,
		round_win = 1000,
		round_loss = 500,
	},
	BuyLimits = {
		weapon_per_round = 0,
		nade_each = 0,
	},
	AdminSuperOnly = false,
}

local INT = { kind = "int", min = 0, max = 1000000 }
local SCHEMA = {
	SlotsPerTeam = { kind = "int", min = 1, max = 16 },
	MinPerTeam = { kind = "int", min = 0, max = 16 },
	BuyTime = { kind = "number", min = 1, max = 3600 },
	RoundTime = { kind = "number", min = 1, max = 3600 },
	PostRoundTime = { kind = "number", min = 1, max = 3600 },
	RoundsToWin = { kind = "int", min = 0, max = 1000 },
	TimeoutWinner = { kind = "enum", values = { draw = true, good = true, bad = true } },
	FreezeInBuy = { kind = "bool" },
	HealthMode = { kind = "enum", values = { realistic = true, arcade = true } },
	ModelGood = { kind = "string" },
	ModelBad = { kind = "string" },
	ObjectiveRadius = { kind = "number", min = 16, max = 1000 },
	CustomizeRadius = { kind = "number", min = 16, max = 1000 },
	CaptureTimeOne = { kind = "number", min = 1, max = 3600 },
	CaptureTimeTwo = { kind = "number", min = 1, max = 3600 },
	CaptureMaxCounted = { kind = "int", min = 1, max = 16 },
	CaptureDecay = { kind = "bool" },
	CaptureDecayRate = { kind = "number", min = 0, max = 10 },
	CaptureContestedFreeze = { kind = "bool" },
	TickRate = { kind = "number", min = 0.01, max = 5 },
	BuyAmmoMags = { kind = "int", min = 0, max = 30 },
	StartMoney = { kind = "int", min = 0, max = 1000000 },
	MaxMoney = { kind = "int", min = 0, max = 1000000 },
	Costs = { kind = "map", value = INT },
	AttCosts = { kind = "map", value = INT },
	AttRefundOnDetach = { kind = "bool" },
	Gains = { kind = "map", value = INT },
	BuyLimits = { kind = "map", value = { kind = "int", min = 0, max = 100 } },
	AdminSuperOnly = { kind = "bool" },
}

local COST_GROUPS = {
	weapons = {
		"tacrp_ex_m1911", "tacrp_mr96", "tacrp_skorpion", "tacrp_mp5",
		"tacrp_ex_ak47", "tacrp_hk417", "tacrp_tgs12", "tacrp_spr",
	},
	throwables = { "nade_frag", "nade_smoke", "nade_thermite", "nade_flashbang" },
	meds = { "med_pills", "med_small", "med_trauma", "med_resus" },
}

local SECTIONS = {
	teams = { "SlotsPerTeam", "MinPerTeam" },
	general = {
		"BuyTime", "RoundTime", "PostRoundTime", "RoundsToWin", "TimeoutWinner",
		"FreezeInBuy", "HealthMode", "ModelGood", "ModelBad",
		"ObjectiveRadius", "CustomizeRadius",
		"CaptureTimeOne", "CaptureTimeTwo", "CaptureMaxCounted",
		"CaptureDecay", "CaptureDecayRate", "CaptureContestedFreeze",
		"TickRate", "BuyAmmoMags", "StartMoney", "MaxMoney", "AdminSuperOnly",
	},
	costs = { "Costs" },
	attachments = { "AttCosts", "AttRefundOnDetach" },
	gains = { "Gains" },
	buylimits = { "BuyLimits" },
}

local SECTION_ALIAS = {
	Teams = "teams",
	teams = "teams",
	General = "general",
	general = "general",
	Costs = "costs",
	costs = "costs",
	Weapons = "weapons",
	weapons = "weapons",
	Throwables = "throwables",
	throwables = "throwables",
	Meds = "meds",
	meds = "meds",
	Attachments = "attachments",
	attachments = "attachments",
	Gains = "gains",
	gains = "gains",
	BuyLimits = "buylimits",
	buylimits = "buylimits",
	all = "all",
	All = "all",
}

local function copyTable(src)
	if type(src) ~= "table" then return src end
	local out = {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			out[k] = copyTable(v)
		elseif type(v) ~= "function" then
			out[k] = v
		end
	end
	return out
end

local function coerce(value, spec)
	if not spec then return nil end
	local kind = spec.kind
	if kind == "bool" then
		if value == true or value == false then return value end
		if value == 1 or value == "1" or value == "true" then return true end
		if value == 0 or value == "0" or value == "false" then return false end
		return nil
	elseif kind == "string" then
		if type(value) ~= "string" or value == "" then return nil end
		return value
	elseif kind == "enum" then
		if type(value) ~= "string" then return nil end
		local v = string.lower(value)
		if spec.values[v] then return v end
		return nil
	elseif kind == "int" or kind == "number" then
		local n = tonumber(value)
		if not n then return nil end
		if kind == "int" then n = math.floor(n) end
		if spec.min and n < spec.min then n = spec.min end
		if spec.max and n > spec.max then n = spec.max end
		return n
	end
	return nil
end

local Config = copyTable(DEFAULTS)

local function splitPath(path)
	local parts = {}
	if type(path) ~= "string" then return parts end
	for part in string.gmatch(path, "[^.]+") do
		parts[#parts + 1] = part
	end
	return parts
end

local api = {}

function api.Get(path)
	local parts = splitPath(path)
	if #parts == 0 then return nil end
	local cur = rawget(Config, parts[1])
	for i = 2, #parts do
		if type(cur) ~= "table" then return nil end
		cur = cur[parts[i]]
	end
	return cur
end

function api.Set(path, value)
	local parts = splitPath(path)
	if #parts == 0 then return false, "empty key" end
	local top = parts[1]
	local spec = SCHEMA[top]
	if not spec then return false, "unknown key" end
	if #parts == 1 then
		if spec.kind == "map" then return false, "unknown key" end
		local v = coerce(value, spec)
		if v == nil then return false, "invalid" end
		Config[top] = v
		return true, v
	end
	if spec.kind ~= "map" or #parts ~= 2 then return false, "unknown key" end
	local sub = parts[2]
	if DEFAULTS[top][sub] == nil then return false, "unknown key" end
	local v = coerce(value, spec.value)
	if v == nil then return false, "invalid" end
	Config[top][sub] = v
	return true, v
end

function api.Apply(tbl)
	if type(tbl) ~= "table" then return end
	for k, v in pairs(tbl) do
		local spec = SCHEMA[k]
		if spec then
			if spec.kind == "map" then
				if type(v) == "table" then
					local map = rawget(Config, k)
					local known = DEFAULTS[k]
					for sk, sv in pairs(v) do
						if known[sk] ~= nil then
							local coerced = coerce(sv, spec.value)
							if coerced ~= nil then map[sk] = coerced end
						end
					end
				end
			else
				local coerced = coerce(v, spec)
				if coerced ~= nil then Config[k] = coerced end
			end
		end
	end
end

function api.Export()
	return copyTable(Config)
end

function api.ShippedDefaults()
	return copyTable(DEFAULTS)
end

function api.Reset()
	local fresh = copyTable(DEFAULTS)
	for k, v in pairs(fresh) do
		Config[k] = v
	end
end

function api.ResetSection(name)
	local section = SECTION_ALIAS[name or ""]
	if not section then return false, "unknown section" end
	if section == "all" then
		api.Reset()
		return true
	end
	local group = COST_GROUPS[section]
	if group then
		local costs = rawget(Config, "Costs")
		for i = 1, #group do
			local key = group[i]
			costs[key] = DEFAULTS.Costs[key]
		end
		return true
	end
	local keys = SECTIONS[section]
	if not keys then return false, "unknown section" end
	for i = 1, #keys do
		local key = keys[i]
		local def = DEFAULTS[key]
		if type(def) == "table" then
			Config[key] = copyTable(def)
		else
			Config[key] = def
		end
	end
	return true
end

setmetatable(Config, { __index = api })

BALLISTICS.Config = Config

function BALLISTICS.IsAdmin(ply)
	if ply == nil then return false end
	if Config.AdminSuperOnly then
		return type(ply.IsSuperAdmin) == "function" and ply:IsSuperAdmin() == true
	end
	return type(ply.IsAdmin) == "function" and ply:IsAdmin() == true
end
