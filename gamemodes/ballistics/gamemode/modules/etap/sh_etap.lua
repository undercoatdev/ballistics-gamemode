-- E on bodies: TAP (released within TAP_MAX) toggles Player Ballistics drag,
-- HOLD opens loot (modules/loot). Replaces PB's double-tap without editing PB:
-- we wrap PLAYER_BALLISTICS.DragButton (its PlayerButtonDown hook calls the
-- global each time) to swallow the drag key, then call PB's own
-- DragTryGrab / DragRelease on release.
BALLISTICS = BALLISTICS or {}
BALLISTICS.ETap = BALLISTICS.ETap or {}
local E = BALLISTICS.ETap

E.TAP_MAX = 0.2

-- press: { at = time, consumed = bool }. Returns "grab", "drop" or nil.
function E.OnRelease(press, now, dragging)
	if type(press) ~= "table" or press.consumed then return nil end
	local held = (tonumber(now) or 0) - (tonumber(press.at) or 0)
	if held < 0 or held > E.TAP_MAX then return nil end
	return dragging and "drop" or "grab"
end

function E.HintText(keyName, dragging, aimingBody)
	if type(keyName) ~= "string" or keyName == "" then return nil end
	if dragging then return "Tap " .. keyName .. " to drop" end
	if aimingBody then return "Tap " .. keyName .. " to drag, hold " .. keyName .. " to loot" end
	return nil
end
