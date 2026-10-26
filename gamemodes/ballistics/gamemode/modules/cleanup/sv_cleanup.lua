-- Round start removes corpses and blood. Player Ballistics has no "remove every
-- body" call: drop its kept-body list here, then any other prop_ragdoll.
-- A record still worn by a living player (a knockout) is not deleted.
-- Spawn flags are prop_dynamic and fail ShouldRemove.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Cleanup = BALLISTICS.Cleanup or {}

local function valid(ent)
	if ent == nil or ent == false then return false end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	if IsValid then return IsValid(ent) == true end
	return type(ent) == "table"
end

local function eachPlayer(fn)
	local seen = {}
	local function one(ply)
		if ply == nil or seen[ply] then return end
		seen[ply] = true
		fn(ply)
	end
	if BALLISTICS.Player and BALLISTICS.Player.Each then
		BALLISTICS.Player.Each(one)
	end
	if player and player.GetAll then
		local all = player.GetAll()
		if type(all) == "table" then
			for i = 1, #all do one(all[i]) end
		end
	end
end

local function living(ply)
	if not valid(ply) then return false end
	if type(ply.Alive) ~= "function" then return true end
	return ply:Alive() == true
end

local function aliveOwns(id)
	if id == nil or id == "" then return false end
	local owns = false
	eachPlayer(function(ply)
		if owns then return end
		if ply.bd_id == id and living(ply) then owns = true end
	end)
	return owns
end

local function classOf(ent)
	if type(ent.GetClass) ~= "function" then return "" end
	local ok, class = pcall(ent.GetClass, ent)
	if ok and type(class) == "string" then return class end
	return ""
end

local function flagTeam(ent)
	if type(ent.GetNW2Int) ~= "function" then return 0 end
	local ok, teamId = pcall(ent.GetNW2Int, ent, "bal_flag_team", 0)
	if not ok or teamId == nil then return 0 end
	return teamId
end

local function describe(ent)
	return {
		class = classOf(ent),
		isPlayer = type(ent.IsPlayer) == "function" and ent:IsPlayer() == true or false,
		keep = ent.BallisticsKeep == true,
		flagTeam = flagTeam(ent),
	}
end

local function spared(ent)
	local info = describe(ent)
	if info.isPlayer or info.keep then return true end
	local flag = info.flagTeam
	if flag ~= nil and flag ~= 0 and flag ~= "" and flag ~= false then return true end
	return false
end

local function removeEnt(ent)
	if not valid(ent) or type(ent.Remove) ~= "function" then return false end
	if not BALLISTICS.Cleanup.ShouldRemove(describe(ent)) then return false end
	pcall(ent.Remove, ent)
	return true
end

-- Kept bodies are corpses even when their class is not prop_ragdoll.
local function removeBody(ent)
	if not valid(ent) then return true end
	if spared(ent) or type(ent.Remove) ~= "function" then return false end
	pcall(ent.Remove, ent)
	return true
end

local function clearPointers(rec, rag)
	if type(rec) ~= "table" then return end
	if rag == nil or rec.corpse == rag then rec.corpse = nil end
	if rag == nil or rec.puppet == rag then rec.puppet = nil end
end

local function dropBodies()
	local pb = PLAYER_BALLISTICS
	if not pb or type(pb.Bodies) ~= "table" then return end
	eachPlayer(function(ply)
		if type(pb.ReleaseBodyHandle) == "function" then
			pcall(pb.ReleaseBodyHandle, ply)
		end
	end)
	local kept = {}
	local list = pb.Bodies
	for i = 1, #list do
		local entry = list[i]
		if type(entry) ~= "table" then
			-- drop junk rows
		else
			local rag = entry.ent
			clearPointers(entry.rec, rag)
			local gone = removeBody(rag)
			if gone then
				local id = entry.id
				if id ~= nil and not aliveOwns(id) then
					local records = BODY_DAMAGE and BODY_DAMAGE.Records
					if type(records) == "table" then records[id] = nil end
				end
			else
				kept[#kept + 1] = entry
			end
		end
	end
	pb.Bodies = kept
end

local function dropLooseRagdolls()
	if not (ents and ents.FindByClass) then return end
	local list = ents.FindByClass("prop_ragdoll")
	if type(list) ~= "table" then return end
	for i = 1, #list do
		removeEnt(list[i])
	end
end

local function clearDecals(ent)
	if valid(ent) and type(ent.RemoveAllDecals) == "function" then
		pcall(ent.RemoveAllDecals, ent)
	end
end

local function dropDecals()
	if game and game.GetWorld then
		local ok, world = pcall(game.GetWorld)
		if ok then clearDecals(world) end
	end
	if ents and ents.GetAll then
		local all = ents.GetAll()
		if type(all) == "table" then
			for i = 1, #all do
				clearDecals(all[i])
			end
		end
	end
end

function BALLISTICS.Cleanup.Round()
	dropBodies()
	dropLooseRagdolls()
	dropDecals()
	if BALLISTICS.Net and BALLISTICS.Net.Broadcast then
		BALLISTICS.Net.Broadcast("bal_cleanup")
	end
end
