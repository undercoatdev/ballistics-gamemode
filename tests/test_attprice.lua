-- Attachment prices: category prefixes, gate, charge, no refund, HUD colour.
-- Run: luajit tests/test_attprice.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_ledger.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_money.lua")
dofile("gamemodes/ballistics/gamemode/modules/customize/sh_ckey.lua")
dofile("gamemodes/ballistics/gamemode/modules/customize/sh_attprice.lua")

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

local pure = readAll("gamemodes/ballistics/gamemode/modules/customize/sh_attprice.lua")
check("price logic does not touch the game", not pure:find("hook.Add", 1, true)
	and not pure:find("net.Start", 1, true)
	and not pure:find("ents.Create", 1, true)
	and not pure:find("LocalPlayer", 1, true))

local P = BALLISTICS.AttPrice

local function slot(name, category)
	return { PrintName = name, Category = category }
end

local cases = {
	{ slot("Optic", { "optic_cqb", "optic_medium", "optic_sniper" }), "optic", 250 },
	{ slot("Optic", "optic_ak"), "optic", 250 },
	{ slot("Optic", "ironsights_sniper"), "optic", 250 },
	{ slot("Optic", { "ironsights_pistol", "optic_cqb" }), "optic", 250 },
	{ slot("Bolt", "bolt_automatic"), "bolt", 100 },
	{ slot("Bolt", { "bolt_manual" }), "bolt", 100 },
	{ slot("Muzzle", "silencer"), "muzzle", 100 },
	{ slot("Muzzle", "SILENCER"), "muzzle", 100 },
	{ slot("Muzzle", { "silencer", "muzz_ak" }), "muzzle", 100 },
	{ slot("Muzzle", "muzz_ak"), "muzzle", 100 },
	{ slot("Trigger", "trigger_auto"), "trigger", 200 },
	{ slot("Trigger", "trigger_manual"), "trigger", 200 },
	{ slot("Trigger", { "trigger_pump" }), "trigger", 200 },
	{ slot("Trigger", "trigger_revolver"), "trigger", 200 },
	{ slot("Trigger", "trigger_semi"), "trigger", 200 },
	{ slot("Tactical", "tactical"), "tactical", 300 },
	{ slot("Tactical", { "tactical_zoom", "tactical_ebullet" }), "tactical", 300 },
	{ slot("Tactical", "tactical_ebullet"), "tactical", 300 },
	{ slot("Ammo", "ammo_pistol"), "ammo", 400 },
	{ slot("Ammo", "ammo_rifle"), "ammo", 400 },
	{ slot("Ammo", "ammo_shotgun"), "ammo", 400 },
	{ slot("Ammo", { "ammo_sniper", "ammo_R700" }), "ammo", 400 },
	{ slot("Ammo", "ammo_R700"), "ammo", 400 },
	{ slot("Ammo", "ammo_roulette"), "ammo", 400 },
	{ slot("Accessory", "acc"), "accessory", 200 },
	{ slot("Accessory", "acc_sling"), "accessory", 200 },
	{ slot("Accessory", { "acc_duffle", "acc_bipod" }), "accessory", 200 },
	{ slot("Accessory", "acc_extmag_sniper"), "accessory", 200 },
	{ slot("Accessory", "acc_holster"), "accessory", 200 },
	{ slot("Accessory", "acc_brace"), "accessory", 200 },
	{ slot("Perk", "perk"), "perk", 700 },
	{ slot("Perk", { "perk_melee", "perk_shooting", "perk_reload" }), "perk", 700 },
	{ slot("Perk", "perk_extendedmag"), "perk", 700 },
}

local mapped = true
for i = 1, #cases do
	local row = cases[i]
	local key = P.Key(row[1])
	local price = P.Cost(row[1])
	if key ~= row[2] or price ~= row[3] then mapped = false end
end
check("every category prefix maps to its price", mapped == true)

