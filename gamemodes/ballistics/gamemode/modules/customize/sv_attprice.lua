-- Attachment ownership and price. TacRP's att inventory is bypassed.
-- TacRP_CanCustomize gates the phase, the own-flag radius, and the balance.
-- An empty detach is refused. TacRP's menu replaces by Detach(slot, true, true)
-- then Attach; the server net path is a bare Detach(slot, true) followed by
-- Attach into a still-occupied slot, so Attach detaches with that pair first.
-- WeaponEquip wraps Attach: a successful install spends the slot price.
-- Detach does not refund.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.AttPrice = BALLISTICS.AttPrice or {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function validEnt(ent)
	if ent == nil or ent == false then return false end
	local kind = type(ent)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Player" and kind ~= "Entity" and kind ~= "Weapon" then
		return false
	end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	if kind ~= "table" and IsValid then return IsValid(ent) == true end
	return kind == "table"
end

local function radius()
	local n = BALLISTICS.Config and tonumber(BALLISTICS.Config.CustomizeRadius)
	if not finite(n) or n <= 0 then n = 2 / 0.01905 end
	return n
end

local function phaseOf()
	if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
		local p = BALLISTICS.Round.Phase()
		if type(p) == "string" and p ~= "" then return p end
	end
	return "lobby"
end

local function teamOf(ply)
	if not validEnt(ply) then return nil end
	if BALLISTICS.Slots and type(BALLISTICS.Slots.TeamOf) == "function" then
		local id = BALLISTICS.Slots.TeamOf(ply)
		if id ~= nil then return id end
	end
	if type(ply.Team) == "function" then return ply:Team() end
	return nil
end

local function inZone(ply)
	if not validEnt(ply) or type(ply.GetPos) ~= "function" then return false end
	local snap
	if BALLISTICS.Spawns and type(BALLISTICS.Spawns.Snapshot) == "function" then
		snap = BALLISTICS.Spawns.Snapshot()
	end
	local flag = BALLISTICS.CKey.FlagPos(snap, teamOf(ply))
	return BALLISTICS.CKey.InRadius(ply:GetPos(), flag, radius())
end

local function isAlive(ply)
	if not validEnt(ply) or type(ply.Alive) ~= "function" then return false end
	return ply:Alive() == true
end

local function balanceOf(ply)
	if not (BALLISTICS.Money and type(BALLISTICS.Money.Get) == "function") then return 0 end
	local n = BALLISTICS.Money.Get(ply)
	n = tonumber(n)
	if not finite(n) then return 0 end
	return n
end

local function slotTable(wep, slot)
	if type(slot) == "table" then return slot end
	local n = tonumber(slot)
	if n == nil or wep == nil or type(wep.Attachments) ~= "table" then return nil end
	local slottbl = wep.Attachments[n]
	if type(slottbl) ~= "table" then return nil end
	return slottbl
end

-- att is unused on purpose. The slot category sets the price, not the attachment.
function BALLISTICS.AttPrice.Decide(ply, wep, att, slot, detach)
	local slottbl = slotTable(wep, slot)
	local price
	if slottbl then price = BALLISTICS.AttPrice.Cost(slottbl) end
	local replacing = detach == true and BALLISTICS.AttPrice.IsReplace(wep, slot)
	return BALLISTICS.AttPrice.Gate({
		phase = phaseOf(),
		inZone = inZone(ply),
		alive = isAlive(ply),
		balance = balanceOf(ply),
		price = price,
		detach = detach == true,
		replace = replacing,
	})
end

local function ownerOf(wep)
	if wep == nil or type(wep.GetOwner) ~= "function" then return nil end
	local ok, got = pcall(wep.GetOwner, wep)
	if not ok or got == nil then return nil end
	return got
end

local function installedOf(v)
	return v ~= nil and v ~= false and v ~= ""
end

-- Detach(slot, true, true) is TacRP's replace (and gear restore). Mark it so
-- the hook allows that detach. A bare Detach(slot) or Detach(slot, true) is
-- an empty detach and the hook refuses it.
local function wrapDetach(wep)
	if wep == nil or wep.BallisticsDetWrapped == true then return end
	if type(wep.Detach) ~= "function" then return end
	wep.BallisticsDetWrapped = true
	local original = wep.Detach
	wep.BallisticsDetOriginal = original
	wep.Detach = function(self, slot, silent, suppress)
		local replacing = silent == true and suppress == true
		if replacing then self.BallisticsAttReplacing = slot end
		local r1, r2 = original(self, slot, silent, suppress)
		if replacing then self.BallisticsAttReplacing = nil end
		return r1, r2
	end
end

local function wrapAttach(wep)
	if wep == nil or wep.ArcticTacRP ~= true then return end
	if wep.BallisticsAttWrapped == true then return end
	if type(wep.Attach) ~= "function" then return end
	wrapDetach(wep)
	local original = wep.Attach
	wep.BallisticsAttWrapped = true
	-- Gear restore calls this, not the wrapper, so a kept gun is not charged.
	wep.BallisticsAttOriginal = original
	wep.Attach = function(self, slot, att, silent, suppress)
		local slottbl = self.Attachments and self.Attachments[slot]
		local before = slottbl and slottbl.Installed
		-- The server hears a replace as Attach while the old attachment is
		-- still in the slot (the detach net message was refused). Take it
		-- off only when the new one is allowed, then let Attach install it.
		if self.BallisticsAttRestore ~= true and installedOf(before) and before ~= att and type(self.CanAttach) == "function" then
			local okCall, res = pcall(self.CanAttach, self, slot, att)
			if not okCall or res == false then return end
			if type(self.Detach) == "function" then self:Detach(slot, true, true) end
		end
		local r1, r2 = original(self, slot, att, silent, suppress)
		if self.BallisticsAttRestore == true then return r1, r2 end
		slottbl = self.Attachments and self.Attachments[slot]
		local after = slottbl and slottbl.Installed
		local price = slottbl and BALLISTICS.AttPrice.Cost(slottbl) or nil
		local amount = BALLISTICS.AttPrice.ChargeAmount(before, after, att, price)
		if amount > 0 and BALLISTICS.Money and BALLISTICS.Money.Spend then
			local owner = ownerOf(self)
			if owner ~= nil then BALLISTICS.Money.Spend(owner, amount) end
		end
		return r1, r2
	end
end

local function onEquip(a, b)
	if a ~= nil and a.ArcticTacRP == true then
		wrapAttach(a)
		return
	end
	if b ~= nil and b.ArcticTacRP == true then
		wrapAttach(b)
	end
end

if hook and hook.Add then
	-- Attachment inventory hooks live in sh_attprice.lua: TacRP checks the
	-- count on the client too (predicted Attach and the slot UI).

	hook.Add("TacRP_CanCustomize", "Ballistics_AttGate", function(ply, wep, att, slot, detach)
		return BALLISTICS.AttPrice.Decide(ply, wep, att, slot, detach)
	end)

	hook.Add("WeaponEquip", "Ballistics_AttWrap", function(wep, ply)
		onEquip(wep, ply)
	end)
end

-- No weapon drops through TacRP in this gamemode (its customize-menu Drop
-- button / tacrp_drop). Guns leave a player only through our loot/inventory.
local function blockTacDrop()
	if type(TacRP) ~= "table" or type(TacRP.DropWeapon) ~= "function" or TacRP.BallisticsNoDrop then return end
	TacRP.BallisticsNoDrop = true
	TacRP.DropWeapon = function() return end
end
BALLISTICS.AttPrice.BlockTacDrop = blockTacDrop
if hook and hook.Add then
	hook.Add("InitPostEntity", "Ballistics_NoTacDrop", function() blockTacDrop() end)
	hook.Add("Think", "Ballistics_NoTacDrop", function() blockTacDrop() end)
end
