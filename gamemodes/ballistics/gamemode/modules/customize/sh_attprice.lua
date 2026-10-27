-- Pure attachment prices. No game API.
-- The price key is the first slot category that matches a prefix, not the
-- attachment that is about to be installed. PrintName is only the fallback,
-- so an Accessory slot that also lists perk_extendedmag stays an accessory.
-- An empty detach is refused. A replace (detach that is part of fitting a
-- different attachment in the same slot) is allowed and still costs the slot.
-- Detach never refunds.

BALLISTICS = BALLISTICS or {}
BALLISTICS.AttPrice = BALLISTICS.AttPrice or {}

local P = BALLISTICS.AttPrice

local DEFAULTS = {
	optic = 250,
	bolt = 100,
	muzzle = 100,
	trigger = 200,
	tactical = 300,
	ammo = 400,
	accessory = 200,
	perk = 700,
	technique = 300,
	special = 500,
	boost = 500,
}

-- First matching rule wins for a single category string.
local RULES = {
	{ key = "optic", exact = {}, prefix = { "optic_", "ironsights_" } },
	{ key = "bolt", exact = {}, prefix = { "bolt_" } },
	{ key = "muzzle", exact = { "silencer" }, prefix = { "muzz_" } },
	{ key = "trigger", exact = {}, prefix = { "trigger_" } },
	{ key = "tactical", exact = { "tactical" }, prefix = { "tactical_" } },
	{ key = "ammo", exact = {}, prefix = { "ammo_" } },
	{ key = "accessory", exact = { "acc" }, prefix = { "acc_" } },
	{ key = "perk", exact = { "perk" }, prefix = { "perk_" } },
	-- Melee (knife) slots. TacRP categories melee_tech / melee_spec / melee_boost.
	{ key = "technique", exact = { "melee_tech" }, prefix = { "melee_tech_" } },
	{ key = "special", exact = { "melee_spec" }, prefix = { "melee_spec_" } },
	{ key = "boost", exact = { "melee_boost" }, prefix = { "melee_boost_" } },
}

local BY_NAME = {
	optic = "optic",
	bolt = "bolt",
	muzzle = "muzzle",
	trigger = "trigger",
	tactical = "tactical",
	ammo = "ammo",
	accessory = "accessory",
	perk = "perk",
	technique = "technique",
	special = "special",
	boost = "boost",
}

local function norm(text)
	if type(text) ~= "string" then return "" end
	text = string.lower(text)
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text
end

