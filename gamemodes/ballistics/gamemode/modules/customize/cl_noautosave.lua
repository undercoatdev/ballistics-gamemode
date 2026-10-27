-- TacRP client autosave (tacrp_autosave, on with free_atts) saves your
-- attachments to data/tacrp_presets/<gun>/autosave.txt when the customize
-- menu closes and re-applies them on every newly given gun. In this
-- gamemode a bought gun must start bare, so autosave is forced off while the
-- gamemode runs and the old value is put back on shutdown. Kept gear between
-- rounds uses our own snapshot (modules/gear), not TacRP presets.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.NoAutosave = BALLISTICS.NoAutosave or {}
local N = BALLISTICS.NoAutosave
local NAME = "tacrp_autosave"
local remembered = nil
local running = false

local function cv()
	if type(GetConVar) ~= "function" then return nil end
	return GetConVar(NAME)
end

function N.Force()
	local c = cv()
	if not c then return end
	if remembered == nil then remembered = c:GetInt() end
	running = true
	if c:GetInt() ~= 0 then RunConsoleCommand(NAME, "0") end
end

function N.Restore()
	running = false
	if remembered ~= nil and remembered ~= 0 then RunConsoleCommand(NAME, tostring(remembered)) end
	remembered = nil
end

function N.Running() return running end

if hook and hook.Add then
	hook.Add("InitPostEntity", "Ballistics_NoAutosave", function() N.Force() end) -- never return a value: it would stop later hooks (TacRP indexes quick nades here)
	hook.Add("ShutDown", "Ballistics_NoAutosave", N.Restore)
end
if timer and timer.Create then
	timer.Create("Ballistics_NoAutosave", 1, 0, function() if running or remembered == nil then N.Force() end end)
end
N.Force()
