-- Snapshot a living winner's gear when the round ends and put it back after
-- the next buy spawn's ApplyLoadout. Guns are restored in loadout slot order
-- (key 1, then key 2). Attachments go through the weapon's
-- original Attach (saved by the price wrapper) with BallisticsAttRestore set,
-- so the price wrapper does not charge. A death before that spawn drops the
-- snapshot. Match start clears every snapshot.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Gear = BALLISTICS.Gear or {}

local KNIFE = "tacrp_knife"
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local pending = {}
local lastWinner = nil

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

local function teamOf(id)
	if id == nil or not (BALLISTICS.Slots and BALLISTICS.Slots.TeamOf) then return nil end
	return BALLISTICS.Slots.TeamOf(id)
end

local function medIds()
	local ids = {}
	local meds = BALLISTICS.Catalog and BALLISTICS.Catalog.Meds and BALLISTICS.Catalog.Meds()
	if type(meds) == "table" then
		for i = 1, #meds do
			if meds[i].id ~= nil then ids[#ids + 1] = meds[i].id end
		end
	end
	if #ids == 0 then ids = { 1, 2, 3, 4 } end
	return ids
end

local function medHave(ply, id)
	local pb = PLAYER_BALLISTICS
	if pb and type(pb.MedBag) == "function" then
		local ok, bag = pcall(pb.MedBag, ply)
		if ok and type(bag) == "table" and type(bag.counts) == "table" then
			return math.floor(tonumber(bag.counts[id]) or 0)
		end
	end
	local bag = ply.pbMed
	if type(bag) == "table" and type(bag.counts) == "table" then
		return math.floor(tonumber(bag.counts[id]) or 0)
	end
	return nil
end

local function setMed(ply, id, want)
	want = tonumber(want) or 0
	if want < 0 then want = 0 end
	want = math.floor(want)
	local have = medHave(ply, id)
	if have == nil then have = 0 end
	local delta = want - have
	if delta == 0 then return end
	if BALLISTICS.GiveMed then
		BALLISTICS.GiveMed(ply, id, delta)
		return
	end
	if type(ply.pbMed) == "table" and type(ply.pbMed.counts) == "table" then
		ply.pbMed.counts[id] = want
	end
end

local function weaponClass(wep)
	if type(wep.GetClass) ~= "function" then return nil end
	local ok, class = pcall(wep.GetClass, wep)
	if ok and type(class) == "string" and class ~= "" then return class end
	return nil
end

local function numberCall(fn, self)
	if type(fn) ~= "function" then return 0 end
	local ok, got = pcall(fn, self)
	got = ok and tonumber(got) or nil
	if not got or got ~= got or got < 0 then return 0 end
	return math.floor(got)
end

local function meleeClass(ply)
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.Knife) == "function" then
		local knife = BALLISTICS.Loadout.Knife(ply)
		if type(knife) == "string" and knife ~= "" then return knife end
	end
	return nil
end

