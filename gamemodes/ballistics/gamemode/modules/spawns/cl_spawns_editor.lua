-- Overhead spawn editor and the flag circles everyone sees.
-- Scroll zooms, WASD pans, click traces straight down and asks the server to place.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spawns = BALLISTICS.Spawns or {}

local D = BALLISTICS.SpawnData
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local view = { map = "", source = "none", dirty = false, good = nil, bad = nil }
local listeners = {}
local side = GOOD
local editing = false
local cam = nil
local toolbar = nil
local wheelAt = 0

local function emit()
	for i = 1, #listeners do
		local fn = listeners[i]
		if fn then fn() end
	end
end

function BALLISTICS.Spawns.Listen(fn)
	if type(fn) ~= "function" then return end
	listeners[#listeners + 1] = fn
end

function BALLISTICS.Spawns.Snapshot()
	return {
		map = view.map,
		source = view.source,
		dirty = view.dirty == true,
		good = view.good,
		bad = view.bad,
	}
end

function BALLISTICS.Spawns.Side()
	return side
end

function BALLISTICS.Spawns.SetSide(teamId)
	teamId = tonumber(teamId)
	if teamId ~= GOOD and teamId ~= BAD then return end
	side = teamId
	emit()
end

function BALLISTICS.Spawns.IsEditing()
	return editing == true
end

local function syncCursor()
	if BALLISTICS.UI and BALLISTICS.UI.SyncCursor then
		BALLISTICS.UI.SyncCursor()
		return
	end
	if gui and gui.EnableScreenClicker then
		gui.EnableScreenClicker(editing or (IsValid(toolbar) and toolbar:IsVisible()))
	end
end

local function send(op, team, pos, ang)
	if not net or not net.Start then return end
	pos = pos or {}
	ang = ang or {}
	net.Start("bal_spawn_place")
	net.WriteUInt(op or 0, 8)
	net.WriteUInt(team or 0, 8)
	net.WriteFloat(tonumber(pos.x) or 0)
	net.WriteFloat(tonumber(pos.y) or 0)
	net.WriteFloat(tonumber(pos.z) or 0)
	net.WriteFloat(tonumber(ang.p) or 0)
	net.WriteFloat(tonumber(ang.y) or 0)
	net.WriteFloat(tonumber(ang.r) or 0)
	net.SendToServer()
end

function BALLISTICS.Spawns.RequestSave()
	send(D.OP_SAVE, 0)
end

function BALLISTICS.Spawns.RequestReset()
	send(D.OP_RESET, 0)
end

function BALLISTICS.Spawns.ConfirmReset()
	local function go()
		BALLISTICS.Spawns.RequestReset()
	end
	if not Derma_Query then
		go()
		return
	end
	Derma_Query(
		"Reset this map's flags to the built-in defaults? A saved layout for this map is removed.",
		"Reset to defaults",
		"Reset",
		go,
		"Cancel",
		function() end
	)
end

local function readFlag()
	if not net.ReadBool() then return nil end
	return {
		pos = { x = net.ReadFloat(), y = net.ReadFloat(), z = net.ReadFloat() },
		ang = { p = net.ReadFloat(), y = net.ReadFloat(), r = net.ReadFloat() },
	}
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_spawns_sync", function()
		view.map = net.ReadString() or ""
		view.source = net.ReadString() or "none"
		view.dirty = net.ReadBool() == true
		view.good = readFlag()
		view.bad = readFlag()
		emit()
	end)
end

local function aspect()
	local sw = (ScrW and ScrW()) or 1280
	local sh = (ScrH and ScrH()) or 720
	if sw < 1 then sw = 1 end
	if sh < 1 then sh = 1 end
	return sw / sh, sw, sh
end

local function vec3(v)
	if not v then return nil end
	return { x = v.x, y = v.y, z = v.z }
end

