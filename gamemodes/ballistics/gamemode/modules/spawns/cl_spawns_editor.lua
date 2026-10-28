-- Free-cam spawn editor. Fly through walls, aim a crosshair, place/swivel items.
-- Scroll cycles type. Existing save/reset/net stay. No slice cut.

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
local toolbar = nil
local wheelAt = 0
local types = { GOOD, BAD, "box" }
local swivel = nil -- { op, team, pos, sx, sy } while LMB held after place
local aimHit = nil -- last aim hit for ghost
local aimNormal = nil

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
	-- Free-cam uses mouse look; Alt holds the cursor for the toolbar.
	local want = false
	if editing and input and input.IsKeyDown and KEY_LALT then
		want = input.IsKeyDown(KEY_LALT) or (KEY_RALT and input.IsKeyDown(KEY_RALT))
	end
	if not editing and IsValid(toolbar) and toolbar:IsVisible() then
		want = true
	end
	if BALLISTICS.UI and BALLISTICS.UI.SyncCursor then
		-- Prefer explicit clicker so freelook works when Alt is up.
		if gui and gui.EnableScreenClicker then
			gui.EnableScreenClicker(want)
		end
		return
	end
	if gui and gui.EnableScreenClicker then
		gui.EnableScreenClicker(want)
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

local function altDown()
	if not input or not input.IsKeyDown then return false end
	return (KEY_LALT and input.IsKeyDown(KEY_LALT)) or (KEY_RALT and input.IsKeyDown(KEY_RALT))
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
	if altDown() or overUI() then return end
	if swivel then
		-- While swiveling, mouse X only turns the placed item.
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
	if altDown() then return end
	local typing = vgui and vgui.GetKeyboardFocus and IsValid and IsValid(vgui.GetKeyboardFocus())
	if typing then return end
	local speed = 600
	if shiftDown() then speed = 1800 end
	if ctrlDown() then speed = 180 end
	speed = speed * (dt or 0.015)
	local ang = camAngles()
	local forward = ang:Forward()
	local right = ang:Right()
	local up = Vector(0, 0, 1)
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
	if not editing or not cam or overUI() or altDown() then return end
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

local lmbWas = false

hook.Add("Think", "Ballistics_SpawnEditor", function()
	if not editing or not cam then return end
	local alt = altDown()
	syncCursor()
	if IsValid(toolbar) then
		toolbar:SetMouseInputEnabled(alt == true)
		toolbar:SetKeyboardInputEnabled(false)
	end
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

	local lmb = input and input.IsMouseDown and MOUSE_LEFT and input.IsMouseDown(MOUSE_LEFT)
	if lmb and not lmbWas and not alt and not overUI() and not swivel then
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

hook.Add("GUIMousePressed", "Ballistics_SpawnEditor", function(code)
	if not editing then return end
	if not altDown() then return end
	-- With Alt (cursor on), left click on world still places.
	if MOUSE_LEFT and code == MOUSE_LEFT and not overUI() then
		placeAtAim()
	end
end)

hook.Add("HUDPaint", "Ballistics_SpawnEditor", function()
	if not editing then return end
	local sw = (ScrW and ScrW()) or 1280
	local sh = (ScrH and ScrH()) or 720
	local cx, cy = sw * 0.5, sh * 0.5
	surface.SetDrawColor(255, 255, 255, 200)
	surface.DrawRect(cx - 8, cy - 1, 16, 2)
	surface.DrawRect(cx - 1, cy - 8, 2, 16)
	local label = typeLabel(side)
	if swivel then label = label .. "  ·  swivel yaw" end
	draw.SimpleText(label, "BallisticsSmall", cx, cy + 28, Color(240, 230, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	draw.SimpleText("WASD fly · mouse look · Shift fast · Ctrl slow · Space up · wheel type · LMB place/hold yaw · Alt UI", "BallisticsSmall", cx, sh - 36, Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
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
	if IsValid(toolbar.balType) then
		toolbar.balType:SetText("Type: " .. typeLabel(side) .. "  (scroll)")
	end
end

local function ensureToolbar()
	if IsValid(toolbar) then return toolbar end
	if not vgui or not vgui.Create then return nil end
	toolbar = vgui.Create("DFrame")
	toolbar:SetTitle("Edit spawns")
	toolbar:SetSize(480, 150)
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
		squad:SetTooltip("Place and resize the firing squad box. Hold LMB after place to swivel yaw.")
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

	toolbar.balType = vgui.Create("DLabel", toolbar)
	toolbar.balType:Dock(TOP)
	toolbar.balType:SetTall(18)
	toolbar.balType:SetText("")
	if toolbar.balType.SetTextColor then toolbar.balType:SetTextColor(Color(200, 220, 240)) end

	local hint = vgui.Create("DLabel", toolbar)
	hint:Dock(TOP)
	hint:SetTall(28)
	hint:SetWrap(true)
	hint:SetText("Hold Alt to use this panel. Scroll cycles type. LMB places; hold and move mouse to set yaw.")
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
	swivel = nil
	aimHit = nil
	if IsValid(toolbar) then
		toolbar.balClosing = true
		toolbar:SetVisible(false)
		toolbar.balClosing = false
	end
	if BALLISTICS.UI then BALLISTICS.UI.Mark("spawns", toolbar) end
	if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(false) end
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
	local pnl = ensureToolbar()
	if IsValid(pnl) then
		pnl:SetVisible(true)
		pnl:MakePopup()
		pnl:SetKeyboardInputEnabled(false)
		pnl:SetMouseInputEnabled(true)
		if BALLISTICS.UI then BALLISTICS.UI.Mark("spawns", pnl) end
		refreshToolbar()
	end
	syncCursor()
end
