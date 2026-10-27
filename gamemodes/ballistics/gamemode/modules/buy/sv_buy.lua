-- Server buy: validate, spend, then grant. Refund if the grant fails.
-- Guns: Give(class, true) so TacRP EquipAmmo does not add its default magazines,
-- then reserve is set to the pre-give count plus BuyAmmoMags of that gun's clip.
-- 0 magazines is infinite ammo: the clip is filled and no reserve is written.
-- Throwables: GiveAmmo(1, ammo type) only. TacRP quick-throw (CheckGrenade)
-- reads GetAmmoCount, so the grenade proxy weapon is not given and the ammo
-- entity is never spawned.
-- Meds: BALLISTICS.GiveMed. A false return, or a count that did not rise, refunds.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Buy = BALLISTICS.Buy or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local bought = {}

local function isValid(ent)
	if ent == nil or ent == false then return false end
	if type(ent) == "table" and type(ent.IsValid) == "function" then
		return ent:IsValid() == true
	end
	if type(ent) ~= "table" and IsValid then return IsValid(ent) end
	return type(ent) == "table"
end

local function playerId(ply)
	if BALLISTICS.PlayerId then return BALLISTICS.PlayerId(ply) end
	return nil
end

local function record(id)
	local row = bought[id]
	if not row then
		row = { weapons = 0, nades = {} }
		bought[id] = row
	end
	return row
end

local function buyMags()
	local n = BALLISTICS.Config and BALLISTICS.Config.BuyAmmoMags
	n = tonumber(n) or 0
	if n ~= n or n < 0 then n = 0 end
	n = math.floor(n)
	if n > 30 then n = 30 end
	return n
end

local function eachPly(fn)
	local seen = {}
	local function one(ply)
		if ply == nil or seen[ply] then return end
		seen[ply] = true
		fn(ply)
	end
	if BALLISTICS.Player and BALLISTICS.Player.Each then
		BALLISTICS.Player.Each(one)
	end
	if player and player.GetAll then
		local all = player.GetAll()
		if type(all) == "table" then
			for i = 1, #all do one(all[i]) end
		end
	end
end

local function phaseInfo()
	local phase = "lobby"
	local ends = 0
	if BALLISTICS.Round and BALLISTICS.Round.Phase then
		phase = BALLISTICS.Round.Phase() or "lobby"
	end
	if BALLISTICS.Round and BALLISTICS.Round.Snapshot then
		local snap = BALLISTICS.Round.Snapshot()
		if type(snap) == "table" then
			if type(snap.phase) == "string" and snap.phase ~= "" then phase = snap.phase end
			ends = tonumber(snap.endsAt) or 0
		end
	end
	return phase, ends
end

local function menuOn()
	if BALLISTICS.BuyMenuEnabled then return BALLISTICS.BuyMenuEnabled() == true end
	return true
end

local function publish(target)
	local phase, ends = phaseInfo()
	local show = phase == "buy" and menuOn()
	local function one(ply)
		if type(ply.SetNW2Bool) == "function" then ply:SetNW2Bool("bal_buy_show", show) end
		if type(ply.SetNW2Float) == "function" then ply:SetNW2Float("bal_phase_ends", ends) end
		if type(ply.SetNW2String) == "function" then
			ply:SetNW2String("bal_phase", phase)
			ply:SetNW2String("bal_buy_note", "")
		end
	end
	if target ~= nil then
		one(target)
	else
		eachPly(one)
	end
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	local now = (CurTime and CurTime()) or 0
	local left = ends - now
	if left < 0 then left = 0 end
	if not show then left = 0 end
	BALLISTICS.Net.Send("bal_buy_open", target, { open = show, timeLeft = left })
end

local function note(ply, err)
	local text = BALLISTICS.Buy.ReasonText and BALLISTICS.Buy.ReasonText(err) or "Could not buy that."
	if type(ply.SetNW2String) == "function" then ply:SetNW2String("bal_buy_note", text) end
	if type(ply.ChatPrint) == "function" then ply:ChatPrint("Ballistics: " .. text) end
end

