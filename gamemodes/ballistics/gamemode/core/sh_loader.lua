-- Include core, then every module file prefixed sh_/sv_/cl_. Removing a
-- module folder must not break the core.

BALLISTICS = BALLISTICS or {}

local function realmPrefix(name)
	return name:sub(1, 3)
end

local function realmOrder(name)
	local p = realmPrefix(name)
	if p == "sh_" then return 1 end
	if p == "sv_" then return 2 end
	if p == "cl_" then return 3 end
	return 9
end

local function sortRealm(a, b)
	local oa, ob = realmOrder(a), realmOrder(b)
	if oa ~= ob then return oa < ob end
	return a < b
end

local function findLua(rel)
	if not file or not file.Find then return {}, {} end
	local folder = (GM and GM.FolderName) or "ballistics"
	local files, dirs = file.Find(folder .. "/gamemode/" .. rel, "LUA")
	if (not files or #files == 0) and (not dirs or #dirs == 0) then
		files, dirs = file.Find("gamemodes/" .. folder .. "/gamemode/" .. rel, "GAME")
	end
	return files or {}, dirs or {}
end

local function includeFile(rel, name)
	local realm = realmPrefix(name)
	if realm == "sv_" then
		if SERVER then include(rel) end
	elseif realm == "cl_" then
		if SERVER then
			AddCSLuaFile(rel)
		else
			include(rel)
		end
	elseif realm == "sh_" then
		if SERVER then AddCSLuaFile(rel) end
		include(rel)
	end
end

local CORE_ORDER = {
	"sh_config.lua",
	"sh_teams.lua",
	"sh_net.lua",
	"sh_deps.lua",
	"sh_catalog.lua",
	"sv_config.lua",
}

local coreFiles = findLua("core/*.lua")
local loaded = { ["sh_loader.lua"] = true }

-- Always include the known core list so a bad file.Find path still boots.
for i = 1, #CORE_ORDER do
	local f = CORE_ORDER[i]
	includeFile("core/" .. f, f)
	loaded[f] = true
end

local rest = {}
for i = 1, #coreFiles do
	local f = coreFiles[i]
	if not loaded[f] then rest[#rest + 1] = f end
end
table.sort(rest, sortRealm)
for i = 1, #rest do
	includeFile("core/" .. rest[i], rest[i])
end

local function loadDir(relDir)
	local files, dirs = findLua(relDir .. "/*")
	local luaFiles = {}
	for i = 1, #files do
		local f = files[i]
		if f:sub(-4) == ".lua" then
			luaFiles[#luaFiles + 1] = f
		end
	end
	table.sort(luaFiles, sortRealm)
	for i = 1, #luaFiles do
		includeFile(relDir .. "/" .. luaFiles[i], luaFiles[i])
	end
	table.sort(dirs)
	for i = 1, #dirs do
		loadDir(relDir .. "/" .. dirs[i])
	end
end

loadDir("modules")
