-- Server config persistence: data/ballistics/config.json, admin net, client sync.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}

local DATA_DIR = "ballistics"
local DATA_FILE = "ballistics/config.json"

local function applyHealthMode()
	local mode = BALLISTICS.Config.HealthMode
	if BALLISTICS.Config.Get then
		mode = BALLISTICS.Config.Get("HealthMode") or mode
	end
	local n = (mode == "arcade") and 0 or 1
	if not GetConVar then return end
	local cv = GetConVar("bodydamage_mode")
	if cv and cv.SetInt then cv:SetInt(n) end
end

function BALLISTICS.SaveConfig()
	if not file or not file.Write then return end
	if not util or not util.TableToJSON then return end
	if file.CreateDir then file.CreateDir(DATA_DIR) end
	local data = BALLISTICS.Config.Export and BALLISTICS.Config.Export() or BALLISTICS.Config
	file.Write(DATA_FILE, util.TableToJSON(data, true) or "")
end

function BALLISTICS.LoadConfig()
	if not file or not file.Read then return false end
	if file.Exists and not file.Exists(DATA_FILE, "DATA") then return false end
	local raw = file.Read(DATA_FILE, "DATA")
	if not raw or raw == "" then return false end
	if not util or not util.JSONToTable then return false end
	local tbl = util.JSONToTable(raw)
	if type(tbl) ~= "table" then return false end
	if BALLISTICS.Config.Apply then
		BALLISTICS.Config.Apply(tbl)
	end
	return true
end

function BALLISTICS.BroadcastConfig(ply)
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	local payload = BALLISTICS.Config.Export and BALLISTICS.Config.Export() or BALLISTICS.Config
	BALLISTICS.Net.Send("bal_config_sync", ply, payload)
end

BALLISTICS.LoadConfig()
applyHealthMode()
-- Addon autoruns (Body Damage) load after the gamemode, so its convar may not
-- exist yet at file load. Apply again once everything is up.
if hook and hook.Add then
	hook.Add("InitPostEntity", "Ballistics_HealthMode", applyHealthMode)
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_config_set", function(_, payload)
		if type(payload) ~= "table" then return end
		if payload.reset and payload.section then
			BALLISTICS.Config.ResetSection(payload.section)
		elseif payload.key ~= nil then
			BALLISTICS.Config.Set(payload.key, payload.value)
		else
			BALLISTICS.Config.Apply(payload)
		end
		applyHealthMode()
		BALLISTICS.SaveConfig()
		BALLISTICS.BroadcastConfig()
	end, { admin = true, rate = 10, read = "table" })
end

if hook and hook.Add then
	hook.Add("PlayerInitialSpawn", "Ballistics_ConfigSync", function(ply)
		BALLISTICS.BroadcastConfig(ply)
	end)
end
