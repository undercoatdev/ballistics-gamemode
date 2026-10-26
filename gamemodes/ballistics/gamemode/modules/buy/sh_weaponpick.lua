-- Weapon pick while the buy wheel holds the mouse and keyboard. The popup
-- eats the scroll wheel and slot keys, so binds never reach the HUD selector.
-- No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.WeaponPick = BALLISTICS.WeaponPick or {}
local W = BALLISTICS.WeaponPick

-- list: { { class=, slot=, pos= }, ... }. Sorted like the HUD: slot, then pos, then class.
function W.Sort(list)
	local out = {}
	for i = 1, #(list or {}) do out[i] = list[i] end
	table.sort(out, function(a, b)
		if (a.slot or 0) ~= (b.slot or 0) then return (a.slot or 0) < (b.slot or 0) end
		if (a.pos or 0) ~= (b.pos or 0) then return (a.pos or 0) < (b.pos or 0) end
		return tostring(a.class) < tostring(b.class)
	end)
	return out
end

-- dir 1 = next (invnext), -1 = previous (invprev). Wraps around.
function W.Cycle(list, current, dir)
	local sorted = W.Sort(list)
	local n = #sorted
	if n == 0 then return nil end
	local at = 0
	for i = 1, n do
		if sorted[i].class == current then at = i break end
	end
	if at == 0 then return sorted[dir < 0 and n or 1].class end
	local nxt = ((at - 1 + (dir < 0 and -1 or 1)) % n) + 1
	return sorted[nxt].class
end

-- slotN bind (1-based HUD slot). Pressing again cycles inside that slot.
function W.Slot(list, current, slotNumber)
	local inSlot = {}
	local sorted = W.Sort(list)
	for i = 1, #sorted do
		if (sorted[i].slot or 0) + 1 == slotNumber then inSlot[#inSlot + 1] = sorted[i] end
	end
	if #inSlot == 0 then return nil end
	return W.Cycle(inSlot, current, 1)
end

-- Bind text -> action. Returns "next", "prev", a slot number, or nil.
function W.BindAction(bind)
	if type(bind) ~= "string" then return nil end
	bind = string.lower(bind)
	if bind == "invnext" then return "next" end
	if bind == "invprev" then return "prev" end
	local n = bind:match("^slot(%d)$")
	if n then return tonumber(n) end
	return nil
end