local function clearNote(ply)
	if type(ply.SetNW2String) == "function" then ply:SetNW2String("bal_buy_note", "") end
end

local function medHave(ply, id)
	local pb = PLAYER_BALLISTICS
	if pb and type(pb.MedBag) == "function" then
		local ok, bag = pcall(pb.MedBag, ply)
		if ok and type(bag) == "table" and type(bag.counts) == "table" then
			return math.floor(tonumber(bag.counts[id]) or 0)
		end
	end
	local bag = ply.pbMed
	if type(bag) == "table" and type(bag.counts) == "table" then
		return math.floor(tonumber(bag.counts[id]) or 0)
	end
	return nil
end

local function stripWeapon(ply, class)
	if type(class) ~= "string" or class == "" then return end
	if type(ply.StripWeapon) == "function" then
		ply:StripWeapon(class)
		return
	end
	if type(ply.GetWeapon) ~= "function" then return end
	local wep = ply:GetWeapon(class)
	if isValid(wep) and type(wep.Remove) == "function" then wep:Remove() end
end

local function giveAmmo(ply, amount, ammoType)
	if type(ply.GiveAmmo) ~= "function" then return false end
	if type(ammoType) ~= "string" or ammoType == "" or ammoType == "none" then return false end
	if amount < 1 then return true end
	local gave = ply:GiveAmmo(amount, ammoType, true)
	if gave == false then return false end
	if type(gave) == "number" and gave <= 0 then return false end
	return true
end

-- Counts taken before Give. TacRP's default grant must not become the baseline.
local function copyAmmo(ply)
	if type(ply.GetAmmo) ~= "function" then return nil end
	local ok, got = pcall(ply.GetAmmo, ply)
	if not ok or type(got) ~= "table" then return nil end
	local snap = {}
	for id, n in pairs(got) do
		n = tonumber(n) or 0
		if n < 0 or n ~= n or n == math.huge then n = 0 end
		n = math.floor(n)
		snap[id] = n
		if type(id) == "number" and game and type(game.GetAmmoName) == "function" then
			local named, name = pcall(game.GetAmmoName, id)
			if named and type(name) == "string" and name ~= "" then snap[name] = n end
		end
	end
	return snap
end

local function snappedCount(snap, ammoType)
	if type(snap) ~= "table" or type(ammoType) ~= "string" then return nil end
	if snap[ammoType] ~= nil then return snap[ammoType] end
	if game and type(game.GetAmmoID) == "function" then
		local ok, id = pcall(game.GetAmmoID, ammoType)
		if ok and id ~= nil and snap[id] ~= nil then return snap[id] end
	end
	-- A numeric id we could not translate is not "zero". Adding N mags is safer
	-- than replacing an unknown reserve.
	for key in pairs(snap) do
		if type(key) == "number" then return nil end
	end
	return 0
end

local function fillClip(wep, clip)
	if not clip or clip < 1 or wep == nil or type(wep.SetClip1) ~= "function" then return end
	local current = nil
	if type(wep.Clip1) == "function" then
		local ok, n = pcall(wep.Clip1, wep)
		if ok then current = tonumber(n) end
	end
	if current == nil or current < clip then pcall(wep.SetClip1, wep, clip) end
end

local function slotsFull(ply)
	local maxGuns = 2
	if BALLISTICS.Loadout and tonumber(BALLISTICS.Loadout.MAX_GUNS) then
		maxGuns = BALLISTICS.Loadout.MAX_GUNS
	end
	if not (BALLISTICS.Loadout and type(BALLISTICS.Loadout.GunCount) == "function") then
		return false
	end
	return BALLISTICS.Loadout.GunCount(ply) >= maxGuns
end

-- Select the new gun now and again next tick. TacRP deploy can switch back
-- in the same frame as Give, which would leave C customizing the old weapon.
local function tookGun(ply, class)
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.NoteGun) == "function" then
		BALLISTICS.Loadout.NoteGun(ply, class)
	end
	if BALLISTICS.Loadout and type(BALLISTICS.Loadout.Equip) == "function" then
		BALLISTICS.Loadout.Equip(ply, class)
	elseif type(ply.SelectWeapon) == "function" then
		ply:SelectWeapon(class)
	end
	return true
