-- Loadout slots. Independent of TacRP SWEP.Slot. No GMod calls.
-- Slot 1 is the knife (the melee the loadout gave).
-- Slots 2 and 3 are guns, at most two. Meds and throwables take no slot.
-- Slots are fixed: removing the slot-2 gun leaves slot 2 empty and the
-- slot-3 gun stays on key 3. A new gun fills the first free slot.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loadout = BALLISTICS.Loadout or {}

local L = BALLISTICS.Loadout

L.MAX_GUNS = 2
L.FULL = "full"

local SKIP = {
	nade = true,
	med = true,
	grenade = true,
	throwable = true,
}

local function classRole(entry)
	if type(entry) == "string" then
		if entry == "" then return nil end
		return entry, "gun"
	end
	if type(entry) ~= "table" then return nil end
	local class = entry.class
	if type(class) ~= "string" or class == "" then return nil end
	local role = entry.role
	if type(role) ~= "string" or role == "" then role = "gun" end
	return class, role
end

-- prev: fixed slot table { [1] = class or false, [2] = class or false }
--   (slot 2 and slot 3). A plain ordered list works too.
-- carried: classes still in hand. A string is a gun.
--   { class=, role= } may be "gun", "melee", "nade", "med", "grenade", "throwable".
-- knife: the melee class, when the loadout already decided it.
-- A carried gun keeps its slot. A gun no longer carried leaves its slot
-- empty (the other gun does not shift). A new gun fills the first free slot.
-- Returns knife, slots (always MAX_GUNS entries, false when empty).
function L.ResolveSlots(prev, carried, knife)
	if type(knife) ~= "string" or knife == "" then knife = nil end
	local have = {}
	local seenCarry = {}
	local carriedGuns = {}
	if type(carried) == "table" then
		for i = 1, #carried do
			local class, role = classRole(carried[i])
			if class and not SKIP[role] then
				if role == "melee" then
					if not knife then knife = class end
				elseif class ~= knife and not seenCarry[class] then
					seenCarry[class] = true
					have[class] = true
					carriedGuns[#carriedGuns + 1] = class
				end
			end
		end
	end
	local slots = {}
	for i = 1, L.MAX_GUNS do slots[i] = false end
	local seen = {}
	if type(prev) == "table" then
		for i = 1, L.MAX_GUNS do
			local class = prev[i]
			if type(class) == "string" and class ~= "" and class ~= knife and have[class] and not seen[class] then
				seen[class] = true
				slots[i] = class
			end
		end
	end
	for i = 1, #carriedGuns do
		local class = carriedGuns[i]
		if not seen[class] then
			for j = 1, L.MAX_GUNS do
				if slots[j] == false then
					slots[j] = class
					seen[class] = true
					break
				end
			end
		end
	end
	return knife, slots
end

-- Slot table to a plain list, slot order, empties skipped.
function L.Compact(slots)
	local out = {}
	if type(slots) ~= "table" then return out end
	for i = 1, L.MAX_GUNS do
		local class = slots[i]
		if type(class) == "string" and class ~= "" then out[#out + 1] = class end
	end
	return out
end

-- First empty slot index (1 = loadout slot 2), or nil when full.
function L.FreeSlot(slots)
	if type(slots) ~= "table" then return 1 end
	for i = 1, L.MAX_GUNS do
		local class = slots[i]
		if type(class) ~= "string" or class == "" then return i end
	end
	return nil
end

-- Returns knife, compact gun list, and the fixed slot table.
function L.Resolve(remembered, carried, knife)
	local k, slots = L.ResolveSlots(remembered, carried, knife)
	return k, L.Compact(slots), slots
end

-- guns may be the fixed slot table or a compact list.
function L.At(knife, guns, slot)
	slot = tonumber(slot)
	if slot == 1 then
		if type(knife) == "string" and knife ~= "" then return knife end
		return nil
	end
	if type(guns) ~= "table" then return nil end
	local class = nil
	if slot == 2 then class = guns[1] end
	if slot == 3 then class = guns[2] end
	if type(class) ~= "string" or class == "" then return nil end
	return class
end

function L.Full(guns)
	return type(guns) == "table" and #L.Compact(guns) >= L.MAX_GUNS
end

-- slot1/slot2/slot3 only. slot4 stays with the throwables key.
function L.BindSlot(bind)
	if type(bind) ~= "string" then return nil end
	local n = string.lower(bind):match("^slot([123])$")
	if not n then return nil end
	return tonumber(n)
end

function L.BlockScroll(bind)
	if type(bind) ~= "string" then return false end
	local name = string.lower(bind)
	return name == "invnext" or name == "invprev"
end
