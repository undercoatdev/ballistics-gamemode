-- Losers see a centred countdown while the firing squad holds them still.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}

local state = { active = false, winner = "", freezeEnd = 0, frozen = false }

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsSquadFreeze", { font = "Roboto", size = 64, weight = 800, antialias = true })
end

local FONT = "BallisticsSquadFreeze"

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_squad", function()
		state.active = net.ReadBool() == true
		state.winner = net.ReadString() or ""
		state.freezeEnd = net.ReadFloat() or 0
		state.frozen = net.ReadBool() == true
	end)
end

local function localPlayer()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	if IsValid and not IsValid(ply) then return nil end
	return ply
end

local function paint()
	if not state.active or not state.frozen then return end
	local squad = BALLISTICS.Squad
	if not squad or type(squad.FreezeLabel) ~= "function" then return end
	if not draw or type(draw.SimpleText) ~= "function" then return end
	local ply = localPlayer()
	if ply and ply.Alive and ply:Alive() == false then return end
	local now = (CurTime and CurTime()) or 0
	local label = squad.FreezeLabel((state.freezeEnd or 0) - now)
	if type(label) ~= "string" then return end
	local sw = (ScrW and ScrW()) or 0
	local sh = (ScrH and ScrH()) or 0
	local x = sw * 0.5
	local y = sh * 0.52
	local ax = TEXT_ALIGN_CENTER or 1
	local ay = TEXT_ALIGN_CENTER or 1
	draw.SimpleText(label, FONT, x + 2, y + 2, Color(0, 0, 0, 220), ax, ay)
	draw.SimpleText(label, FONT, x, y, Color(255, 255, 255), ax, ay)
end

if hook and hook.Add then
	hook.Add("HUDPaint", "Ballistics_SquadFreeze", paint)
end
