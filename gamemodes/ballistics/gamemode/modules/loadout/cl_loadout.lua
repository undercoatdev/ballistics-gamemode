-- Keys 1 and 2 select gun slots. Pressing the active gun's key holsters the
-- knife. The scroll wheel does not switch weapons. Slot 3 is throwables,
-- slot 4 inventory; those binds are swallowed by the keys module.
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

-- Keys 1 and 2 still work when the player has no slot1/slot2 bind (custom
-- or wiped config): poll the raw key, only for a slot nothing is bound to.
if hook and hook.Add then
	local latch = {}
	local function unbound(cmd)
		if not input or type(input.LookupBinding) ~= "function" then return false end
		local ok, key = pcall(input.LookupBinding, cmd)
		return not ok or key == nil or key == ""
	end
	local function blocked()
		if gui and gui.IsConsoleVisible and gui.IsConsoleVisible() then return true end
		if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return true end
		local ply = LocalPlayer and LocalPlayer()
		if IsValid(ply) and ply:IsTyping() then return true end
		if vgui and vgui.GetKeyboardFocus and IsValid(vgui.GetKeyboardFocus()) then return true end
		return editingSpawns()
	end
	hook.Add("Think", "Ballistics_LoadoutKeys", function()
		if not input or type(input.IsKeyDown) ~= "function" then return end
		for slot, code in pairs({ [1] = KEY_1, [2] = KEY_2 }) do
			local down = code and unbound("slot" .. slot) and input.IsKeyDown(code) == true or false
			if down and not latch[slot] and not blocked() and RunConsoleCommand then
				RunConsoleCommand("bal_slot", tostring(slot))
			end
			latch[slot] = down
		end
	end)
end