local akAcc = slot("Accessory", { "acc", "acc_sling", "acc_duffle", "perk_extendedmag" })
check("an accessory slot that lists perk_extendedmag stays accessory", P.Key(akAcc) == "accessory" and P.Cost(akAcc) == 200)
local perkFirst = slot("Accessory", { "perk_extendedmag", "acc" })
check("the first matching category wins", P.Key(perkFirst) == "perk" and P.Cost(perkFirst) == 700)
local later = slot("Muzzle", { "not_a_real_cat", "muzz_ak" })
check("a later matching category is used", P.Key(later) == "muzzle")
local named = slot("Bolt", { "not_a_real_cat" })
check("PrintName is the fallback", P.Key(named) == "bolt" and P.Cost(named) == 100)
local trimmed = slot("  Optic ", nil)
check("PrintName is trimmed", P.Key(trimmed) == "optic")
local fight = slot("Perk", "optic_cqb")
check("a matching category beats PrintName", P.Key(fight) == "optic" and P.Cost(fight) == 250)
check("an unknown slot has no price", P.Key(slot("Nope", "nope")) == nil and P.Cost(slot("Nope", nil)) == nil)
check("a non-table slot has no key", P.Key("optic") == nil)

check("an override replaces the default", P.Cost(slot("Optic", "optic_cqb"), { optic = 12 }) == 12)
check("an explicit zero stays free", P.Cost(slot("Optic", "optic_cqb"), { optic = 0 }) == 0)
check("a missing override key uses the default", P.Cost(slot("Bolt", "bolt_manual"), {}) == 100)
check("a negative price is rejected", P.Cost(slot("Optic", "optic_cqb"), { optic = -5 }) == nil)

-- A constructed table cannot store nil, so CLEAR drops the field.
local CLEAR = {}

local function gate(over)
	local ctx = {
		phase = "live",
		inZone = true,
		alive = true,
		balance = 1000,
		price = 250,
		detach = false,
	}
	for k, v in pairs(over or {}) do
		if v == CLEAR then
			ctx[k] = nil
		else
			ctx[k] = v
		end
	end
	return P.Gate(ctx)
end

local ok, reason = gate(nil)
check("live in zone with money can attach", ok == true and reason == nil)
ok, reason = gate({ inZone = false })
check("live outside the zone cannot attach", ok == false and reason == "Only at your objective")
ok, reason = gate({ phase = "buy", inZone = false })
check("buy can attach away from the flag", ok == true)
ok, reason = gate({ phase = "lobby" })
check("lobby cannot attach", ok == false and reason == "Only at your objective")
ok, reason = gate({ phase = "post" })
check("post cannot attach", ok == false and reason == "Only at your objective")
ok, reason = gate({ balance = 249 })
check("a short balance cannot attach", ok == false and reason == "Not enough money")
ok, reason = gate({ balance = 250 })
check("an exact balance can attach", ok == true)
ok, reason = gate({ balance = 0, detach = true })
check("empty detach in the zone is refused", ok == false and reason == "Can only replace")
ok, reason = gate({ balance = 0, detach = true, replace = true })
check("replace detach in the zone does not need money", ok == true and reason == nil)
ok, reason = gate({ inZone = false, detach = true, balance = 0 })
check("detach outside the zone is refused", ok == false and reason == "Only at your objective")
ok, reason = gate({ phase = "buy", inZone = false, detach = true, balance = 0 })
check("empty detach during buy is refused", ok == false and reason == "Can only replace")
ok, reason = gate({ phase = "buy", inZone = false, detach = true, replace = true, balance = 0 })
check("replace detach during buy does not need money or the flag", ok == true)
ok, reason = gate({ alive = false })
check("a dead player cannot attach", ok == false and reason == "You are not alive.")
ok, reason = gate({ price = CLEAR })
check("a slot with no price cannot be bought", ok == false and reason == "That slot has no price.")
check("a free slot can be taken", gate({ price = 0, balance = 0 }) == true)

local function client(over)
	local ctx = {
		phase = "live",
		inZone = true,
		alive = true,
		balance = 1000,
		price = 250,
		detach = false,
	}
	for k, v in pairs(over or {}) do
		if v == CLEAR then
			ctx[k] = nil
		else
			ctx[k] = v
		end
	end
	return P.ClientDecide(ctx)
end

