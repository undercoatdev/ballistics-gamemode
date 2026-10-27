-- Pure buy checks. No GMod calls.
-- Phase must be buy, the buyer alive and slotted, the price payable, limits
-- respected, a gun not already owned, both gun slots not already full, and a
-- med under MedMax.
-- Purchase spends, grants, and refunds if the grant fails.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Buy = BALLISTICS.Buy or {}

BALLISTICS.Buy.TabOrder = { "weapon", "nade", "med" }

BALLISTICS.Buy.TabTitle = {
	weapon = "Weapons",
	nade = "Throwables",
	med = "Meds",
}

local REASONS = {
	phase = "Buying is closed.",
	alive = "You are not alive.",
	slot = "You are not in a slot.",
	menu = "The buy menu is disabled.",
	item = "That item is not for sale.",
	price = "That item has no price.",
	money = "Not enough money.",
	duplicate = "You already have that weapon.",
	full = "Gun slots full",
	limit = "You have reached the buy limit.",
	medcap = "You cannot carry more of that med.",
	nadecap = "You cannot carry more of that grenade.",
	give = "Could not give that item.",
	med = "Could not give that med.",
	player = "Could not buy that.",
}

local function whole(n, allowNegative)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
	n = math.floor(n)
	if not allowNegative and n < 0 then return nil end
	return n
end

local function countOf(n)
	local v = whole(n, true)
	if v == nil or v < 0 then return 0 end
	return v
end

function BALLISTICS.Buy.ReasonText(err)
	if type(err) == "string" and REASONS[err] then return REASONS[err] end
	return "Could not buy that."
end

-- Left click on the buy wheel. Guns sell when you own one bought this phase.
-- Grenades and meds stay a buy until you hold the cap, and sell only then if
-- at least one was bought this phase (fresh > 0). Right click is not this.
function BALLISTICS.Buy.LeftAction(kind, have, max, fresh, owned)
	fresh = countOf(fresh)
	if kind == "weapon" then
		if owned == true and fresh > 0 then return "sell" end
		return "buy"
	end
	if kind ~= "nade" and kind ~= "med" then return "buy" end
	have = countOf(have)
	max = tonumber(max)
	if max == nil or max ~= max or max == math.huge or max == -math.huge then return "buy" end
	max = math.floor(max)
	if max < 0 then max = 0 end
	if have >= max and fresh > 0 then return "sell" end
	return "buy"
end

function BALLISTICS.Buy.StackCount(have, max)
	return tostring(countOf(have)) .. " / " .. tostring(countOf(max))
end

function BALLISTICS.Buy.List(kind)
	local cat = BALLISTICS.Catalog
	if not cat then return {} end
	if kind == "weapon" and cat.Weapons then return cat.Weapons() end
	if kind == "nade" and cat.Throwables then return cat.Throwables() end
	if kind == "med" and cat.Meds then return cat.Meds() end
	return {}
end

-- Rounds of reserve ammo for BuyAmmoMags full clips. 0 mags or an unknown clip gives nothing.
function BALLISTICS.Buy.AmmoRounds(clipSize, mags)
	clipSize = whole(clipSize)
	mags = whole(mags)
	if not clipSize or not mags then return 0 end
	if clipSize < 1 or mags < 1 then return 0 end
	return clipSize * mags
end

-- TacRP copies SWEP.Ammo into Primary.Ammo inside SetBaseSettings during Give.
-- GetMaxClip1 is the live per-weapon clip (attachments can change it). Primary
-- .ClipSize is the fallback TacRP writes at Give. Weapons are userdata in
-- GMod, so this only reads fields and methods.
function BALLISTICS.Buy.WeaponAmmo(wep)
	if wep == nil then return nil, nil end
	local kind = type(wep)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Entity" and kind ~= "Weapon" then
		return nil, nil
	end
	local ammo, clip
	local primary = wep.Primary
	if type(primary) == "table" then
		if type(primary.Ammo) == "string" and primary.Ammo ~= "" and primary.Ammo ~= "none" then
			ammo = primary.Ammo
		end
	end
	if not ammo and type(wep.GetAmmoType) == "function" then
		local ok, got = pcall(wep.GetAmmoType, wep)
		if ok and type(got) == "string" and got ~= "" and got ~= "none" then ammo = got end
	end
	if not ammo and type(wep.Ammo) == "string" and wep.Ammo ~= "" and wep.Ammo ~= "none" then
		ammo = wep.Ammo
	end
	if type(wep.GetMaxClip1) == "function" then
		local ok, got = pcall(wep.GetMaxClip1, wep)
		got = ok and tonumber(got) or nil
		if got and got > 0 then clip = math.floor(got) end
	end
	if not clip and type(primary) == "table" then
		local primaryClip = tonumber(primary.ClipSize)
		if primaryClip and primaryClip > 0 then clip = math.floor(primaryClip) end
	end
	if not clip and type(wep.GetCapacity) == "function" then
		local ok, got = pcall(wep.GetCapacity, wep)
		got = ok and tonumber(got) or nil
		if got and got > 0 then clip = math.floor(got) end
	end
	if not clip then
		local stored = tonumber(wep.ClipSize)
		if stored and stored > 0 then clip = math.floor(stored) end
	end
	return ammo, clip
