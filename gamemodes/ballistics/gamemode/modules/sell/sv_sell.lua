if not SERVER then return end
local S = BALLISTICS.Sell
-- GOOD/BAD are not globals (sv_buy keeps them local); nil here refused every sale.
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local function valid(e) return e ~= nil and (not IsValid or IsValid(e)) end

local function attRefund(wep)
	local total = 0
	if not valid(wep) or type(wep.Attachments) ~= "table" then return 0 end
	local P = BALLISTICS.AttPrice
	for _, slot in pairs(wep.Attachments) do
		if type(slot) == "table" and slot.Installed ~= nil and slot.Installed ~= "" and P and P.Cost then
			local price = P.Cost(slot)
			if tonumber(price) then total = total + price end
		end
	end
	return total
end

local function haveOf(ply, item)
	if item.kind == "weapon" then
		return (type(ply.HasWeapon) == "function" and ply:HasWeapon(item.class)) and 1 or 0
	elseif item.kind == "nade" then
		return type(ply.GetAmmoCount) == "function" and (tonumber(ply:GetAmmoCount(item.ammo)) or 0) or 0
	elseif item.kind == "med" then
		local pb = PLAYER_BALLISTICS
		if pb and pb.MedBag then
			local ok, bag = pcall(pb.MedBag, ply)
			if ok and type(bag) == "table" and type(bag.counts) == "table" then return tonumber(bag.counts[item.id]) or 0 end
		end
	end
	return 0
end

local function takeOne(ply, item)
	if item.kind == "weapon" then
		ply:StripWeapon(item.class)
		return not ply:HasWeapon(item.class)
	elseif item.kind == "nade" then
		ply:RemoveAmmo(1, item.ammo)
		return true
	elseif item.kind == "med" then
		return BALLISTICS.GiveMed and BALLISTICS.GiveMed(ply, item.id, -1) == true
	end
	return false
end

function S.Request(ply, key)
	if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return false end
	if type(key) ~= "string" or not key:match("^[%w_]+$") then return false end
	local item = BALLISTICS.Catalog and BALLISTICS.Catalog.Get and BALLISTICS.Catalog.Get(key)
	local teamId = BALLISTICS.Slots and BALLISTICS.Slots.TeamOf and BALLISTICS.Slots.TeamOf(ply)
	local wep = item and item.kind == "weapon" and ply.GetWeapon and ply:GetWeapon(item.class) or nil
	local plan = S.Plan({
		phase = BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() or "lobby",
		alive = ply:Alive() == true,
		slotted = teamId == GOOD or teamId == BAD,
		item = item,
		have = item and haveOf(ply, item) or 0,
		price = item and BALLISTICS.Catalog.Price and BALLISTICS.Catalog.Price(item.key) or 0,
		attRefund = attRefund(wep),
	})
	if not plan.ok then return false, plan.err end
	if not takeOne(ply, item) then return false, "take" end
	if BALLISTICS.Buy and BALLISTICS.Buy.Unrecord then BALLISTICS.Buy.Unrecord(ply, item) end
	if plan.refund > 0 and BALLISTICS.Money and BALLISTICS.Money.Refund then
		BALLISTICS.Money.Refund(ply, plan.refund)
	end
	BALLISTICS.Net.Send("bal_sell_ok", ply, { amount = plan.refund })
	return true
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_sell", function(ply, key) S.Request(ply, key) end, {
		rate = 10,
		read = function() return net.ReadString() end,
	})
	BALLISTICS.Net.Register("bal_sell_ok", nil, { write = function(p) net.WriteUInt(math.Clamp(math.floor(p.amount or 0), 0, 65535), 16) end })
end
