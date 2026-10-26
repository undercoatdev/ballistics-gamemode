-- Pure attachment prices. No game API.
-- The price key is the first slot category that matches a prefix, not the
-- attachment that is about to be installed. PrintName is only the fallback,
-- so an Accessory slot that also lists perk_extendedmag stays an accessory.
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

-- ctx.detach skips the balance check. Location still applies:
-- BUY anywhere, or LIVE inside the own-flag radius.
function P.Gate(ctx)
	if type(ctx) ~= "table" then return false, "Only at your objective" end
	if ctx.alive == false then return false, "You are not alive." end
	local place = ctx.phase == "buy" or (ctx.phase == "live" and ctx.inZone == true)
	if not place then return false, "Only at your objective" end
	if ctx.detach == true then return true end
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
-- Detach is always allowed here. Attach uses the same place and money rules
-- as Gate, with the balance taken from the local player's networked money.
function P.ClientDecide(ctx)
	if type(ctx) == "table" and ctx.detach == true then return true end
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
