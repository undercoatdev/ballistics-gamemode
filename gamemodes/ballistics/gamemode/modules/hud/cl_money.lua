-- Bottom-middle "$balance", with "+pending" in green on its right.
-- Both numbers are the local player's NW2 ints bal_money and bal_pending.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsMoney", { font = "Roboto", size = 22, weight = 700, antialias = true })
end

local FONT = "BallisticsMoney"
local GAP = 12

local function localPlayer()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	if IsValid and not IsValid(ply) then return nil end
	return ply
end

local function readInts(ply)
	if ply == nil or type(ply.GetNW2Int) ~= "function" then return 0, 0 end
	return ply:GetNW2Int("bal_money", 0), ply:GetNW2Int("bal_pending", 0)
end

local function textWidth(text)
	if surface and surface.SetFont and surface.GetTextSize then
		surface.SetFont(FONT)
		local w = surface.GetTextSize(text)
		if type(w) == "number" and w > 0 then return w end
	end
	return #tostring(text) * 12
end

local function paintText(text, x, y, col)
	local shadow = Color(0, 0, 0, 200)
	local ink = Color(col.r or 255, col.g or 255, col.b or 255)
	local ax = TEXT_ALIGN_LEFT or 0
	local ay = TEXT_ALIGN_CENTER or 1
	draw.SimpleText(text, FONT, x + 1, y + 1, shadow, ax, ay)
	draw.SimpleText(text, FONT, x, y, ink, ax, ay)
end

local function paint()
	local hud = BALLISTICS.MoneyHud
	if not hud or type(hud.Parts) ~= "function" or type(hud.Place) ~= "function" then return end
	if not draw or type(draw.SimpleText) ~= "function" then return end
	local balance, pending = readInts(localPlayer())
	local left, right = hud.Parts(balance, pending)
	local place = hud.Place((ScrW and ScrW()) or 0, (ScrH and ScrH()) or 0, textWidth(left), textWidth(right), GAP)
	if not place or not place.balance or not place.pending then return end
	local colors = (type(hud.Colors) == "function" and hud.Colors()) or {}
	local bc = colors.balance or { r = 245, g = 245, b = 245 }
	local pc = colors.pending or { r = 80, g = 220, b = 110 }
	local by = place.balance.y + (place.balance.h or 0) / 2
	local py = place.pending.y + (place.pending.h or 0) / 2
	paintText(left, place.balance.x, by, bc)
	paintText(right, place.pending.x, py, pc)
end

if hook and hook.Add then
	hook.Add("HUDPaint", "Ballistics_Money", paint)
end
