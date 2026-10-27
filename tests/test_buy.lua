-- Buy validation and granting: phase, price, limits, duplicate gun, med cap, refund.
-- Run: luajit tests/test_buy.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

dofile("tests/support/gmod_stub.lua")
TacRP = {}
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_deps.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_state.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_ledger.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_money.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_round.lua")
dofile("gamemodes/ballistics/gamemode/modules/buy/sh_buy.lua")
dofile("gamemodes/ballistics/gamemode/modules/buy/sv_buy.lua")
dofile("gamemodes/ballistics/gamemode/modules/loadout/sh_loadout.lua")
dofile("gamemodes/ballistics/gamemode/modules/loadout/sv_loadout.lua")
-- These server buys assert three magazines. 0 is covered in the reserve block.
BALLISTICS.Config.BuyAmmoMags = 3

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

local buySrc = readAll("gamemodes/ballistics/gamemode/modules/buy/sh_buy.lua")
	.. readAll("gamemodes/ballistics/gamemode/modules/buy/sv_buy.lua")
	.. readAll("gamemodes/ballistics/gamemode/modules/buy/cl_buywheel.lua")
check("buy files do not spawn entities", not buySrc:find("ents.Create", 1, true) and not buySrc:find("ents.Spawn", 1, true))
check("buy files do not hook ShowTeam", not buySrc:find("ShowTeam", 1, true))
check("buy files do not hook GUIMouseWheeled", not buySrc:find("GUIMouseWheeled", 1, true))
check("buy files do not bind the C key", not buySrc:find("menu_context", 1, true))
check("wheel exposes Open Hide IsOpen", buySrc:find("BuyWheel.Open", 1, true)
	and buySrc:find("BuyWheel.Hide", 1, true)
	and buySrc:find("BuyWheel.IsOpen", 1, true))
check("weapon tab groups by category", buySrc:find("WeaponGroups", 1, true) ~= nil)
check("buy wheel does not switch weapons on the scroll wheel", buySrc:find("bal_slot", 1, true) ~= nil and not buySrc:find("OnMouseWheeled", 1, true))

local compiled = loadfile("gamemodes/ballistics/gamemode/modules/buy/cl_buywheel.lua")
check("client wheel compiles", compiled ~= nil)

local function ctx(over)
	local base = {
		phase = "buy",
		alive = true,
		slotted = true,
		menuEnabled = true,
		item = BALLISTICS.Catalog.Get("tacrp_ex_m1911"),
		price = 100,
		balance = 1000,
		owned = false,
		weaponBuys = 0,
		nadeCount = 0,
		limits = { weapon_per_round = 0, nade_each = 0 },
		medCount = 0,
		medMax = 5,
	}
	if over then
		for k, v in pairs(over) do base[k] = v end
	end
	return base
end

local function purchase(over, deps)
	return BALLISTICS.Buy.Purchase(ctx(over), deps)
end

local ok, err = BALLISTICS.Buy.Validate(ctx({ phase = "live" }))
check("live phase is refused", ok == false and err == "phase")
ok, err = BALLISTICS.Buy.Validate(ctx({ phase = "lobby" }))
check("lobby phase is refused", ok == false and err == "phase")
ok, err = BALLISTICS.Buy.Validate(ctx({ phase = "post" }))
check("post phase is refused", ok == false and err == "phase")
ok, err = BALLISTICS.Buy.Validate(ctx({ phase = "BUY" }))
check("phase match is exact", ok == false and err == "phase")

local spent = false
local result = purchase({ phase = "live" }, {
	spend = function() spent = true return true end,
	grant = function() return true end,
})
check("phase gate does not spend", result.ok == false and result.err == "phase" and spent == false and result.spent == false)