ok, reason = client({ inZone = false, balance = 0, detach = true })
check("client empty detach outside the zone is refused", ok == false and reason == "Only at your objective")
ok, reason = client({ phase = "lobby", inZone = false, alive = false, balance = 0, price = 700, detach = true })
check("client empty detach while dead is refused", ok == false and reason == "You are not alive.")
ok, reason = client({ phase = "live", inZone = true, alive = true, balance = 0, detach = true })
check("client empty detach in the zone is refused", ok == false and reason == "Can only replace")
ok, reason = client({ phase = "live", inZone = true, alive = true, balance = 0, detach = true, replace = true })
check("client replace detach does not need money", ok == true and reason == nil)
ok, reason = client({ phase = "buy", inZone = false, alive = true, balance = 0, detach = true, replace = true })
check("client replace during buy does not need the flag", ok == true and reason == nil)
ok, reason = P.Gate({ phase = "live", inZone = false, alive = true, balance = 0, price = 250, detach = true })
check("the server still refuses that detach", ok == false and reason == "Only at your objective")
ok, reason = client({ inZone = false, balance = 1000 })
check("client attach outside the zone is refused", ok == false and reason == "Only at your objective")
ok, reason = client({ balance = 249 })
check("client attach over the balance is refused", ok == false and reason == "Not enough money")
ok, reason = client({ balance = 250 })
check("client attach at the exact balance is allowed", ok == true and reason == nil)
ok, reason = client({ phase = "buy", inZone = false, balance = 250 })
check("client attach during buy does not need the flag", ok == true)
ok, reason = client({ phase = "post", balance = 9999, price = 100 })
check("client attach outside buy and live is refused", ok == false and reason == "Only at your objective")
ok, reason = client({ alive = false, balance = 9999 })
check("client attach while dead is refused", ok == false and reason == "You are not alive.")
ok, reason = client({ price = CLEAR })
check("client attach with no price is refused", ok == false and reason == "That slot has no price.")
check("a bad client context cannot attach", P.ClientDecide(nil) == false)

check("installing from empty charges", P.ShouldCharge(nil, "optic_a", "optic_a") == true)
check("a failed install does not charge", P.ShouldCharge(nil, nil, "optic_a") == false)
check("the same attachment does not charge again", P.ShouldCharge("optic_a", "optic_a", "optic_a") == false)
check("a swap charges the new attachment", P.ShouldCharge("optic_a", "optic_b", "optic_b") == true)
check("a mismatched result does not charge", P.ShouldCharge(nil, "other", "optic_a") == false)
check("charge amount is the slot price", P.ChargeAmount(nil, "optic_a", "optic_a", 250) == 250)
check("no charge means zero", P.ChargeAmount("optic_a", "optic_a", "optic_a", 250) == 0)
check("detach refunds nothing", P.RefundOnDetach(700) == 0 and P.RefundOnDetach(700, true) == 0)
check("the drop button is the bottom centre DButton", P.IsDropButton("DButton", 934, 700, 52, 20, 1920, 720) == true)
check("the news button is not the drop button", P.IsDropButton("DButton", 8, 8, 24, 24, 1920, 720) == false)
check("a slot is not the drop button", P.IsDropButton("TacRPAttSlot", 934, 700, 52, 20, 1920, 720) == false)
local mx, my = P.MoneyPlace(1920, 1080, 160, 24)
check("customize money sits bottom centre", mx == 880 and my == 1048)
check("refund stays off in config", BALLISTICS.Config.AttRefundOnDetach == false)
check("unaffordable is the red case", P.Afford(250, 249) == false and P.Afford(250, 250) == true)

-- Server gate, inventory bypass, and the per-weapon Attach wrap.
function BALLISTICS.PlayerId(ply)
	if type(ply) == "table" and type(ply.SteamID64) == "function" then
		local id = ply:SteamID64()
		if type(id) == "string" and id ~= "" then return id end
	end
	return nil
end

dofile("gamemodes/ballistics/gamemode/modules/customize/sh_attinv.lua")
dofile("gamemodes/ballistics/gamemode/modules/customize/sv_attprice.lua")

local phaseName = "live"
BALLISTICS.Round = { Phase = function() return phaseName end }
BALLISTICS.Spawns = {
	Snapshot = function()
		return {
			good = { pos = { x = 0, y = 0, z = 0 } },
			bad = { pos = { x = 1000, y = 0, z = 0 } },
		}
	end,
}
BALLISTICS.Config.CustomizeRadius = 100

