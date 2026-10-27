-- Sell-back in the buy phase: anything you own (except the knife) at full
-- catalog price. A gun also refunds its installed attachments at their
-- current Rules > Costs price, since attachments cost money here.
BALLISTICS = BALLISTICS or {}
BALLISTICS.Sell = BALLISTICS.Sell or {}
local S = BALLISTICS.Sell

S.KNIFE = "tacrp_knife"
S.SOUND = "buttons/lightswitch2.wav"

-- ctx: phase, alive, slotted, item, have (count owned), price, attRefund
function S.Plan(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local item = ctx.item
	if ctx.phase ~= "buy" then return { ok = false, err = "phase" } end
	if ctx.alive ~= true or ctx.slotted ~= true then return { ok = false, err = "player" } end
	if type(item) ~= "table" then return { ok = false, err = "item" } end
	if item.class == S.KNIFE or item.key == S.KNIFE then return { ok = false, err = "knife" } end
	if (tonumber(ctx.have) or 0) < 1 then return { ok = false, err = "none" } end
	local price = math.max(0, math.floor(tonumber(ctx.price) or 0))
	local att = 0
	if item.kind == "weapon" then att = math.max(0, math.floor(tonumber(ctx.attRefund) or 0)) end
	return { ok = true, refund = price + att, price = price, att = att }
end

function S.Label(amount)
	return "+$" .. tostring(math.floor(tonumber(amount) or 0))
end