local function probe(x, y)
	if not util or not util.TraceLine then return nil, nil end
	local mask = MASK_SOLID_BRUSHONLY or 16395
	local down = util.TraceLine({
		start = Vector(x, y, 16384),
		endpos = Vector(x, y, -16384),
		mask = mask,
	})
	local ground = nil
	if down and down.Hit and not down.HitSky and down.HitPos then
		ground = down.HitPos.z
	end
	local startZ = (ground or 0) + 32
	local up = util.TraceLine({
		start = Vector(x, y, startZ),
		endpos = Vector(x, y, startZ + 65536),
		mask = mask,
	})
	local sky = nil
	if up and up.HitSky and up.HitPos then sky = up.HitPos.z end
	return ground, sky
end

local function sampleCeiling(cx, cy)
	local offsets = {
		{ 0, 0 }, { 1500, 0 }, { -1500, 0 }, { 0, 1500 }, { 0, -1500 },
		{ 3000, 3000 }, { -3000, -3000 },
	}
	local ground, sky
	for i = 1, #offsets do
		local g, s = probe(cx + offsets[i][1], cy + offsets[i][2])
		if g and (not ground or g > ground) then ground = g end
		if s and (not sky or s < sky) then sky = s end
	end
	return ground, sky
end

local function frameMap()
	local mins, maxs
	if game and game.GetWorld then
		local world = game.GetWorld()
		if world and (not IsValid or IsValid(world)) and world.GetModelBounds then
			local a, b = world:GetModelBounds()
			mins, maxs = vec3(a), vec3(b)
		end
	end
	local ratio = aspect()
	local framed = D.overview(mins, maxs, 90, ratio)
	local ground, sky = sampleCeiling(framed.x, framed.y)
	if sky and framed.z > sky - 96 then framed.z = sky - 96 end
	if ground and framed.z < ground + 64 then framed.z = ground + 64 end
	if ground then framed.groundZ = ground end
	framed.ortho = true
	return framed
end

local function zoom(direction)
	if not cam then return end
	local now = (RealTime and RealTime()) or 0
	if wheelAt > 0 and (now - wheelAt) < 0.01 then return end
	wheelAt = now
	local ratio = aspect()
	if cam.ortho then
		cam.halfH, cam.halfW = D.zoom(cam.halfH, direction, ratio)
	else
		local ground = cam.groundZ or 0
		local dist = cam.z - ground
		if dist < 200 then dist = 200 end
		if (tonumber(direction) or 0) > 0 then
			dist = dist * 0.85
		else
			dist = dist * 1.18
		end
		if dist < 200 then dist = 200 end
		if dist > 80000 then dist = 80000 end
		cam.z = ground + dist
	end
end

local function teamOf(flagSide)
	if flagSide == "bad" then return BAD end
	return GOOD
end

local function drawRing(flag, teamId)
	if not flag or not flag.pos or not render or not render.DrawLine then return end
	local radius = 105
	local cfg = BALLISTICS.Config
	if cfg and type(cfg.ObjectiveRadius) == "number" then radius = cfg.ObjectiveRadius end
	local col = (BALLISTICS.TeamColor and BALLISTICS.TeamColor[teamId]) or Color(255, 255, 255)
	local pos = Vector(flag.pos.x, flag.pos.y, flag.pos.z + 2)
	if render.SetColorMaterial then render.SetColorMaterial() end
	local segs = 48
	local colour = Color(col.r or 255, col.g or 255, col.b or 255, 220)
	for i = 1, segs do
		local a0 = (i - 1) / segs * math.pi * 2
		local a1 = i / segs * math.pi * 2
		render.DrawLine(
			pos + Vector(math.cos(a0) * radius, math.sin(a0) * radius, 0),
			pos + Vector(math.cos(a1) * radius, math.sin(a1) * radius, 0),
			colour,
			true
		)
	end
	if render.DrawWireframeSphere then
		render.DrawWireframeSphere(pos, radius, 20, 8, Color(col.r or 255, col.g or 255, col.b or 255, 70), true)
	end
end

