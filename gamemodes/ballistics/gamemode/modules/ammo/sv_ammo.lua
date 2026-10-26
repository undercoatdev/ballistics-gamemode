-- While this gamemode is up, TacRP uses finite ammo. The previous
-- tacrp_infiniteammo value is put back on ShutDown. A change while we are
-- running is forced back to 0. The callback guard stops that write from
-- looping. Addons create the convar after the gamemode file loads, so this
-- arms on Initialize and again on InitPostEntity.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Ammo = BALLISTICS.Ammo or {}

local CONVAR = "tacrp_infiniteammo"
local remembered = nil
local running = false
local forcing = false

local function convar()
	if type(GetConVar) ~= "function" then return nil end
	local ok, cv = pcall(GetConVar, CONVAR)
	if not ok then return nil end
	return cv
end

local function readValue(cv)
	if cv == nil then return nil end
	if type(cv.GetString) == "function" then
		local ok, value = pcall(cv.GetString, cv)
		if ok and value ~= nil then return tostring(value) end
	end
	if type(cv.GetInt) == "function" then
		local ok, value = pcall(cv.GetInt, cv)
		if ok and value ~= nil then return tostring(value) end
	end
	return nil
end

local function forceZero()
	if forcing then return end
	local cv = convar()
	forcing = true
	if cv and type(cv.SetInt) == "function" then
		pcall(cv.SetInt, cv, 0)
	elseif type(RunConsoleCommand) == "function" then
		pcall(RunConsoleCommand, CONVAR, "0")
	end
	forcing = false
end

local function arm()
	running = true
	if remembered == nil then
		local now = readValue(convar())
		if now ~= nil then remembered = now end
	end
	local now = readValue(convar())
	if now ~= "0" then forceZero() end
end

local function restore()
	running = false
	local value = remembered
	remembered = nil
	if value == nil then return end
	local cv = convar()
	forcing = true
	if cv and type(cv.SetString) == "function" then
		pcall(cv.SetString, cv, value)
	elseif type(RunConsoleCommand) == "function" then
		pcall(RunConsoleCommand, CONVAR, value)
	end
	forcing = false
end

if cvars and type(cvars.AddChangeCallback) == "function" then
	cvars.AddChangeCallback(CONVAR, function(_, _, new)
		if not running or forcing then return end
		if new == "0" or new == "0.0" then return end
		forceZero()
	end, "Ballistics_FiniteAmmo")
end

if hook and hook.Add then
	hook.Add("Initialize", "Ballistics_FiniteAmmo", arm)
	hook.Add("InitPostEntity", "Ballistics_FiniteAmmo", arm)
	hook.Add("ShutDown", "Ballistics_FiniteAmmo", restore)
end

arm()
