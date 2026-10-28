-- Free-cam spawn editor. Fly through walls, aim a crosshair, place/swivel items.
-- Scroll cycles type. Compact HUD; Enter saves+exits. No Derma toolbar.

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
local cam = nil -- { x, y, z, pitch, yaw }
local wheelAt = 0
local types = { GOOD, BAD, "box" }
local swivel = nil -- while LMB held after place
local aimHit = nil
local aimNormal = nil
local lmbWas = false
local keyLatch = {}

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

local function typeLabel(t)
	if t == "box" then return "Squad box" end
	if t == BAD then return (BALLISTICS.TeamName and BALLISTICS.TeamName[BAD]) or "Bad spawn" end
	return (BALLISTICS.TeamName and BALLISTICS.TeamName[GOOD]) or "Good spawn"
end

local function cycleType(dir)
	local idx = 1
	for i = 1, #types do
		if types[i] == side then
			idx = i
			break
		end
	end
	idx = idx + ((tonumber(dir) or 0) > 0 and 1 or -1)
	if idx < 1 then idx = #types end
	if idx > #types then idx = 1 end
	BALLISTICS.Spawns.SetSide(types[idx])
end

local function syncCursor()
	if gui and gui.EnableScreenClicker then
		gui.EnableScreenClicker(false)
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

local function camOrigin()
	if not cam then return Vector(0, 0, 0) end
	return Vector(cam.x, cam.y, cam.z)
end

local function camAngles()
	if not cam then return Angle(0, 0, 0) end
	return Angle(cam.pitch or 0, cam.yaw or 0, 0)
end

local function shiftDown()
	if not input or not input.IsKeyDown then return false end
	return (KEY_LSHIFT and input.IsKeyDown(KEY_LSHIFT)) or (KEY_RSHIFT and input.IsKeyDown(KEY_RSHIFT))
end

local function ctrlDown()
	if not input or not input.IsKeyDown then return false end
	return (KEY_LCONTROL and input.IsKeyDown(KEY_LCONTROL)) or (KEY_RCONTROL and input.IsKeyDown(KEY_RCONTROL))
end

local function overUI()
	if not vgui or not vgui.GetHoveredPanel then return false end
	local hovered = vgui.GetHoveredPanel()
	if not IsValid(hovered) then return false end
	local world = vgui.GetWorldPanel and vgui.GetWorldPanel()
	if world and hovered == world then return false end
	return true
end

local function aimTrace()
	if not cam or not util or not util.TraceLine then return nil, nil end
	local origin = camOrigin()
	local ang = camAngles()
	local dir = ang:Forward()
	local mask = MASK_SOLID_BRUSHONLY or 16395
	local tr = util.TraceLine({
		start = origin,
		endpos = origin + dir * 200000,
		mask = mask,
	})
	if not tr or not tr.Hit or not tr.HitPos then return nil, nil end
	if tr.HitSky then return nil, nil end
	return tr.HitPos, tr.HitNormal
end

local function drawRing(flag, teamId, alpha)
	if not flag or not flag.pos or not render or not render.DrawLine then return end
	local radius = 105
	local cfg = BALLISTICS.Config
	if cfg and type(cfg.ObjectiveRadius) == "number" then radius = cfg.ObjectiveRadius end
	local col = (BALLISTICS.TeamColor and BALLISTICS.TeamColor[teamId]) or Color(255, 255, 255)
	local pos = Vector(flag.pos.x, flag.pos.y, flag.pos.z + 2)
	if render.SetColorMaterial then render.SetColorMaterial() end
	local segs = 48
	local a = alpha or 220
	local colour = Color(col.r or 255, col.g or 255, col.b or 255, a)
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
		render.DrawWireframeSphere(pos, radius, 20, 8, Color(col.r or 255, col.g or 255, col.b or 255, math.min(70, a)), true)
	end
end

local function drawBox(box, alpha)
	if not box or not render or not render.DrawLine or not D.boxCorners then return end
	local corners = D.boxCorners(box)
	local edges = D.BOX_EDGES
	if not corners or not edges then return end
	local col = Color(240, 200, 60, alpha or 220)
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
	return editing == true
end

local function ghostPreview()
	if not editing or not aimHit then return end
	if side == "box" then
		local lift = (D.BOX_HEIGHT or 128) * 0.5
		drawBox({
			pos = { x = aimHit.x, y = aimHit.y, z = aimHit.z + lift },
			yaw = boxDraft.yaw,
			sx = boxDraft.sx,
			sy = boxDraft.sy,
		}, 90)
		return
	end
	drawRing({ pos = { x = aimHit.x, y = aimHit.y, z = aimHit.z } }, side, 90)
end

hook.Add("PostDrawTranslucentRenderables", "Ballistics_FlagRings", function(_, sky)
	if sky then return end
	drawRing(view.good, GOOD)
	drawRing(view.bad, BAD)
	if showBox() then drawBox(view.box) end
	ghostPreview()
end)