hook.Add("PostDrawTranslucentRenderables", "Ballistics_FlagRings", function(_, sky)
	if sky then return end
	drawRing(view.good, GOOD)
	drawRing(view.bad, BAD)
end)

hook.Add("CalcView", "Ballistics_SpawnEditor", function()
	if not editing or not cam then return end
	local ratio = aspect()
	if cam.ortho then
		cam.halfW = cam.halfH * ratio
	end
	local viewTable = {
		origin = Vector(cam.x, cam.y, cam.z),
		angles = Angle(90, cam.yaw or 0, 0),
		fov = 90,
		znear = 1,
		zfar = 200000,
		drawviewer = false,
	}
	if cam.ortho then
		viewTable.ortho = {
			left = -cam.halfW,
			right = cam.halfW,
			top = -cam.halfH,
			bottom = cam.halfH,
		}
	end
	return viewTable
end)

hook.Add("CreateMove", "Ballistics_SpawnEditor", function(cmd)
	if not editing or not cmd then return end
	if cmd.ClearMovement then cmd:ClearMovement() end
	if cmd.ClearButtons then cmd:ClearButtons() end
end)

local keyZoomAt = 0

hook.Add("Think", "Ballistics_SpawnEditor", function()
	if not editing or not cam or not input or not input.IsKeyDown or not KEY_W then return end
	local ratio = aspect()
	local speed
	if cam.ortho then
		speed = (cam.halfH or 1000) * 1.4 * ((FrameTime and FrameTime()) or 0.015)
	else
		local dist = cam.z - (cam.groundZ or 0)
		speed = math.max(200, dist * 0.9) * ((FrameTime and FrameTime()) or 0.015)
	end
	local dx, dy = D.pan(cam.yaw or 0, {
		w = input.IsKeyDown(KEY_W),
		a = input.IsKeyDown(KEY_A),
		s = input.IsKeyDown(KEY_S),
		d = input.IsKeyDown(KEY_D),
	}, speed)
	cam.x = cam.x + dx
	cam.y = cam.y + dy
	if cam.ortho then cam.halfW = cam.halfH * ratio end
	-- Zoom: GMod has no GUIMouseWheeled hook and binds don't fire while the
	-- screen clicker is on, so take the wheel from the world panel, plus E/Q
	-- (and PgUp/PgDn) as keyboard zoom.
	local wp = vgui and vgui.GetWorldPanel and vgui.GetWorldPanel()
	if IsValid(wp) and not wp.balSpawnWheel then
		wp.balSpawnWheel = true
		local old = wp.OnMouseWheeled
		wp.OnMouseWheeled = function(pnl, delta)
			if editing then
				zoom(delta)
				return true
			end
			if old then return old(pnl, delta) end
		end
	end
	local zin = input.IsKeyDown(KEY_E) or (KEY_PAGEUP and input.IsKeyDown(KEY_PAGEUP))
	local zout = input.IsKeyDown(KEY_Q) or (KEY_PAGEDOWN and input.IsKeyDown(KEY_PAGEDOWN))
	local now = (RealTime and RealTime()) or 0
	if (zin or zout) and (now - keyZoomAt) > 0.05 then
		keyZoomAt = now
		zoom(zin and 1 or -1)
	end
end)

hook.Add("PlayerBindPress", "Ballistics_SpawnEditor", function(_, bind, pressed)
	if not editing then return end
	if bind == "invnext" or bind == "invprev" then
		if pressed then zoom(bind == "invprev" and 1 or -1) end
		return true
	end
	if bind == "+attack" or bind == "+attack2" or bind == "+jump" or bind == "+duck" then
		return true
	end
end)

hook.Add("GUIMouseWheeled", "Ballistics_SpawnEditor", function(delta)
	if not editing then return end
	zoom(delta)
end)

local function overUI()
	if not vgui or not vgui.GetHoveredPanel then return false end
	local hovered = vgui.GetHoveredPanel()
	if not IsValid(hovered) then return false end
	local world = vgui.GetWorldPanel and vgui.GetWorldPanel()
	if world and hovered == world then return false end
	return true
