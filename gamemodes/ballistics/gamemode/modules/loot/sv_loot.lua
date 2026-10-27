-- Server loot sessions. One looter per body. Dead targets use the snapshot
-- taken in DoPlayerDeath, before the gamemode wipes them. Unconscious and
-- awake targets use the weapons they are actually holding.
-- Dropped guns are real weapon entities in front of the looter, marked
-- BallisticsLootDrop so round cleanup can remove the ones nobody picked up.
-- Own inventory drops grenades as the catalog ammo entity (one each, unless
-- that entity accepts an ammo count) and meds as the catalog med entity,
-- one per med. Ammo rows are not dropped.
-- +use is not hooked here. Player Ballistics drag stays on its own key.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loot = BALLISTICS.Loot or {}

local L = BALLISTICS.Loot
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local snaps = {}
local byBody = {}
local sessions = {}
local locks = {}
local last = {}

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

local function playerById(id)
	if type(id) ~= "string" or id == "" then return nil end
	local found
	eachPlayer(function(ply)
		if not found and playerId(ply) == id then found = ply end
	end)
	return found
end

local function phase()
	if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
		return BALLISTICS.Round.Phase() or "lobby"
	end
	return "lobby"
end

local function classOf(ent)
	if ent == nil or type(ent.GetClass) ~= "function" then return "" end
	local ok, class = pcall(ent.GetClass, ent)
	if ok and type(class) == "string" then return class end
	return ""
end

local function bodyIdOf(ent)
	if ent == nil then return nil end
	if type(ent.bd_id) == "string" and ent.bd_id ~= "" then return ent.bd_id end
	if type(ent.GetNWString) == "function" then
		local ok, id = pcall(ent.GetNWString, ent, "bd_id", "")
		if ok and type(id) == "string" and id ~= "" then return id end
	end
	return nil
end

local function knifeOf(ply)
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.Knife) == "function" then
		local knife = BALLISTICS.Loadout.Knife(ply)
		if type(knife) == "string" and knife ~= "" then return knife end
	end
	return L.KNIFE
end

local function isKnife(ply, class)
	if type(class) ~= "string" or class == "" then return true end
	if class == L.KNIFE or class == knifeOf(ply) then return true end
	return false
end

local function numberCall(fn, self)
	if type(fn) ~= "function" then return 0 end
	local ok, got = pcall(fn, self)
	got = ok and tonumber(got) or nil
	if not got or got ~= got or got < 0 or got == math.huge then return 0 end
	return math.floor(got)
end

local function aliveOf(ply)
	return valid(ply) and type(ply.Alive) == "function" and ply:Alive() == true
end

local function consciousOf(ply)
	if not aliveOf(ply) then return false end
	if BALLISTICS.IsConscious then return BALLISTICS.IsConscious(ply) == true end
	return true
end

-- Dead is its own error. Spectating is an observer mode while still alive.
local function spectatingOf(ply)
	if not aliveOf(ply) then return false end
	if type(ply.GetObserverMode) ~= "function" then return false end
	local ok, mode = pcall(ply.GetObserverMode, ply)
	if not ok or type(mode) ~= "number" then return false end
	return mode ~= (OBS_MODE_NONE or 0)
end

local function slottedOf(ply)
	if not (BALLISTICS.Slots and type(BALLISTICS.Slots.TeamOf) == "function") then return false end
	local teamId = BALLISTICS.Slots.TeamOf(ply)
	return teamId == GOOD or teamId == BAD
end

local function selfCtx(ply)
	return {
		phase = phase(),
		alive = aliveOf(ply),
		spectating = spectatingOf(ply),
		slotted = slottedOf(ply),
		conscious = consciousOf(ply),
	}
end

local function pointOf(ent)
	if ent == nil then return nil end
	if type(ent.WorldSpaceCenter) == "function" then
		local ok, pos = pcall(ent.WorldSpaceCenter, ent)
		if ok and pos ~= nil then return pos end
	end
	if type(ent.GetPos) == "function" then
		local ok, pos = pcall(ent.GetPos, ent)
		if ok and pos ~= nil then return pos end
	end
	return nil
end

local function eyeOf(ply)
	if ply == nil or type(ply.EyePos) ~= "function" then return nil end
	local ok, pos = pcall(ply.EyePos, ply)
	if ok then return pos end
	return nil
end

local function distTo(ply, ent)
	local eye = eyeOf(ply)
	local dest = pointOf(ent)
	if eye == nil or dest == nil then return math.huge end
	if type(ent.NearestPoint) == "function" then
		local ok, near = pcall(ent.NearestPoint, ent, eye)
		if ok and near ~= nil then dest = near end
	end
	return L.Dist(eye, dest)
end

local function sees(ply, ent)
	if not (util and type(util.TraceLine) == "function") then return false end
	local eye = eyeOf(ply)
	local dest = pointOf(ent)
	if eye == nil or dest == nil then return false end
	local tr = util.TraceLine({
		start = eye,
		endpos = dest,
		filter = ply,
		mask = MASK_SHOT,
	})
	if type(tr) ~= "table" then return false end
	if tr.Entity == ent then return true end
	if tr.Hit == false or tr.Fraction == 1 then return true end
	return false
end

