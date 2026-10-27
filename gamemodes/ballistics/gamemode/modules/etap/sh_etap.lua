-- E on bodies: DOUBLE-TAP toggles Player Ballistics drag (a single tap does nothing),
-- HOLD opens loot (modules/loot). Replaces PB's double-tap without editing PB:
-- we wrap PLAYER_BALLISTICS.DragButton (its PlayerButtonDown hook calls the
-- global each time) to swallow the drag key, then call PB's own
-- DragTryGrab / DragRelease on release.
BALLISTICS = BALLISTICS or {}
BALLISTICS.ETap = BALLISTICS.ETap or {}
local E = BALLISTICS.ETap

E.TAP_MAX = 0.2
E.DOUBLE_GAP = 0.35

-- press: { at = time, consumed = bool }. lastTap: release time of the previous
-- short tap (or nil). A single tap does nothing; a second tap released within
-- DOUBLE_GAP of the first grabs (or drops while dragging). Returns the action
-- ("grab", "drop" or nil) and the new lastTap to remember.
function E.OnRelease(press, now, dragging, lastTap)
	if type(press) ~= "table" or press.consumed then return nil, nil end
	now = tonumber(now) or 0
	local held = now - (tonumber(press.at) or 0)
	if held < 0 or held > E.TAP_MAX then return nil, nil end
	lastTap = tonumber(lastTap)
	if lastTap and now - lastTap >= 0 and now - lastTap <= E.DOUBLE_GAP then
		return dragging and "drop" or "grab", nil
	end
	return nil, now
end

function E.HintText(keyName, dragging, aimingBody)
	if type(keyName) ~= "string" or keyName == "" then return nil end
	if dragging then return "Double-tap " .. keyName .. " to drop" end
	if aimingBody then return "Double-tap " .. keyName .. " to drag, hold " .. keyName .. " to loot" end
	return nil
end