end

local function grantWeapon(ply, item)
	if type(ply.HasWeapon) == "function" and ply:HasWeapon(item.class) == true then
		return false, "duplicate"
	end
	if type(ply.Give) ~= "function" then return false, "give" end
	local beforeAmmo = copyAmmo(ply)
	-- true skips engine/TacRP default ammo. EquipAmmo would add extra magazines.
	local wep = ply:Give(item.class, true)
	if not isValid(wep) and type(ply.GetWeapon) == "function" then
		wep = ply:GetWeapon(item.class)
	end
	if not isValid(wep) then return false, "give" end
	local ammoType, clip = nil, nil
	if BALLISTICS.Buy.WeaponAmmo then
		ammoType, clip = BALLISTICS.Buy.WeaponAmmo(wep)
	end
	local mags = buyMags()
	if BALLISTICS.Ammo and BALLISTICS.Ammo.WritesReserve and not BALLISTICS.Ammo.WritesReserve(mags) then
		fillClip(wep, clip)
		return tookGun(ply, item.class)
	end
	local rounds = 0
	if BALLISTICS.Buy.AmmoRounds then
		rounds = BALLISTICS.Buy.AmmoRounds(clip, mags)
	end
	local before = snappedCount(beforeAmmo, ammoType)
	if before ~= nil and type(ply.SetAmmo) == "function" and type(ammoType) == "string" and ammoType ~= "" and ammoType ~= "none" then
		local target = before + rounds
		if BALLISTICS.Ammo and type(BALLISTICS.Ammo.ReserveTarget) == "function" then
			target = BALLISTICS.Ammo.ReserveTarget(before, clip, mags)
		end
		ply:SetAmmo(target, ammoType)
		fillClip(wep, clip)
		return tookGun(ply, item.class)
	end
	if rounds > 0 and not giveAmmo(ply, rounds, ammoType) then
		stripWeapon(ply, item.class)
		return false, "give"
	end
	fillClip(wep, clip)
	return tookGun(ply, item.class)
end

local function grantNade(ply, item)
	if not giveAmmo(ply, 1, item.ammo) then return false, "give" end
	return true
end

local function grantMed(ply, item)
	local before = medHave(ply, item.id)
	local ok = false
	if BALLISTICS.GiveMed then ok = BALLISTICS.GiveMed(ply, item.id, 1) end
	local after = medHave(ply, item.id)
	if not (BALLISTICS.Buy.MedGranted and BALLISTICS.Buy.MedGranted(before, after, ok == true)) then
		return false, "med"
	end
	return true
end

local function grantItem(ply, item)
	if type(item) ~= "table" then return false, "item" end
	if item.kind == "weapon" then return grantWeapon(ply, item) end
	if item.kind == "nade" then return grantNade(ply, item) end
	if item.kind == "med" then return grantMed(ply, item) end
	return false, "item"
end

local function cleanKey(key)
	if type(key) ~= "string" then return nil end
	if #key < 1 or #key > 64 then return nil end
	if not string.match(key, "^[%w_]+$") then return nil end
	return key
end