hook.Add("CalcView", "Ballistics_SpawnEditor", function()
	if not editing or not cam then return end
	return {
		origin = camOrigin(),
		angles = camAngles(),
		fov = 90,
		znear = 0.1,
		zfar = 200000,
		drawviewer = false,
	}
end)

-- Keep the player body still; freecam is view-only.
hook.Add("CreateMove", "Ballistics_SpawnEditor", function(cmd)
	if not editing or not cmd then return end
	if cmd.ClearMovement then cmd:ClearMovement() end
	if cmd.ClearButtons then cmd:ClearButtons() end
	if cmd.SetViewAngles and cam then
		cmd:SetViewAngles(camAngles())
	end
end)

hook.Add("InputMouseApply", "Ballistics_SpawnEditor", function(cmd, x, y, ang)
	if not editing or not cam then return end
	if overUI() then return end
	if swivel then
		local sens = 0.12
		local dyaw = -(tonumber(x) or 0) * sens
		if side == "box" then
			boxDraft.yaw = wrapYaw(boxDraft.yaw + dyaw)
			send(D.OP_BOX, 0, swivel.pos, { p = 0, y = boxDraft.yaw, r = 0 }, swivel.sx, swivel.sy)
		else
			swivel.yaw = wrapYaw((swivel.yaw or 0) + dyaw)
			send(D.OP_PLACE, swivel.team, swivel.pos, { p = 0, y = swivel.yaw, r = 0 })
		end
		return true
	end
	local sens = 0.022
	cam.pitch = math.Clamp((cam.pitch or 0) + (tonumber(y) or 0) * sens, -89, 89)
	cam.yaw = wrapYaw((cam.yaw or 0) - (tonumber(x) or 0) * sens)
	return true
end)

local function moveCam(dt)
	if not cam or not input or not input.IsKeyDown or not KEY_W then return end
	local typing = vgui and vgui.GetKeyboardFocus and IsValid and IsValid(vgui.GetKeyboardFocus())
	if typing then return end
	local speed = 600
	if shiftDown() then speed = 1800 end
	if ctrlDown() then speed = 180 end
	speed = speed * (dt or 0.015)
	local ang = camAngles()
	local forward = ang:Forward()
	local right = ang:Right()
	local dx, dy, dz = 0, 0, 0
	if input.IsKeyDown(KEY_W) then
		dx = dx + forward.x * speed
		dy = dy + forward.y * speed
		dz = dz + forward.z * speed
	end
	if input.IsKeyDown(KEY_S) then
		dx = dx - forward.x * speed
		dy = dy - forward.y * speed
		dz = dz - forward.z * speed
	end
	if input.IsKeyDown(KEY_D) then
		dx = dx + right.x * speed
		dy = dy + right.y * speed
		dz = dz + right.z * speed
	end
	if input.IsKeyDown(KEY_A) then
		dx = dx - right.x * speed
		dy = dy - right.y * speed
		dz = dz - right.z * speed
	end
	if KEY_SPACE and input.IsKeyDown(KEY_SPACE) then
		dz = dz + speed
	end
	cam.x = cam.x + dx
	cam.y = cam.y + dy
	cam.z = cam.z + dz
end

local function placeAtAim()
	if not editing or not cam then return end
	local hit = aimHit
	if not hit then
		hit = select(1, aimTrace())
	end
	if not hit then return end
	if side == "box" then
		local lift = (D.BOX_HEIGHT or 128) * 0.5
		local pos = { x = hit.x, y = hit.y, z = hit.z + lift }
		send(D.OP_BOX, 0, pos, { p = 0, y = boxDraft.yaw, r = 0 }, boxDraft.sx, boxDraft.sy)
		swivel = { op = D.OP_BOX, team = 0, pos = pos, sx = boxDraft.sx, sy = boxDraft.sy, yaw = boxDraft.yaw }
		return
	end
	local yaw = cam.yaw or 0
	local other = side == GOOD and view.bad or view.good
	if other and other.pos then
		yaw = math.deg(math.atan2(other.pos.y - hit.y, other.pos.x - hit.x))
	end
	local pos = { x = hit.x, y = hit.y, z = hit.z }
	send(D.OP_PLACE, side, pos, { p = 0, y = yaw, r = 0 })
	swivel = { op = D.OP_PLACE, team = side, pos = pos, yaw = yaw }
end

local function keyPressed(key)
	if not input or not input.IsKeyDown or not key then return false end
	local down = input.IsKeyDown(key)
	local was = keyLatch[key] == true
	keyLatch[key] = down
	return down and not was
end

