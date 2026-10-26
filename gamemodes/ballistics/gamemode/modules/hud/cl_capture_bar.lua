-- Top-middle capture bar. Hidden until either flag has progress.
-- Colour and label are the flag being taken. The circles stay on the spawns.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsCapture", { font = "Roboto", size = 16, weight = 700, antialias = true })
end

local BAR_W = 300
local BAR_H = 18
local BAR_GAP = 6

local function paintBar(x, y, bar)
	local col = (BALLISTICS.TeamColor and BALLISTICS.TeamColor[bar.team]) or Color(255, 255, 255)
	local r = col.r or 255
	local g = col.g or 255
	local b = col.b or 255
	surface.SetDrawColor(0, 0, 0, 170)
	surface.DrawRect(x, y, BAR_W, BAR_H)
	local fill = math.floor(BAR_W * (tonumber(bar.progress) or 0) + 0.5)
	if fill < 0 then fill = 0 end
	if fill > BAR_W then fill = BAR_W end
	if fill > 0 then
		surface.SetDrawColor(r, g, b, 210)
		surface.DrawRect(x, y, fill, BAR_H)
	end
	if surface.DrawOutlinedRect then
		surface.SetDrawColor(r, g, b, 255)
		surface.DrawOutlinedRect(x, y, BAR_W, BAR_H)
	end
	if draw and type(draw.SimpleText) == "function" then
		draw.SimpleText(
			bar.text or "",
			"BallisticsCapture",
			x + BAR_W / 2,
			y + BAR_H / 2,
			Color(255, 255, 255),
			TEXT_ALIGN_CENTER or 1,
			TEXT_ALIGN_CENTER or 1
		)
	end
end

local function paint()
	local cap = BALLISTICS.Capture
	if not cap or type(cap.View) ~= "function" or type(cap.Bars) ~= "function" then return end
	if not surface or type(surface.DrawRect) ~= "function" or type(surface.SetDrawColor) ~= "function" then return end
	local good, bad = cap.View()
	local bars = cap.Bars(good, bad)
	if #bars == 0 then return end
	local sw = (ScrW and ScrW()) or 0
	local x = math.floor((sw - BAR_W) / 2)
	if x < 0 then x = 0 end
	local y = 8
	for i = 1, #bars do
		paintBar(x, y, bars[i])
		y = y + BAR_H + BAR_GAP
	end
end

if hook and hook.Add then
	hook.Add("HUDPaint", "Ballistics_CaptureBar", paint)
end
