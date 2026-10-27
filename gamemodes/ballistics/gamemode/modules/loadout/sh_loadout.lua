-- Loadout slots. Independent of TacRP SWEP.Slot. No GMod calls.
-- Two gun boxes: key 1 and key 2. The knife has no key.
-- Meds and throwables take no slot.
-- Slots are fixed: removing the key-1 gun leaves that box empty and the
-- key-2 gun stays on key 2. A new gun fills the first free slot.

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

-- extra: a stored twin of the same class as a live gun. A class string, a
-- { class = } row, or { [class] = extraCount }. Each extra copy lets
-- ResolveSlots keep that class in a second slot. Carried duplicates without
-- extra still collapse to one slot (GMod only has one entity per class).
function L.ExtraCopies(extra)
	local bonus = {}
	if type(extra) == "string" and extra ~= "" then
		bonus[extra] = 1
		return bonus
	end
	if type(extra) ~= "table" then return bonus end
	if type(extra.class) == "string" and extra.class ~= "" then
		bonus[extra.class] = 1
		return bonus
	end
	for class, n in pairs(extra) do
		if type(class) == "string" and class ~= "" then
			n = math.floor(tonumber(n) or 0)
			if n > 0 then bonus[class] = n end
		end
	end
	return bonus
end

function L.TwinClassOf(slots)
	if type(slots) ~= "table" then return nil end
	local a, b = slots[1], slots[2]
	if type(a) == "string" and a ~= "" and a == b then return a end
	return nil
end

