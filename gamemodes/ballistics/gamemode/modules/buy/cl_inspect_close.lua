-- The injury panel (G) stays open into buy, and one opened while downed
-- cannot be closed. Buy enter closes it. Body Damage is not edited.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

local function panelValid(panel)
	if panel == nil or type(IsValid) ~= "function" then return false end
	local ok, valid = pcall(IsValid, panel)
	return ok and valid == true
end

function BALLISTICS.CloseInspect()
	local bd = BODY_DAMAGE
	if type(bd) ~= "table" then return end
	if type(bd.ClosePanel) == "function" then
		pcall(bd.ClosePanel)
	end
	local panel = bd.Panel
	if not panelValid(panel) then return end
	if type(panel.Close) == "function" then pcall(panel.Close, panel) end
	if type(panel.Remove) == "function" then pcall(panel.Remove, panel) end
	bd.Panel = nil
end

local seenPhase = nil

local function phaseOf()
	if type(LocalPlayer) ~= "function" then return nil end
	local ok, ply = pcall(LocalPlayer)
	if not ok or ply == nil or type(ply.GetNW2String) ~= "function" then return nil end
	local readOk, phase = pcall(ply.GetNW2String, ply, "bal_phase", "")
	if not readOk or type(phase) ~= "string" or phase == "" then return nil end
	return phase
end

if hook and hook.Add then
	hook.Add("Ballistics_PhaseChanged", "Ballistics_InspectClose", function(_, new)
		if new == "buy" then BALLISTICS.CloseInspect() end
	end)
	-- The phase hook runs on the server. The client sees buy through the
	-- networked phase (and bal_buy_open, which calls CloseInspect too).
	hook.Add("Think", "Ballistics_InspectClose", function()
		local phase = phaseOf()
		if phase == nil or phase == seenPhase then return end
		seenPhase = phase
		if phase == "buy" then BALLISTICS.CloseInspect() end
	end)
end
