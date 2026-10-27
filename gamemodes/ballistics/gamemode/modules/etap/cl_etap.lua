if not CLIENT then return end
-- Player Ballistics' drag hint says "Double tap E to drag"; in this gamemode
-- a tap drags/drops and a hold loots (modules/etap, modules/loot). Wrap its
-- text function (PB files untouched).
local E = BALLISTICS.ETap

function E.WrapHint()
	local PB = PLAYER_BALLISTICS
	if type(PB) ~= "table" or type(PB.DragHintText) ~= "function" or PB.BallisticsHintWrapped then return end
	PB.BallisticsHintWrapped = true
	PB.DragHintText = function(keyName, dragging, aimingBody)
		return E.HintText(keyName, dragging, aimingBody)
	end
end

E.WrapHint()
hook.Add("InitPostEntity", "Ballistics_ETapHint", function() E.WrapHint() end)
