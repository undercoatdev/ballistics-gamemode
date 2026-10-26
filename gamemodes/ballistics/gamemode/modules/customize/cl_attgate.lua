-- Client TacRP_CanCustomize. Predicted SWEP:Attach checks this before it
-- installs anything or tells the server. A false answer is what stops that
-- prediction. Detach is always allowed here; the server still validates it.
-- Balance is the local NW2 bal_money, not the server ledger.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.AttPrice = BALLISTICS.AttPrice or {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function valid(ply)
	if ply == nil or ply == false then return false end
	local kind = type(ply)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Player" and kind ~= "Entity" then
		return false
	end
	if type(ply.IsValid) == "function" then return ply:IsValid() == true end
	if kind ~= "table" and IsValid then return IsValid(ply) == true end
	return kind == "table"
end

local function radius()
	local n = BALLISTICS.Config and tonumber(BALLISTICS.Config.CustomizeRadius)
	if not finite(n) or n <= 0 then n = 2 / 0.01905 end
	return n
end

local function phaseOf(ply)
	if valid(ply) and type(ply.GetNW2String) == "function" then
		local p = ply:GetNW2String("bal_phase", "")
		if type(p) == "string" and p ~= "" then return p end
	end
	return "lobby"
end

local function teamOf(ply)
	if not valid(ply) or type(ply.Team) ~= "function" then return nil end
	return ply:Team()
end

local function inZone(ply)
	if not valid(ply) or type(ply.GetPos) ~= "function" then return false end
	local ckey = BALLISTICS.CKey
	if not ckey or type(ckey.FlagPos) ~= "function" or type(ckey.InRadius) ~= "function" then
		return false
	end
	local snap
	if BALLISTICS.Spawns and type(BALLISTICS.Spawns.Snapshot) == "function" then
		snap = BALLISTICS.Spawns.Snapshot()
	end
	return ckey.InRadius(ply:GetPos(), ckey.FlagPos(snap, teamOf(ply)), radius())
end

local function aliveOf(ply)
	if not valid(ply) or type(ply.Alive) ~= "function" then return false end
	return ply:Alive() == true
end

-- Prefer the owner TacRP passed. Fall back to the local player. Never the ledger.
local function balanceOf(ply)
	local target = ply
	if not valid(target) or type(target.GetNW2Int) ~= "function" then
		if LocalPlayer then target = LocalPlayer() end
	end
	if target == nil or type(target.GetNW2Int) ~= "function" then return 0 end
	local n = tonumber(target:GetNW2Int("bal_money", 0))
	if not finite(n) then return 0 end
	return n
end

local function slotTable(wep, slot)
	if type(slot) == "table" then return slot end
	local n = tonumber(slot)
	if n == nil or wep == nil or type(wep.Attachments) ~= "table" then return nil end
	local slottbl = wep.Attachments[n]
	if type(slottbl) ~= "table" then return nil end
	return slottbl
end

-- att is unused. The slot category sets the price, not the attachment.
function BALLISTICS.AttPrice.Predict(ply, wep, att, slot, detach)
	if detach == true then
		return BALLISTICS.AttPrice.ClientDecide({ detach = true })
	end
	local slottbl = slotTable(wep, slot)
	local price
	if slottbl and type(BALLISTICS.AttPrice.Cost) == "function" then
		price = BALLISTICS.AttPrice.Cost(slottbl)
	end
	return BALLISTICS.AttPrice.ClientDecide({
		detach = false,
		phase = phaseOf(ply),
		inZone = inZone(ply),
		alive = aliveOf(ply),
		balance = balanceOf(ply),
		price = price,
	})
end

if hook and hook.Add then
	hook.Add("TacRP_CanCustomize", "Ballistics_AttGateClient", function(ply, wep, att, slot, detach)
		return BALLISTICS.AttPrice.Predict(ply, wep, att, slot, detach)
	end)
end
