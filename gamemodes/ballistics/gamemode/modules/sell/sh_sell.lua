-- Sell-back in the buy phase: anything you own (except the knife) at full
-- catalog price. A gun also refunds its installed attachments at their
-- current Rules > Costs price, since attachments cost money here.
BALLISTICS = BALLISTICS or {}
BALLISTICS.Sell = BALLISTICS.Sell or {}
local S = BALLISTICS.Sell

S.KNIFE = "tacrp_knife"
S.SOUND = "buttons/lightswitch2.wav"

-- ctx: phase, alive, slotted, item, have (count owned), price, attRefund.
-- fresh, when set, is how many of this item were bought this buy phase.
-- Below 1 means the gear was carried in, and it does not sell.
function S.Plan(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local item = ctx.item
	if ctx.phase ~= "buy" then return { ok = false, err = "phase" } end
	if ctx.alive ~= true or ctx.slotted ~= true then return { ok = false, err = "player" } end
	if type(item) ~= "table" then return { ok = false, err = "item" } end
	if item.class == S.KNIFE or item.key == S.KNIFE then return { ok = false, err = "knife" } end
	if (tonumber(ctx.have) or 0) < 1 then return { ok = false, err = "none" } end
	if ctx.fresh ~= nil and (tonumber(ctx.fresh) or 0) < 1 then return { ok = false, err = "used" } end
	local price = math.max(0, math.floor(tonumber(ctx.price) or 0))
	local att = 0
	if item.kind == "weapon" then att = math.max(0, math.floor(tonumber(ctx.attRefund) or 0)) end
	return { ok = true, refund = price + att, price = price, att = att }
end

function S.Label(amount)
	return "+$" .. tostring(math.floor(tonumber(amount) or 0))
end

-- Undo one buy of this item in this phase's BuyLimits row, never below 0.
function S.Unbuy(row, item)
	if type(row) ~= "table" or type(item) ~= "table" then return row end
	if item.kind == "weapon" then
		row.weapons = math.max(0, (tonumber(row.weapons) or 0) - 1)
	elseif item.kind == "nade" and type(row.nades) == "table" and item.key then
		local n = math.max(0, (tonumber(row.nades[item.key]) or 0) - 1)
		row.nades[item.key] = n > 0 and n or nil
	end
	return row
end

-- Fresh buys this phase: "key:n,key:n", keys sorted, n > 0 only.
function S.Encode(map)
	if type(map) ~= "table" then return "" end
	local keys = {}
	for key, n in pairs(map) do
		n = tonumber(n)
		if type(key) == "string" and key ~= "" and n ~= nil and n > 0 then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	local parts = {}
	for i = 1, #keys do
		local n = math.floor(tonumber(map[keys[i]]) or 0)
		if n > 0 then parts[#parts + 1] = keys[i] .. ":" .. tostring(n) end
	end
	return table.concat(parts, ",")
end

function S.Decode(str)
	local map = {}
	if type(str) ~= "string" or str == "" then return map end
	for part in string.gmatch(str, "[^,]+") do
		local key, num = string.match(part, "^%s*([%w_]+)%s*:%s*(%d+)%s*$")
		num = tonumber(num)
		if key and num and num > 0 then map[key] = math.floor(num) end
	end
	return map
end

function S.FreshAdd(map, key, n)
	if type(map) ~= "table" or type(key) ~= "string" or key == "" then return end
	n = math.floor(tonumber(n) or 0)
	if n < 1 then return end
	local cur = math.floor(tonumber(map[key]) or 0)
	if cur < 0 then cur = 0 end
	map[key] = cur + n
end

-- Decrement one. Removes the key at zero. False when there was nothing to take.
function S.FreshTake(map, key)
	if type(map) ~= "table" or type(key) ~= "string" or key == "" then return false end
	local cur = math.floor(tonumber(map[key]) or 0)
	if cur < 1 then
		map[key] = nil
		return false
	end
	cur = cur - 1
	if cur < 1 then map[key] = nil else map[key] = cur end
	return true
end
