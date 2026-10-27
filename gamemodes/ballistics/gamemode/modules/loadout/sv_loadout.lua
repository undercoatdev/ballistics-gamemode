-- Tracks knife + gun order and selects a loadout slot. TacRP is not edited.
-- A bought gun is selected here, twice: immediately and on the next tick,
-- because TacRP deploy can put the previous weapon back in the same frame.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loadout = BALLISTICS.Loadout or {}

local L = BALLISTICS.Loadout

local gunsOf = {}
local knifeOf = {}

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

function L.Reset(ply, knifeClass)
	local id = playerId(ply)
	if not id then return end
	gunsOf[id] = {}
	if type(knifeClass) ~= "string" or knifeClass == "" then knifeClass = nil end
	knifeOf[id] = knifeClass
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

-- Fixed slot table: { [1] = slot-2 class or false, [2] = slot-3 class or false }.
function L.Slots(ply)
	local id = playerId(ply)
	if not id then return copySlots(nil) end
	local knife, _, slots = L.Resolve(storedGuns(id), carriedClasses(ply), knifeOf[id])
	gunsOf[id] = slots
	if knife and not knifeOf[id] then knifeOf[id] = knife end
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
	local carried = carriedClasses(ply)
	local found = false
	for i = 1, #carried do
		if carried[i] == class then found = true break end
	end
	if not found then carried[#carried + 1] = class end
	local _, _, slots = L.Resolve(storedGuns(id), carried, knifeOf[id])
	gunsOf[id] = slots
	for i = 1, L.MAX_GUNS do
		if slots[i] == class then return true end
	end
	return false
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
	local _, _, slots = L.Resolve(classes, carried, knifeOf[id])
	gunsOf[id] = slots
end

function L.ClassFor(ply, slot)
	local id = playerId(ply)
	if not id or ply == nil then return nil end
	slot = tonumber(slot)
	if slot == 1 then
		local knife = knifeOf[id]
		if type(knife) ~= "string" or knife == "" then return nil end
		if type(ply.HasWeapon) == "function" and ply:HasWeapon(knife) ~= true then return nil end
		return knife
	end
	if slot ~= 2 and slot ~= 3 then return nil end
	local slots = L.Slots(ply)
	local class = slots[slot - 1]
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

local function selectSlot(ply, slot)
	local class = L.ClassFor(ply, slot)
	if not class then return end
	if type(ply.HasWeapon) == "function" and ply:HasWeapon(class) ~= true then return end
	if type(ply.SelectWeapon) == "function" then ply:SelectWeapon(class) end
end

local function forget(ply)
	local id = playerId(ply)
	if not id then return end
	gunsOf[id] = nil
	knifeOf[id] = nil
end

if concommand and concommand.Add then
	concommand.Add("bal_slot", function(ply, _, args)
		if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return end
		local n = tonumber(args and args[1])
		if n ~= 1 and n ~= 2 and n ~= 3 then return end
		selectSlot(ply, n)
	end)
end

if hook and hook.Add then
	hook.Add("PlayerDisconnected", "Ballistics_Loadout", forget)
end