end

local function placeAtCursor()
	if not editing or not cam or overUI() then return end
	if not util or not util.TraceLine then return end
	local _, sw, sh = aspect()
	local mx = (gui and gui.MouseX and gui.MouseX()) or 0
	local my = (gui and gui.MouseY and gui.MouseY()) or 0
	local mask = MASK_SOLID_BRUSHONLY or 16395
	local tr
	if cam.ortho ~= false then
		local hit = D.groundPoint(mx, my, sw, sh, cam)
		if not hit then return end
		tr = util.TraceLine({
			start = Vector(hit.x, hit.y, cam.z),
			endpos = Vector(hit.x, hit.y, cam.z - 200000),
			mask = mask,
		})
	elseif gui and gui.ScreenToVector then
		local dir = gui.ScreenToVector(mx, my)
		local origin = Vector(cam.x, cam.y, cam.z)
		if not dir then return end
		tr = util.TraceLine({
			start = origin,
			endpos = origin + dir * 200000,
			mask = mask,
		})
	end
	if not tr or not tr.Hit or tr.HitSky or not tr.HitPos then return end
	local yaw = 0
	local other = side == GOOD and view.bad or view.good
	if other and other.pos then
		yaw = math.deg(math.atan2(other.pos.y - tr.HitPos.y, other.pos.x - tr.HitPos.x))
	end
	send(D.OP_PLACE, side, {
		x = tr.HitPos.x, y = tr.HitPos.y, z = tr.HitPos.z,
	}, { p = 0, y = yaw, r = 0 })
end

hook.Add("GUIMousePressed", "Ballistics_SpawnEditor", function(code)
	if not editing then return end
	if MOUSE_LEFT and code ~= MOUSE_LEFT then return end
	placeAtCursor()
end)

