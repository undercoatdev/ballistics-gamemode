-- TacRP attachment inventory: every player owns every attachment; money is the gate.
-- Shared on purpose: TacRP:PlayerGetAtts runs on the client as well (the
-- predicted SWEP:Attach and TacRPAttSlot), so the "everyone owns every
-- attachment" answer must exist in both realms. Money is the real gate.
if hook and hook.Add then
	hook.Add("TacRP_PlayerAttCount", "Ballistics_AttCount", function(ply)
		if ply == nil then return end
		return 9999
	end)

	hook.Add("TacRP_PlayerTakeAtt", "Ballistics_AttTake", function()
		return true
	end)

	hook.Add("TacRP_PlayerGiveAtt", "Ballistics_AttGive", function()
		return true
	end)
end
