-- Tracks knife + gun order and selects a loadout slot. TacRP is not edited.
-- A bought gun is selected here, twice: immediately and on the next tick,
-- because TacRP deploy can put the previous weapon back in the same frame.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loadout = BALLISTICS.Loadout or {}

local L = BALLISTICS.Loadout

local gunsOf = {}
local knifeOf = {}
local twinOf = {}
local liveSlotOf = {}

local function playerId(ply)
	if BALLISTICS.PlayerId then return BALLISTICS.PlayerId(ply) end
	return nil
end

local function weaponClass(wep)
	if type(wep) == "string" and wep ~= "" then return wep end
	if wep == nil or type(wep.GetClass) ~= "function" then return nil end
	local ok, class = pcall(wep.GetClass, wep)
	if ok and type(class) == "string" and class ~= "" then return class end
	return nil
end

local function carriedClasses(ply)
	local list = {}
	local seen = {}
	local function add(class)
		if type(class) ~= "string" or class == "" or seen[class] then return end
		seen[class] = true
		list[#list + 1] = class
	end
	local sawWeapons = false
	if ply ~= nil and type(ply.GetWeapons) == "function" then
		local ok, weps = pcall(ply.GetWeapons, ply)
		if ok and type(weps) == "table" then
			sawWeapons = true
			for i = 1, #weps do
				local wep = weps[i]
				if wep ~= nil and not (type(wep.IsValid) == "function" and wep:IsValid() == false) then
					add(weaponClass(wep))
				end
			end
		end
	end
	if ply ~= nil and type(ply.HasWeapon) == "function" then
		local id = playerId(ply)
		local knife = id and knifeOf[id] or nil
		if knife and ply:HasWeapon(knife) == true then add(knife) end
		-- Noted guns stay in order even when GetWeapons has not caught up.
		local remembered = id and gunsOf[id]
		if type(remembered) == "table" then
			for i = 1, L.MAX_GUNS or 2 do
				local class = remembered[i]
				if type(class) == "string" and class ~= "" and ply:HasWeapon(class) == true then add(class) end
			end
		end
		if not sawWeapons and BALLISTICS.Catalog and BALLISTICS.Catalog.Weapons then
			local weapons = BALLISTICS.Catalog.Weapons()
			if type(weapons) == "table" then
				for i = 1, #weapons do
					local class = weapons[i] and weapons[i].class
					if ply:HasWeapon(class) == true then add(class) end
				end
			end
		end
	end
	return list
end

local function storedGuns(id)
	local guns = gunsOf[id]
	if type(guns) ~= "table" then return {} end
	return guns
end

local function twinExtra(id)
	local twin = id and twinOf[id] or nil
	if type(twin) == "table" and type(twin.class) == "string" and twin.class ~= "" then
		return twin.class
	end
	return nil
end

local function validEnt(ent)
	if ent == nil or ent == false then return false end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	if IsValid then return IsValid(ent) == true end
	return type(ent) == "table"
end

local function numberCall(fn, self)
	if type(fn) ~= "function" then return 0 end
	local ok, got = pcall(fn, self)
	got = ok and tonumber(got) or nil
	if not got or got ~= got or got < 0 or got == math.huge then return 0 end
	return math.floor(got)
end

local function publish(ply)
	if ply == nil or type(ply.SetNW2String) ~= "function" then return end
	local id = playerId(ply)
	local slots = id and gunsOf[id] or nil
	pcall(ply.SetNW2String, ply, "bal_slots", L.EncodeSlots(slots))
	local live = id and liveSlotOf[id] or 0
	if type(ply.SetNW2Int) == "function" then
		pcall(ply.SetNW2Int, ply, "bal_live", tonumber(live) or 0)
	end
end

function L.Reset(ply, knifeClass)
	local id = playerId(ply)
	if not id then return end
	gunsOf[id] = {}
	twinOf[id] = nil
	liveSlotOf[id] = nil
	if type(knifeClass) ~= "string" or knifeClass == "" then knifeClass = nil end
	knifeOf[id] = knifeClass
	publish(ply)
end

function L.Knife(ply)
	local id = playerId(ply)
	if not id then return nil end
	return knifeOf[id]
end

local function copySlots(slots)
	local out = {}
	for i = 1, L.MAX_GUNS or 2 do out[i] = type(slots) == "table" and slots[i] or false end
	return out
end

-- Fixed slot table: { [1] = key-1 class or false, [2] = key-2 class or false }.
function L.Slots(ply)
	local id = playerId(ply)
	if not id then return copySlots(nil) end
	local knife, _, slots = L.Resolve(storedGuns(id), carriedClasses(ply), knifeOf[id], twinExtra(id))
	gunsOf[id] = slots
	if knife and not knifeOf[id] then knifeOf[id] = knife end
	publish(ply)
	return copySlots(slots)
end

-- Carried guns in slot order, empties skipped.
function L.Guns(ply)
	return L.Compact(L.Slots(ply))
end

function L.GunCount(ply)
	return #L.Guns(ply)
end

function L.NoteGun(ply, class)
	local id = playerId(ply)
	if not id or type(class) ~= "string" or class == "" then return false end
	if class == knifeOf[id] then return false end
	local prev = storedGuns(id)
	local had = 0
	for i = 1, L.MAX_GUNS do
		if prev[i] == class then had = had + 1 end
	end
	local carried = carriedClasses(ply)
	local found = false
	for i = 1, #carried do
		if carried[i] == class then found = true break end
	end
	if not found then carried[#carried + 1] = class end
	local _, _, slots = L.Resolve(prev, carried, knifeOf[id], twinExtra(id))
	gunsOf[id] = slots
	local placed = nil
	for i = 1, L.MAX_GUNS do
		if slots[i] == class then
			if placed == nil then placed = i end
			-- A first copy of this class becomes the live slot.
			if had < 1 and liveSlotOf[id] == nil then liveSlotOf[id] = i end
		end
	end
	publish(ply)
	return placed ~= nil
end

-- classes: a fixed slot table (false = empty) or a list in slot order.
function L.Restore(ply, classes)
	local id = playerId(ply)
	if not id then return end
	local carried = {}
	if type(classes) == "table" then
		for i = 1, math.max(#classes, L.MAX_GUNS) do
			local class = classes[i]
			if type(class) == "string" and class ~= "" then carried[#carried + 1] = class end
		end
	end
	local extra = twinExtra(id) or L.TwinClassOf(classes)
	local _, _, slots = L.Resolve(classes, carried, knifeOf[id], extra)
	gunsOf[id] = slots
	local live = liveSlotOf[id]
	if live ~= 1 and live ~= 2 then
		for i = 1, L.MAX_GUNS do
			if type(slots[i]) == "string" and slots[i] ~= "" then
				liveSlotOf[id] = i
				break
			end
		end
	end
	publish(ply)
end

function L.Twin(ply)
	local id = playerId(ply)
	if not id then return nil end
	return L.CopyTwin(twinOf[id])
end

function L.SetTwin(ply, gun)
	local id = playerId(ply)
	if not id then return false end
	local row = L.CopyTwin(gun)
	twinOf[id] = row
	return row ~= nil
end

function L.ClearTwin(ply)
	local id = playerId(ply)
	if not id then return end
	twinOf[id] = nil
end

function L.LiveSlot(ply)
	local id = playerId(ply)
	if not id then return nil end
	local n = tonumber(liveSlotOf[id])
	if n == 1 or n == 2 then return n end
	return nil
end

function L.SetLiveSlot(ply, slot)
	local id = playerId(ply)
	if not id then return end
	slot = tonumber(slot)
	if slot == 1 or slot == 2 then
		liveSlotOf[id] = slot
	else
		liveSlotOf[id] = nil
	end
	publish(ply)
end

-- Same capture shape as loot's captureGun: class, clip1, ammo, attachments.
function L.CaptureGun(wep)
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
	local name = class
	if BALLISTICS.Loot and type(BALLISTICS.Loot.WeaponName) == "function" then
		name = BALLISTICS.Loot.WeaponName(class) or class
	end
	return {
		class = class,
		name = name,
		clip1 = numberCall(wep.Clip1, wep),
		clip2 = numberCall(wep.Clip2, wep),
		ammo = ammo,
		clip = clip,
		attachments = atts,
	}
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

-- Install attachments and set the magazine on a TacRP weapon (live or world).
function L.ApplyGun(wep, gun)
	if wep == nil or type(gun) ~= "table" then return false end
	local atts = gun.attachments or {}
	for i = 1, #atts do
		local row = atts[i]
		if type(row) == "table" then installAtt(wep, row.slot, row.att) end
	end
	if type(wep.SetClip1) == "function" then pcall(wep.SetClip1, wep, tonumber(gun.clip1) or 0) end
	if type(wep.SetClip2) == "function" then pcall(wep.SetClip2, wep, tonumber(gun.clip2) or 0) end
	if type(wep.NetworkWeapon) == "function" then pcall(wep.NetworkWeapon, wep) end
	return true
end

-- Capture the live entity into the twin store, apply the stored twin onto it.
function L.SwapTwin(ply, toSlot)
	local id = playerId(ply)
	if not id or ply == nil then return false end
	local twin = twinOf[id]
	if type(twin) ~= "table" or type(twin.class) ~= "string" or twin.class == "" then return false end
	toSlot = tonumber(toSlot)
	local live = liveSlotOf[id]
	if toSlot ~= 1 and toSlot ~= 2 then
		toSlot = (live == 1) and 2 or 1
	end
	if live == toSlot then return false end
	local wep = nil
	if type(ply.GetWeapon) == "function" then
		local ok, got = pcall(ply.GetWeapon, ply, twin.class)
		if ok then wep = got end
	end
	if not validEnt(wep) then return false end
	local captured = L.CaptureGun(wep)
	if not captured then return false end
	L.ApplyGun(wep, twin)
	twinOf[id] = L.CopyTwin(captured)
	liveSlotOf[id] = toSlot
	publish(ply)
	return true
end

function L.ClassFor(ply, slot)
	local id = playerId(ply)
	if not id or ply == nil then return nil end
	slot = tonumber(slot)
	if slot ~= 1 and slot ~= 2 then return nil end
	local slots = L.Slots(ply)
	local class = slots[slot]
	if type(class) ~= "string" or class == "" then return nil end
	return class
end

function L.Equip(ply, class)
	if ply == nil or type(class) ~= "string" or class == "" then return end
	local function go()
		if type(ply.IsValid) == "function" and ply:IsValid() == false then return end
		if type(ply.HasWeapon) == "function" and ply:HasWeapon(class) ~= true then return end
		if type(ply.SelectWeapon) == "function" then ply:SelectWeapon(class) end
	end
	go()
	if timer and timer.Simple then timer.Simple(0, go) end
end

local function activeClass(ply)
	if ply == nil or type(ply.GetActiveWeapon) ~= "function" then return nil end
	local ok, wep = pcall(ply.GetActiveWeapon, ply)
	if not ok then return nil end
	return weaponClass(wep)
end

-- The knife class this player holds: the tracked one, else any held knife.
local function heldKnife(ply)
	local k = L.Knife(ply)
	if k and type(ply.HasWeapon) == "function" and ply:HasWeapon(k) == true then return k end
	if type(ply.GetWeapons) ~= "function" then return nil end
	for _, w in ipairs(ply:GetWeapons() or {}) do
		local c = weaponClass(w)
		if type(c) == "string" and c:find("knife", 1, true) then return c end
	end
	return nil
end

local function selectSlot(ply, slot)
	local knife = heldKnife(ply)
	local slots = L.Slots(ply)
	local live = L.LiveSlot(ply)
	local active = activeClass(ply)
	local class = L.Toggle(slots, active, knife, slot, live)
	if not class then return end
	if class == slots[slot] and live ~= nil and live ~= slot and slots[live] == class then
		L.SwapTwin(ply, slot)
	end
	-- A slot that still names a gun the player no longer holds (looted) is empty.
	if type(ply.HasWeapon) == "function" and ply:HasWeapon(class) ~= true then class = knife end
	if class and type(ply.SelectWeapon) == "function" then ply:SelectWeapon(class) end
	if class and class ~= knife then L.SetLiveSlot(ply, slot) end
end

-- Lost the active weapon (looted, dropped, removed): pull the knife out.
function L.EnsureActive(ply)
	if ply == nil or type(ply.Alive) ~= "function" or ply:Alive() ~= true then return false end
	if activeClass(ply) then return false end
	local knife = heldKnife(ply)
	if not knife or type(ply.SelectWeapon) ~= "function" then return false end
	ply:SelectWeapon(knife)
	return true
end

local function forget(ply)
	local id = playerId(ply)
	if not id then return end
	gunsOf[id] = nil
	knifeOf[id] = nil
	twinOf[id] = nil
	liveSlotOf[id] = nil
end

if concommand and concommand.Add then
	concommand.Add("bal_slot", function(ply, _, args)
		if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return end
		local n = tonumber(args and args[1])
		if n ~= 1 and n ~= 2 then return end
		selectSlot(ply, n)
	end)
end

if hook and hook.Add then
	hook.Add("PlayerDisconnected", "Ballistics_Loadout", forget)
	hook.Add("Ballistics_MatchEnd", "Ballistics_Loadout", function()
		twinOf = {}
		liveSlotOf = {}
	end)
	local nextAt = 0
	hook.Add("Think", "Ballistics_LoadoutKnife", function()
		local now = (CurTime and CurTime()) or 0
		if now < nextAt then return end
		nextAt = now + 0.2
		if not (player and player.GetAll) then return end
		for _, ply in ipairs(player.GetAll()) do
			if IsValid(ply) then L.EnsureActive(ply) end
		end
	end)
end