function BALLISTICS.Buy.Request(ply, key)
	if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return false, "player" end
	local id = playerId(ply)
	if not id then return false, "player" end
	key = cleanKey(key)
	local item = key and BALLISTICS.Catalog and BALLISTICS.Catalog.Get and BALLISTICS.Catalog.Get(key) or nil
	local teamId = nil
	if BALLISTICS.Slots and BALLISTICS.Slots.TeamOf then
		teamId = BALLISTICS.Slots.TeamOf(ply)
	end
	local slotted = teamId == GOOD or teamId == BAD
	local alive = type(ply.Alive) == "function" and ply:Alive() == true
	local phase = "lobby"
	if BALLISTICS.Round and BALLISTICS.Round.Phase then
		phase = BALLISTICS.Round.Phase() or "lobby"
	end
	local balance = 0
	if BALLISTICS.Money and BALLISTICS.Money.Get then
		balance = BALLISTICS.Money.Get(ply) or 0
	end
	local price = nil
	if item and BALLISTICS.Catalog.Price then price = BALLISTICS.Catalog.Price(item.key) end
	local owned = false
	if item and item.kind == "weapon" and type(ply.HasWeapon) == "function" then
		owned = ply:HasWeapon(item.class) == true
	end
	local row = record(id)
	local medCount, medMax = 0, 0
	if item and item.kind == "med" then
		if BALLISTICS.MedMax then medMax = BALLISTICS.MedMax() or 0 end
		local have = medHave(ply, item.id)
		if have ~= nil then medCount = have end
	end
	local limits = BALLISTICS.Config and BALLISTICS.Config.BuyLimits or {}
	local ctx = {
		phase = phase,
		alive = alive,
		slotted = slotted,
		menuEnabled = menuOn(),
		item = item,
		price = price,
		balance = balance,
		owned = owned,
		gunSlotsFull = item ~= nil and item.kind == "weapon" and slotsFull(ply) or false,
		weaponBuys = row.weapons,
		nadeCount = item and row.nades[item.key] or 0,
		limits = limits,
		medCount = medCount,
		medMax = medMax,
	}
	local result = BALLISTICS.Buy.Purchase(ctx, {
		spend = function(amount)
			if not (BALLISTICS.Money and BALLISTICS.Money.Spend) then return false, "money" end
			return BALLISTICS.Money.Spend(ply, amount)
		end,
		refund = function(amount)
			if not (BALLISTICS.Money and BALLISTICS.Money.Refund) then return false end
			return BALLISTICS.Money.Refund(ply, amount)
		end,
		grant = function(it)
			local okCall, a, b = pcall(grantItem, ply, it)
			if not okCall then
				if it and it.kind == "weapon" then stripWeapon(ply, it.class) end
				return false, "give"
			end
			return a, b
		end,
	})
	if result.ok then
		clearNote(ply)
		-- Cha-ching for the buyer only.
		if BALLISTICS.Net and BALLISTICS.Net.Send then BALLISTICS.Net.Send("bal_buy_ok", ply, {}) end
		if item.kind == "weapon" then
			row.weapons = row.weapons + 1
		elseif item.kind == "nade" then
			row.nades[item.key] = (row.nades[item.key] or 0) + 1
		end
		return true
	end
	note(ply, result.err)
	return false, result.err
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_buy", function(ply, key)
		BALLISTICS.Buy.Request(ply, key)
	end, {
		rate = 10,
		read = function()
			return net.ReadString()
		end,
	})

	BALLISTICS.Net.Register("bal_buy_ok", nil, { write = function() end })

	-- bool open, float seconds left in the buy phase
	BALLISTICS.Net.Register("bal_buy_open", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteBool(payload.open and true or false)
			net.WriteFloat(tonumber(payload.timeLeft) or 0)
		end,
	})
end

if hook and hook.Add then
	hook.Add("Ballistics_PhaseChanged", "Ballistics_BuyPhase", function(_, new)
		if new == "buy" then bought = {} end
		publish(nil)
	end)

	hook.Add("PlayerInitialSpawn", "Ballistics_BuySync", function(ply)
		publish(ply)
		if timer and timer.Simple then
			timer.Simple(0, function()
				if not isValid(ply) then return end
				publish(ply)
			end)
		end
	end)

	hook.Add("PlayerDisconnected", "Ballistics_BuyForget", function(ply)
		local id = playerId(ply)
		if id then bought[id] = nil end
	end)
end

-- Weapon pick from the buy wheel (it holds the mouse, so binds never fire).
-- Only an owned weapon can be selected; movement stays frozen.
if concommand and concommand.Add then
	concommand.Add("bal_select", function(ply, _, args)
		if not (BALLISTICS.IsPlayer and BALLISTICS.IsPlayer(ply)) then return end
		local class = args and args[1]
		if type(class) ~= "string" or class == "" then return end
		if type(ply.HasWeapon) ~= "function" or ply:HasWeapon(class) ~= true then return end
		if ply.SelectWeapon then ply:SelectWeapon(class) end
	end)
end

