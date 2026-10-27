if not SERVER then return end
local S = BALLISTICS.Sell
-- GOOD/BAD are not globals (sv_buy keeps them local); nil here refused every sale.
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

-- Bought this buy phase, keyed by player id. Cleared when buy starts again.
local freshOf = {}

local function publishFresh(ply, map)
	if ply == nil or type(ply.SetNW2String) ~= "function" then return end
	local text = ""
	if type(map) == "table" and type(S.Encode) == "function" then
		text = S.Encode(map) or ""
	end
	if type(text) ~= "string" then text = "" end
	pcall(ply.SetNW2String, ply, "bal_fresh", text)
end

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

local function attRefundTwin(twin)
	local total = 0
	if type(twin) ~= "table" or type(twin.attachments) ~= "table" then return 0 end
	local P = BALLISTICS.AttPrice
	if not (P and P.Cost) then return 0 end
	for i = 1, #twin.attachments do
		local row = twin.attachments[i]
		if type(row) == "table" and type(row.att) == "string" and row.att ~= "" then
			local price = P.Cost({ Category = row.att, Installed = row.att, PrintName = row.att })
			if tonumber(price) then total = total + price end
		end
	end
	return total
end

local function haveOf(ply, item)
	if item.kind == "weapon" then
		local n = (type(ply.HasWeapon) == "function" and ply:HasWeapon(item.class)) and 1 or 0
		if BALLISTICS.Loadout and type(BALLISTICS.Loadout.Twin) == "function" then
			local twin = BALLISTICS.Loadout.Twin(ply)
			if type(twin) == "table" and twin.class == item.class then n = n + 1 end
		end
		return n
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
		local Load = BALLISTICS.Loadout
		local twin = Load and Load.Twin and Load.Twin(ply) or nil
		if type(twin) == "table" and twin.class == item.class then
			if Load.ClearTwin then Load.ClearTwin(ply) end
			local live = Load.LiveSlot and Load.LiveSlot(ply)
			local keep = { false, false }
			if live == 1 or live == 2 then keep[live] = item.class else keep[1] = item.class end
			if Load.Restore then Load.Restore(ply, keep) end
			return true
		end
		ply:StripWeapon(item.class)
		twin = Load and Load.Twin and Load.Twin(ply) or nil
		if type(twin) == "table" and twin.class == item.class then
			if type(ply.Give) == "function" then
				local wep = ply:Give(item.class, true)
				if (not wep or (type(wep.IsValid) == "function" and wep:IsValid() == false)) and type(ply.GetWeapon) == "function" then
					wep = ply:GetWeapon(item.class)
				end
				if wep and Load.ApplyGun then Load.ApplyGun(wep, twin) end
			end
			if Load.ClearTwin then Load.ClearTwin(ply) end
			if Load.Slots then Load.Slots(ply) end
			return ply:HasWeapon(item.class)
		end
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
	local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply) or nil
	local map = id and freshOf[id] or nil
	local fresh = 0
	if type(map) == "table" and item and type(item.key) == "string" then
		fresh = math.floor(tonumber(map[item.key]) or 0)
		if fresh < 0 then fresh = 0 end
	end
	local refundAtt = attRefund(wep)
	if item and item.kind == "weapon" and BALLISTICS.Loadout and type(BALLISTICS.Loadout.Twin) == "function" then
		local twin = BALLISTICS.Loadout.Twin(ply)
		if type(twin) == "table" and twin.class == item.class then
			refundAtt = attRefundTwin(twin)
		end
	end
	local plan = S.Plan({
		phase = BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() or "lobby",
		alive = ply:Alive() == true,
		slotted = teamId == GOOD or teamId == BAD,
		item = item,
		have = item and haveOf(ply, item) or 0,
		price = item and BALLISTICS.Catalog.Price and BALLISTICS.Catalog.Price(item.key) or 0,
		attRefund = refundAtt,
		fresh = fresh,
	})
	if not plan.ok then return false, plan.err end
	if not takeOne(ply, item) then return false, "take" end
	if type(map) == "table" and item and type(item.key) == "string" then
		S.FreshTake(map, item.key)
		publishFresh(ply, map)
	end
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

if hook and hook.Add then
	hook.Add("Ballistics_Bought", "Ballistics_SellFresh", function(ply, item)
		if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return end
		if type(item) ~= "table" or type(item.key) ~= "string" or item.key == "" then return end
		local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply)
		if not id then return end
		local map = freshOf[id]
		if type(map) ~= "table" then
			map = {}
			freshOf[id] = map
		end
		S.FreshAdd(map, item.key, 1)
		publishFresh(ply, map)
	end)

	hook.Add("Ballistics_PhaseChanged", "Ballistics_SellFreshClear", function(_, new)
		if new ~= "buy" then return end
		freshOf = {}
		local all = {}
		if player and type(player.GetAll) == "function" then
			local ok, got = pcall(player.GetAll)
			if ok and type(got) == "table" then all = got end
		end
		for i = 1, #all do
			publishFresh(all[i], {})
		end
	end)

	hook.Add("PlayerDisconnected", "Ballistics_SellFreshForget", function(ply)
		local id = BALLISTICS.PlayerId and BALLISTICS.PlayerId(ply)
		if id then freshOf[id] = nil end
	end)
end