local ply = {
	alive = true,
	teamId = 1,
	pos = { x = 0, y = 0, z = 0 },
}
function ply:IsValid() return true end
function ply:SteamID64() return "76561198000000031" end
function ply:Alive() return self.alive == true end
function ply:Team() return self.teamId end
function ply:GetPos() return self.pos end
function ply:SetNW2Int() end

BALLISTICS.Money.Reset()
check("starting balance is 1000", BALLISTICS.Money.Get(ply) == 1000)

check("att count is unlimited", hook.Run("TacRP_PlayerAttCount", ply, "optic_a") == 9999)
check("a missing player does not fake a count", hook.Run("TacRP_PlayerAttCount", nil, "optic_a") == nil)
check("take is a no-op", hook.Run("TacRP_PlayerTakeAtt", ply, "optic_a", 1) == true)
check("give is a no-op", hook.Run("TacRP_PlayerGiveAtt", ply, "optic_a", 1) == true)

local optic = slot("Optic", { "optic_cqb", "optic_medium" })
local accessory = slot("Accessory", { "acc", "acc_sling", "perk_extendedmag" })

local function gun(attachments, install)
	local wep = { ArcticTacRP = true, Attachments = attachments }
	function wep:IsValid() return true end
	function wep:GetOwner() return ply end
	function wep:Attach(s, att)
		local allow = BALLISTICS.AttPrice.Decide(ply, self, att, s, false)
		if not allow then return end
		local row = self.Attachments[s]
		if row.Installed then return end
		if install then return install(self, s, att) end
		row.Installed = att
	end
	function wep:Detach(s)
		self.Attachments[s].Installed = nil
	end
	return wep
end

ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("decide allows a numbered slot in the zone", ok == true and reason == nil)
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", optic, true)
check("decide refuses an empty detach", ok == false and reason == "Can only replace")
local replacing = { Attachments = { [1] = optic }, BallisticsAttReplacing = 1 }
ok, reason = BALLISTICS.AttPrice.Decide(ply, replacing, "optic_a", 1, true)
check("decide allows a marked replace detach", ok == true and reason == nil)
check("the hook agrees", hook.Run("TacRP_CanCustomize", ply, { Attachments = { [1] = optic } }, "optic_a", 1, false) == true)

ply.pos = { x = 250, y = 0, z = 0 }
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("decide blocks live outside the radius", ok == false and reason == "Only at your objective")
check("the hook blocks it too", hook.Run("TacRP_CanCustomize", ply, { Attachments = { [1] = optic } }, "optic_a", 1, false) == false)
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, true)
check("detach outside the zone is blocked", ok == false and reason == "Only at your objective")

ply.pos = { x = 1000, y = 0, z = 0 }
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("the enemy flag is not the customize zone", ok == false and reason == "Only at your objective")

ply.pos = { x = 0, y = 0, z = 150 }
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("decide counts height", ok == false and reason == "Only at your objective")

ply.pos = { x = 0, y = 0, z = 0 }
phaseName = "buy"
ply.pos = { x = 800, y = 0, z = 0 }
ok = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("buy can attach far from the flag", ok == true)

phaseName = "live"
ply.pos = { x = 0, y = 0, z = 0 }
BALLISTICS.Money.Spend(ply, 900)
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("a broke player cannot attach", ok == false and reason == "Not enough money" and BALLISTICS.Money.Get(ply) == 100)
ok, reason = BALLISTICS.AttPrice.Decide(ply, { Attachments = { [1] = optic } }, "optic_a", 1, true)
check("a broke player cannot detach to empty", ok == false and reason == "Can only replace" and BALLISTICS.Money.Get(ply) == 100)
ok, reason = BALLISTICS.AttPrice.Decide(ply, replacing, "optic_a", 1, true)
check("a broke player can replace in the zone", ok == true and reason == nil and BALLISTICS.Money.Get(ply) == 100)

local brokeGun = gun({ [1] = { PrintName = "Optic", Category = "optic_cqb", Installed = nil } })
hook.Run("WeaponEquip", brokeGun, ply)
brokeGun:Attach(1, "optic_a")
check("a blocked attach does not install or charge", brokeGun.Attachments[1].Installed == nil and BALLISTICS.Money.Get(ply) == 100)

BALLISTICS.Money.Reset()
check("reset restores 1000", BALLISTICS.Money.Get(ply) == 1000)

