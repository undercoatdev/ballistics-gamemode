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

local failed = {}
BALLISTICS.LoadErrors = failed

-- One broken file must not stop every file after it from loading.
local function safeInclude(path)
	local ok, err = pcall(include, path)
	if not ok then
		failed[#failed + 1] = path
		local msg = "[Ballistics] failed to load " .. tostring(path) .. ": " .. tostring(err) .. "\n"
		if ErrorNoHalt then ErrorNoHalt(msg) else print(msg) end
	end
end

local function includeFile(rel, name)
	-- GMod resolves include paths from the lua/gamemodes root, not the gamemode folder.
	rel = ((GM and GM.FolderName) or "ballistics") .. "/gamemode/" .. rel
	local realm = realmPrefix(name)
	if realm == "sv_" then
		if SERVER then safeInclude(rel) end
	elseif realm == "cl_" then
		if SERVER then
			AddCSLuaFile(rel)
		else
			safeInclude(rel)
		end
	elseif realm == "sh_" then
		if SERVER then AddCSLuaFile(rel) end
		safeInclude(rel)
	end
end

local CORE_ORDER = {
	"sh_config.lua",
	"sh_teams.lua",
	"sh_net.lua",
	"sh_deps.lua",
	"sh_catalog.lua",
	"sh_state.lua",
	"sh_ledger.lua",
	"sv_config.lua",
	"sv_slots.lua",
	"sv_money.lua",
	"sv_player.lua",
	"sv_round.lua",
}

-- Static file list, used when file.Find sees nothing (remote clients).
includeFile("core/sh_manifest.lua", "sh_manifest.lua")
local manifest = BALLISTICS.Manifest or {}

local coreFiles = findLua("core/*.lua")
if #coreFiles == 0 and type(manifest.core) == "table" then coreFiles = manifest.core end
local loaded = { ["sh_loader.lua"] = true, ["sh_manifest.lua"] = true }

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

local modFiles = findLua("modules/*")
local _, modDirs = findLua("modules/*")
if (#modFiles > 0 or #modDirs > 0) then
	loadDir("modules")
elseif type(manifest.modules) == "table" then
	-- Group by folder, keep the sh_/sv_/cl_ order inside each folder.
	local byDir, order = {}, {}
	for i = 1, #manifest.modules do
		local path = manifest.modules[i]
		local dir, name = path:match("^(.*)/([^/]+)$")
		if dir and name then
			if not byDir[dir] then byDir[dir] = {}; order[#order + 1] = dir end
			table.insert(byDir[dir], name)
		end
	end
	table.sort(order)
	for _, dir in ipairs(order) do
		table.sort(byDir[dir], sortRealm)
		for _, name in ipairs(byDir[dir]) do includeFile(dir .. "/" .. name, name) end
	end
end
