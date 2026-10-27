-- While this gamemode is up, TacRP ammo follows the active magazine count.
-- 0 magazines keeps tacrp_infiniteammo on. Any higher count forces it off.
-- The value from before the gamemode is put back on ShutDown. A change while
-- we are running is forced back to the value we want. The callback guard
-- stops that write from looping. Addons create the convar after the gamemode
-- file loads, so this arms on Initialize and again on InitPostEntity.

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

local function norm(value)
	if value == "1" or value == "1.0" then return "1" end
	if value == "0" or value == "0.0" then return "0" end
	return value
end

local function desired()
	if BALLISTICS.Ammo and type(BALLISTICS.Ammo.ForcedValue) == "function" then
		return BALLISTICS.Ammo.ForcedValue()
	end
	return "1"
end

local function writeValue(value)
	if forcing then return end
	forcing = true
	local cv = convar()
	if cv and type(cv.SetString) == "function" then
		pcall(cv.SetString, cv, value)
	elseif cv and type(cv.SetInt) == "function" then
		pcall(cv.SetInt, cv, tonumber(value) or 0)
	elseif type(RunConsoleCommand) == "function" then
		pcall(RunConsoleCommand, CONVAR, value)
	end
	forcing = false
end

function BALLISTICS.Ammo.ApplyConVar()
	if not running then return end
	local want = desired()
	if norm(readValue(convar())) ~= want then writeValue(want) end
end

local function arm()
	running = true
	if remembered == nil then
		local now = readValue(convar())
		if now ~= nil then remembered = now end
	end
	BALLISTICS.Ammo.ApplyConVar()
end

local function restore()
	running = false
	local value = remembered
	remembered = nil
	if value == nil then return end
	writeValue(value)
end

if cvars and type(cvars.AddChangeCallback) == "function" then
	cvars.AddChangeCallback(CONVAR, function(_, _, new)
		if not running or forcing then return end
		if norm(new) == desired() then return end
		writeValue(desired())
	end, "Ballistics_AmmoMode")
end

if hook and hook.Add then
	hook.Add("Initialize", "Ballistics_AmmoMode", function() arm() end) -- never return a value: it would stop later hooks (TacRP indexes quick nades here)
	hook.Add("InitPostEntity", "Ballistics_AmmoMode", function() arm() end) -- never return a value: it would stop later hooks (TacRP indexes quick nades here)
	hook.Add("ShutDown", "Ballistics_AmmoMode", restore)
	hook.Add("Ballistics_PhaseChanged", "Ballistics_AmmoMode", function()
		BALLISTICS.Ammo.ApplyConVar()
	end)
end

arm()