local accGun = gun({
	[1] = { PrintName = "Accessory", Category = { "acc", "acc_sling", "acc_duffle", "perk_extendedmag" }, Installed = nil },
})
hook.Run("WeaponEquip", accGun, ply)
hook.Run("WeaponEquip", accGun, ply)
accGun:Attach(1, "acc_sling")
check("accessory charges 200 and not the perk price", accGun.Attachments[1].Installed == "acc_sling" and BALLISTICS.Money.Get(ply) == 800)
accGun:Attach(1, "acc_duffle")
check("an occupied slot does not charge again", BALLISTICS.Money.Get(ply) == 800)
accGun:Detach(1)
check("detach does not refund", accGun.Attachments[1].Installed == nil and BALLISTICS.Money.Get(ply) == 800)
accGun:Attach(1, "acc_duffle")
check("a swap pays the full slot price again", accGun.Attachments[1].Installed == "acc_duffle" and BALLISTICS.Money.Get(ply) == 600)

local opticGun = gun({ [1] = { PrintName = "Optic", Category = { "optic_cqb" }, Installed = nil } })
hook.Run("WeaponEquip", opticGun, ply)
opticGun:Attach(1, "optic_a")
check("an optic charges 250", opticGun.Attachments[1].Installed == "optic_a" and BALLISTICS.Money.Get(ply) == 350)

local refused = gun({ [1] = { PrintName = "Optic", Category = "optic_cqb", Installed = nil } }, function() end)
hook.Run("WeaponEquip", refused, ply)
local before = BALLISTICS.Money.Get(ply)
refused:Attach(1, "perk_melee")
check("an attach that does not stick does not charge", refused.Attachments[1].Installed == nil and BALLISTICS.Money.Get(ply) == before)

local plain = { ArcticTacRP = false, Attach = function() end }
hook.Run("WeaponEquip", plain, ply)
check("a non TacRP weapon is not wrapped", plain.BallisticsAttWrapped ~= true)

ply.alive = false
ok, reason = BALLISTICS.AttPrice.Decide(ply, opticGun, "optic_a", 1, false)
check("decide blocks a dead player", ok == false and reason == "You are not alive.")
ply.alive = true

BALLISTICS.Money.Reset()
ply.pos = { x = 0, y = 0, z = 0 }
phaseName = "live"
local function gatedGun(installed)
	local wep = {
		ArcticTacRP = true,
		Attachments = {
			[1] = { PrintName = "Optic", Category = "optic_cqb", Installed = installed },
		},
	}
	function wep:IsValid() return true end
	function wep:GetOwner() return ply end
	function wep:CanAttach(slot, att)
		return BALLISTICS.AttPrice.Decide(ply, self, att, slot, false) == true
	end
	function wep:CanDetach(slot)
		local row = self.Attachments[slot]
		return BALLISTICS.AttPrice.Decide(ply, self, row and row.Installed, slot, true) == true
	end
	function wep:Detach(slot)
		if not self:CanDetach(slot) then return false end
		self.Attachments[slot].Installed = nil
		return true
	end
	function wep:Attach(slot, att)
		if self.Attachments[slot].Installed then return end
		if not self:CanAttach(slot, att) then return end
		self.Attachments[slot].Installed = att
	end
	return wep
end
local gated = gatedGun("optic_a")
hook.Run("WeaponEquip", gated, ply)
local gatedBefore = BALLISTICS.Money.Get(ply)
gated:Detach(1)
check("plain detach leaves the attachment", gated.Attachments[1].Installed == "optic_a" and BALLISTICS.Money.Get(ply) == gatedBefore)
gated:Detach(1, true)
check("a silent detach is not a replace", gated.Attachments[1].Installed == "optic_a" and BALLISTICS.Money.Get(ply) == gatedBefore)
gated:Attach(1, "optic_b")
check("replacing an occupied slot installs and charges", gated.Attachments[1].Installed == "optic_b" and BALLISTICS.Money.Get(ply) == gatedBefore - 250)
BALLISTICS.Money.Spend(ply, BALLISTICS.Money.Get(ply) - 50)
local brokeReplace = BALLISTICS.Money.Get(ply)
gated:Attach(1, "optic_c")
check("a broke replace does not strip the slot", gated.Attachments[1].Installed == "optic_b" and BALLISTICS.Money.Get(ply) == brokeReplace)
BALLISTICS.Money.Reset()

