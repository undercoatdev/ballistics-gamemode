-- Loadout slots. Independent of TacRP SWEP.Slot. No GMod calls.
-- Slot 1 is the knife (the melee the loadout gave).
-- Slots 2 and 3 are guns, at most two, in the order they were first acquired.
-- Meds and throwables take no slot.
-- When a gun is removed, later guns shift down so slot 2 stays the earliest
-- gun still carried and slot 3 the next. A new gun fills the first free slot.

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

-- remembered: gun classes in acquisition order (dropped ones may still be listed).
-- carried: classes still in hand, oldest-known order. A string is a gun.
--   { class=, role= } may be "gun", "melee", "nade", "med", "grenade", "throwable".
-- knife: the melee class, when the loadout already decided it.
-- Returns the knife class (may be nil) and the gun classes, length 0 to MAX_GUNS.
function L.Resolve(remembered, carried, knife)
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
	local guns = {}
	local seen = {}
	local function push(class)
		if type(class) ~= "string" or class == "" or class == knife then return end
		if not have[class] or seen[class] then return end
		if #guns >= L.MAX_GUNS then return end
		seen[class] = true
		guns[#guns + 1] = class
	end
	if type(remembered) == "table" then
		for i = 1, #remembered do push(remembered[i]) end
	end
	for i = 1, #carriedGuns do push(carriedGuns[i]) end
	return knife, guns
end

function L.At(knife, guns, slot)
	slot = tonumber(slot)
	if slot == 1 then
		if type(knife) == "string" and knife ~= "" then return knife end
		return nil
	end
	if type(guns) ~= "table" then return nil end
	if slot == 2 then return guns[1] end
	if slot == 3 then return guns[2] end
	return nil
end

function L.Full(guns)
	return type(guns) == "table" and #guns >= L.MAX_GUNS
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
