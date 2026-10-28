-- TacRP trims for this gamemode (no TacRP file edits):
-- 1) The quick-grenade wheel only lists throwables sold in our buy menu.
-- 2) Novelty / reserve-ammo atts are hidden, refused and stripped:
--    shotgun+revolver roulette, dragon's breath, surplus rounds, and the
--    Gun Bag (acc_duffelbag / category acc_duffle).
BALLISTICS = BALLISTICS or {}
BALLISTICS.TacFilter = BALLISTICS.TacFilter or {}
local F = BALLISTICS.TacFilter

F.BLOCKED_ATTS = {
	ammo_buckshotroulette = true,
	ammo_shotgun_dragon = true,
	ammo_roulette = true,
	ammo_surplus = true,
	ammo_surplus2 = true,
	acc_duffelbag = true,
}

-- Ammo types of the buy-menu throwables (frag, flashbang, smoke, thermite).
function F.AllowedNadeAmmo()
	local set = {}
	local list = BALLISTICS.Catalog and BALLISTICS.Catalog.Throwables and BALLISTICS.Catalog.Throwables() or {}
	for i = 1, #list do
		if type(list[i].ammo) == "string" then set[list[i].ammo] = true end
	end
	return set
end

function F.NadeAllowed(nade, allowed)
	if type(nade) ~= "table" then return false end
	allowed = allowed or F.AllowedNadeAmmo()
	return type(nade.Ammo) == "string" and allowed[nade.Ammo] == true
end

function F.AttBlocked(name)
	return type(name) == "string" and F.BLOCKED_ATTS[name] == true
end

-- Hide blocked attachments from every list: GetAttsForCats skips an
-- attachment whose Compatibility returns false.
function F.HideAtts()
	if type(TacRP) ~= "table" or type(TacRP.Attachments) ~= "table" then return end
	for name in pairs(F.BLOCKED_ATTS) do
		local att = TacRP.Attachments[name]
		if type(att) == "table" then
			att.Compatibility = function() return false end
			att.Free = false
		end
	end
end

local function wrapWeapon(wep)
	if not IsValid(wep) or wep.ArcticTacRP ~= true or wep.BallisticsNadeFiltered then return end
	local orig = wep.CheckGrenade
	if type(orig) ~= "function" then return end
	wep.BallisticsNadeFiltered = true
	wep.CheckGrenade = function(self, index, checkammo)
		local ok = orig(self, index, checkammo)
		if not ok then return false end
		local nade = self.GetGrenade and self:GetGrenade(index)
		if not nade then return ok end
		return F.NadeAllowed(nade)
	end
end
F.WrapWeapon = wrapWeapon

-- Strip a blocked round that is somehow installed.
function F.Strip(wep)
	if not SERVER or not IsValid(wep) or type(wep.Attachments) ~= "table" then return end
	for slot, tbl in pairs(wep.Attachments) do
		if type(tbl) == "table" and F.AttBlocked(tbl.Installed) then
			if type(wep.Detach) == "function" then pcall(wep.Detach, wep, slot, true) end
			if F.AttBlocked(tbl.Installed) then tbl.Installed = nil end
			if wep.NetworkWeapon then pcall(wep.NetworkWeapon, wep) end
		end
	end
end

if hook and hook.Add then
	F.HideAtts()
	hook.Add("TacRP_LoadAtts", "Ballistics_TacFilter", function() F.HideAtts() end)
	hook.Add("InitPostEntity", "Ballistics_TacFilter", function() F.HideAtts() end)
	hook.Add("TacRP_CanCustomize", "Ballistics_TacFilter", function(_, _, att, _, detach)
		if not detach and F.AttBlocked(att) then return false, "Not allowed" end
	end)
	hook.Add("OnEntityCreated", "Ballistics_TacFilter", function(ent)
		if timer and timer.Simple then timer.Simple(0, function() wrapWeapon(ent) end) end
	end)
	if SERVER then
		hook.Add("WeaponEquip", "Ballistics_TacFilter", function(wep)
			timer.Simple(0, function() wrapWeapon(wep) F.Strip(wep) end)
		end)
	end
end
