if not SERVER then return end
local E = BALLISTICS.ETap
local presses = setmetatable({}, { __mode = "k" })
local lastTaps = setmetatable({}, { __mode = "k" })

local function dragKey(ply)
	local fallback = KEY_E or 15
	if ply and ply.GetInfoNum and PLAYER_BALLISTICS and PLAYER_BALLISTICS.DragKeyConVar then
		return math.floor(tonumber(ply:GetInfoNum(PLAYER_BALLISTICS.DragKeyConVar, fallback)) or fallback)
	end
	return fallback
end

function E.Wrap()
	local PB = PLAYER_BALLISTICS
	if type(PB) ~= "table" or type(PB.DragButton) ~= "function" or PB.BallisticsETapWrapped then return end
	local orig = PB.DragButton
	PB.DragButton = function(ply, button, ...)
		if math.floor(tonumber(button) or 0) == dragKey(ply) then
			-- Our tap/hold logic owns the key; PB's double-tap stays off.
			presses[ply] = {
				at = CurTime(),
				consumed = BALLISTICS.Loot and BALLISTICS.Loot.HasSession and BALLISTICS.Loot.HasSession(ply) or false,
			}
			return true
		end
		return orig(ply, button, ...)
	end
	PB.BallisticsETapWrapped = true
end

E.Wrap()
hook.Add("InitPostEntity", "Ballistics_ETap", function() E.Wrap() end)
hook.Add("PlayerButtonUp", "Ballistics_ETap", function(ply, button)
	local PB = PLAYER_BALLISTICS
	if type(PB) ~= "table" or math.floor(tonumber(button) or 0) ~= dragKey(ply) then return end
	local press = presses[ply]
	presses[ply] = nil
	local dragging = PB.Drags and PB.Drags[ply] ~= nil
	local act, tapAt = E.OnRelease(press, CurTime(), dragging, lastTaps[ply])
	lastTaps[ply] = tapAt
	if act == "drop" and PB.DragRelease then
		PB.DragRelease(ply, "key")
	elseif act == "grab" and PB.DragTryGrab then
		PB.DragTryGrab(ply)
	end
end)