ok, err = BALLISTICS.Buy.Validate(ctx({ alive = false }))
check("dead buyer is refused", ok == false and err == "alive")
ok, err = BALLISTICS.Buy.Validate(ctx({ slotted = false }))
check("spectator is refused", ok == false and err == "slot")
ok, err = BALLISTICS.Buy.Validate(ctx({ menuEnabled = false }))
check("disabled menu is refused", ok == false and err == "menu")
local unknown = ctx()
unknown.item = nil
ok, err = BALLISTICS.Buy.Validate(unknown)
check("unknown item is refused", ok == false and err == "item")
ok, err = BALLISTICS.Buy.Validate(ctx({ item = { kind = "gas", key = "nade_gas" }, price = 1 }))
check("removed grenade kind is refused", ok == false and err == "item")

local missing = ctx()
missing.price = nil
ok, err = BALLISTICS.Buy.Validate(missing)
check("missing price is refused", ok == false and err == "price")
ok, err = BALLISTICS.Buy.Validate(ctx({ price = -5 }))
check("negative price is refused", ok == false and err == "price")
ok, err = BALLISTICS.Buy.Validate(ctx({ price = 0 / 0 }))
check("nan price is refused", ok == false and err == "price")

ok, err = BALLISTICS.Buy.Validate(ctx({ price = 100, balance = 99 }))
check("short balance is refused", ok == false and err == "money")
result = purchase({ price = 100, balance = 99 }, {
	spend = function() error("spent") end,
	grant = function() error("granted") end,
})
check("short balance does not spend", result.ok == false and result.err == "money" and result.spent == false)

local paid
result = purchase({ price = 10.9, balance = 10 }, {
	spend = function(n) paid = n return true, n end,
	grant = function() return true end,
	refund = function() error("refunded") end,
})
check("price floors and exact floored balance pays", result.ok == true and result.price == 10 and paid == 10)

result = purchase({ price = 9.9, balance = 8 }, {
	spend = function() error("spent") end,
})
check("floored price still needs the money", result.ok == false and result.err == "money")

ok, err = BALLISTICS.Buy.Validate(ctx({ owned = true }))
check("duplicate gun is refused", ok == false and err == "duplicate")
result = purchase({ owned = true }, {
	spend = function() error("spent") end,
	grant = function() error("granted") end,
})
check("duplicate gun does not spend", result.ok == false and result.err == "duplicate" and result.spent == false)
ok, err = BALLISTICS.Buy.Validate(ctx({ gunSlotsFull = true }))
check("full gun slots are refused", ok == false and err == "full")
result = purchase({ gunSlotsFull = true }, {
	spend = function() error("spent") end,
	grant = function() error("granted") end,
})
check("full gun slots do not spend", result.ok == false and result.err == "full" and result.spent == false)
check("full gun slots say so", BALLISTICS.Buy.ReasonText("full") == "Gun slots full")
ok, err = BALLISTICS.Buy.Validate(ctx({ owned = true, gunSlotsFull = true }))
check("an owned gun is still a duplicate when slots are full", ok == false and err == "duplicate")
ok = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("nade_frag"),
	price = 1,
	gunSlotsFull = true,
}))
check("a throwable ignores full gun slots", ok == true)

ok = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("nade_frag"),
	price = 500,
	owned = true,
}))
check("owning a gun does not block a grenade", ok == true)

ok, err = BALLISTICS.Buy.Validate(ctx({
	limits = { weapon_per_round = 1, nade_each = 0 },
	weaponBuys = 1,
	item = BALLISTICS.Catalog.Get("tacrp_mp5"),
	price = 600,
}))
check("weapon per round limit", ok == false and err == "limit")
ok = BALLISTICS.Buy.Validate(ctx({
	limits = { weapon_per_round = 0 },
	weaponBuys = 40,
}))
check("weapon limit 0 is unlimited", ok == true)

ok, err = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("nade_smoke"),
	price = 200,
	limits = { nade_each = 2 },
	nadeCount = 2,
}))
check("per grenade limit", ok == false and err == "limit")
ok = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("nade_smoke"),
	price = 200,
	limits = { nade_each = 0 },
	nadeCount = 9,
}))
check("grenade limit 0 is unlimited", ok == true)