-- Twin payload stored for the inactive copy of a class.
-- { class, clip1, ammo, attachments = { { slot, att }, ... } }
function L.CopyTwin(gun)
	if type(gun) ~= "table" then return nil end
	local class = gun.class
	if type(class) ~= "string" or class == "" then return nil end
	local ammo = gun.ammo
	if type(ammo) ~= "string" or ammo == "" or ammo == "none" then ammo = nil end
	local atts = {}
	local src = gun.attachments
	if type(src) == "table" then
		for i = 1, #src do
			local row = src[i]
			if type(row) == "table" then
				local att = row.att
				if type(att) == "string" and att ~= "" then
					atts[#atts + 1] = { slot = math.floor(tonumber(row.slot) or 0), att = att }
				end
			end
		end
	end
	local clip1 = math.floor(tonumber(gun.clip1) or 0)
	if clip1 < 0 then clip1 = 0 end
	local out = { class = class, clip1 = clip1, attachments = atts }
	if ammo then out.ammo = ammo end
	local clip2 = tonumber(gun.clip2)
	if clip2 ~= nil then
		clip2 = math.floor(clip2)
		if clip2 < 0 then clip2 = 0 end
		out.clip2 = clip2
	end
	return out
end

function L.EncodeSlots(slots)
	local a, b = "", ""
	if type(slots) == "table" then
		if type(slots[1]) == "string" then a = slots[1] end
		if type(slots[2]) == "string" then b = slots[2] end
	end
	return a .. "\n" .. b
end

function L.DecodeSlots(raw)
	local slots = { false, false }
	if type(raw) ~= "string" or raw == "" then return slots end
	local a, b = string.match(raw, "^([^\n]*)\n(.*)$")
	if a == nil then a, b = raw, "" end
	if type(a) == "string" and a ~= "" then slots[1] = a end
	if type(b) == "string" and b ~= "" then slots[2] = b end
	return slots
end

function L.CountClass(slots, class)
	if type(slots) ~= "table" or type(class) ~= "string" or class == "" then return 0 end
	local n = 0
	for i = 1, L.MAX_GUNS do
		if slots[i] == class then n = n + 1 end
	end
	return n
end

-- prev: fixed slot table { [1] = class or false, [2] = class or false }
--   (key 1 and key 2). A plain ordered list works too.
-- carried: classes still in hand. A string is a gun.
--   { class=, role= } may be "gun", "melee", "nade", "med", "grenade", "throwable".
-- knife: the melee class, when the loadout already decided it.
-- extra: see ExtraCopies. A stored twin of a carried class keeps a second slot.
-- A carried gun keeps its slot. A gun no longer carried leaves its slot
-- empty (the other gun does not shift). A new gun fills the first free slot.
-- Returns knife, slots (always MAX_GUNS entries, false when empty).
function L.ResolveSlots(prev, carried, knife, extra)
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
	local bonus = L.ExtraCopies(extra)
	local remaining = {}
	for class in pairs(have) do
		remaining[class] = 1 + (bonus[class] or 0)
	end
	local slots = {}
	for i = 1, L.MAX_GUNS do slots[i] = false end
	local placed = {}
	if type(prev) == "table" then
		for i = 1, L.MAX_GUNS do
			local class = prev[i]
			local left = type(class) == "string" and remaining[class] or 0
			if type(class) == "string" and class ~= "" and class ~= knife and left and left > 0 then
				slots[i] = class
				remaining[class] = left - 1
				placed[class] = (placed[class] or 0) + 1
			end
		end
	end
	for i = 1, #carriedGuns do
		local class = carriedGuns[i]
		local left = remaining[class] or 0
		while left > 0 do
			local filled = false
			for j = 1, L.MAX_GUNS do
				if slots[j] == false then
					slots[j] = class
					remaining[class] = left - 1
					left = remaining[class]
					placed[class] = (placed[class] or 0) + 1
					filled = true
					break
				end
			end
			if not filled then break end
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

-- First empty slot index (1 = key 1), or nil when full.
function L.FreeSlot(slots)
	if type(slots) ~= "table" then return 1 end
	for i = 1, L.MAX_GUNS do
		local class = slots[i]
		if type(class) ~= "string" or class == "" then return i end
	end
	return nil
end

-- Returns knife, compact gun list, and the fixed slot table.
function L.Resolve(remembered, carried, knife, extra)
	local k, slots = L.ResolveSlots(remembered, carried, knife, extra)
	return k, L.Compact(slots), slots
end

-- guns may be the fixed slot table or a compact list.
-- First box is key 1, second is key 2. The knife has no key.
function L.At(knife, guns, slot)
	slot = tonumber(slot)
	if type(guns) ~= "table" then return nil end
	local class = nil
	if slot == 1 then class = guns[1] end
	if slot == 2 then class = guns[2] end
	if type(class) ~= "string" or class == "" then return nil end
	return class
end

-- Class to select for gun slot idx: that slot's class, the knife if that
-- class is already active, or nil if the slot is empty.
-- liveSlot is the slot the live entity currently represents. Pressing the
-- other slot of the same class (a stored twin) still selects that class so
-- the server can swap state onto the live entity.
function L.Toggle(slots, activeClass, knife, idx, liveSlot)
	idx = tonumber(idx)
	if type(slots) ~= "table" or idx == nil or idx < 1 or idx > (L.MAX_GUNS or 2) or idx % 1 ~= 0 then return nil end
	local class = slots[idx]
	if type(class) ~= "string" or class == "" then
		-- Empty gun slot: bring the knife out.
		if type(knife) == "string" and knife ~= "" then return knife end
		return nil
	end
	if type(activeClass) == "string" and activeClass == class then
		local live = tonumber(liveSlot)
		if live ~= nil and live ~= idx then return class end
		if type(knife) == "string" and knife ~= "" then return knife end
		return nil
	end
	return class
end

function L.Full(guns)
	return type(guns) == "table" and #L.Compact(guns) >= L.MAX_GUNS
end

-- slot1/slot2 only (gun indexes). slot3 is throwables, slot4 inventory.
function L.BindSlot(bind)
	if type(bind) ~= "string" then return nil end
	local n = string.lower(bind):match("^slot([12])$")
	if not n then return nil end
	return tonumber(n)
end

function L.BlockScroll(bind)
	if type(bind) ~= "string" then return false end
	local name = string.lower(bind)
	return name == "invnext" or name == "invprev"
end
