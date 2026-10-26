-- Organ health carried from one round into the next, then healed.
-- A destroyed organ (hp <= 0) always comes back at 1 or more, even when the
-- heal amount is 0. The result never passes a positive max. No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Organs = BALLISTICS.Organs or {}

local function real(n)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

function BALLISTICS.Organs.Heal(hp, maxHp, amount)
	hp = real(hp) or 0
	amount = real(amount) or 0
	if amount < 0 then amount = 0 end
	local nextHp = hp + amount
	local destroyed = hp <= 0
	if destroyed and nextHp < 1 then nextHp = 1 end
	maxHp = real(maxHp) or 0
	if maxHp > 0 and nextHp > maxHp then nextHp = maxHp end
	if destroyed and nextHp < 1 then nextHp = 1 end
	return nextHp
end

local function layoutEntry(rec, uid)
	local layout = rec and rec.organs and rec.organs.layout
	if type(layout) ~= "table" then return nil end
	for i = 1, #layout do
		local entry = layout[i]
		if type(entry) == "table" and entry.uid == uid then return entry end
	end
	return nil
end

local function callMax(maxOf, entry, side)
	if type(maxOf) ~= "function" then return nil end
	local ok, got = pcall(maxOf, entry, side)
	if not ok then return nil end
	return real(got)
end

-- Plain snapshot: parts[uid][side] = { hp, max }. Nil when the record has none.
function BALLISTICS.Organs.SnapshotRecord(rec, maxOf)
	local runtime = rec and rec.organs and rec.organs.copies
	if type(runtime) ~= "table" then return nil end
	local parts = {}
	local any = false
	for uid, copy in pairs(runtime) do
		if type(copy) == "table" and type(copy.parts) == "table" then
			local sides = {}
			local entry = layoutEntry(rec, uid)
			for side, hp in pairs(copy.parts) do
				local maxHp = callMax(maxOf, entry, side)
				sides[side] = { hp = real(hp) or 0, max = maxHp }
				any = true
			end
			parts[uid] = sides
		end
	end
	if not any then return nil end
	return { parts = parts }
end

-- Writes healed hp back into rec.organs.copies. Returns true when it wrote.
function BALLISTICS.Organs.ApplyRecord(rec, snap, amount, maxOf)
	local runtime = rec and rec.organs and rec.organs.copies
	if type(runtime) ~= "table" or type(snap) ~= "table" or type(snap.parts) ~= "table" then
		return false
	end
	local wrote = false
	for uid, sides in pairs(snap.parts) do
		if type(sides) == "table" then
			local copy = runtime[uid]
			if type(copy) == "table" then
				if type(copy.parts) ~= "table" then copy.parts = {} end
				local entry = layoutEntry(rec, uid)
				for side, info in pairs(sides) do
					local hp = info
					local storedMax = nil
					if type(info) == "table" then
						hp = info.hp
						storedMax = real(info.max)
					end
					local maxHp = callMax(maxOf, entry, side)
					if maxHp == nil or maxHp <= 0 then maxHp = storedMax end
					local healed = BALLISTICS.Organs.Heal(hp, maxHp, amount)
					copy.parts[side] = healed
					if healed > 0 and type(copy.deadFired) == "table" then
						copy.deadFired[side] = nil
					end
					wrote = true
				end
			end
		end
	end
	return wrote
end