ok, err = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("med_pills"),
	price = 50,
	medCount = 5,
	medMax = 5,
}))
check("med at cap is refused", ok == false and err == "medcap")
ok, err = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("med_pills"),
	price = 50,
	medCount = 0,
	medMax = 0,
}))
check("med max 0 is a full cap", ok == false and err == "medcap")
ok = BALLISTICS.Buy.Validate(ctx({
	item = BALLISTICS.Catalog.Get("med_trauma"),
	price = 100,
	medCount = 4,
	medMax = 5,
}))
check("med under the cap is allowed", ok == true)

local refunds = 0
result = purchase({}, {
	spend = function(n) return true, n end,
	grant = function() return false, "give" end,
	refund = function()
		refunds = refunds + 1
		return true
	end,
})
check("failed give refunds", result.ok == false and result.err == "give" and result.spent == true and result.refunded == true and refunds == 1)

refunds = 0
result = purchase({}, {
	spend = function() return true end,
	grant = function() return true end,
	refund = function()
		refunds = refunds + 1
		return true
	end,
})
check("successful give does not refund", result.ok == true and result.refunded == false and refunds == 0)

result = purchase({}, {
	spend = function() return true end,
	grant = function() return false, "give" end,
	refund = function() return false end,
})
check("failed refund is reported", result.ok == false and result.spent == true and result.refunded == false)

check("three mags of a 30 round clip", BALLISTICS.Buy.AmmoRounds(30, 3) == 90)
check("seven round pistol mag times three", BALLISTICS.Buy.AmmoRounds(7, 3) == 21)
check("zero mags gives no reserve", BALLISTICS.Buy.AmmoRounds(30, 0) == 0)
check("unknown clip gives no reserve", BALLISTICS.Buy.AmmoRounds(-1, 3) == 0)
check("ammo rounds floor", BALLISTICS.Buy.AmmoRounds(7.9, 3.2) == 21)

local ammo, clip = BALLISTICS.Buy.WeaponAmmo({
	Primary = { Ammo = "ar2", ClipSize = 30 },
	Ammo = "pistol",
	ClipSize = 7,
})
check("Primary.Ammo wins over the SWEP field", ammo == "ar2" and clip == 30)

ammo, clip = BALLISTICS.Buy.WeaponAmmo({
	Primary = { Ammo = "ar2", ClipSize = 30 },
	GetMaxClip1 = function() return 12 end,
	ClipSize = 7,
})
check("GetMaxClip1 wins over Primary.ClipSize", ammo == "ar2" and clip == 12)

ammo, clip = BALLISTICS.Buy.WeaponAmmo({
	Primary = { Ammo = "pistol", ClipSize = 7 },
	GetMaxClip1 = function() return 0 end,
})
check("a zero GetMaxClip1 falls back to Primary.ClipSize", ammo == "pistol" and clip == 7)

ammo, clip = BALLISTICS.Buy.WeaponAmmo({
	Primary = { Ammo = "", ClipSize = 0 },
	GetAmmoType = function() return "pistol" end,
	GetCapacity = function() return 7 end,
	Ammo = "ar2",
	ClipSize = 30,
})
check("empty Primary falls back to GetAmmoType", ammo == "pistol" and clip == 7)

ammo, clip = BALLISTICS.Buy.WeaponAmmo({
	Primary = { Ammo = "", ClipSize = -1 },
	GetAmmoType = function() error("unset") end,
	Ammo = "buckshot",
	ClipSize = 8,
})
check("throwing GetAmmoType still reads SWEP.Ammo", ammo == "buckshot" and clip == 8)

ammo, clip = BALLISTICS.Buy.WeaponAmmo(4)
check("a number is not a weapon", ammo == nil and clip == nil)

check("med count that did not rise is not granted", BALLISTICS.Buy.MedGranted(5, 5, true) == false)
check("med count that rose is granted", BALLISTICS.Buy.MedGranted(4, 5, true) == true)
check("med give false is not granted", BALLISTICS.Buy.MedGranted(0, 1, false) == false)
check("unread med bag trusts a true give", BALLISTICS.Buy.MedGranted(nil, nil, true) == true)