local function captureFromWep(wep)
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.CaptureGun) == "function" then
		local gun = BALLISTICS.Loadout.CaptureGun(wep)
		if type(gun) ~= "table" then return nil end
		return {
			class = gun.class,
			clip1 = gun.clip1,
			clip2 = gun.clip2,
			ammo = gun.ammo,
			attachments = gun.attachments or {},
		}
	end
	local class = wep ~= nil and weaponClass(wep) or nil
	if not class then return nil end
	local atts = {}
	if type(wep.Attachments) == "table" then
		for slot, slottbl in pairs(wep.Attachments) do
			if type(slottbl) == "table" then
				local att = slottbl.Installed
				if type(att) == "string" and att ~= "" then
					atts[#atts + 1] = { slot = slot, att = att }
				end
			end
		end
	end
	return {
		class = class,
		clip1 = numberCall(wep.Clip1, wep),
		clip2 = numberCall(wep.Clip2, wep),
		attachments = atts,
	}
end

local function captureWeapons(ply)
	local liveByClass = {}
	if type(ply.GetWeapons) == "function" then
		local ok, weps = pcall(ply.GetWeapons, ply)
		if ok and type(weps) == "table" then
			local melee = meleeClass(ply)
			for i = 1, #weps do
				local wep = weps[i]
				local class = wep ~= nil and weaponClass(wep) or nil
				if class and class ~= KNIFE and class ~= melee then
					liveByClass[class] = captureFromWep(wep)
				end
			end
		end
	end
	local Load = BALLISTICS.Loadout
	local slots, twin, liveSlot
	if Load and type(Load.Slots) == "function" then slots = Load.Slots(ply) end
	if Load and type(Load.Twin) == "function" then twin = Load.Twin(ply) end
	if Load and type(Load.LiveSlot) == "function" then liveSlot = Load.LiveSlot(ply) end
	local list = {}
	if type(slots) == "table" then
		local seen = {}
		for i = 1, 2 do
			local class = slots[i]
			if type(class) == "string" and class ~= "" then
				local useTwin = type(twin) == "table" and twin.class == class
				if useTwin then
					if liveSlot == 1 or liveSlot == 2 then
						useTwin = liveSlot ~= i
					else
						useTwin = seen[class] == true
					end
				end
				seen[class] = true
				local row
				if useTwin then
					row = {
						class = twin.class,
						clip1 = twin.clip1,
						clip2 = twin.clip2,
						ammo = twin.ammo,
						attachments = twin.attachments or {},
					}
				else
					row = liveByClass[class]
				end
				if type(row) == "table" then
					row.slot = i
					list[#list + 1] = row
				end
			end
		end
		return list
	end
	for class, row in pairs(liveByClass) do
		list[#list + 1] = row
	end
	table.sort(list, function(a, b) return (a.class or "") < (b.class or "") end)
	return list
end

local function ammoName(id, stored)
	if type(stored) == "string" and stored ~= "" then return stored end
	if type(id) == "string" and id ~= "" then return id end
	if type(id) == "number" and game and type(game.GetAmmoName) == "function" then
		local ok, name = pcall(game.GetAmmoName, id)
		if ok and type(name) == "string" and name ~= "" then return name end
	end
	return nil
end

local function captureAmmo(ply)
	local ammo = {}
	if type(ply.GetAmmo) ~= "function" then return ammo end
	local ok, got = pcall(ply.GetAmmo, ply)
	if not ok or type(got) ~= "table" then return ammo end
	for id, n in pairs(got) do
		n = tonumber(n) or 0
		if n > 0 then
			n = math.floor(n)
			ammo[#ammo + 1] = { id = id, name = ammoName(id), count = n }
		end
	end
	return ammo
end

local function captureMeds(ply)
	local counts = {}
	local ids = medIds()
	for i = 1, #ids do
		local have = medHave(ply, ids[i])
		counts[ids[i]] = have or 0
	end
	return counts
end

local function takeSnapshot(ply)
	local liveSlot
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.LiveSlot) == "function" then
		liveSlot = BALLISTICS.Loadout.LiveSlot(ply)
	end
	return {
		weapons = captureWeapons(ply),
		liveSlot = liveSlot,
		ammo = captureAmmo(ply),
		meds = captureMeds(ply),
	}
end

function BALLISTICS.Gear.Capture(winner)
	pending = {}
	lastWinner = winner
	eachSlotted(function(ply, teamId)
		local id = playerId(ply)
		if not id then return end
		local alive = type(ply.Alive) == "function" and ply:Alive() == true
		if not BALLISTICS.Gear.Keeps({
			matchStart = false,
			alive = alive,
			winner = winner,
			team = teamId,
		}) then
			return
		end
		pending[id] = takeSnapshot(ply)
	end)
end

function BALLISTICS.Gear.Reset()
	pending = {}
	lastWinner = nil
end

function BALLISTICS.Gear.WillKeep(ply)
	local id = playerId(ply)
	if not id or pending[id] == nil then return false end
	local alive = type(ply.Alive) == "function" and ply:Alive() == true
	if not BALLISTICS.Gear.Keeps({
		matchStart = false,
		alive = alive,
		winner = lastWinner,
		team = teamOf(id),
	}) then
		pending[id] = nil
		return false
	end
	return true
end

local function installAtt(wep, slot, att)
	if type(att) ~= "string" or att == "" then return end
	if type(wep.Attachments) ~= "table" then return end
	local slottbl = wep.Attachments[slot]
	if type(slottbl) ~= "table" then return end
	if slottbl.Installed == att then return end
	if slottbl.Installed ~= nil and slottbl.Installed ~= false and slottbl.Installed ~= "" then
		if type(wep.Detach) == "function" then
			pcall(wep.Detach, wep, slot, true, true)
		end
		slottbl = wep.Attachments[slot]
		if type(slottbl) == "table" and slottbl.Installed ~= nil and slottbl.Installed ~= att then
			slottbl.Installed = nil
		end
	end
	local fn = wep.BallisticsAttOriginal
	if type(fn) ~= "function" then fn = wep.Attach end
	wep.BallisticsAttRestore = true
	if type(fn) == "function" then
		pcall(fn, wep, slot, att, true, true)
	end
	wep.BallisticsAttRestore = false
	slottbl = wep.Attachments and wep.Attachments[slot]
	if type(slottbl) ~= "table" or slottbl.Installed == att then return end
	slottbl.Installed = att
	if type(wep.InvalidateCache) == "function" then pcall(wep.InvalidateCache, wep) end
	if type(wep.SetBaseSettings) == "function" then pcall(wep.SetBaseSettings, wep) end
end

local function giveWeapon(ply, class)
	if type(ply.Give) ~= "function" then return nil end
	local wep = ply:Give(class, true)
	if not valid(wep) and type(ply.GetWeapon) == "function" then
		wep = ply:GetWeapon(class)
	end
	if not valid(wep) then return nil end
	return wep
end

local function applyRow(wep, row)
	if wep == nil or type(row) ~= "table" then return end
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.ApplyGun) == "function" then
		BALLISTICS.Loadout.ApplyGun(wep, row)
		return
	end
	local atts = row.attachments or {}
	for a = 1, #atts do
		installAtt(wep, atts[a].slot, atts[a].att)
	end
	if type(wep.SetClip1) == "function" then pcall(wep.SetClip1, wep, tonumber(row.clip1) or 0) end
	if type(wep.SetClip2) == "function" then pcall(wep.SetClip2, wep, tonumber(row.clip2) or 0) end
	if type(wep.NetworkWeapon) == "function" then pcall(wep.NetworkWeapon, wep) end
end

local function restoreWeapons(ply, list, liveSlot)
	if type(list) ~= "table" then return end
	local melee = meleeClass(ply)
	local counts = {}
	local rows = {}
	for i = 1, #list do
		local row = list[i]
		if type(row) == "table" and type(row.class) == "string" and row.class ~= KNIFE and row.class ~= melee then
			rows[#rows + 1] = row
			counts[row.class] = (counts[row.class] or 0) + 1
		end
	end
	local given = {}
	local ordered = {}
	for i = 1, #rows do
		local row = rows[i]
		local slot = math.floor(tonumber(row.slot) or 0)
		if slot < 1 or slot > 2 then slot = #ordered + 1 end
		ordered[slot] = row.class
		if given[row.class] == nil then
			given[row.class] = giveWeapon(ply, row.class)
		end
	end
	local Load = BALLISTICS.Loadout
	if Load and Load.ClearTwin then Load.ClearTwin(ply) end
	for i = 1, #rows do
		local row = rows[i]
		local wep = given[row.class]
		local copies = counts[row.class] or 0
		local slot = math.floor(tonumber(row.slot) or 0)
		if copies < 2 then
			applyRow(wep, row)
		elseif (liveSlot == 1 or liveSlot == 2) and slot == liveSlot then
			applyRow(wep, row)
		elseif (liveSlot == 1 or liveSlot == 2) and slot ~= liveSlot then
			if Load and Load.SetTwin then Load.SetTwin(ply, row) end
		elseif given[row.class] ~= true and wep ~= nil then
			-- First row of a twin pair without liveSlot is the live copy.
			applyRow(wep, row)
			given[row.class] = true
		else
			if Load and Load.SetTwin then Load.SetTwin(ply, row) end
		end
	end
	-- given[class] was the wep, then may have been set to true. Restore slots.
	if Load and type(Load.Restore) == "function" then
		Load.Restore(ply, ordered)
	end
	if Load and type(Load.SetLiveSlot) == "function" and (liveSlot == 1 or liveSlot == 2) then
		Load.SetLiveSlot(ply, liveSlot)
	end
	-- A carried-over gun is drawn instead of the knife (first slot, else the
	-- second). Equip selects now and next tick; one more pass after the spawn
	-- loadout so its knife select cannot win.
	local first = ordered[1] or ordered[2]
	if first and Load and type(Load.Equip) == "function" then
		Load.Equip(ply, first)
		if timer and timer.Simple then
			timer.Simple(0.2, function()
				if IsValid and not IsValid(ply) then return end
				Load.Equip(ply, first)
			end)
		end
	end
end

local function restoreAmmo(ply, saved)
	if type(ply.SetAmmo) ~= "function" then return end
	local keep = {}
	if type(saved) == "table" then
		for i = 1, #saved do
			local row = saved[i]
			local name = ammoName(row.id, row.name)
			local key = name
			if key == nil and type(row.id) == "number" then key = row.id end
			if key ~= nil then
				if type(name) == "string" then keep[name] = true end
				pcall(ply.SetAmmo, ply, tonumber(row.count) or 0, key)
			end
		end
	end
	if type(ply.GetAmmo) ~= "function" then return end
	local ok, got = pcall(ply.GetAmmo, ply)
	if not ok or type(got) ~= "table" then return end
	for id, n in pairs(got) do
		local name = ammoName(id)
		n = tonumber(n) or 0
		if name and not keep[name] and n ~= 0 then
			pcall(ply.SetAmmo, ply, 0, name)
		end
	end
end

local function restoreMeds(ply, counts)
	local ids = medIds()
	for i = 1, #ids do
		local id = ids[i]
		local want = 0
		if type(counts) == "table" and counts[id] ~= nil then want = counts[id] end
		setMed(ply, id, want)
	end
end

function BALLISTICS.Gear.ApplySpawn(ply)
	local id = playerId(ply)
	if not id then return end
	local snap = pending[id]
	pending[id] = nil
	if type(snap) ~= "table" then return end
	restoreWeapons(ply, snap.weapons, snap.liveSlot)
	restoreAmmo(ply, snap.ammo)
	restoreMeds(ply, snap.meds)
end

function BALLISTICS.Gear.ClearMeds(ply)
	if not valid(ply) then return end
	local ids = medIds()
	for i = 1, #ids do
		setMed(ply, ids[i], 0)
	end
	if type(ply.pbMed) == "table" then ply.pbMed.out = nil end
end

if hook and hook.Add then
	-- Carried gear only lives inside one game: drop it at the firing squad,
	-- back in the lobby, and (already) at a new match.
	hook.Add("Ballistics_PhaseChanged", "Ballistics_GearDrop", function(_, new)
		if new == "squad" or new == "lobby" then BALLISTICS.Gear.Reset() end
	end)
	hook.Add("Ballistics_MatchEnd", "Ballistics_GearDrop", function() BALLISTICS.Gear.Reset() end)
	hook.Add("Ballistics_RoundEnd", "Ballistics_GearKeep", function(winner)
		BALLISTICS.Gear.Capture(winner)
	end)
end