local function hit(cat, rule)
	local exact = rule.exact
	for i = 1, #exact do
		if cat == exact[i] then return true end
	end
	local prefix = rule.prefix
	for i = 1, #prefix do
		local p = prefix[i]
		if cat:sub(1, #p) == p then return true end
	end
	return false
end

local function matchCategory(cat)
	cat = norm(cat)
	if cat == "" then return nil end
	for i = 1, #RULES do
		if hit(cat, RULES[i]) then return RULES[i].key end
	end
	return nil
end

local function categoryList(slot)
	local cat = slot.Category
	if type(cat) == "string" then
		if cat == "" then return {} end
		return { cat }
	end
	if type(cat) ~= "table" then return {} end
	local list = {}
	local n = #cat
	if n > 0 then
		for i = 1, n do
			if type(cat[i]) == "string" and cat[i] ~= "" then
				list[#list + 1] = cat[i]
			end
		end
		return list
	end
	for _, value in pairs(cat) do
		if type(value) == "string" and value ~= "" then
			list[#list + 1] = value
		end
	end
	return list
end

function P.Key(slot)
	if type(slot) ~= "table" then return nil end
	local cats = categoryList(slot)
	for i = 1, #cats do
		local key = matchCategory(cats[i])
		if key then return key end
	end
	local name = BY_NAME[norm(slot.PrintName)]
	if name then return name end
	return nil
end

-- costs nil reads Config.AttCosts. A missing key falls back to the shipped
-- default. An explicit 0 stays free. A negative value is not a price.
function P.Cost(slot, costs)
	local key = P.Key(slot)
	if not key then return nil, nil end
	if costs == nil and BALLISTICS.Config then
		costs = BALLISTICS.Config.AttCosts
	end
	local price
	if type(costs) == "table" then price = tonumber(costs[key]) end
	if price == nil then price = DEFAULTS[key] end
	if price == nil or price ~= price or price < 0 or price == math.huge then
		return nil, key
	end
	return math.floor(price), key
end

function P.Afford(price, balance)
	price = tonumber(price)
	balance = tonumber(balance)
	if price == nil or balance == nil then return false end
	if price ~= price or balance ~= balance then return false end
	return balance >= price
end

-- True when this customize call is the detach half of a replace.
-- TacRP's menu does that as Detach(slot, true, true) before Attach. The hook
-- itself only receives detach==true, so the weapon carries the mark.
function P.IsReplace(wep, slot)
	if wep == nil or wep == false then return false end
	local kind = type(wep)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Entity" and kind ~= "Weapon" then
		return false
	end
	local mark = wep.BallisticsAttReplacing
	if mark == true then return true end
	if mark == nil or mark == false then return false end
	return mark == slot
end

-- The Drop Weapon button is the DButton centred on the bottom of the customize
-- screen. The news button sits at the top left, so it does not match.
function P.IsDropButton(className, x, y, w, h, screenW, screenH)
	if className ~= "DButton" then return false end
	x = tonumber(x) or 0
	y = tonumber(y) or 0
	w = tonumber(w) or 0
	h = tonumber(h) or 0
	screenW = tonumber(screenW) or 0
	screenH = tonumber(screenH) or 0
	if w <= 0 or h <= 0 or screenW <= 0 or screenH <= 0 then return false end
	local cx = x + w / 2
	if math.abs(cx - screenW / 2) > 8 then return false end
	if y < screenH * 0.75 then return false end
	return true
end

-- Bottom-centre spot where the Drop Weapon button sat.
function P.MoneyPlace(screenW, screenH, labelW, labelH)
	local sw = tonumber(screenW) or 0
	local sh = tonumber(screenH) or 0
	local lw = tonumber(labelW) or 0
	local lh = tonumber(labelH) or 0
	if sw < 0 then sw = 0 end
	if sh < 0 then sh = 0 end
	if lw < 0 then lw = 0 end
	if lh < 0 then lh = 0 end
	local x = math.floor((sw - lw) / 2)
	if x < 0 then x = 0 end
	local y = math.floor(sh - lh - 8)
	if y < 0 then y = 0 end
	return x, y
end

-- ctx.detach with ctx.replace skips the balance check. Location still applies:
-- BUY anywhere, or LIVE inside the own-flag radius. An empty detach is refused.
function P.Gate(ctx)
	if type(ctx) ~= "table" then return false, "Only at your objective" end
	if ctx.alive == false then return false, "You are not alive." end
	local place = ctx.phase == "buy" or (ctx.phase == "live" and ctx.inZone == true)
	if not place then return false, "Only at your objective" end
	if ctx.detach == true then
		if ctx.replace ~= true then return false, "Can only replace" end
		return true
	end
	local price = tonumber(ctx.price)
	if price == nil or price ~= price or price < 0 or price == math.huge then
		return false, "That slot has no price."
	end
	local balance = tonumber(ctx.balance) or 0
	if balance < price then return false, "Not enough money" end
	return true
end

-- Client prediction. TacRP calls CanCustomize from the shared CanAttach,
-- which runs on the client before the predicted install and the net message.
-- Empty detach is refused here too, so the menu does not strip a slot the
-- server will keep. A replace detach uses the same place rules as Gate.
function P.ClientDecide(ctx)
	return P.Gate(ctx)
end

local function blank(v)
	return v == nil or v == false or v == ""
end

-- True only when this call is what installed `att`. A swap is a detach
-- followed by an attach, so the attach is charged the full slot price.
function P.ShouldCharge(before, after, att)
	if blank(att) or blank(after) then return false end
	if after ~= att then return false end
	if not blank(before) and before == after then return false end
	return true
end

function P.ChargeAmount(before, after, att, price)
	if not P.ShouldCharge(before, after, att) then return 0 end
	local n = tonumber(price)
	if n == nil or n ~= n or n <= 0 or n == math.huge then return 0 end
	return math.floor(n)
end

-- Detach does not pay anything back. AttRefundOnDetach stays off.
function P.RefundOnDetach()
	return 0
end
