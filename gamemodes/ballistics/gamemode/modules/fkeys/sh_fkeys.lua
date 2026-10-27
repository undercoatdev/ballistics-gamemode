-- F2 (TEAMS) / F3 (ADMIN) toggles, read on the client by polling the keys.
-- Why polling: the lobby/admin windows are MakePopup()ed, so while one is
-- open it owns the keyboard and the F2/F3 binds never fire (cannot close).
-- The old server ShowTeam/ShowSpare1 net forward is gone so a key press
-- never toggles twice.
BALLISTICS = BALLISTICS or {}
BALLISTICS.FKeys = BALLISTICS.FKeys or {}
local F = BALLISTICS.FKeys

F.DEBOUNCE = 0.25

-- Edge detector: returns true once per press (down edge), debounced.
function F.NewEdge()
	return { down = false, last = -math.huge }
end

function F.Step(edge, isDown, now, blocked)
	local fire = false
	if isDown and not edge.down and not blocked and (now - edge.last) >= F.DEBOUNCE then
		fire = true
		edge.last = now
	end
	edge.down = isDown and true or false
	return fire
end
