-- Overhead spawn editor and the flag circles everyone sees.
-- Scroll zooms, WASD pans, click traces straight down and asks the server to place.
-- Slice height clips the world above a Z. Traces start on that plane.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spawns = BALLISTICS.Spawns or {}

local D = BALLISTICS.SpawnData
local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local view = { map = "", source = "none", dirty = false, good = nil, bad = nil, box = nil }
local listeners = {}
local side = GOOD
local boxDraft = { yaw = 0, sx = D.BOX_LENGTH or 768, sy = D.BOX_WIDTH or 384 }
local editing = false
local send
local cam = nil
local toolbar = nil
local wheelAt = 0
local sliceBottom, sliceTop = 0, 0
local sliceZ = 0
local mapXY = nil
local muteSlice = false
local clipOn = false
local clipPrev = nil
local inScene = false

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
		box = view.box,
	}
end

function BALLISTICS.Spawns.Side()
	return side
end

local function wrapYaw(y)
	y = (tonumber(y) or 0) % 360
	if y < 0 then y = y + 360 end
	if y >= 360 then y = 0 end
	return y
end

function BALLISTICS.Spawns.BoxDraft()
	return { yaw = boxDraft.yaw, sx = boxDraft.sx, sy = boxDraft.sy }
end

-- sendNow places or resizes only when a box already exists. Otherwise the
-- next ground click uses this draft.
function BALLISTICS.Spawns.SetBoxDraft(yaw, sx, sy, sendNow)
	if yaw ~= nil then boxDraft.yaw = wrapYaw(yaw) end
	if sx ~= nil then boxDraft.sx = tonumber(sx) or boxDraft.sx end
	if sy ~= nil then boxDraft.sy = tonumber(sy) or boxDraft.sy end
	if sendNow and view.box and view.box.pos then
		send(D.OP_BOX, 0, view.box.pos, { p = 0, y = boxDraft.yaw, r = 0 }, boxDraft.sx, boxDraft.sy)
	end
	emit()
end

function BALLISTICS.Spawns.SetSide(teamId)
	if teamId == "box" then
		side = "box"
		emit()
		return
	end
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

function send(op, team, pos, ang, sx, sy)
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
	net.WriteFloat(tonumber(sx) or 0)
	net.WriteFloat(tonumber(sy) or 0)
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
		"Reset this map's flags and firing squad box to the built-in defaults? A saved layout for this map is removed.",
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

local function readBox()
	if not net.ReadBool() then return nil end
	return {
		pos = { x = net.ReadFloat(), y = net.ReadFloat(), z = net.ReadFloat() },
		yaw = net.ReadFloat(),
		sx = net.ReadFloat(),
		sy = net.ReadFloat(),
	}
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_spawns_sync", function()
		view.map = net.ReadString() or ""
		view.source = net.ReadString() or "none"
		view.dirty = net.ReadBool() == true
		view.good = readFlag()
		view.bad = readFlag()
		view.box = readBox()
		if view.box then
			boxDraft.yaw = view.box.yaw or boxDraft.yaw
			boxDraft.sx = view.box.sx or boxDraft.sx
			boxDraft.sy = view.box.sy or boxDraft.sy
		end
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