hook.Add("Think", "Ballistics_SpawnEditor", function()
	if not editing or not cam then return end
	syncCursor()
	moveCam((FrameTime and FrameTime()) or 0.015)
	local hit, nrm = aimTrace()
	aimHit, aimNormal = hit, nrm

	local wp = vgui and vgui.GetWorldPanel and vgui.GetWorldPanel()
	if IsValid(wp) and not wp.balSpawnWheel then
		wp.balSpawnWheel = true
		local old = wp.OnMouseWheeled
		wp.OnMouseWheeled = function(pnl, delta)
			if editing then
				local now = (RealTime and RealTime()) or 0
				if wheelAt > 0 and (now - wheelAt) < 0.05 then return true end
				wheelAt = now
				cycleType(delta)
				return true
			end
			if old then return old(pnl, delta) end
		end
	end

	local typing = vgui and vgui.GetKeyboardFocus and IsValid and IsValid(vgui.GetKeyboardFocus())
	if not typing then
		if keyPressed(KEY_ENTER) or (KEY_PAD_ENTER and keyPressed(KEY_PAD_ENTER)) then
			BALLISTICS.Spawns.RequestSave()
			BALLISTICS.Spawns.EndEdit(true)
			return
		end
		if keyPressed(KEY_ESCAPE) or (KEY_BACKSPACE and keyPressed(KEY_BACKSPACE)) then
			BALLISTICS.Spawns.EndEdit(true)
			return
		end
		if KEY_R and keyPressed(KEY_R) then
			BALLISTICS.Spawns.ConfirmReset()
		end
	end

	local lmb = input and input.IsMouseDown and MOUSE_LEFT and input.IsMouseDown(MOUSE_LEFT)
	if lmb and not lmbWas and not overUI() and not swivel then
		placeAtAim()
	end
	if swivel and not lmb then
		swivel = nil
	end
	lmbWas = lmb and true or false
end)

hook.Add("PlayerBindPress", "Ballistics_SpawnEditor", function(_, bind, pressed)
	if not editing then return end
	if bind == "invnext" or bind == "invprev" then
		if pressed then cycleType(bind == "invprev" and 1 or -1) end
		return true
	end
	if bind == "+attack" then
		if pressed and not swivel then
			placeAtAim()
		elseif not pressed then
			swivel = nil
		end
		return true
	end
	if bind == "+attack2" or bind == "+jump" or bind == "+duck" then
		return true
	end
end)

hook.Add("GUIMouseWheeled", "Ballistics_SpawnEditor", function(delta)
	if not editing then return end
	cycleType(delta)
end)

hook.Add("HUDPaint", "Ballistics_SpawnEditor", function()
	if not editing then return end
	local sw = (ScrW and ScrW()) or 1280
	local sh = (ScrH and ScrH()) or 720
	local cx, cy = sw * 0.5, sh * 0.5
	surface.SetDrawColor(255, 255, 255, 200)
	surface.DrawRect(cx - 8, cy - 1, 16, 2)
	surface.DrawRect(cx - 1, cy - 8, 2, 16)

	local snap = BALLISTICS.Spawns.Snapshot()
	local map = (snap.map ~= "" and snap.map) or "map"
	local state = D.statusText(snap)
	local typ = typeLabel(side)
	if swivel then typ = typ .. " · swivel" end

	local x, y = 12, 12
	local w, h = 380, 70
	surface.SetDrawColor(12, 14, 18, 200)
	surface.DrawRect(x, y, w, h)
	surface.SetDrawColor(80, 90, 100, 220)
	surface.DrawOutlinedRect(x, y, w, h)
	draw.SimpleText(typ, "BallisticsSmall", x + 10, y + 8, Color(240, 230, 180), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText(map .. "  ·  " .. state, "BallisticsSmall", x + 10, y + 28, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	draw.SimpleText("WASD look · wheel type · LMB place/yaw · Enter save+exit · R reset · Esc exit", "BallisticsSmall", x + 10, y + 48, Color(160, 160, 160), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
end)

function BALLISTICS.Spawns.EndEdit(reopen)
	editing = false
	swivel = nil
	aimHit = nil
	keyLatch = {}
	if BALLISTICS.UI then BALLISTICS.UI.Mark("spawns", nil) end
	syncCursor()
	if reopen and BALLISTICS.Admin and BALLISTICS.Admin.Open then
		BALLISTICS.Admin.Open()
	end
end

local function startCam()
	local ply = LocalPlayer and LocalPlayer()
	local x, y, z, pitch, yaw = 0, 0, 128, 0, 0
	if IsValid(ply) then
		local eye = ply:EyePos()
		local ang = ply:EyeAngles()
		x, y, z = eye.x, eye.y, eye.z
		pitch, yaw = ang.p, ang.y
	end
	return { x = x, y = y, z = z, pitch = pitch, yaw = yaw }
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
	cam = startCam()
	editing = true
	swivel = nil
	keyLatch = {}
	syncCursor()
end