local function paintSide(self, w, h)
	local on = side == self.balTeam
	local col = (BALLISTICS.TeamColor and BALLISTICS.TeamColor[self.balTeam]) or Color(180, 180, 180)
	if on then
		surface.SetDrawColor(col.r, col.g, col.b, 255)
	else
		surface.SetDrawColor(36, 36, 42, 255)
	end
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(col.r, col.g, col.b, 255)
	surface.DrawOutlinedRect(0, 0, w, h)
	local name = (BALLISTICS.TeamName and BALLISTICS.TeamName[self.balTeam]) or "Flag"
	draw.SimpleText(name, "BallisticsSmall", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function refreshToolbar()
	if not IsValid(toolbar) then return end
	local snap = BALLISTICS.Spawns.Snapshot()
	if IsValid(toolbar.balStatus) then
		toolbar.balStatus:SetText(D.statusText(snap) .. "  ·  " .. (snap.map ~= "" and snap.map or "map"))
	end
	if IsValid(toolbar.balReady) then
		toolbar.balReady:SetText(D.readiness(snap))
	end
end

local function ensureToolbar()
	if IsValid(toolbar) then return toolbar end
	if not vgui or not vgui.Create then return nil end
	toolbar = vgui.Create("DFrame")
	toolbar:SetTitle("Edit spawns")
	toolbar:SetSize(360, 168)
	toolbar:SetPos(12, 12)
	toolbar:SetDeleteOnClose(false)
	toolbar:SetSizable(false)
	toolbar:DockPadding(8, 28, 8, 8)
	function toolbar:OnClose()
		BALLISTICS.Spawns.EndEdit(true)
	end

	local row = vgui.Create("DPanel", toolbar)
	row:Dock(TOP)
	row:SetTall(28)
	row.Paint = function() end
	for _, teamId in ipairs({ GOOD, BAD }) do
		local btn = vgui.Create("DButton", row)
		btn:Dock(LEFT)
		btn:SetWide(120)
		btn:DockMargin(0, 0, 8, 0)
		btn:SetText("")
		btn.balTeam = teamId
		btn.Paint = paintSide
		btn.DoClick = function()
			BALLISTICS.Spawns.SetSide(teamId)
		end
	end

	local ortho = vgui.Create("DButton", row)
	ortho:Dock(FILL)
	ortho:SetText("Ortho")
	ortho.DoClick = function()
		if not cam then return end
		cam.ortho = not cam.ortho
		if not cam.ortho then
			local ground = cam.groundZ or 0
			cam.z = ground + D.fitDistance(cam.halfH, 90)
		end
		ortho:SetText(cam.ortho and "Ortho" or "Perspective")
	end

	toolbar.balStatus = vgui.Create("DLabel", toolbar)
	toolbar.balStatus:Dock(TOP)
	toolbar.balStatus:SetTall(18)
	toolbar.balStatus:SetText("")
	if toolbar.balStatus.SetTextColor then toolbar.balStatus:SetTextColor(Color(220, 210, 160)) end

	toolbar.balReady = vgui.Create("DLabel", toolbar)
	toolbar.balReady:Dock(TOP)
	toolbar.balReady:SetTall(18)
	toolbar.balReady:SetText("")
	if toolbar.balReady.SetTextColor then toolbar.balReady:SetTextColor(Color(200, 200, 200)) end

	local hint = vgui.Create("DLabel", toolbar)
	hint:Dock(TOP)
	hint:SetTall(18)
	hint:SetText("WASD pan, wheel zooms, click the ground to place.")
	if hint.SetTextColor then hint:SetTextColor(Color(170, 170, 170)) end

	local bar = vgui.Create("DPanel", toolbar)
	bar:Dock(BOTTOM)
	bar:SetTall(28)
	bar.Paint = function() end

	local function barButton(text, fn)
		local btn = vgui.Create("DButton", bar)
		btn:Dock(LEFT)
		btn:SetWide(100)
		btn:DockMargin(0, 0, 8, 0)
		btn:SetText(text)
		btn.DoClick = fn
		return btn
	end
	barButton("Save", function() BALLISTICS.Spawns.RequestSave() end)
	barButton("Reset", function() BALLISTICS.Spawns.ConfirmReset() end)
	barButton("Done", function() BALLISTICS.Spawns.EndEdit(true) end)

	BALLISTICS.Spawns.Listen(refreshToolbar)
	return toolbar
end

function BALLISTICS.Spawns.EndEdit(reopen)
	if toolbar and toolbar.balClosing then return end
	editing = false
	if IsValid(toolbar) then
		toolbar.balClosing = true
		toolbar:SetVisible(false)
		toolbar.balClosing = false
	end
	if BALLISTICS.UI then BALLISTICS.UI.Mark("spawns", toolbar) end
	syncCursor()
	if reopen and BALLISTICS.Admin and BALLISTICS.Admin.Open then
		BALLISTICS.Admin.Open()
	end
end

function BALLISTICS.Spawns.BeginEdit()
	local allowed = false
	if BALLISTICS.ClientIsAdmin then
		allowed = BALLISTICS.ClientIsAdmin() == true
	elseif BALLISTICS.IsAdmin and LocalPlayer then
		local ply = LocalPlayer()
		allowed = ply ~= nil and BALLISTICS.IsAdmin(ply) == true
	end
	if not allowed then return end
	if BALLISTICS.Lobby and BALLISTICS.Lobby.Close then BALLISTICS.Lobby.Close() end
	if BALLISTICS.Admin and BALLISTICS.Admin.Close then BALLISTICS.Admin.Close() end
	cam = frameMap()
	editing = true
	local pnl = ensureToolbar()
	if IsValid(pnl) then
		pnl:SetVisible(true)
		pnl:MakePopup()
		if BALLISTICS.UI then BALLISTICS.UI.Mark("spawns", pnl) end
		refreshToolbar()
	end
	syncCursor()
end

hook.Add("OnScreenSizeChanged", "Ballistics_SpawnEditor", function()
	if cam and cam.ortho then
		cam.halfW = cam.halfH * aspect()
	end
end)