local function finiteNum(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function xyBounds(mins, maxs)
	if type(mins) ~= "table" or type(maxs) ~= "table" then return nil end
	local x0, y0 = tonumber(mins.x), tonumber(mins.y)
	local x1, y1 = tonumber(maxs.x), tonumber(maxs.y)
	if not (finiteNum(x0) and finiteNum(y0) and finiteNum(x1) and finiteNum(y1)) then return nil end
	if x1 < x0 then x0, x1 = x1, x0 end
	if y1 < y0 then y0, y1 = y1, y0 end
	if x1 - x0 < 1 or y1 - y0 < 1 then return nil end
	return { minx = x0, miny = y0, maxx = x1, maxy = y1 }
end

local function worldBounds()
	if not game or not game.GetWorld then return nil, nil end
	local world = game.GetWorld()
	if not world or (IsValid and not IsValid(world)) or not world.GetModelBounds then return nil, nil end
	local a, b = world:GetModelBounds()
	return vec3(a), vec3(b)
end

-- Map Z when it is usable, otherwise the overhead view's own vertical span.
local function measureSlice()
	local mins, maxs = worldBounds()
	local bottom, top = D.SliceBounds(mins, maxs)
	mapXY = nil
	if bottom and top and (top - bottom) >= 1 then
		mapXY = xyBounds(mins, maxs)
	else
		local hi = (cam and tonumber(cam.z)) or 4096
		local lo = cam and tonumber(cam.groundZ) or nil
		bottom, top = D.SliceBounds({ z = lo }, { z = hi })
		if not bottom or (top - bottom) < 1 then
			bottom, top = D.SliceBounds({ z = hi - 8192 }, { z = hi })
		end
	end
	sliceBottom = bottom or 0
	sliceTop = top or (sliceBottom + 1)
	if sliceTop < sliceBottom then sliceBottom, sliceTop = sliceTop, sliceBottom end
	if sliceTop - sliceBottom < 1 then sliceTop = sliceBottom + 1 end
	sliceZ = sliceTop
end

local function applySliceSlider()
	local slider = toolbar and toolbar.balSlice
	if not slider or (IsValid and not IsValid(slider)) then return end
	muteSlice = true
	if slider.SetMin then slider:SetMin(sliceBottom) end
	if slider.SetMax then slider:SetMax(sliceTop) end
	if slider.SetValue then slider:SetValue(sliceZ or sliceTop) end
	muteSlice = false
end

-- Top of the range is no cut. A rounded slider tick on the max counts as the top.
local function sliceActive()
	if editing ~= true or not cam then return false end
	if not finiteNum(sliceZ) or not finiteNum(sliceTop) then return false end
	return sliceZ < sliceTop - 1e-3
end

local function popClip()
	if not clipOn then return end
	clipOn = false
	if render and render.PopCustomClipPlane then render.PopCustomClipPlane() end
	if render and render.EnableClipping then render.EnableClipping(clipPrev == true) end
	clipPrev = nil
end

local function pushClip(z)
	if clipOn then popClip() end
	if not render or not render.EnableClipping or not render.PushCustomClipPlane or not Vector then
		return false
	end
	clipPrev = render.EnableClipping(true)
	render.PushCustomClipPlane(Vector(0, 0, -1), -(tonumber(z) or 0))
	clipOn = true
	return true
end

-- Outside the scene render, a stuck plane must not leak into normal play.
local function guardClip()
	if inScene then return end
	if clipOn then popClip() end
end

local function along(startPos, endPos, z)
	local dz = endPos.z - startPos.z
	if math.abs(dz) < 1e-6 then
		return Vector(startPos.x, startPos.y, z)
	end
	local t = (z - startPos.z) / dz
	if t < 0 then t = 0 end
	if t > 1 then t = 1 end
	return Vector(
		startPos.x + (endPos.x - startPos.x) * t,
		startPos.y + (endPos.y - startPos.y) * t,
		z
	)
end

-- Start the placement ray on the slice, still heading down the same line.
local function clipTrace(startPos, endPos)
	if not sliceActive() then return startPos, endPos end
	local z0 = D.SliceStart(startPos.z, sliceZ)
	local z1 = D.SliceStart(endPos.z, sliceZ)
	if not z0 or not z1 then return startPos, endPos end
	local a = along(startPos, endPos, z0)
	local b = along(startPos, endPos, z1)
	if math.abs(a.x - b.x) < 0.01 and math.abs(a.y - b.y) < 0.01 and math.abs(a.z - b.z) < 0.01 then
		return nil, nil
	end
	return a, b
end

local function drawSliceRect()
	if not sliceActive() or not mapXY then return end
	if not render or not render.DrawLine or not Vector then return end
	local z = sliceZ - 2
	local x0, y0 = mapXY.minx, mapXY.miny
	local x1, y1 = mapXY.maxx, mapXY.maxy
	if render.SetColorMaterial then render.SetColorMaterial() end
	local col = Color(140, 170, 190, 60)
	local pts = {
		Vector(x0, y0, z), Vector(x1, y0, z),
		Vector(x1, y1, z), Vector(x0, y1, z),
	}
	for i = 1, 4 do
		render.DrawLine(pts[i], pts[i % 4 + 1], col, true)
	end
end

local function shiftDown()
	if not input or not input.IsKeyDown then return false end
	local left = KEY_LSHIFT and input.IsKeyDown(KEY_LSHIFT)
	local right = KEY_RSHIFT and input.IsKeyDown(KEY_RSHIFT)
	return left or right
end

local function zoom(direction)
	if not cam then return end
	if side == "box" and shiftDown() then
		local step = (tonumber(direction) or 0) > 0 and 15 or -15
		BALLISTICS.Spawns.SetBoxDraft(boxDraft.yaw + step, nil, nil, true)
		return
	end
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

local function drawBox(box)
	if not box or not render or not render.DrawLine or not D.boxCorners then return end
	local corners = D.boxCorners(box)
	local edges = D.BOX_EDGES
	if not corners or not edges then return end
	local col = Color(240, 200, 60, 220)
	if render.SetColorMaterial then render.SetColorMaterial() end
	for i = 1, #edges do
		local edge = edges[i]
		local a = corners[edge[1]]
		local b = corners[edge[2]]
		if a and b then
			render.DrawLine(Vector(a.x, a.y, a.z), Vector(b.x, b.y, b.z), col, true)
		end
	end
end

local function showBox()
	-- Only in the overhead Spawns editor; in play the big box is distracting.
	return editing == true
end

hook.Add("PostDrawTranslucentRenderables", "Ballistics_FlagRings", function(_, sky)
	if sky then return end
	drawRing(view.good, GOOD)
	drawRing(view.bad, BAD)
	if showBox() then drawBox(view.box) end
	drawSliceRect()
end)

local function cameraView()
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
end

hook.Add("CalcView", "Ballistics_SpawnEditor", function()
	if not editing or not cam then return end
	return cameraView()
end)

-- World brushes are drawn before PreDrawOpaqueRenderables, so a clip pushed
-- there never cuts the map. This editor has no RenderView of its own: CalcView
-- only supplies the camera and the engine paints the BSP. Take over RenderScene
-- and draw that same camera with the plane already pushed. The inner RenderView
-- re-enters this hook; inScene lets the engine draw that pass.
hook.Add("RenderScene", "Ballistics_SpawnEditorSlice", function()
	if inScene then return end
	if not sliceActive() then return end
	if not render or not render.RenderView then return end
	local viewTable = cameraView()
	viewTable.x = 0
	viewTable.y = 0
	viewTable.w = (ScrW and ScrW()) or 1280
	viewTable.h = (ScrH and ScrH()) or 720
	viewTable.drawviewmodel = false
	viewTable.drawhud = false
	viewTable.dopostprocess = true
	inScene = true
	local pushed = pushClip(sliceZ)
	if pushed then
		pcall(render.RenderView, viewTable)
		popClip()
	end
	inScene = false
	if not pushed then return end
	return true
end)

hook.Add("PreRender", "Ballistics_SpawnEditorSlice", guardClip)
hook.Add("PostRender", "Ballistics_SpawnEditorSlice", guardClip)
hook.Add("Think", "Ballistics_SpawnEditorSlice", guardClip)

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
	-- Arrows rotate the box. Q and E stay on zoom.
	if side == "box" and (now - keyZoomAt) > 0.12 then
		local typing = vgui and vgui.GetKeyboardFocus and IsValid and IsValid(vgui.GetKeyboardFocus())
		local left = KEY_LEFT and input.IsKeyDown(KEY_LEFT)
		local right = KEY_RIGHT and input.IsKeyDown(KEY_RIGHT)
		if not typing and (left or right) and not (left and right) then
			keyZoomAt = now
			BALLISTICS.Spawns.SetBoxDraft(boxDraft.yaw + (right and 15 or -15), nil, nil, true)
		end
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
		local startPos, endPos = clipTrace(
			Vector(hit.x, hit.y, cam.z),
			Vector(hit.x, hit.y, cam.z - 200000)
		)
		if not startPos or not endPos then return end
		tr = util.TraceLine({
			start = startPos,
			endpos = endPos,
			mask = mask,
		})
	elseif gui and gui.ScreenToVector then
		local dir = gui.ScreenToVector(mx, my)
		local origin = Vector(cam.x, cam.y, cam.z)
		if not dir then return end
		local startPos, endPos = clipTrace(origin, origin + dir * 200000)
		if not startPos or not endPos then return end
		tr = util.TraceLine({
			start = startPos,
			endpos = endPos,
			mask = mask,
		})
	end
	if not tr or not tr.Hit or tr.HitSky or not tr.HitPos then return end
	if side == "box" then
		local lift = (D.BOX_HEIGHT or 128) * 0.5
		send(D.OP_BOX, 0, {
			x = tr.HitPos.x, y = tr.HitPos.y, z = tr.HitPos.z + lift,
		}, { p = 0, y = boxDraft.yaw, r = 0 }, boxDraft.sx, boxDraft.sy)
		return
	end
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
	toolbar:SetSize(480, 232)
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
		btn:SetWide(100)
		btn:DockMargin(0, 0, 8, 0)
		btn:SetText("")
		btn.balTeam = teamId
		btn.Paint = paintSide
		btn.DoClick = function()
			BALLISTICS.Spawns.SetSide(teamId)
		end
	end

	local squad = vgui.Create("DButton", row)
	squad:Dock(LEFT)
	squad:SetWide(110)
	squad:DockMargin(0, 0, 8, 0)
	squad:SetText("")
	squad.Paint = function(_, w, h)
		local on = side == "box"
		if on then
			surface.SetDrawColor(240, 200, 60, 255)
		else
			surface.SetDrawColor(36, 36, 42, 255)
		end
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(240, 200, 60, 255)
		surface.DrawOutlinedRect(0, 0, w, h)
		draw.SimpleText("Squad", "BallisticsSmall", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	squad.DoClick = function()
		BALLISTICS.Spawns.SetSide("box")
	end
	if squad.SetTooltip then
		squad:SetTooltip("Place and resize the firing squad box. Arrows or shift+wheel rotate it.")
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
	hint:SetTall(32)
	hint:SetWrap(true)
	hint:SetText("WASD pan, wheel zooms, click the ground. Squad: arrows or shift+wheel rotate. Sliders resize.")
	if hint.SetTextColor then hint:SetTextColor(Color(170, 170, 170)) end

	local sliceLine = vgui.Create("DPanel", toolbar)
	sliceLine:Dock(TOP)
	sliceLine:SetTall(32)
	sliceLine:DockMargin(0, 4, 0, 0)
	sliceLine.Paint = function(_, w, h)
		surface.SetDrawColor(32, 34, 40, 255)
		surface.DrawRect(0, 0, w, h)
	end
	if sliceLine.SetTooltip then
		sliceLine:SetTooltip("Hide everything above this height. The top of the range is no cut.")
	end
	local slice = vgui.Create("DNumSlider", sliceLine)
	slice:Dock(FILL)
	slice:DockMargin(8, 0, 8, 0)
	slice:SetText("Slice height")
	if slice.SetDark then slice:SetDark(false) end
	if slice.SetDecimals then slice:SetDecimals(0) end
	if slice.SetTooltip then
		slice:SetTooltip("Hide everything above this height. The top of the range is no cut.")
	end
	if slice.Label and slice.Label.SetTextColor then
		slice.Label:SetTextColor(Color(230, 230, 230))
	end
	muteSlice = true
	if slice.SetMin then slice:SetMin(sliceBottom) end
	if slice.SetMax then slice:SetMax(sliceTop) end
	if slice.SetValue then slice:SetValue(sliceZ or sliceTop) end
	muteSlice = false
	slice.OnValueChanged = function(_, val)
		if muteSlice or editing ~= true then return end
		local z = D.ClampSlice(val, sliceBottom, sliceTop)
		if not z or math.abs(z - sliceTop) < 0.5 then
			sliceZ = sliceTop
			return
		end
		sliceZ = z
	end
	toolbar.balSlice = slice

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
	sliceZ = sliceTop
	applySliceSlider()
	popClip()
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
	local fresh = not editing
	cam = frameMap()
	if fresh then measureSlice() end
	editing = true
	local pnl = ensureToolbar()
	applySliceSlider()
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
