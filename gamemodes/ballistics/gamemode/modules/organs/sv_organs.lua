-- At a continuing buy, remember every slotted player's organ hp, then write
-- it onto the record Spawn/MintPlayer (and Player Ballistics' deferred
-- GiveOrgans) just created. GiveOrgans runs on timer.Simple(0) from
-- PlayerSpawn and replaces that record, so the write is deferred the same
-- way and queued after it. Clients hear it through Body Damage's own
-- WriteOrganCopies + OrganNetPush. Match start keeps the fresh full set.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Organs = BALLISTICS.Organs or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local captured = {}

local function valid(ent)
	if ent == nil or ent == false then return false end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	if IsValid then return IsValid(ent) == true end
	return type(ent) == "table"
end

local function playerId(ply)
	if BALLISTICS.PlayerId then return BALLISTICS.PlayerId(ply) end
	return nil
end

local function eachSlotted(fn)
	if not (BALLISTICS.Slots and BALLISTICS.Slots.Members and BALLISTICS.Slots.Player) then return end
	for _, teamId in ipairs({ GOOD, BAD }) do
		local members = BALLISTICS.Slots.Members(teamId) or {}
		for i = 1, #members do
			local ply = BALLISTICS.Slots.Player(members[i])
			if ply then fn(ply, teamId, members[i]) end
		end
	end
end

local function hasOrgans(rec)
	return type(rec) == "table" and type(rec.organs) == "table" and type(rec.organs.copies) == "table"
end

local function steamOf(ply)
	if type(ply.SteamID) ~= "function" then return nil end
	local ok, id = pcall(ply.SteamID, ply)
	if ok and type(id) == "string" and id ~= "" then return id end
	return nil
end

local function findRecord(ply)
	local bd = BODY_DAMAGE
	if not bd or not valid(ply) then return nil end
	if type(bd.FindRecord) == "function" then
		local ok, rec = pcall(bd.FindRecord, ply)
		if ok and hasOrgans(rec) then return rec end
	end
	if type(ply.bd_id) == "string" and ply.bd_id ~= "" and type(bd.Records) == "table" then
		local rec = bd.Records[ply.bd_id]
		if hasOrgans(rec) then return rec end
	end
	if type(bd.Records) == "table" then
		for _, rec in pairs(bd.Records) do
			if hasOrgans(rec) and (rec.ent == ply or (type(rec.corpse) == "table" and rec.corpse.bd_owner == ply)) then
				return rec
			end
		end
	end
	local pb = PLAYER_BALLISTICS
	local steam = steamOf(ply)
	if pb and type(pb.Bodies) == "table" then
		local found = nil
		for i = 1, #pb.Bodies do
			local row = pb.Bodies[i]
			if type(row) == "table" and hasOrgans(row.rec) then
				local owner = row.ent and row.ent.bd_owner
				if owner == ply or (steam and row.steam == steam) then found = row.rec end
			end
		end
		if found then return found end
	end
	if pb and type(pb.ParkedRecord) == "function" then
		local ok, parked = pcall(pb.ParkedRecord, ply)
		if ok and type(parked) == "table" and hasOrgans(parked.rec) then return parked.rec end
	end
	return nil
end

local function sideMax(entry, side)
	local bd = BODY_DAMAGE
	if not bd or type(bd.SideHealth) ~= "function" or type(entry) ~= "table" then return nil end
	local ok, got = pcall(bd.SideHealth, entry, side)
	if not ok then return nil end
	return tonumber(got)
end

local function healAmount()
	local n = BALLISTICS.Config and BALLISTICS.Config.HealedUpOrgans
	n = tonumber(n) or 0
	if n ~= n or n < 0 or n == math.huge then n = 0 end
	return math.floor(n)
end

local function sync(ply, rec)
	ply.bd_organNetSig = nil
	local bd = BODY_DAMAGE
	local wrote = 0
	if bd and type(bd.WriteOrganCopies) == "function" then
		local ok, n = pcall(bd.WriteOrganCopies, ply, rec)
		if ok and type(n) == "number" then wrote = n end
	end
	if wrote < 1 and type(rec.organs) == "table" and type(rec.organs.copies) == "table" then
		local keys = {}
		for uid, copy in pairs(rec.organs.copies) do
			if type(copy) == "table" and type(copy.parts) == "table" then
				for side, hp in pairs(copy.parts) do
					local key = "bd_copy_" .. tostring(uid) .. "_" .. tostring(side)
					hp = tonumber(hp) or 0
					if bd and type(bd.SetBodyFloat) == "function" then
						pcall(bd.SetBodyFloat, ply, key, hp)
					elseif type(ply.SetNW2Float) == "function" then
						pcall(ply.SetNW2Float, ply, key, hp)
					end
					keys[#keys + 1] = key
				end
			end
		end
		if #keys > 0 then ply.bd_copyKeys = keys end
	end
	if bd and type(bd.OrganNetPush) == "function" then
		pcall(bd.OrganNetPush, ply)
	end
end

function BALLISTICS.Organs.Capture()
	captured = {}
	eachSlotted(function(ply)
		local id = playerId(ply)
		if not id then return end
		local snap = BALLISTICS.Organs.SnapshotRecord(findRecord(ply), sideMax)
		if snap then captured[id] = snap end
	end)
end

function BALLISTICS.Organs.Reset()
	captured = {}
end

function BALLISTICS.Organs.ApplySpawn(ply)
	local id = playerId(ply)
	if not id then return end
	local snap = captured[id]
	if not snap then return end
	captured[id] = nil
	local amount = healAmount()
	local function write()
		if not valid(ply) then return end
		local rec = findRecord(ply)
		if not rec then return end
		if not BALLISTICS.Organs.ApplyRecord(rec, snap, amount, sideMax) then return end
		sync(ply, rec)
	end
	-- Queued after Player Ballistics' PlayerSpawn GiveOrgans, which also
	-- uses timer.Simple(0) and would replace a record written during Spawn.
	if timer and timer.Simple then
		timer.Simple(0, write)
	else
		write()
	end
end