local function ownerOf(ent)
	local pb = PLAYER_BALLISTICS
	if pb and type(pb.RagdollOwner) == "function" then
		local ok, owner = pcall(pb.RagdollOwner, ent)
		if ok and valid(owner) then return owner end
	end
	local bd = BODY_DAMAGE
	if bd and type(bd.GetBodyEntity) == "function" then
		local ok, owner = pcall(bd.GetBodyEntity, ent, "pb_owner")
		if ok and valid(owner) and type(owner.IsPlayer) == "function" and owner:IsPlayer() then
			return owner
		end
	end
	if valid(ent.bd_owner) and type(ent.bd_owner.IsPlayer) == "function" and ent.bd_owner:IsPlayer() then
		return ent.bd_owner
	end
	return nil
end

local function markedId(ent)
	if type(ent.balLootId) == "string" and ent.balLootId ~= "" then return ent.balLootId end
	if type(ent.GetNW2String) == "function" then
		local ok, id = pcall(ent.GetNW2String, ent, "bal_loot_id", "")
		if ok and type(id) == "string" and id ~= "" then return id end
	end
	return nil
end

local function markBody(ent, id)
	if not valid(ent) or type(id) ~= "string" or id == "" then return end
	ent.balLootId = id
	if type(ent.SetNW2String) == "function" then
		pcall(ent.SetNW2String, ent, "bal_loot_id", id)
	end
	local body = bodyIdOf(ent)
	if body then byBody[body] = id end
end

local function findBodies(ply)
	local list = {}
	local seen = {}
	local function add(ent)
		if not valid(ent) or seen[ent] then return end
		seen[ent] = true
		list[#list + 1] = ent
	end
	if type(ply.GetRagdollEntity) == "function" then
		local ok, rag = pcall(ply.GetRagdollEntity, ply)
		if ok then add(rag) end
	end
	local bd = BODY_DAMAGE
	if bd and type(bd.FindRecord) == "function" then
		local ok, rec = pcall(bd.FindRecord, ply)
		if ok and type(rec) == "table" then
			add(rec.corpse)
			add(rec.puppet)
			if type(rec.id) == "string" and rec.id ~= "" then
				byBody[rec.id] = playerId(ply)
			end
		end
	end
	local pb = PLAYER_BALLISTICS
	if pb and type(pb.Bodies) == "table" then
		local id = playerId(ply)
		local steam = type(ply.SteamID64) == "function" and ply:SteamID64() or nil
		for i = 1, #pb.Bodies do
			local entry = pb.Bodies[i]
			if type(entry) == "table" then
				local mine = entry.steam == steam or entry.steam == id or (entry.id ~= nil and byBody[entry.id] == id)
				if mine then add(entry.ent) end
			end
		end
	end
	return list
end

local function tagBodies(ply)
	local id = playerId(ply)
	if not id then return end
	local bodies = findBodies(ply)
	for i = 1, #bodies do
		markBody(bodies[i], id)
	end
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
	return 0
end

local function ammoCount(ply, ammoType)
	if type(ammoType) ~= "string" or ammoType == "" then return 0 end
	if type(ply.GetAmmoCount) ~= "function" then return 0 end
	local ok, n = pcall(ply.GetAmmoCount, ply, ammoType)
	n = ok and tonumber(n) or 0
	if n == nil or n ~= n or n < 0 then return 0 end
	return math.floor(n)
end

local function setAmmo(ply, ammoType, count)
	if type(ammoType) ~= "string" or ammoType == "" or ammoType == "none" then return end
	count = math.floor(tonumber(count) or 0)
	if count < 0 then count = 0 end
	if type(ply.SetAmmo) == "function" then
		pcall(ply.SetAmmo, ply, count, ammoType)
	end
end

local function captureGun(wep)
	if wep == nil or type(wep.GetClass) ~= "function" then return nil end
	local ok, class = pcall(wep.GetClass, wep)
	if not ok or type(class) ~= "string" or class == "" then return nil end
	local ammo, clip = nil, nil
	if BALLISTICS.Buy and type(BALLISTICS.Buy.WeaponAmmo) == "function" then
		ammo, clip = BALLISTICS.Buy.WeaponAmmo(wep)
	end
	if type(ammo) ~= "string" or ammo == "" or ammo == "none" then ammo = nil end
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
		name = L.WeaponName(class),
		clip1 = numberCall(wep.Clip1, wep),
		clip2 = numberCall(wep.Clip2, wep),
		ammo = ammo,
		clip = clip,
		attachments = atts,
	}
end