local guns = BALLISTICS.Catalog.Weapons()
local nades = BALLISTICS.Catalog.Throwables()
local meds = BALLISTICS.Catalog.Meds()
local allOk = true
for i = 1, #guns do
	local item = guns[i]
	local allowed = BALLISTICS.Buy.Validate(ctx({
		item = item,
		price = BALLISTICS.Catalog.Price(item.key),
		balance = 100000,
	}))
	if not allowed then allOk = false end
end
for i = 1, #nades do
	local item = nades[i]
	local allowed = BALLISTICS.Buy.Validate(ctx({
		item = item,
		price = BALLISTICS.Catalog.Price(item.key),
		balance = 100000,
	}))
	if not allowed then allOk = false end
end
for i = 1, #meds do
	local item = meds[i]
	local allowed = BALLISTICS.Buy.Validate(ctx({
		item = item,
		price = BALLISTICS.Catalog.Price(item.key),
		balance = 100000,
		medCount = 0,
		medMax = 5,
	}))
	if not allowed then allOk = false end
end
check("every catalog item can be bought in buy", allOk == true and #guns == 8 and #nades == 4 and #meds == 4)

local blocked = true
for i = 1, #guns + #nades + #meds do
	local item = BALLISTICS.Catalog.All()[i]
	local allowed = BALLISTICS.Buy.Validate(ctx({
		phase = "live",
		item = item,
		price = BALLISTICS.Catalog.Price(item.key),
		balance = 100000,
	}))
	if allowed then blocked = false end
end
check("nothing sells once the phase is live", blocked == true)

check("three buy tabs", BALLISTICS.Buy.TabTitle.weapon == "Weapons"
	and BALLISTICS.Buy.TabTitle.nade == "Throwables"
	and BALLISTICS.Buy.TabTitle.med == "Meds")
check("reason text for a duplicate", BALLISTICS.Buy.ReasonText("duplicate") == "You already have that weapon.")

-- Server grant path. Players are tables here; GMod players are userdata and the
-- server only calls methods on them.
local phase = "buy"
BALLISTICS.Round.Phase = function()
	return phase
end

local medMax = 5
local lying = false
local medCalls = {}
PLAYER_BALLISTICS = {
	MedMax = function() return medMax end,
	MedBag = function(p) return p.pbMed end,
	GiveMed = function(p, id, n)
		medCalls[#medCalls + 1] = { id = id, n = n }
		if lying then return true end
		local have = p.pbMed.counts[id] or 0
		if have >= medMax then return false end
		p.pbMed.counts[id] = have + n
		return true
	end,
}
BALLISTICS.BuyDisabled = false

local spawned = false
ents = {
	Create = function()
		spawned = true
		error("buy spawned an entity")
	end,
}

local ply = {
	weapons = {},
	ammo = {},
	giveCalls = {},
	failGive = false,
	failAmmo = false,
	alive = true,
	chats = {},
	pbMed = { counts = { 0, 0, 0, 0 } },
}
function ply:IsValid() return true end
function ply:SteamID64() return "76561198000000001" end
function ply:Alive() return self.alive == true end
function ply:HasWeapon(class) return self.weapons[class] ~= nil end
function ply:GetWeapon(class) return self.weapons[class] end
function ply:Give(class)
	self.giveCalls[#self.giveCalls + 1] = class
	if self.failGive then return nil end
	local spec = self.specs and self.specs[class] or { ammo = "pistol", clip = 7 }
	local wep = {
		Primary = { Ammo = spec.ammo, ClipSize = spec.clip },
		Ammo = "wrong",
		ClipSize = 1,
	}
	function wep:IsValid() return true end
	self.weapons[class] = wep
	return wep
end
function ply:GiveAmmo(amount, ammoType)
	if self.failAmmo then return 0 end
	self.ammo[#self.ammo + 1] = { amount = amount, ammoType = ammoType }
	return amount
end
function ply:StripWeapon(class)
	self.weapons[class] = nil
end
function ply:ChatPrint(text)
	self.chats[#self.chats + 1] = text
end

BALLISTICS.Slots.Take(ply, TEAM_GOOD, 1)

local function fresh()
	phase = "buy"
	ply.weapons = {}
	ply.ammo = {}
	ply.giveCalls = {}
	ply.failGive = false
	ply.failAmmo = false
	ply.alive = true
	ply.chats = {}
	ply.pbMed = { counts = { 0, 0, 0, 0 } }
	ply.specs = {
		tacrp_ex_m1911 = { ammo = "pistol", clip = 7 },
		tacrp_ex_ak47 = { ammo = "ar2", clip = 30 },
	}
	medCalls = {}
	lying = false
	medMax = 5
	BALLISTICS.BuyDisabled = false
	BALLISTICS.Config.BuyLimits.weapon_per_round = 0
	BALLISTICS.Config.BuyLimits.nade_each = 0
	BALLISTICS.Config.Costs.med_pills = 50
	BALLISTICS.Money.Reset(ply)
	hook.Run("Ballistics_PhaseChanged", "post", "buy")
	ply.chats = {}
end

fresh()
local buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("server sells the m1911", buyOk == true and buyErr == nil)
check("m1911 was given, not spawned", #ply.giveCalls == 1 and ply.giveCalls[1] == "tacrp_ex_m1911" and spawned == false)
check("m1911 reserve is 3 clips of Primary.Ammo", #ply.ammo == 1 and ply.ammo[1].amount == 21 and ply.ammo[1].ammoType == "pistol")
check("m1911 costs 100", BALLISTICS.Money.Get(ply) == 900)

buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("server refuses the duplicate gun", buyOk == false and buyErr == "duplicate" and BALLISTICS.Money.Get(ply) == 900)
check("duplicate does not give again", #ply.giveCalls == 1)
check("duplicate tells the player", ply.chats[#ply.chats] == "Ballistics: You already have that weapon.")

fresh()
buyOk = BALLISTICS.Buy.Request(ply, "tacrp_ex_ak47")
check("ak reserve is 3 clips of ar2", buyOk == true and ply.ammo[1].amount == 90 and ply.ammo[1].ammoType == "ar2")
check("ak costs 900", BALLISTICS.Money.Get(ply) == 100)

fresh()
buyOk = BALLISTICS.Buy.Request(ply, "nade_frag")
check("frag is ammo only", buyOk == true and #ply.giveCalls == 0 and #ply.ammo == 1 and ply.ammo[1].amount == 1 and ply.ammo[1].ammoType == "grenade")
check("frag costs 500", BALLISTICS.Money.Get(ply) == 500 and spawned == false)

fresh()
buyOk = BALLISTICS.Buy.Request(ply, "med_pills")
check("pills go through GiveMed", buyOk == true and #medCalls == 1 and medCalls[1].id == 1 and medCalls[1].n == 1)
check("pills land in the bag", ply.pbMed.counts[1] == 1 and BALLISTICS.Money.Get(ply) == 950 and #ply.giveCalls == 0)

fresh()
ply.pbMed.counts[1] = 5
medMax = 5
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "med_pills")
check("server med cap does not spend", buyOk == false and buyErr == "medcap" and BALLISTICS.Money.Get(ply) == 1000 and #medCalls == 0)

fresh()
lying = true
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "med_pills")
check("clamped med refunds", buyOk == false and buyErr == "med" and BALLISTICS.Money.Get(ply) == 1000 and ply.pbMed.counts[1] == 0 and #medCalls == 1)

fresh()
ply.failGive = true
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("failed Give refunds", buyOk == false and buyErr == "give" and BALLISTICS.Money.Get(ply) == 1000 and ply:HasWeapon("tacrp_ex_m1911") == false)

fresh()
ply.failAmmo = true
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("failed ammo strips the gun and refunds", buyOk == false and buyErr == "give" and BALLISTICS.Money.Get(ply) == 1000)
check("failed ammo leaves nothing equipped", ply:HasWeapon("tacrp_ex_m1911") == false)

fresh()
phase = "live"
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("server refuses a buy after live", buyOk == false and buyErr == "phase" and BALLISTICS.Money.Get(ply) == 1000 and #ply.giveCalls == 0)

fresh()
ply.alive = false
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("server refuses a dead buyer", buyOk == false and buyErr == "alive" and #ply.giveCalls == 0)

fresh()
BALLISTICS.Slots.Leave(ply)
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "nade_smoke")
check("server refuses a spectator", buyOk == false and buyErr == "slot" and BALLISTICS.Money.Get(ply) == 1000)
BALLISTICS.Slots.Take(ply, TEAM_GOOD, 1)

fresh()
BALLISTICS.BuyDisabled = true
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("server refuses when the menu is disabled", buyOk == false and buyErr == "menu" and #ply.giveCalls == 0)
BALLISTICS.BuyDisabled = false

fresh()
BALLISTICS.Config.BuyLimits.weapon_per_round = 1
buyOk = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
local secondOk, secondErr = BALLISTICS.Buy.Request(ply, "tacrp_mp5")
check("server weapon limit allows the first gun", buyOk == true)
check("server weapon limit blocks the second gun", secondOk == false and secondErr == "limit" and BALLISTICS.Money.Get(ply) == 900)
check("limited second gun was not given", ply:HasWeapon("tacrp_mp5") == false)

fresh()
BALLISTICS.Config.Costs.med_pills = 10
buyOk = BALLISTICS.Buy.Request(ply, "med_pills")
check("server price follows Config.Costs", buyOk == true and BALLISTICS.Money.Get(ply) == 990)
BALLISTICS.Config.Costs.med_pills = 50

fresh()
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "nade_gas")
check("cs gas is not sold", buyOk == false and buyErr == "item")
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ak47")
check("beryl is not sold", buyOk == false and buyErr == "item" and BALLISTICS.Money.Get(ply) == 1000)
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_knife")
check("knife is not sold", buyOk == false and buyErr == "item")

fresh()
buyOk = BALLISTICS.Buy.Request(ply, "tacrp_hk417")
check("exact balance can buy the hk417", buyOk == true and BALLISTICS.Money.Get(ply) == 0)
buyOk, buyErr = BALLISTICS.Buy.Request(ply, "med_pills")
check("broke player is refused", buyOk == false and buyErr == "money" and ply.pbMed.counts[1] == 0)

-- TacRP EquipAmmo adds default magazines during Give. The reserve must ignore them.
dofile("gamemodes/ballistics/gamemode/modules/ammo/sh_ammo.lua")
fresh()
local store = { pistol = 0 }
function ply:GetAmmo() return store end
function ply:SetAmmo(n, name) store[name] = n end
function ply:Give(class, noAmmo)
	self.giveCalls[#self.giveCalls + 1] = class
	self.noAmmo = noAmmo
	if self.failGive then return nil end
	local spec = self.specs and self.specs[class] or { ammo = "pistol", clip = 7 }
	local wep = {
		Primary = { Ammo = spec.ammo, ClipSize = spec.clip },
	}
	function wep:IsValid() return true end
	function wep:GetMaxClip1() return 9 end
	function wep:SetClip1(n) self.clipSet = n end
	store[spec.ammo] = (store[spec.ammo] or 0) + spec.clip * 2
	self.weapons[class] = wep
	return wep
end
BALLISTICS.Config.BuyAmmoMags = 0
buyOk = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
local given = ply:GetWeapon("tacrp_ex_m1911")
check("give skips default ammo", buyOk == true and ply.noAmmo == true)
check("zero magazines leaves the injected reserve and fills the clip", store.pistol == 14 and given and given.clipSet == 9)
BALLISTICS.Config.BuyAmmoMags = 3
ply:StripWeapon("tacrp_ex_m1911")
store.pistol = 0
buyOk = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
given = ply:GetWeapon("tacrp_ex_m1911")
check("three magazines write three live clips", buyOk == true and store.pistol == 27 and given and given.clipSet == 9)
ply:StripWeapon("tacrp_ex_m1911")
store.pistol = 90
buyOk = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
check("a second gun adds 3 clips to the old reserve", buyOk == true and store.pistol == 117)
BALLISTICS.Config.BuyAmmoMags = 0

-- Cha-ching: only the buyer, only on success.
do
	local sent = {}
	local realSend = BALLISTICS.Net.Send
	BALLISTICS.Net.Send = function(name, target, payload)
		if name == "bal_buy_ok" then sent[#sent + 1] = target end
		if realSend then return realSend(name, target, payload) end
	end
	fresh()
	BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
	check("successful buy plays the sound for the buyer", #sent == 1 and sent[1] == ply)
	BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
	check("refused buy plays no sound", #sent == 1)
	BALLISTICS.Net.Send = realSend
end

-- Two guns fill the loadout. A third is refused with no charge and no cha-ching.
do
	local sent = {}
	local realSend = BALLISTICS.Net.Send
	BALLISTICS.Net.Send = function(name, target, payload)
		if name == "bal_buy_ok" then sent[#sent + 1] = target end
		if realSend then return realSend(name, target, payload) end
	end
	local queued = {}
	local oldTimer = timer.Simple
	timer.Simple = function(delay, fn) queued[#queued + 1] = { delay = delay, fn = fn } end
	fresh()
	BALLISTICS.Loadout.Reset(ply, "tacrp_knife")
	function ply:SelectWeapon(class) self.selected = class end
	buyOk = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
	check("the bought gun is selected", buyOk == true and ply.selected == "tacrp_ex_m1911")
	check("select runs again next tick", #queued == 1 and queued[1].delay == 0)
	ply.selected = nil
	queued[1].fn()
	check("the deferred select still equips the bought gun", ply.selected == "tacrp_ex_m1911")
	buyOk = BALLISTICS.Buy.Request(ply, "tacrp_skorpion")
	check("the second gun takes the other slot and is selected", buyOk == true and ply.selected == "tacrp_skorpion" and BALLISTICS.Loadout.GunCount(ply) == 2)
	local guns = BALLISTICS.Loadout.Guns(ply)
	check("guns stay in buy order", guns[1] == "tacrp_ex_m1911" and guns[2] == "tacrp_skorpion")
	BALLISTICS.Money.Refund(ply, 5000)
	local before = BALLISTICS.Money.Get(ply)
	local gives = #ply.giveCalls
	buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_mp5")
	check("a third gun is refused", buyOk == false and buyErr == "full")
	check("a third gun does not charge", BALLISTICS.Money.Get(ply) == before)
	check("a third gun is not given", ply:HasWeapon("tacrp_mp5") == false and #ply.giveCalls == gives)
	check("a third gun tells the player", ply.chats[#ply.chats] == "Ballistics: Gun slots full")
	check("a third gun plays no cha-ching", #sent == 2)
	buyOk, buyErr = BALLISTICS.Buy.Request(ply, "tacrp_ex_m1911")
	check("the owned gun is still a duplicate", buyOk == false and buyErr == "duplicate" and BALLISTICS.Money.Get(ply) == before and #sent == 2)
	buyOk = BALLISTICS.Buy.Request(ply, "nade_smoke")
	check("a throwable still buys when gun slots are full", buyOk == true and BALLISTICS.Money.Get(ply) == before - 200 and #sent == 3)
	before = BALLISTICS.Money.Get(ply)
	buyOk = BALLISTICS.Buy.Request(ply, "med_pills")
	check("a med still buys when gun slots are full", buyOk == true and BALLISTICS.Money.Get(ply) == before - 50 and ply.pbMed.counts[1] == 1 and #sent == 4)
	timer.Simple = oldTimer
	BALLISTICS.Net.Send = realSend
end

if failed then os.exit(1) end