end

-- GiveMed that returns true but does not raise the count (PB clamps at MedMax) did not grant.
function BALLISTICS.Buy.MedGranted(before, after, giveReturned)
	if giveReturned ~= true then return false end
	if type(before) ~= "number" or type(after) ~= "number" then return true end
	return after > before
end

function BALLISTICS.Buy.Validate(ctx)
	ctx = ctx or {}
	if ctx.phase ~= "buy" then return false, "phase" end
	if ctx.alive ~= true then return false, "alive" end
	if ctx.slotted ~= true then return false, "slot" end
	if ctx.menuEnabled == false then return false, "menu" end
	local item = ctx.item
	if type(item) ~= "table" then return false, "item" end
	if item.kind ~= "weapon" and item.kind ~= "nade" and item.kind ~= "med" then
		return false, "item"
	end
	local price = whole(ctx.price)
	if price == nil then return false, "price" end
	local balance = tonumber(ctx.balance)
	if balance == nil or balance ~= balance or balance == math.huge or balance == -math.huge then
		balance = 0
	end
	if balance < price then return false, "money" end
	if item.kind == "weapon" and ctx.owned == true then return false, "duplicate" end
	if item.kind == "weapon" and ctx.gunSlotsFull == true then return false, "full" end
	local limits = ctx.limits
	if type(limits) ~= "table" then limits = {} end
	if item.kind == "weapon" then
		local cap = countOf(limits.weapon_per_round)
		if cap > 0 and countOf(ctx.weaponBuys) >= cap then return false, "limit" end
	elseif item.kind == "nade" then
		local cap = countOf(limits.nade_each)
		if cap > 0 and countOf(ctx.nadeCount) >= cap then return false, "limit" end
		-- nil leaves old callers alone. A set cap, including 0, is a full stop.
		if ctx.grenadeMax ~= nil then
			local gmax = whole(ctx.grenadeMax)
			if gmax == nil or gmax < 0 then gmax = 0 end
			if countOf(ctx.grenadeCount) >= gmax then return false, "nadecap" end
		end
	elseif item.kind == "med" then
		local max = whole(ctx.medMax)
		if max == nil or max < 0 then max = 0 end
		if countOf(ctx.medCount) >= max then return false, "medcap" end
	end
	return true, price
end

-- deps.spend(price) -> ok, err; deps.grant(item) -> ok, err; deps.refund(price) -> ok
function BALLISTICS.Buy.Purchase(ctx, deps)
	deps = deps or {}
	local ok, priceOrErr = BALLISTICS.Buy.Validate(ctx)
	if not ok then
		return { ok = false, err = priceOrErr, spent = false, refunded = false }
	end
	local price = priceOrErr
	if type(deps.spend) ~= "function" then
		return { ok = false, err = "money", spent = false, refunded = false }
	end
	local spentOk, spendErr = deps.spend(price)
	if not spentOk then
		return { ok = false, err = spendErr or "money", spent = false, refunded = false }
	end
	local granted, grantErr = false, "give"
	if type(deps.grant) == "function" then
		granted, grantErr = deps.grant(ctx.item)
	end
	if granted == true then
		return { ok = true, spent = true, refunded = false, price = price }
	end
	local refunded = false
	if type(deps.refund) == "function" then
		local refundOk = deps.refund(price)
		refunded = refundOk ~= false
	end
	return {
		ok = false,
		err = grantErr or "give",
		spent = true,
		refunded = refunded,
		price = price,
	}
end

-- Owned count of med id from PB's client med state { counts = { [id] = n } }.
function BALLISTICS.Buy.MedFromState(state, id)
	if type(state) ~= "table" or type(state.counts) ~= "table" then return 0 end
	local n = tonumber(state.counts[math.floor(tonumber(id) or 0)]) or 0
	if n ~= n or n < 0 then return 0 end
	return math.floor(n)
end