local function readGuns(ply)
	local captured = {}
	if type(ply.GetWeapons) == "function" then
		local ok, weps = pcall(ply.GetWeapons, ply)
		if ok and type(weps) == "table" then
			for i = 1, #weps do
				local gun = captureGun(weps[i])
				if gun and not isKnife(ply, gun.class) then
					captured[gun.class] = gun
				end
			end
		end
	end
	local order = {}
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.Guns) == "function" then
		local guns = BALLISTICS.Loadout.Guns(ply)
		if type(guns) == "table" then order = guns end
	end
	if #order == 0 then
		for class in pairs(captured) do
			order[#order + 1] = class
		end
		table.sort(order)
	end
	local list = {}
	local maxGuns = (L.Caps(BALLISTICS.Config).guns) or L.GUNS
	for i = 1, #order do
		local gun = captured[order[i]]
		if gun and #list < maxGuns then
			list[#list + 1] = gun
		end
	end
	return list
end

function L.ReadLive(ply)
	local inv = L.Blank()
	if not valid(ply) then return inv end
	inv.guns = readGuns(ply)
	local nades = BALLISTICS.Catalog and BALLISTICS.Catalog.Throwables and BALLISTICS.Catalog.Throwables() or {}
	for i = 1, #nades do
		local item = nades[i]
		inv.nades[item.key] = ammoCount(ply, item.ammo)
	end
	local meds = BALLISTICS.Catalog and BALLISTICS.Catalog.Meds and BALLISTICS.Catalog.Meds() or {}
	for i = 1, #meds do
		local item = meds[i]
		inv.meds[item.key] = medHave(ply, item.id)
	end
	local seen = {}
	for i = 1, #inv.guns do
		local ammo = inv.guns[i].ammo
		if type(ammo) == "string" and ammo ~= "" and not seen[ammo] and not L.NadeByAmmo(ammo) then
			seen[ammo] = true
			inv.ammo[ammo] = ammoCount(ply, ammo)
		end
	end
	return inv
end

function L.RememberDeath(ply)
	local id = playerId(ply)
	if not id or not valid(ply) then return end
	snaps[id] = L.Clone(L.ReadLive(ply))
	local body = bodyIdOf(ply)
	if body then byBody[body] = id end
end

function L.ForgetDeath(ply)
	local id = playerId(ply)
	if not id then return end
	snaps[id] = nil
	local drop = {}
	for body, owner in pairs(byBody) do
		if owner == id then drop[#drop + 1] = body end
	end
	for i = 1, #drop do
		byBody[drop[i]] = nil
	end
end

local function resolve(ent, looter)
	if not valid(ent) or ent == looter then return nil, "target" end
	local looterId = playerId(looter)
	if type(ent.IsPlayer) == "function" and ent:IsPlayer() == true then
		local id = playerId(ent)
		if not id or id == looterId then return nil, "self" end
		return { ent = ent, owner = ent, ownerId = id, kind = "player" }
	end
	local class = classOf(ent)
	local rag = class == "prop_ragdoll"
	if not rag and type(ent.IsRagdoll) == "function" then
		rag = ent:IsRagdoll() == true
	end
	if not rag then return nil, "target" end
	local owner = ownerOf(ent)
	local id = owner and playerId(owner) or nil
	if not id then
		local body = bodyIdOf(ent)
		if body then id = byBody[body] end
	end
	if not id then id = markedId(ent) end
	if type(id) ~= "string" or id == "" or id == looterId then
		if id == looterId then return nil, "self" end
		return nil, "target"
	end
	if not valid(owner) then owner = playerById(id) end
	return {
		ent = ent,
		owner = valid(owner) and owner or nil,
		ownerId = id,
		kind = "corpse",
	}
end

local function modeOf(subject)
	local owner = subject and subject.owner or nil
	return L.TargetMode(aliveOf(owner), consciousOf(owner))
end

local function readSubject(subject, mode)
	if mode == "dead" or not aliveOf(subject.owner) then
		local snap = snaps[subject.ownerId]
		if type(snap) ~= "table" then
			snap = L.Blank()
			snaps[subject.ownerId] = snap
		end
		return L.Clone(snap), true
	end
	return L.ReadLive(subject.owner), false
end

local function publish(ply, state)
	local id = playerId(ply)
	if id then last[id] = state end
	if BALLISTICS.Net and BALLISTICS.Net.Send then
		BALLISTICS.Net.Send("bal_loot_state", ply, state)
	end
end

function L.Last(ply)
	local id = playerId(ply)
	if not id then return nil end
	return last[id]
end

local function tell(ply, err)
	local text = L.Note(err) or ""
	if text ~= "" and ply ~= nil and type(ply.ChatPrint) == "function" then
		ply:ChatPrint("Ballistics: " .. text)
	end
	return text
end

-- Player Ballistics clamps each med to its own MedMax. The loot cap is the
-- lower of that and MedsMax, so a transfer is not planned past what GiveMed keeps.
local function capsNow()
	local caps = L.Caps(BALLISTICS.Config)
	if BALLISTICS.MedMax then
		local pbMax = tonumber(BALLISTICS.MedMax())
		if pbMax ~= nil and pbMax == pbMax and pbMax ~= math.huge and pbMax < caps.meds then
			caps.meds = math.floor(pbMax)
			if caps.meds < 0 then caps.meds = 0 end
		end
	end
	return caps
end

local function publishSession(session, note)
	local mode = session.mode
	local them = readSubject(session, mode)
	local you = L.ReadLive(session.looter)
	local caps = capsNow()
	local infinite = L.InfiniteAmmo(BALLISTICS.Config, phase())
	publish(session.looter, L.View(you, them, {
		open = true,
		giveOnly = L.GiveOnly(mode),
		infinite = infinite,
		note = note or "",
		caps = caps,
	}))
end

local function publishSelf(session, note)
	local you = L.ReadLive(session.looter)
	local caps = capsNow()
	local infinite = L.InfiniteAmmo(BALLISTICS.Config, phase())
	publish(session.looter, L.View(you, L.Blank(), {
		open = true,
		self = true,
		giveOnly = false,
		infinite = infinite,
		note = note or "",
		caps = caps,
	}))
end

function L.Close(ply, err)
	local id = playerId(ply)
	if not id then return false end
	local session = sessions[id]
	if not session then return false end
	L.Unlock(locks, session.key, id)
	sessions[id] = nil
	local text = ""
	if err ~= nil then text = tell(ply, err) end
	publish(ply, { open = false, note = text })
	return true
end

function L.Reset()
	local open = {}
	for _, session in pairs(sessions) do
		open[#open + 1] = session.looter
	end
	for i = 1, #open do
		L.Close(open[i], "phase")
	end
	snaps = {}
	byBody = {}
	locks = {}
end

local function measure(ply, ent)
	return distTo(ply, ent), sees(ply, ent)
end

function L.Open(ply, ent)
	if not valid(ply) then return false, "alive" end
	local id = playerId(ply)
	if not id then return false, "alive" end
	local subject, why = resolve(ent, ply)
	if not subject then
		tell(ply, why or "target")
		publish(ply, { open = false, note = L.Note(why or "target") or "" })
		return false, why or "target"
	end
	local key = L.BodyKey(subject.ownerId)
	local dist, los = measure(ply, subject.ent)
	local busy = key ~= nil and locks[key] ~= nil and locks[key] ~= id
	local ok, err = L.CanOpen({
		phase = phase(),
		alive = aliveOf(ply),
		conscious = consciousOf(ply),
		self = false,
		target = subject.kind,
		dist = dist,
		range = L.Range(BALLISTICS.Config),
		los = los,
		busy = busy,
	})
	if not ok then
		tell(ply, err)
		publish(ply, { open = false, note = L.Note(err) or "" })
		return false, err
	end
	local previous = sessions[id]
	if previous and previous.key ~= key then
		L.Unlock(locks, previous.key, id)
	end
	if not L.Lock(locks, key, id) then
		tell(ply, "busy")
		publish(ply, { open = false, note = L.Note("busy") or "" })
		return false, "busy"
	end
	local mode = modeOf(subject)
	sessions[id] = {
		looter = ply,
		looterId = id,
		ent = subject.ent,
		owner = subject.owner,
		ownerId = subject.ownerId,
		key = key,
		mode = mode,
	}
	if mode == "dead" and snaps[subject.ownerId] == nil then
		snaps[subject.ownerId] = L.Blank()
	end
	publishSession(sessions[id], "")
	return true
end

-- looter == owner. No body lock, no range, no line of sight.
function L.OpenSelf(ply)
	if not valid(ply) then return false, "alive" end
	local id = playerId(ply)
	if not id then return false, "alive" end
	local ok, err = L.CanOpenSelf(selfCtx(ply))
	if not ok then
		tell(ply, err)
		publish(ply, { open = false, note = L.Note(err) or "" })
		return false, err
	end
	local previous = sessions[id]
	if previous and previous.key then
		L.Unlock(locks, previous.key, id)
	end
	sessions[id] = {
		looter = ply,
		looterId = id,
		ent = ply,
		owner = ply,
		ownerId = id,
		key = nil,
		mode = "self",
		self = true,
	}
	publishSelf(sessions[id], "")
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

local function giveGun(ply, gun)
	if type(ply.Give) ~= "function" then return false end
	local wep = ply:Give(gun.class, true)
	if not valid(wep) and type(ply.GetWeapon) == "function" then
		wep = ply:GetWeapon(gun.class)
	end
	if not valid(wep) then return false end
	local atts = gun.attachments or {}
	for i = 1, #atts do
		installAtt(wep, atts[i].slot, atts[i].att)
	end
	if type(wep.SetClip1) == "function" then pcall(wep.SetClip1, wep, tonumber(gun.clip1) or 0) end
	if type(wep.SetClip2) == "function" then pcall(wep.SetClip2, wep, tonumber(gun.clip2) or 0) end
	if type(wep.NetworkWeapon) == "function" then pcall(wep.NetworkWeapon, wep) end
	return true
end

local function stripGun(ply, class)
	if type(class) ~= "string" or class == "" then return end
	if type(ply.StripWeapon) == "function" then
		pcall(ply.StripWeapon, ply, class)
		return
	end
	if type(ply.GetWeapon) ~= "function" then return end
	local wep = ply:GetWeapon(class)
	if valid(wep) and type(wep.Remove) == "function" then pcall(wep.Remove, wep) end
end

local function gunMap(inv)
	local map = {}
	local guns = type(inv) == "table" and inv.guns or {}
	for i = 1, #guns do
		local gun = guns[i]
		if gun and gun.class then map[gun.class] = gun end
	end
	return map
end

local function applyMeds(ply, before, after)
	local keys = {}
	for key in pairs(before or {}) do keys[key] = true end
	for key in pairs(after or {}) do keys[key] = true end
	for key in pairs(keys) do
		local want = math.floor(tonumber(after[key]) or 0)
		local have = math.floor(tonumber(before[key]) or 0)
		local delta = want - have
		if delta ~= 0 then
			local item = BALLISTICS.Catalog and BALLISTICS.Catalog.Get and BALLISTICS.Catalog.Get(key)
			local id = item and item.id
			if id ~= nil and BALLISTICS.GiveMed then
				BALLISTICS.GiveMed(ply, id, delta)
			elseif id ~= nil and type(ply.pbMed) == "table" and type(ply.pbMed.counts) == "table" then
				local nextCount = (tonumber(ply.pbMed.counts[id]) or 0) + delta
				if nextCount < 0 then nextCount = 0 end
				ply.pbMed.counts[id] = nextCount
			end
		end
	end
end

local function applyNamed(ply, before, after, ammoOf)
	local keys = {}
	for key in pairs(before or {}) do keys[key] = true end
	for key in pairs(after or {}) do keys[key] = true end
	for key in pairs(keys) do
		local want = math.floor(tonumber(after[key]) or 0)
		local have = math.floor(tonumber(before[key]) or 0)
		if want ~= have then
			local ammo = ammoOf(key)
			if ammo then setAmmo(ply, ammo, want) end
		end
	end
end

local function applyLive(ply, before, after, infinite)
	if not valid(ply) then return false end
	local oldGuns = gunMap(before)
	local newGuns = gunMap(after)
	for class, gun in pairs(newGuns) do
		if not oldGuns[class] then
			if not giveGun(ply, gun) then return false end
		end
	end
	for class in pairs(oldGuns) do
		if not newGuns[class] then stripGun(ply, class) end
	end
	local order = {}
	local guns = after.guns or {}
	for i = 1, #guns do
		order[i] = guns[i].class
	end
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.Restore) == "function" then
		BALLISTICS.Loadout.Restore(ply, order)
	end
	applyMeds(ply, before.meds, after.meds)
	applyNamed(ply, before.nades, after.nades, function(key)
		local item = BALLISTICS.Catalog and BALLISTICS.Catalog.Get and BALLISTICS.Catalog.Get(key)
		return item and item.ammo or nil
	end)
	if infinite ~= true then
		applyNamed(ply, before.ammo, after.ammo, function(key) return key end)
	end
	return true
end

local function asVector(pos)
	if Vector then return Vector(pos.x or 0, pos.y or 0, pos.z or 0) end
	return pos
end

local function markDrop(ent)
	ent.BallisticsLootDrop = true
	if type(ent.SetNW2Bool) == "function" then
		pcall(ent.SetNW2Bool, ent, "bal_loot_drop", true)
	end
end

-- Weapons auto-pickup on touch, and Player Ballistics meds do it in StartTouch.
-- StripWeapon also drops the held gun and deletes it; if the new entity was
-- already back in the player's hands, that delete removes the only copy.
local function armGrace(ply, ent)
	if ent == nil then return end
	local grace = tonumber(L.DROP_GRACE) or 1.5
	local nowT = (CurTime and CurTime()) or 0
	ent.BallisticsDropOwner = ply
	ent.BallisticsDropUntil = nowT + grace
	-- Instance methods shadow the scripted table. Spawn can copy the ENT
	-- method back over a wrap done before it, so this is safe to call again.
	local function wrap(name)
		local old = ent[name]
		if type(old) ~= "function" then return end
		-- The saved function is the wrap itself. Spawn replacing the method
		-- makes them differ, so the new method gets wrapped too.
		if ent["balWrapFn" .. name] == old then return end
		local function wrapped(self, toucher)
			local t = (CurTime and CurTime()) or 0
			if L.PickupBlocked(toucher, self, t) then return end
			return old(self, toucher)
		end
		ent["balWrapFn" .. name] = wrapped
		ent[name] = wrapped
	end
	wrap("StartTouch")
	wrap("Touch")
	wrap("Use")
end

local function dropSpot(ply, nudge)
	local origin = { x = 0, y = 0, z = 0 }
	if type(ply.GetPos) == "function" then
		local ok, got = pcall(ply.GetPos, ply)
		if ok and got ~= nil then origin = got end
	end
	local forward = nil
	if type(ply.GetForward) == "function" then
		local ok, got = pcall(ply.GetForward, ply)
		if ok and got ~= nil then forward = got end
	end
	local pos = L.DropPos(origin, forward, L.DROP_DIST or 40, L.DROP_UP or 48)
	nudge = tonumber(nudge) or 0
	if nudge ~= 0 then pos.y = (tonumber(pos.y) or 0) + nudge end
	return pos
end

local function placeDrop(ply, ent, nudge)
	if not valid(ent) then return false end
	-- Before Spawn, so a touch during Spawn cannot re-equip it.
	armGrace(ply, ent)
	local pos = dropSpot(ply, nudge)
	local function put()
		if not valid(ent) or type(ent.SetPos) ~= "function" then return end
		pcall(ent.SetPos, ent, asVector(pos))
	end
	put()
	if type(ply.EyeAngles) == "function" and type(ent.SetAngles) == "function" then
		local ok, ang = pcall(ply.EyeAngles, ply)
		if ok and ang ~= nil then pcall(ent.SetAngles, ent, ang) end
	end
	if COLLISION_GROUP_WEAPON and type(ent.SetCollisionGroup) == "function" then
		pcall(ent.SetCollisionGroup, ent, COLLISION_GROUP_WEAPON)
	end
	if type(ent.Spawn) == "function" then
		local ok = pcall(ent.Spawn, ent)
		if not ok or not valid(ent) then
			if valid(ent) and type(ent.Remove) == "function" then pcall(ent.Remove, ent) end
			return false
		end
	end
	if not valid(ent) then return false end
	-- Spawn resets the origin on a lot of weapons. Put it back at chest
	-- height, then let it fall to the floor in front of the player.
	put()
	if type(ent.Activate) == "function" then pcall(ent.Activate, ent) end
	if not valid(ent) then return false end
	put()
	if type(ent.DropToFloor) == "function" then pcall(ent.DropToFloor, ent) end
	if not valid(ent) then return false end
	-- Spawn may have replaced the touch methods. Block the dropper again.
	armGrace(ply, ent)
	if type(ent.GetPhysicsObject) == "function" then
		local ok, phys = pcall(ent.GetPhysicsObject, ent)
		if ok and phys ~= nil and type(phys.Wake) == "function" then
			if not phys.IsValid or phys:IsValid() ~= false then pcall(phys.Wake, phys) end
		end
	end
	return valid(ent)
end

local function spawnDrop(ply, gun)
	if not (ents and type(ents.Create) == "function") then return nil end
	if type(gun) ~= "table" or type(gun.class) ~= "string" or gun.class == "" then return nil end
	local held = nil
	if type(ply.GetWeapon) == "function" then
		local ok, got = pcall(ply.GetWeapon, ply, gun.class)
		if ok then held = got end
	end
	local ent = ents.Create(gun.class)
	if not valid(ent) or ent == held then return nil end
	if not placeDrop(ply, ent, 0) then
		-- A failed spawn must not leave a half-made weapon, and must not be
		-- the gun the player is still holding.
		if valid(ent) and ent ~= held and type(ent.Remove) == "function" then pcall(ent.Remove, ent) end
		return nil
	end
	local atts = gun.attachments or {}
	for i = 1, #atts do
		installAtt(ent, atts[i].slot, atts[i].att)
	end
	if type(ent.SetClip1) == "function" then pcall(ent.SetClip1, ent, tonumber(gun.clip1) or 0) end
	if type(ent.SetClip2) == "function" then pcall(ent.SetClip2, ent, tonumber(gun.clip2) or 0) end
	if type(ent.NetworkWeapon) == "function" then pcall(ent.NetworkWeapon, ent) end
	if not valid(ent) then
		if ent ~= held and type(ent) == "table" and type(ent.Remove) == "function" then pcall(ent.Remove, ent) end
		return nil
	end
	markDrop(ent)
	return ent
end

-- A pickup that stores a count can take the whole stack. TacRP grenade ammo
-- entities grant 1 and have none of these, so each grenade is its own entity.
local function applyAmount(ent, n)
	n = math.floor(tonumber(n) or 0)
	if n < 1 or ent == nil then return false end
	if type(ent.SetAmmoCount) == "function" then
		local ok = pcall(ent.SetAmmoCount, ent, n)
		if ok then return true end
	end
	if type(ent.SetAmmo) == "function" then
		local ok = pcall(ent.SetAmmo, ent, n)
		if ok then return true end
	end
	if type(ent.AmmoCount) == "number" then
		ent.AmmoCount = n
		return true
	end
	return false
end

local function rollback(list)
	if type(list) ~= "table" then return end
	for i = 1, #list do
		local ent = list[i]
		if valid(ent) and type(ent.Remove) == "function" then pcall(ent.Remove, ent) end
	end
end

local function spawnPickup(ply, class, nudge)
	if not (ents and type(ents.Create) == "function") then return nil end
	if type(class) ~= "string" or class == "" then return nil end
	local ent = ents.Create(class)
	if not valid(ent) then return nil end
	if not placeDrop(ply, ent, nudge) then
		if valid(ent) and type(ent.Remove) == "function" then pcall(ent.Remove, ent) end
		return nil
	end
	markDrop(ent)
	return ent
end

-- Grenades: one entity with the stack count when the entity supports it,
-- otherwise one entity per grenade. Meds are always one entity per med.
local function spawnStack(ply, drop)
	if type(drop) ~= "table" then return false end
	local class = drop.entity
	local amount = math.floor(tonumber(drop.amount) or 0)
	if amount < 1 then return false end
	local made = {}
	local function one(i)
		local ent = spawnPickup(ply, class, (i - 1) * 8)
		if not ent then return false end
		made[#made + 1] = ent
		return true
	end
	if not one(1) then
		rollback(made)
		return false
	end
	if drop.kind == "nade" and amount > 1 and applyAmount(made[1], amount) then
		return true, made
	end
	for i = 2, amount do
		if not one(i) then
			rollback(made)
			return false
		end
	end
	return true, made
end

local function retarget(session)
	if valid(session.ent) then return true end
	local owner = session.owner
	if not valid(owner) then owner = playerById(session.ownerId) end
	session.owner = valid(owner) and owner or nil
	if session.owner then
		local bodies = findBodies(session.owner)
		if bodies[1] then
			session.ent = bodies[1]
			markBody(bodies[1], session.ownerId)
			return true
		end
		if aliveOf(session.owner) then
			session.ent = session.owner
			return true
		end
	end
	return false
end

-- True while this player has a loot window open (E then closes it, not drag).
function L.HasSession(ply)
	local id = playerId(ply)
	local session = id and sessions[id] or nil
	return session ~= nil and session.looter == ply
end

local function actSelf(ply, session, req)
	if req.kind == "close" then
		L.Close(ply, nil)
		return true
	end
	local shut, why = L.ShouldCloseSelf(selfCtx(ply))
	if shut then
		L.Close(ply, why)
		return false, why
	end
	-- Own slots do not move. Only a drop of a gun, grenade, or med.
	if req.from ~= "you" or req.to ~= "drop" then
		publishSelf(session, "")
		return false, "side"
	end
	if req.kind == "ammo" then
		publishSelf(session, L.Note("ammo") or "")
		return false, "ammo"
	end
	if req.kind ~= "gun" and req.kind ~= "nade" and req.kind ~= "med" then
		publishSelf(session, "")
		return false, "kind"
	end
	local infinite = L.InfiniteAmmo(BALLISTICS.Config, phase())
	local you = L.ReadLive(ply)
	local result = L.Transfer({
		you = you,
		them = L.Blank(),
		from = "you",
		kind = req.kind,
		key = req.key,
		amount = req.amount,
		to = "drop",
		slot = 0,
		whole = false,
		selfDrop = true,
		giveOnly = false,
		caps = capsNow(),
		infiniteAmmo = infinite,
		knife = knifeOf(ply),
	})
	if not result.ok then
		publishSelf(session, result.note or "")
		return false, result.err
	end
	-- The world entity has to exist before StripWeapon. StripWeapon drops the
	-- held gun and then deletes it; a spawn that failed must leave the gun on
	-- the player, and a spawn that landed back in their hands would be deleted
	-- with it.
	local spawned, made
	if req.kind == "gun" then
		spawned = spawnDrop(ply, result.drop)
		if spawned then made = { spawned } end
	else
		spawned, made = spawnStack(ply, result.drop)
	end
	if not spawned or (req.kind == "gun" and not valid(spawned)) then
		rollback(made)
		publishSelf(session, "Could not drop that.")
		return false, "drop"
	end
	if req.kind == "gun" then armGrace(ply, ply.GetWeapon and select(2, pcall(ply.GetWeapon, ply, req.key)) or nil) end
	-- Same writes as a loot transfer: StripWeapon, SetAmmo down to the
	-- remainder (grenades), GiveMed(ply, id, -n) for meds.
	if not applyLive(ply, you, result.you, infinite) then
		rollback(made)
		publishSelf(session, "Could not move that.")
		return false, "give"
	end
	publishSelf(session, "")
	return true
end

function L.Act(ply, req)
	local id = playerId(ply)
	local session = id and sessions[id] or nil
	if not session or session.looter ~= ply then
		publish(ply, { open = false, note = "" })
		return false, "phase"
	end
	req = type(req) == "table" and req or {}
	if session.self == true then
		return actSelf(ply, session, req)
	end
	if req.kind == "close" then
		L.Close(ply, nil)
		return true
	end
	if not retarget(session) then
		L.Close(ply, "target")
		return false, "target"
	end
	local mode = modeOf(session)
	session.mode = mode
	local dist, los = measure(ply, session.ent)
	local shut, why = L.ShouldClose({
		phase = phase(),
		alive = aliveOf(ply),
		conscious = consciousOf(ply),
		targetValid = true,
		dist = dist,
		range = L.Range(BALLISTICS.Config),
	})
	if shut then
		L.Close(ply, why)
		return false, why
	end
	if los ~= true then
		publishSession(session, L.Note("los") or "")
		return false, "los"
	end
	local infinite = L.InfiniteAmmo(BALLISTICS.Config, phase())
	local you = L.ReadLive(ply)
	local them, corpse = readSubject(session, mode)
	local result = L.Transfer({
		you = you,
		them = them,
		from = req.from,
		kind = req.kind,
		key = req.key,
		amount = req.amount,
		to = req.to,
		slot = req.slot,
		whole = req.whole == true,
		giveOnly = L.GiveOnly(mode),
		caps = capsNow(),
		infiniteAmmo = infinite,
		knife = knifeOf(ply),
	})
	if not result.ok then
		publishSession(session, result.note or "")
		return false, result.err
	end
	-- Spawn and keep the world entity first. StripWeapon (inside the commit)
	-- drops the held gun and then deletes it; if that delete is the only copy,
	-- or the commit fails, the player must still have their item.
	local dropped = nil
	if result.drop then
		dropped = spawnDrop(ply, result.drop)
		if not valid(dropped) then
			if dropped then rollback({ dropped }) end
			publishSession(session, "Could not drop that.")
			return false, "drop"
		end
		if req.kind == "gun" then
			local holder = req.from == "you" and ply or session.owner
			if type(holder) == "table" and type(holder.GetWeapon) == "function" then
				local okW, heldW = pcall(holder.GetWeapon, holder, req.key)
				if okW then armGrace(holder, heldW) end
			end
		end
	end
	-- The side that receives the item is applied first. A failed Give leaves
	-- the source untouched. A corpse has no Give: its snapshot is the record.
	local function commitLive(who, before, after)
		return applyLive(who, before, after, infinite)
	end
	local function failGive()
		if dropped then rollback({ dropped }) end
		publishSession(session, "Could not move that.")
		return false, "give"
	end
	local to = req.to
	if to == "you" then
		if not commitLive(ply, you, result.you) then return failGive() end
		if corpse then
			snaps[session.ownerId] = L.Clone(result.them)
		elseif not commitLive(session.owner, them, result.them) then
			return failGive()
		end
	elseif to == "them" then
		if corpse then
			snaps[session.ownerId] = L.Clone(result.them)
		elseif not commitLive(session.owner, them, result.them) then
			return failGive()
		end
		if not commitLive(ply, you, result.you) then return failGive() end
	elseif to == "drop" then
		if req.from == "you" then
			if not commitLive(ply, you, result.you) then return failGive() end
		elseif corpse then
			snaps[session.ownerId] = L.Clone(result.them)
		elseif not commitLive(session.owner, them, result.them) then
			return failGive()
		end
	end
	session.mode = modeOf(session)
	publishSession(session, "")
	return true
end

function L.Watch()
	local ids = {}
	for id in pairs(sessions) do
		ids[#ids + 1] = id
	end
	for i = 1, #ids do
		local session = sessions[ids[i]]
		if session then
			local ply = session.looter
			if not valid(ply) then
				L.Unlock(locks, session.key, session.looterId)
				sessions[ids[i]] = nil
			elseif session.self == true then
				local shut, why = L.ShouldCloseSelf(selfCtx(ply))
				if shut then L.Close(ply, why) end
			else
				local keep = retarget(session)
				local dist = keep and distTo(ply, session.ent) or math.huge
				local shut, why = L.ShouldClose({
					phase = phase(),
					alive = aliveOf(ply),
					conscious = consciousOf(ply),
					targetValid = keep,
					dist = dist,
					range = L.Range(BALLISTICS.Config),
				})
				if shut then
					L.Close(ply, why)
				else
					local mode = modeOf(session)
					if mode ~= session.mode then
						session.mode = mode
						publishSession(session, "")
					end
				end
			end
		end
	end
end

local function laterMark(ply)
	if not (timer and timer.Simple) then
		tagBodies(ply)
		return
	end
	timer.Simple(0, function()
		if valid(ply) then tagBodies(ply) end
	end)
	timer.Simple(0.05, function()
		if valid(ply) then tagBodies(ply) end
	end)
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_loot_open", function(ply, idx)
		local ent = nil
		idx = tonumber(idx) or 0
		if idx > 0 and Entity then ent = Entity(idx) end
		local ok, why = L.Open(ply, ent)
		print("[Ballistics loot] open request from " .. tostring(ply) .. " -> " .. tostring(ent) .. ": " .. tostring(ok) .. " " .. tostring(why or ""))
	end, {
		rate = 4,
		read = function()
			return net.ReadUInt(16)
		end,
	})

	BALLISTICS.Net.Register("bal_loot_self", function(ply)
		L.OpenSelf(ply)
	end, { rate = 8 })

	BALLISTICS.Net.Register("bal_loot_act", function(ply, req)
		L.Act(ply, req)
	end, {
		rate = 12,
		read = function()
			return L.ReadAct({
				string = function() return net.ReadString() end,
				uint16 = function() return net.ReadUInt(16) end,
				uint8 = function() return net.ReadUInt(8) end,
				bool = function() return net.ReadBool() end,
			})
		end,
	})

	BALLISTICS.Net.Register("bal_loot_state", nil, {
		write = function(payload)
			L.WriteState({
				bool = function(v) net.WriteBool(v and true or false) end,
				string = function(v) net.WriteString(v or "") end,
				uint8 = function(n) net.WriteUInt(n or 0, 8) end,
				uint16 = function(n) net.WriteUInt(n or 0, 16) end,
			}, payload)
		end,
	})
end

if hook and hook.Add then
	-- Before GM:DoPlayerDeath wipes weapons, ammo, and meds.
	hook.Add("DoPlayerDeath", "Ballistics_LootSnap", function(ply)
		L.RememberDeath(ply)
	end)
	hook.Add("PlayerDeath", "Ballistics_Loot", function(ply)
		local id = playerId(ply)
		if id and sessions[id] then L.Close(ply, "alive") end
		for _, session in pairs(sessions) do
			if session.self ~= true and (session.owner == ply or session.ownerId == id) then
				session.mode = "dead"
				session.owner = valid(ply) and ply or session.owner
				publishSession(session, "")
			end
		end
		laterMark(ply)
	end)
	hook.Add("PlayerSpawn", "Ballistics_Loot", function(ply)
		L.ForgetDeath(ply)
	end)
	hook.Add("PlayerDisconnected", "Ballistics_Loot", function(ply)
		local id = playerId(ply)
		local drop = {}
		for _, session in pairs(sessions) do
			if session.looter == ply or session.owner == ply or session.ownerId == id then
				drop[#drop + 1] = session.looter
			end
		end
		for i = 1, #drop do
			L.Close(drop[i], "target")
		end
		if id then
			snaps[id] = nil
			last[id] = nil
		end
	end)
	hook.Add("Ballistics_PhaseChanged", "Ballistics_Loot", function(_, new)
		if new ~= "live" and new ~= "post" then L.Reset() end
	end)
	hook.Add("WeaponEquip", "Ballistics_LootDrop", function(wep)
		if wep ~= nil then wep.BallisticsLootDrop = nil end
	end)
end

if timer and timer.Create then
	timer.Create("Ballistics_LootWatch", L.WATCH, 0, function()
		L.Watch()
	end)
end
