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

local function paintBar(rect, bar)
	local x, y = rect.x, rect.y
	local bw, bh = rect.w, rect.h
	local col = (BALLISTICS.TeamColor and BALLISTICS.TeamColor[bar.team]) or Color(255, 255, 255)
	local r = col.r or 255
	local g = col.g or 255
	local b = col.b or 255
	surface.SetDrawColor(0, 0, 0, 170)
	surface.DrawRect(x, y, bw, bh)
	local fill = math.floor(bw * (tonumber(bar.progress) or 0) + 0.5)
	if fill < 0 then fill = 0 end
	if fill > bw then fill = bw end
	if fill > 0 then
		surface.SetDrawColor(r, g, b, 210)
		surface.DrawRect(x, y, fill, bh)
	end
	if surface.DrawOutlinedRect then
		surface.SetDrawColor(r, g, b, 255)
		surface.DrawOutlinedRect(x, y, bw, bh)
	end
	if draw and type(draw.SimpleText) == "function" then
		draw.SimpleText(
			bar.text or "",
			"BallisticsCapture",
			x + bw / 2,
			y + bh / 2,
			Color(255, 255, 255),
			TEXT_ALIGN_CENTER or 1,
			TEXT_ALIGN_CENTER or 1
		)
	end
end

local function fallbackRects(screenW, barCount)
	local rects = {}
	local x = math.floor((screenW - BAR_W) / 2)
	if x < 0 then x = 0 end
	local y = 8
	for i = 1, barCount do
		rects[i] = { x = x, y = y, w = BAR_W, h = BAR_H }
		y = y + BAR_H + BAR_GAP
	end
	return rects
end

local function paint()
	local cap = BALLISTICS.Capture
	if not cap or type(cap.View) ~= "function" or type(cap.Bars) ~= "function" then return end
	if not surface or type(surface.DrawRect) ~= "function" or type(surface.SetDrawColor) ~= "function" then return end
	local good, bad = cap.View()
	local bars = cap.Bars(good, bad)
	if #bars == 0 then return end
	local sw = (ScrW and ScrW()) or 0
	local rects
	if type(cap.BarRects) == "function" then
		rects = cap.BarRects(sw, #bars)
	end
	if type(rects) ~= "table" or #rects < #bars then
		rects = fallbackRects(sw, #bars)
	end
	for i = 1, #bars do
		paintBar(rects[i], bars[i])
	end
end

if hook and hook.Add then
	hook.Add("HUDPaint", "Ballistics_CaptureBar", paint)
end
