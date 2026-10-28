-- Rules tab view model. No GMod calls.
-- Round length is edited in minutes and radii in metres. Stored config stays
-- in seconds and Hammer units. Reset payloads come from the admin tab tree.

BALLISTICS = BALLISTICS or {}
BALLISTICS.RulesView = BALLISTICS.RulesView or {}

local V = BALLISTICS.RulesView

-- 1 Hammer unit = 0.75 inch = 0.01905 metres. Same constant as sh_config.
local METRES_PER_UNIT = 0.01905
local MONEY_MAX = 1000000

local ATT = {
	{ key = "optic", label = "Optic" },
	{ key = "bolt", label = "Bolt" },
	{ key = "muzzle", label = "Muzzle" },
	{ key = "trigger", label = "Trigger" },
	{ key = "tactical", label = "Tactical" },
	{ key = "ammo", label = "Ammo" },
	{ key = "accessory", label = "Accessory" },
	{ key = "perk", label = "Perk" },
	{ key = "technique", label = "Technique" },
	{ key = "special", label = "Special" },
	{ key = "boost", label = "Boost" },
}

local GAINS = {
	{ key = "kill", label = "Kill" },
	{ key = "round_win", label = "Round win" },
	{ key = "round_loss", label = "Round loss" },
	{ key = "draw", label = "Draw" },
}

local GENERAL = {
	{ path = "RoundTime", label = "Round length (minutes)", kind = "minutes", min = 1 / 60, max = 60, decimals = 2, unit = "min" },
	{ path = "BuyTime", label = "Buy time (seconds)", kind = "number", min = 1, max = 3600, decimals = 0, unit = "s" },
	{ path = "PostRoundTime", label = "Post-round time (seconds)", kind = "number", min = 1, max = 3600, decimals = 0, unit = "s" },
	{ path = "StartMoney", label = "Start money", kind = "int", min = 0, max = MONEY_MAX, decimals = 0 },
	{ path = "MaxMoney", label = "Max money (0 = no cap)", kind = "int", min = 0, max = MONEY_MAX, decimals = 0 },
	{
		path = "HealedUpOrgans",
		label = "Healed up organs",
		kind = "int",
		min = 0,
		max = 100,
		decimals = 0,
		blurb = "At each new round every organ heals this many units (capped at max). Destroyed organs always come back working, just weak.",
	},
	{ path = "CaptureTimeOne", label = "Capture time, 1 player (seconds)", kind = "number", min = 1, max = 3600, decimals = 0, unit = "s" },
	{ path = "CaptureTimeTwo", label = "Capture time, 2 players (seconds)", kind = "number", min = 1, max = 3600, decimals = 0, unit = "s" },
	{ path = "CaptureDecay", label = "Capture decay", kind = "bool" },
	{ path = "CaptureContestedFreeze", label = "Contested capture freezes", kind = "bool" },
	{ path = "ObjectiveRadius", label = "Objective radius (metres)", kind = "metres", min = 16 * METRES_PER_UNIT, max = 1000 * METRES_PER_UNIT, decimals = 2, unit = "m" },
	{ path = "CustomizeRadius", label = "Customise radius (metres)", kind = "metres", min = 16 * METRES_PER_UNIT, max = 1000 * METRES_PER_UNIT, decimals = 2, unit = "m" },
	{
		path = "BuyAmmoMags",
		label = "Magazines per gun",
		kind = "int",
		min = 0,
		max = 30,
		decimals = 0,
		blurb = "0 = infinite ammo.",
	},
	{
		path = "MedsMax",
		label = "Meds max",
		kind = "int",
		min = 0,
		max = 100,
		decimals = 0,
		blurb = "Most of one med a player can carry. The buy menu and looting both stop here.",
	},
	{
		path = "GrenadesMax",
		label = "Grenades max",
		kind = "int",
		min = 0,
		max = 100,
		decimals = 0,
		blurb = "Most of one throwable a player can carry. The buy menu and looting both stop here.",
	},
}

local SETTINGS = {
	{ path = "RoundsToWin", label = "Rounds to win (0 = endless)", kind = "int", min = 0, max = 1000, decimals = 0 },
	{
		path = "HealthMode",
		label = "Health mode",
		kind = "enum",
		values = {
			{ id = "realistic", label = "Realistic" },
			{ id = "arcade", label = "Arcade" },
		},
	},
	{
		path = "BulletPushForce",
		label = "Bullet push force",
		kind = "number",
		min = 0,
		max = 2,
		decimals = 2,
		blurb = "How hard bullets push bodies and props. 1 = TacRP normal, 0.5 = half (soft), 0.2 = light.",
	},
}

function V.ToMinutes(seconds)
	return (tonumber(seconds) or 0) / 60
end

function V.FromMinutes(minutes)
	return (tonumber(minutes) or 0) * 60
end

function V.ToMetres(units)
	return (tonumber(units) or 0) * METRES_PER_UNIT
end

function V.FromMetres(metres)
	return (tonumber(metres) or 0) / METRES_PER_UNIT
end

function V.Editors()
	return { "weapons", "throwables", "meds", "attachments", "gains", "general" }
end

