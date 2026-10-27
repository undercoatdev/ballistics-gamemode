if not CLIENT then return end
local F = BALLISTICS.FKeys

local edges = { F.NewEdge(), F.NewEdge() }
local chatOpen = false
hook.Add("StartChat", "Ballistics_FKeys", function() chatOpen = true end)
hook.Add("FinishChat", "Ballistics_FKeys", function() chatOpen = false end)

local function typing()
	if chatOpen then return true end
	if gui.IsConsoleVisible and gui.IsConsoleVisible() then return true end
	if gui.IsGameUIVisible and gui.IsGameUIVisible() then return true end
	local f = vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
	if IsValid(f) and f.GetClassName and f:GetClassName() == "TextEntry" then return true end
	return false
end

hook.Add("Think", "Ballistics_FKeys", function()
	local now = RealTime()
	local blocked = typing()
	if F.Step(edges[1], input.IsKeyDown(KEY_F2), now, blocked) then
		if BALLISTICS.Lobby and BALLISTICS.Lobby.Toggle then BALLISTICS.Lobby.Toggle() end
	end
	if F.Step(edges[2], input.IsKeyDown(KEY_F3), now, blocked) then
		if BALLISTICS.Admin and BALLISTICS.Admin.Toggle then BALLISTICS.Admin.Toggle() end
	end
end)
