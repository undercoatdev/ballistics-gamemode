-- Keys 1, 2, 3 select loadout slots. The scroll wheel does not switch weapons.
-- Slot 4 is not handled here: that bind belongs to the throwables key.
-- The spawn editor zooms with invnext/invprev while it is open, so those
-- binds are left for it. TacRP menus that read the wheel themselves are
-- not binds and are left alone. Spectate uses attack, not these binds.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loadout = BALLISTICS.Loadout or {}

local L = BALLISTICS.Loadout

local function editingSpawns()
	return BALLISTICS.Spawns and type(BALLISTICS.Spawns.IsEditing) == "function" and BALLISTICS.Spawns.IsEditing() == true
end

if hook and hook.Add then
	hook.Add("PlayerBindPress", "Ballistics_Loadout", function(_, bind, pressed)
		if type(L.BlockScroll) == "function" and L.BlockScroll(bind) then
			if editingSpawns() then return end
			return true
		end
		local slot = type(L.BindSlot) == "function" and L.BindSlot(bind) or nil
		if not slot then return end
		if pressed ~= false and RunConsoleCommand then
			RunConsoleCommand("bal_slot", tostring(slot))
		end
		return true
	end)
end
