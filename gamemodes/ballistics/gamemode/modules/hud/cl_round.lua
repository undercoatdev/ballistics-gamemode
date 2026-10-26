-- Small phase and timer at the top centre. It drops below the capture bars
-- while those are on screen. The clock comes from bal_round_sync, with the
-- buy-phase NW2 ints as a fallback before that message arrives.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsRound", { font = "Roboto", size = 14, weight = 600, antialias = true })
end

local FONT = "BallisticsRound"

local function localPlayer()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	if IsValid and not IsValid(ply) then return nil end
	return ply
end

-- NW2 is published with the phase. Once bal_round_sync has the same phase,
-- that clock wins so a late buy-module write cannot move the end time.
local function pullNW2()
	local hud = BALLISTICS.RoundHud
	if not hud or type(hud.Apply) ~= "function" then return end
	local ply = localPlayer()
	if ply == nil or type(ply.GetNW2String) ~= "function" then return end
	local phase = ply:GetNW2String("bal_phase", "")
	if type(phase) ~= "string" or phase == "" then return end
	if hud.Seen and hud.Seen() and hud.Snapshot then
		local current = hud.Snapshot()
		if current and current.phase == phase then return end
	end
	local ends = 0
	if type(ply.GetNW2Float) == "function" then
		ends = ply:GetNW2Float("bal_phase_ends", 0) or 0
	end
	hud.Apply({ phase = phase, endsAt = ends })
end

local function barCount()
	local cap = BALLISTICS.Capture
	if not cap or type(cap.View) ~= "function" or type(cap.Bars) ~= "function" then return 0 end
	local good, bad = cap.View()
	local bars = cap.Bars(good, bad)
	if type(bars) ~= "table" then return 0 end
	return #bars
end

local function paint()
	local hud = BALLISTICS.RoundHud
	if not hud or type(hud.Line) ~= "function" or type(hud.Place) ~= "function" then return end
	if not draw or type(draw.SimpleText) ~= "function" then return end
	pullNW2()
	local now = (CurTime and CurTime()) or 0
	local line = hud.Line(now)
	if type(line) ~= "string" or line == "" then return end
	local sw = (ScrW and ScrW()) or 0
	local rect = hud.Place(sw, barCount())
	if not rect then return end
	local x = rect.x + rect.w / 2
	local y = rect.y + rect.h / 2
	local ax = TEXT_ALIGN_CENTER or 1
	local ay = TEXT_ALIGN_CENTER or 1
	draw.SimpleText(line, FONT, x + 1, y + 1, Color(0, 0, 0, 200), ax, ay)
	draw.SimpleText(line, FONT, x, y, Color(235, 235, 235), ax, ay)
end

if hook and hook.Add then
	hook.Add("HUDPaint", "Ballistics_Round", paint)
end
