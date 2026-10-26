-- Big centred line when a round or the match ends.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsBanner", { font = "Roboto", size = 48, weight = 800, antialias = true })
end

local FONT = "BallisticsBanner"

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_banner", function()
		local kind = net.ReadString()
		local winner = net.ReadString()
		if BALLISTICS.Banner and BALLISTICS.Banner.Show then
			BALLISTICS.Banner.Show(kind, winner, (CurTime and CurTime()) or 0)
		end
	end)
end

local function paint()
	local banner = BALLISTICS.Banner
	if not banner or type(banner.Current) ~= "function" then return end
	if not draw or type(draw.SimpleText) ~= "function" then return end
	local now = (CurTime and CurTime()) or 0
	local text, col = banner.Current(now)
	if type(text) ~= "string" or text == "" then return end
	col = col or {}
	local sw = (ScrW and ScrW()) or 0
	local sh = (ScrH and ScrH()) or 0
	local x = sw * 0.5
	local y = sh * 0.38
	local ax = TEXT_ALIGN_CENTER or 1
	local ay = TEXT_ALIGN_CENTER or 1
	local ink = Color(col.r or 255, col.g or 255, col.b or 255, col.a or 255)
	draw.SimpleText(text, FONT, x + 2, y + 2, Color(0, 0, 0, 220), ax, ay)
	draw.SimpleText(text, FONT, x, y, ink, ax, ay)
end

if hook and hook.Add then
	hook.Add("HUDPaint", "Ballistics_Banner", paint)
end