local serverSrc = readAll("gamemodes/ballistics/gamemode/modules/customize/sv_attprice.lua")
check("the server does not refund a detach", not serverSrc:find("Money.Refund", 1, true))
check("client price file compiles", loadfile("gamemodes/ballistics/gamemode/modules/customize/cl_attprice.lua") ~= nil)

-- HUD: price in the corner, red when unaffordable, plus the balance.
CLIENT = true
dofile("gamemodes/ballistics/gamemode/modules/customize/cl_attprice.lua")

local money = 220
function ply:GetNW2Int(key, default)
	if key == "bal_money" then return money end
	return default or 0
end
LocalPlayer = function() return ply end
ScrW = function() return 1920 end

local drawn = {}
draw = {
	SimpleText = function(text, _, _, _, col)
		drawn[#drawn + 1] = { text = text, col = col }
	end,
}

vgui = {
	Create = function(class, parent)
		local panel = { class = class, text = "" }
		function panel:SetText(t) self.text = t end
		function panel:SetFont() end
		function panel:SetTextColor() end
		function panel:SetPos() end
		function panel:SetSize() end
		function panel:SetContentAlignment() end
		function panel:SetMouseInputEnabled() end
		function panel:IsValid() return true end
		function panel:GetClassName() return class end
		function panel:GetChildren() return {} end
		if parent then
			parent.kids[#parent.kids + 1] = panel
		end
		return panel
	end,
}

local hudWep = {
	Attachments = {
		[1] = { PrintName = "Optic", Category = { "optic_cqb" } },
		[2] = { PrintName = "Accessory", Category = { "acc", "perk_extendedmag" } },
		[3] = { PrintName = "Nope", Category = "nope" },
	},
}

local function newSlot(index)
	local panel = { paints = 0, slot = index }
	function panel:GetClassName() return "TacRPAttSlot" end
	function panel:GetSlot() return self.slot end
	function panel:GetWeapon() return hudWep end
	function panel:GetShortName() return "" end
	function panel:GetInstalled() return nil end
	function panel:GetChildren() return {} end
	function panel:PaintOver()
		self.paints = self.paints + 1
	end
	function panel:IsValid() return true end
	return panel
end

local opticSlot = newSlot(1)
local accSlot = newSlot(2)
local root = { kids = { opticSlot, accSlot } }
function root:GetChildren() return self.kids end
function root:GetClassName() return "DPanel" end
function root:IsValid() return true end

hook.Run("TacRP_CreateCustomizeHUD", hudWep, root)

local function paintOf(panel)
	drawn = {}
	panel:PaintOver(64, 64)
	return drawn
end

local opticDraw = paintOf(opticSlot)
local accDraw = paintOf(accSlot)
check("the optic slot paints its own price once", #opticDraw == 1 and opticDraw[1].text == "$250" and opticSlot.paints == 1)
check("unaffordable optic price is red", opticDraw[1].col.r == 220 and opticDraw[1].col.g == 40 and opticDraw[1].col.b == 40)
check("the accessory slot paints 200 and not the perk price", #accDraw == 1 and accDraw[1].text == "$200" and accSlot.paints == 1)
check("an affordable price is not red", accDraw[1].col.r == 235 and accDraw[1].col.g == 235)

local function label()
	for i = 1, #root.kids do
		if root.kids[i].class == "DLabel" then return root.kids[i] end
	end
	return nil
end

check("the screen shows the balance", label() ~= nil and label().text == "$220")
money = 50
root:Think()
check("the balance label follows the wallet", label().text == "$50")

opticDraw = paintOf(opticSlot)
check("wrapping twice does not draw twice", #opticDraw == 1 and opticSlot.paints == 2)

local late = newSlot(2)
root.kids[#root.kids + 1] = late
root:Think()
local lateDraw = paintOf(late)
check("a slot created after the menu still shows its price", #lateDraw == 1 and lateDraw[1].text == "$200" and late.paints == 1)

local blank = newSlot(3)
root.kids[#root.kids + 1] = blank
root:Think()
local blankDraw = paintOf(blank)
check("a slot with no price draws nothing", #blankDraw == 0 and blank.paints == 1)

dofile("gamemodes/ballistics/gamemode/modules/customize/cl_attgate.lua")

local nwPhase = "live"
function ply:GetNW2String(key, default)
	if key == "bal_phase" then return nwPhase end
	return default or ""
end
ply.alive = true
ply.teamId = 1
ply.pos = { x = 0, y = 0, z = 0 }

local ledger = BALLISTICS.Money.Get(ply)
money = 100
ok, reason = BALLISTICS.AttPrice.Predict(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("predicted attach uses NW2 and refuses a short balance", ok == false and reason == "Not enough money" and ledger >= 250)

money = 250
ok, reason = BALLISTICS.AttPrice.Predict(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("predicted attach allows the networked balance in the zone", ok == true and reason == nil)

ply.pos = { x = 400, y = 0, z = 0 }
ok, reason = BALLISTICS.AttPrice.Predict(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("predicted attach outside the zone is refused", ok == false and reason == "Only at your objective")

nwPhase = "buy"
ok, reason = BALLISTICS.AttPrice.Predict(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("predicted attach during buy does not need the flag", ok == true and reason == nil)

money = 0
ply.alive = false
nwPhase = "lobby"
ok, reason = BALLISTICS.AttPrice.Predict(ply, { Attachments = { [1] = optic } }, "optic_a", 1, true)
check("predicted empty detach is refused when dead", ok == false and reason == "You are not alive.")
ply.alive = true
nwPhase = "live"
ply.pos = { x = 0, y = 0, z = 0 }
local marked = { Attachments = { [1] = optic }, BallisticsAttReplacing = 1 }
ok, reason = BALLISTICS.AttPrice.Predict(ply, marked, "optic_a", 1, true)
check("predicted replace detach is allowed in the zone with no money", ok == true and reason == nil)
marked.BallisticsAttReplacing = nil
ok, reason = BALLISTICS.AttPrice.Predict(ply, marked, "optic_a", 1, true)
check("predicted empty detach is refused in the zone", ok == false and reason == "Can only replace")
nwPhase = "lobby"
ok, reason = BALLISTICS.AttPrice.Predict(ply, { Attachments = { [1] = optic } }, "optic_a", 1, false)
check("predicted attach in the lobby does not happen", ok == false and reason == "Only at your objective")

local gateSrc = readAll("gamemodes/ballistics/gamemode/modules/customize/cl_attgate.lua")
check("the client hook is TacRP_CanCustomize", gateSrc:find("TacRP_CanCustomize", 1, true) ~= nil)
check("the client hook reads bal_money", gateSrc:find("bal_money", 1, true) ~= nil)
check("the client hook does not read the server ledger", not gateSrc:find("Money.Get", 1, true))
check("the client holds a replace detach until attach", gateSrc:find("BallisticsPendingReplace", 1, true) ~= nil)

local swaps = 0
local sawReplace = false
local fake = {
	ArcticTacRP = true,
	Attachments = { [1] = { Installed = "optic_a" } },
}
function fake:CanAttach() return self.allow == true end
function fake:Detach(slot)
	swaps = swaps + 1
	sawReplace = self.BallisticsAttReplacing == slot
	self.Attachments[slot].Installed = nil
end
function fake:Attach(slot, att)
	if self.Attachments[slot].Installed then return end
	self.Attachments[slot].Installed = att
end
BALLISTICS.AttPrice.WrapClient(fake)
fake.allow = false
fake:Detach(1, true, true)
fake:Attach(1, "optic_b")
check("a refused replace does not strip", fake.Attachments[1].Installed == "optic_a" and swaps == 0)
fake.allow = true
fake:Detach(1, true, true)
fake:Attach(1, "optic_b")
check("an allowed replace detaches then installs", fake.Attachments[1].Installed == "optic_b" and swaps == 1 and sawReplace == true)

-- Knife slots: Technique 300, Special 500, Boost 500.
check("melee_tech costs 300", BALLISTICS.AttPrice.Cost({ Category = "melee_tech" }) == 300)
check("melee_spec costs 500", BALLISTICS.AttPrice.Cost({ Category = "melee_spec" }) == 500)
check("melee_boost costs 500", BALLISTICS.AttPrice.Cost({ Category = "melee_boost" }) == 500)

if failed then os.exit(1) end