local function read(path)
	local cfg = BALLISTICS.Config
	if type(cfg) ~= "table" then return nil end
	if type(cfg.Get) == "function" then return cfg.Get(path) end
	local cur = cfg
	for part in string.gmatch(path, "[^.]+") do
		if type(cur) ~= "table" then return nil end
		cur = cur[part]
	end
	return cur
end

local function displayOf(kind, value)
	if kind == "minutes" then return V.ToMinutes(value) end
	if kind == "metres" then return V.ToMetres(value) end
	return value
end

local function catalogList(section)
	local cat = BALLISTICS.Catalog
	if not cat then return {} end
	if section == "weapons" and type(cat.Weapons) == "function" then return cat.Weapons() end
	if section == "throwables" and type(cat.Throwables) == "function" then return cat.Throwables() end
	if section == "meds" and type(cat.Meds) == "function" then return cat.Meds() end
	return {}
end

local function costRows(section)
	local items = catalogList(section)
	local rows = {}
	for i = 1, #items do
		local item = items[i]
		local path = "Costs." .. item.key
		local value = read(path)
		rows[i] = {
			path = path,
			label = item.name or item.key,
			kind = "int",
			value = value,
			display = value,
			min = 0,
			max = MONEY_MAX,
			decimals = 0,
		}
	end
	return rows
end

local function mapRows(list, prefix)
	local rows = {}
	for i = 1, #list do
		local item = list[i]
		local path = prefix .. "." .. item.key
		local value = read(path)
		rows[i] = {
			path = path,
			label = item.label,
			kind = "int",
			value = value,
			display = value,
			min = 0,
			max = MONEY_MAX,
			decimals = 0,
		}
	end
	return rows
end

local function specRows(list)
	local rows = {}
	for i = 1, #list do
		local spec = list[i]
		local value = read(spec.path)
		local row = {
			path = spec.path,
			label = spec.label,
			kind = spec.kind,
			value = value,
			display = displayOf(spec.kind, value),
			min = spec.min,
			max = spec.max,
			decimals = spec.decimals,
			unit = spec.unit,
			blurb = spec.blurb,
		}
		if spec.values then
			local values = {}
			for v = 1, #spec.values do
				values[v] = { id = spec.values[v].id, label = spec.values[v].label }
			end
			row.values = values
		end
		rows[i] = row
	end
	return rows
end

function V.Rows(section)
	if section == "weapons" or section == "throwables" or section == "meds" then
		return costRows(section)
	end
	if section == "attachments" then return mapRows(ATT, "AttCosts") end
	if section == "gains" then return mapRows(GAINS, "Gains") end
	if section == "general" then return specRows(GENERAL) end
	if section == "settings" then return specRows(SETTINGS) end
	return {}
end

function V.Same(a, b)
	if a == b then return true end
	if type(a) == "boolean" or type(b) == "boolean" then return false end
	local na = tonumber(a)
	local nb = tonumber(b)
	if na and nb and na == na and nb == nb then
		return math.abs(na - nb) < 0.0005
	end
	return false
end

local function enumId(row, display)
	if type(display) ~= "string" then return nil end
	local want = string.lower(display)
	local values = row.values or {}
	for i = 1, #values do
		if values[i].id == want then return want end
	end
	return nil
end

function V.Commit(row, display)
	if type(row) ~= "table" or type(row.path) ~= "string" or row.path == "" then
		return nil, "field"
	end
	local kind = row.kind
	local value
	if kind == "bool" then
		if display == true or display == false then
			value = display
		elseif display == 1 or display == "1" or display == "true" then
			value = true
		elseif display == 0 or display == "0" or display == "false" then
			value = false
		else
			return nil, "invalid"
		end
	elseif kind == "enum" then
		value = enumId(row, display)
		if value == nil then return nil, "invalid" end
	elseif kind == "minutes" then
		local n = tonumber(display)
		if not n then return nil, "invalid" end
		value = V.FromMinutes(n)
	elseif kind == "metres" then
		local n = tonumber(display)
		if not n then return nil, "invalid" end
		value = V.FromMetres(n)
	elseif kind == "int" then
		local n = tonumber(display)
		if not n then return nil, "invalid" end
		value = math.floor(n)
	else
		local n = tonumber(display)
		if not n then return nil, "invalid" end
		value = n
	end
	return { key = row.path, value = value }
end

function V.ResetPayload(id)
	local tabs = BALLISTICS.AdminTabs
	if not tabs or type(tabs.Find) ~= "function" or type(tabs.ResetRequest) ~= "function" then
		return nil, "tabs"
	end
	return tabs.ResetRequest(tabs.Find(id))
end

-- A non-admin gets nothing back, so the client does not write the net message.
-- Extra fields are dropped. The server still checks admin and the schema.
function V.PayloadFor(isAdmin, payload)
	if isAdmin ~= true then return nil end
	if type(payload) ~= "table" then return nil end
	if payload.reset == true then
		if type(payload.section) ~= "string" or payload.section == "" then return nil end
		return { reset = true, section = payload.section }
	end
	if type(payload.key) ~= "string" or payload.key == "" then return nil end
	return { key = payload.key, value = payload.value }
end
