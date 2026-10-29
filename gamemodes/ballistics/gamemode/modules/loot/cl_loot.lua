-- Loot window and the hold that asks the server to open it.
-- The use button is only watched. It is not consumed, so doors, body drag,
-- and weapon binds keep working. The ring starts only while the crosshair
-- is on a lootable player or body.
-- bal_inventory_key (default 4) toggles the same window in self mode: only
-- "Your inventory". The key is polled, because the popup owns the keyboard.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loot = BALLISTICS.Loot or {}

local L = BALLISTICS.Loot

local USE = IN_USE or 32
local MOUSE_LEFT_CODE = MOUSE_LEFT or 107
local MOUSE_RIGHT_CODE = MOUSE_RIGHT or 108
local DOUBLE = 0.28

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsLootTitle", { font = "Roboto", size = 22, weight = 700, antialias = true })
	surface.CreateFont("BallisticsLoot", { font = "Roboto", size = 16, weight = 600, antialias = true })
	surface.CreateFont("BallisticsLootSmall", { font = "Roboto", size = 14, weight = 500, antialias = true })
end

local root
local leftCard
local rightCard
local invButton
local buyRestore = false
local state = { open = false, note = "" }
local drag
local ghost
local hold
-- E closes an open window; after that (or after opening) E must be released
-- before a new hold can start. useSeen is true once the poll has observed
-- the use key down during this open, so a swallowed poll is not a release.
local useLatch = false
local useWas = false
local useSeen = false
local onLootKeyPressed
local onLootKeyReleased
local ring = 0
local hurtLatch = false
local lastHp
local lastClick
local rightWas = false
local sizedW, sizedH = 0, 0
local hitSlots = {}
local viewYou
local viewThem
local invEdge = (BALLISTICS.FKeys and BALLISTICS.FKeys.NewEdge and BALLISTICS.FKeys.NewEdge()) or { down = false, last = -math.huge }
local chatOpen = false

local function valid(ent)
	if ent == nil or ent == false then return false end
	if IsValid then return IsValid(ent) == true end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	return false
end

local function localPly()
	if not LocalPlayer then return nil end
	local ok, ply = pcall(LocalPlayer)
	if not ok or not valid(ply) then return nil end
	return ply
end

local function now()
	if CurTime then return CurTime() end
	return 0
end

local function screen()
	local w = (ScrW and ScrW()) or 1280
	local h = (ScrH and ScrH()) or 720
	return w, h
end

local function cursor()
	if gui and gui.MouseX and gui.MouseY then
		return gui.MouseX() or 0, gui.MouseY() or 0
	end
	if input and input.GetCursorPos then
		local x, y = input.GetCursorPos()
		return x or 0, y or 0
	end
	return 0, 0
end

local function mouseDown(code)
	if not input or type(input.IsMouseDown) ~= "function" then return nil end
	local ok, down = pcall(input.IsMouseDown, code)
	if not ok then return nil end
	return down == true
end

local function mark()
	if BALLISTICS.UI and BALLISTICS.UI.Mark then
		BALLISTICS.UI.Mark("loot", root)
	end
	if BALLISTICS.UI and BALLISTICS.UI.SyncCursor then
		BALLISTICS.UI.SyncCursor()
	end
end

local function copyPos(v)
	if v == nil then return nil end
	return {
		x = tonumber(v.x) or 0,
		y = tonumber(v.y) or 0,
		z = tonumber(v.z) or 0,
	}
end

local function callPos(ent, name)
	if ent == nil or type(ent[name]) ~= "function" then return nil end
	local ok, pos = pcall(ent[name], ent)
	if ok then return pos end
	return nil
end

local function posOf(ent)
	return callPos(ent, "WorldSpaceCenter") or callPos(ent, "GetPos")
end

local function nwString(ent, key)
	if ent == nil or type(ent.GetNWString) ~= "function" then return "" end
	local ok, value = pcall(ent.GetNWString, ent, key, "")
	if ok and type(value) == "string" then return value end
	return ""
end

local function nw2String(ent, key)
	if ent == nil or type(ent.GetNW2String) ~= "function" then return "" end
	local ok, value = pcall(ent.GetNW2String, ent, key, "")
	if ok and type(value) == "string" then return value end
	return ""
end

local function ownerOf(ent)
	local pb = PLAYER_BALLISTICS
	if pb and type(pb.RagdollOwner) == "function" then
		local ok, owner = pcall(pb.RagdollOwner, ent)
		if ok and valid(owner) then return owner end
	end
	local bd = BODY_DAMAGE
	if bd and type(bd.GetBodyEntity) == "function" then
		local ok, owner = pcall(bd.GetBodyEntity, ent, "pb_owner")
		if ok and valid(owner) and type(owner.IsPlayer) == "function" and owner:IsPlayer() then
			return owner
		end
	end
	if valid(ent.bd_owner) and type(ent.bd_owner.IsPlayer) == "function" and ent.bd_owner:IsPlayer() then
		return ent.bd_owner
	end
	return nil
end

local function describe(ply, ent)
	if not valid(ent) then return {} end
	local owner = ownerOf(ent)
	local self = ent == ply or owner == ply
	local isPlayer = type(ent.IsPlayer) == "function" and ent:IsPlayer() == true
	local class = ""
	if type(ent.GetClass) == "function" then
		local ok, got = pcall(ent.GetClass, ent)
		if ok and type(got) == "string" then class = got end
	end
	local rag = class == "prop_ragdoll"
	if not rag and type(ent.IsRagdoll) == "function" then
		local ok, got = pcall(ent.IsRagdoll, ent)
		rag = ok and got == true
	end
	local bodyId = nwString(ent, "bd_id")
	if bodyId == "" and type(ent.bd_id) == "string" then bodyId = ent.bd_id end
	return {
		isSelf = self,
		isPlayer = isPlayer and ent ~= ply,
		isRagdoll = rag,
		bodyId = bodyId,
		lootId = nw2String(ent, "bal_loot_id"),
		hasOwner = owner ~= nil and owner ~= ply,
	}
end

local function aimTrace(ply, reach)
	local eye = callPos(ply, "EyePos")
	local aim = nil
	if type(ply.GetAimVector) == "function" then
		local ok, got = pcall(ply.GetAimVector, ply)
		if ok then aim = got end
	end
	if eye == nil or aim == nil or not (util and util.TraceLine) then
		if type(ply.GetEyeTrace) == "function" then
			local ok, tr = pcall(ply.GetEyeTrace, ply)
			if ok and type(tr) == "table" then return tr end
		end
		return nil
	end
	local dest
	local okAdd, added = pcall(function() return eye + aim * reach end)
	if okAdd then
		dest = added
	elseif type(eye) == "table" and type(aim) == "table" then
		dest = {
			x = (tonumber(eye.x) or 0) + (tonumber(aim.x) or 0) * reach,
			y = (tonumber(eye.y) or 0) + (tonumber(aim.y) or 0) * reach,
			z = (tonumber(eye.z) or 0) + (tonumber(aim.z) or 0) * reach,
		}
	end
	if dest == nil then return nil end
	local tr = util.TraceLine({
		start = eye,
		endpos = dest,
		filter = ply,
		mask = MASK_SHOT,
	})
	if type(tr) ~= "table" then return nil end
	return tr
end

local function distTo(ply, ent)
	local eye = callPos(ply, "EyePos")
	local dest = posOf(ent)
	if eye ~= nil and type(ent.NearestPoint) == "function" then
		local ok, near = pcall(ent.NearestPoint, ent, eye)
		if ok and near ~= nil then dest = near end
	end
	return L.Dist(eye, dest)
end

local function phaseOf(ply)
	local phase = nw2String(ply, "bal_phase")
	return phase
end

-- Singleplayer does not run client prediction, so LocalPlayer():KeyDown(IN_USE)
-- stays false there and the hold never started. Also read the key bound to
-- +use straight from the keyboard (not while typing or in a menu).
local function useKeyDown()
	if not input or type(input.LookupBinding) ~= "function" or type(input.GetKeyCode) ~= "function" then return false end
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return false end
	if gui and gui.IsConsoleVisible and gui.IsConsoleVisible() then return false end
	local f = vgui and vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
	if valid(f) and f.GetClassName and f:GetClassName() == "TextEntry" then return false end
	local name = input.LookupBinding("+use", true) or "e"
	local code = input.GetKeyCode(name)
	if type(code) ~= "number" or code <= 0 then return false end
	local Keys = BALLISTICS.Keys
	if Keys and Keys.IsBindDown then return Keys.IsBindDown(code) end
	if code >= (MOUSE_FIRST or 107) and code <= (MOUSE_LAST or 113) then
		return type(input.IsMouseDown) == "function" and input.IsMouseDown(code) == true
	end
	if type(input.IsButtonDown) == "function" then
		local ok, down = pcall(input.IsButtonDown, code)
		if ok then return down == true end
	end
	return type(input.IsKeyDown) == "function" and input.IsKeyDown(code) == true
end

local function useDown(ply)
	local cmd = false
	if type(ply.KeyDown) == "function" then
		local ok, down = pcall(ply.KeyDown, ply, USE)
		cmd = ok and down == true
	end
	return L.UseDown(cmd, useKeyDown())
end

local debugCv = CreateClientConVar and CreateClientConVar("bal_loot_debug", "0", false, false, "1 = print why the loot hold cancels") or nil
local lastWhy
local lastGate
-- TEMP: always-on gate trace while hold-E is being debugged.
local function gate(text)
	if not (debugCv and debugCv:GetBool()) or text == lastGate then return end
	lastGate = text
	print("[Ballistics loot] " .. text)
end
print("[Ballistics loot] client module loaded")

local function buyOpen()
	return BALLISTICS.BuyWheel and BALLISTICS.BuyWheel.IsOpen and BALLISTICS.BuyWheel.IsOpen() == true
end

local function windowOpen()
	return state.open == true
end

local function noteHurt(ply)
	local hp = nil
	if type(ply.Health) == "function" then
		local ok, got = pcall(ply.Health, ply)
		if ok then hp = tonumber(got) end
	end
	if lastHp ~= nil and hp ~= nil and hp < lastHp then hurtLatch = true end
	if hp ~= nil then lastHp = hp end
	if ply.pbDown == true then hurtLatch = true end
end

local function clearHold()
	hold = nil
	ring = 0
	hurtLatch = false
end

local function writer()
	return {
		bool = function(v) net.WriteBool(v and true or false) end,
		string = function(v) net.WriteString(v or "") end,
		uint8 = function(n) net.WriteUInt(n or 0, 8) end,
		uint16 = function(n) net.WriteUInt(n or 0, 16) end,
	}
end

local function sendOpen(ent)
	if not (net and net.Start and net.WriteUInt and net.SendToServer) then return end
	local idx = 0
	if ent ~= nil and type(ent.EntIndex) == "function" then
		local ok, n = pcall(ent.EntIndex, ent)
		if ok then idx = tonumber(n) or 0 end
	end
	if idx < 0 then idx = 0 end
	if idx > 65535 then idx = 65535 end
	net.Start("bal_loot_open")
	net.WriteUInt(idx, 16)
	net.SendToServer()
end

local function sendAct(req)
	if not (net and net.Start and net.SendToServer) then return end
	net.Start("bal_loot_act")
	L.WriteAct(writer(), req)
	net.SendToServer()
end

local function destroyGhost()
	local pnl = ghost
	ghost = nil
	if type(pnl) == "table" and type(pnl.Remove) == "function" then pcall(pnl.Remove, pnl) end
end

local function hideWindow()
	drag = nil
	rightWas = false
	destroyGhost()
	if valid(root) then
		root:SetVisible(false)
		root:SetMouseInputEnabled(false)
		if root.SetKeyboardInputEnabled then root:SetKeyboardInputEnabled(false) end
	end
	mark()
	if buyRestore then
		buyRestore = false
		if BALLISTICS.BuyWheel and type(BALLISTICS.BuyWheel.Open) == "function" then
			BALLISTICS.BuyWheel.Open()
		end
	end
end

local function closeWindow()
	if state.open == true then
		sendAct({
			from = "",
			kind = "close",
			key = "",
			amount = 0,
			to = "",
			slot = 0,
			whole = false,
		})
	end
	state = { open = false, note = "" }
	useSeen = false
	hideWindow()
end

-- Own inventory only. Looting someone else is left alone.
function L.CloseSelf()
	if state.open ~= true or state.self ~= true then return false end
	closeWindow()
	return true
end

local function inside(x, y, box)
	if type(box) ~= "table" then return false end
	return x >= box.x and y >= box.y and x < box.x + box.w and y < box.y + box.h
end

local function slotAt(x, y)
	for i = #hitSlots, 1, -1 do
		local row = hitSlots[i]
		if inside(x, y, row) then return row.slot end
	end
	return nil
end

local function acceptCtx()
	return {
		you = viewYou,
		them = viewThem,
		giveOnly = state.giveOnly == true,
		caps = state.caps,
		infinite = state.infinite == true,
		knife = L.KNIFE,
	}
end

local function slotTone(slot)
	if state.self == true then return "idle" end
	if type(drag) ~= "table" or type(slot) ~= "table" then return "idle" end
	if L.Accepts(drag, slot, acceptCtx()) then return "yes" end
	return "no"
end

local function activeBox()
	local sw, sh = screen()
	if state.self == true and type(L.SelfBox) == "function" then
		return L.SelfBox(sw, sh)
	end
	return L.PanelBox(sw, sh)
end

local function paintRing(cx, cy, radius, thick, frac)
	if not surface or type(surface.DrawPoly) ~= "function" then return end
	if draw and draw.NoTexture then draw.NoTexture() end
	local function wedge(sweepFrac, r, g, b, a)
		local steps = 40
		local sweep = math.pi * 2 * sweepFrac
		local start = -math.pi / 2
		local count = math.max(1, math.floor(steps * sweepFrac + 0.5))
		surface.SetDrawColor(r, g, b, a)
		for i = 0, count - 1 do
			local a1 = start + sweep * (i / count)
			local a2 = start + sweep * ((i + 1) / count)
			local function pt(ang, dist)
				return { x = cx + math.cos(ang) * dist, y = cy + math.sin(ang) * dist }
			end
			surface.DrawPoly({
				pt(a1, radius - thick),
				pt(a1, radius),
				pt(a2, radius),
				pt(a2, radius - thick),
			})
		end
	end
	wedge(1, 40, 40, 44, 180)
	if frac > 0 then
		local green = math.floor(70 + 150 * frac)
		local red = math.floor(210 * (1 - frac))
		wedge(frac, red, green, 80, 230)
	end
end

local function paintSlot(pnl, w, h)
	local slot = pnl.balSlot or {}
	local ghosting = pnl.balGhost == true
	local tone = ghosting and "idle" or slotTone(slot)
	local giveDim = state.giveOnly == true and slot.side == "them"
	local bgR, bgG, bgB = 32, 34, 40
	if giveDim then bgR, bgG, bgB = 26, 26, 28 end
	if tone == "yes" then bgR, bgG, bgB = 64, 56, 22 end
	if tone == "no" then bgR, bgG, bgB = 42, 42, 46 end
	local a = ghosting and 190 or 255
	surface.SetDrawColor(bgR, bgG, bgB, a)
	surface.DrawRect(0, 0, w, h)
	if tone == "yes" then
		surface.SetDrawColor(220, 190, 60, a)
	elseif tone == "no" then
		surface.SetDrawColor(90, 90, 96, a)
	else
		surface.SetDrawColor(70, 78, 92, a)
	end
	surface.DrawOutlinedRect(0, 0, w, h)
	local text = slot.name or ""
	if slot.kind == "gun" and slot.empty then text = "Empty" end
	if text == "" then text = slot.key or "" end
	local col = giveDim and Color(140, 140, 146, a) or Color(235, 235, 235, a)
	local sub = ""
	if slot.kind == "gun" and not slot.empty then
		sub = tostring(slot.clip or 0) .. " in mag"
		local atts = tonumber(slot.atts) or 0
		if atts > 0 then sub = sub .. "  " .. tostring(atts) .. " att" end
	elseif slot.kind ~= "gun" then
		sub = tostring(slot.count or 0)
		if slot.cap ~= nil and slot.kind ~= "ammo" then
			sub = sub .. " / " .. tostring(slot.cap)
		elseif slot.kind == "ammo" then
			sub = sub .. " rounds"
		end
	end
	local iconItem = L.IconItem(slot, BALLISTICS.Catalog)
	local rect = L.StackIconRect(slot.kind, w, h)
	if rect then
		-- Tall stack slot: name, count, then the icon centred below.
		draw.SimpleText(text, "BallisticsLoot", 8, 14, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if sub ~= "" then
			draw.SimpleText(sub, "BallisticsLootSmall", 8, 33, Color(170, 186, 204, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		if iconItem and BALLISTICS.BuyWheel and BALLISTICS.BuyWheel.DrawIcon then
			BALLISTICS.BuyWheel.DrawIcon(iconItem, w, h, pnl, rect)
		end
		return
	end
	draw.SimpleText(text, "BallisticsLoot", 8, h / 2 - 8, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	if sub ~= "" then
		draw.SimpleText(sub, "BallisticsLootSmall", 8, h / 2 + 10, Color(170, 186, 204, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	-- Spawn-menu icon on the right, same as the buy panel. The panel is the
	-- parent for a model fallback, and for the ghost copy of this slot.
	if iconItem and BALLISTICS.BuyWheel and BALLISTICS.BuyWheel.DrawIcon then
		BALLISTICS.BuyWheel.DrawIcon(iconItem, w, h, pnl)
	end
end

local function placeGhost()
	if not valid(ghost) or type(drag) ~= "table" then return end
	local slot = ghost.balSlot
	if type(slot) == "table" and slot.kind ~= "gun" then
		slot.count = drag.amount or slot.count
	end
	local mx, my = cursor()
	ghost:SetPos(mx - (tonumber(drag.ox) or 0), my - (tonumber(drag.oy) or 0))
end

local function ensureGhost(slot, wide, tall)
	if not vgui or type(vgui.Create) ~= "function" then return end
	if not valid(ghost) then
		local pnl = vgui.Create("DPanel")
		if not valid(pnl) then return end
		ghost = pnl
		pnl.balGhost = true
		if pnl.SetPaintedManually then pnl:SetPaintedManually(true) end
		pnl:SetMouseInputEnabled(false)
		if pnl.SetKeyboardInputEnabled then pnl:SetKeyboardInputEnabled(false) end
		if pnl.SetAlpha then pnl:SetAlpha(210) end
		if pnl.SetZPos then pnl:SetZPos(32767) end
		pnl.Paint = function(self, w, h)
			paintSlot(self, w, h)
		end
	end
	local copy = {}
	if type(slot) == "table" then
		for k, v in pairs(slot) do copy[k] = v end
	end
	ghost.balSlot = copy
	ghost.balGhost = true
	ghost:SetSize(wide or 96, tall or 48)
	if ghost.SetVisible then ghost:SetVisible(true) end
	placeGhost()
end

local function onSlotPress(slot, pnl)
	if type(slot) ~= "table" or slot.empty then return end
	if state.giveOnly == true and slot.side == "them" then
		state.note = L.Note("giveonly") or ""
		return
	end
	local id = L.SlotId(slot)
	local t = now()
	if L.DoubleClick(lastClick, t, id, DOUBLE) then
		lastClick = nil
		drag = nil
		destroyGhost()
		if type(L.WantsWhole) == "function" and not L.WantsWhole(state.self == true, true) then return end
		local other = L.OtherSide(slot.side)
		if not other then return end
		sendAct({
			from = slot.side,
			kind = slot.kind,
			key = slot.key,
			amount = slot.count or 1,
			to = other,
			slot = 0,
			fromSlot = slot.index or 0,
			whole = true,
		})
		return
	end
	lastClick = { t = t, id = id }
	local have = slot.count or 1
	if slot.kind == "gun" then have = 1 end
	local wide, tall = 96, 48
	local ox, oy = 16, 16
	if valid(pnl) then
		if type(pnl.GetWide) == "function" then wide = tonumber(pnl:GetWide()) or wide end
		if type(pnl.GetTall) == "function" then tall = tonumber(pnl:GetTall()) or tall end
		if type(pnl.LocalToScreen) == "function" then
			local ok, sx, sy = pcall(pnl.LocalToScreen, pnl, 0, 0)
			if ok and sx ~= nil then
				local mx, my = cursor()
				ox = mx - (tonumber(sx) or 0)
				oy = my - (tonumber(sy) or 0)
			end
		end
	end
	drag = {
		from = slot.side,
		kind = slot.kind,
		key = slot.key,
		index = slot.index or 0,
		have = have,
		clicks = 0,
		amount = 1,
		name = slot.name or slot.key,
		w = wide,
		h = tall,
		ox = ox,
		oy = oy,
	}
	ensureGhost(slot, wide, tall)
end

local function finishDrag()
	local current = drag
	drag = nil
	rightWas = false
	destroyGhost()
	if type(current) ~= "table" then return end
	local x, y = cursor()
	local box = activeBox()
	local insideCards = inside(x, y, box.left) or inside(x, y, box.right)
	local target = slotAt(x, y)
	local action = L.Release(current, target, insideCards, state.self == true)
	if action == "cancel" then
		if state.self == true and current.kind == "ammo" and not insideCards and type(target) ~= "table" then
			state.note = L.Note("ammo") or ""
		end
		return
	end
	if action == "drop" then
		sendAct({
			from = current.from,
			kind = current.kind,
			key = current.key,
			amount = current.amount or 1,
			to = "drop",
			slot = 0,
			fromSlot = current.index or 0,
			whole = false,
		})
		return
	end
	if type(target) ~= "table" then return end
	if not L.Accepts(current, target, acceptCtx()) then return end
	sendAct({
		from = current.from,
		kind = current.kind,
		key = current.key,
		amount = current.amount or 1,
		to = target.side,
		slot = target.index or 0,
		fromSlot = current.index or 0,
		whole = false,
	})
end

local function addSlot(parent, slot, x, y, w, h, originX, originY)
	if not vgui or not vgui.Create then return end
	local pnl = vgui.Create("DPanel", parent)
	if not valid(pnl) and pnl == nil then return end
	pnl.balSlot = slot
	pnl:SetPos(x, y)
	pnl:SetSize(w, h)
	pnl:SetMouseInputEnabled(true)
	if pnl.SetKeyboardInputEnabled then pnl:SetKeyboardInputEnabled(false) end
	pnl.Paint = paintSlot
	-- After the icon child, so the source slot reads as grey while it is held.
	function pnl:PaintOver(pw, ph)
		if not surface or not surface.DrawRect then return end
		if not L.IsDragSource or not L.IsDragSource(self.balSlot, drag) then return end
		surface.SetDrawColor(12, 12, 16, 150)
		surface.DrawRect(0, 0, pw, ph)
	end
	function pnl:OnMousePressed(code)
		if code == MOUSE_RIGHT_CODE then return end
		onSlotPress(self.balSlot, self)
	end
	function pnl:OnMouseReleased(code)
		-- Right release only adds to the stack; the left release ends the drag.
		if code == MOUSE_RIGHT_CODE then return end
		if drag then finishDrag() end
	end
	hitSlots[#hitSlots + 1] = {
		x = originX + x,
		y = originY + y,
		w = w,
		h = h,
		slot = slot,
	}
end

local function clearKids(pnl)
	if not valid(pnl) or type(pnl.GetChildren) ~= "function" then return end
	local kids = pnl:GetChildren()
	if type(kids) ~= "table" then return end
	for i = 1, #kids do
		if valid(kids[i]) and kids[i].Remove then kids[i]:Remove() end
	end
end

local function fillCard(card, side, view, box)
	if not valid(card) or type(view) ~= "table" then return end
	clearKids(card)
	local pad = 10
	local y = 40
	local inner = box.w - pad * 2
	local function label(text, tall)
		local pnl = vgui.Create("DPanel", card)
		pnl:SetPos(pad, y)
		pnl:SetSize(inner, tall)
		pnl:SetMouseInputEnabled(false)
		if pnl.SetKeyboardInputEnabled then pnl:SetKeyboardInputEnabled(false) end
		pnl.Paint = function(_, w, h)
			draw.SimpleText(text, "BallisticsLootSmall", 0, h / 2, Color(170, 186, 204), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		y = y + tall
	end
	local function rowSlots(list, kind, tall)
		list = type(list) == "table" and list or {}
		local n = #list
		if n < 1 then return end
		local gap = 6
		local w = math.floor((inner - gap * (n - 1)) / n)
		if w < 36 then w = 36 end
		for i = 1, n do
			local row = list[i]
			local empty = true
			local key = ""
			local count = 0
			if kind == "gun" then
				key = type(row.class) == "string" and row.class or ""
				empty = key == ""
				count = empty and 0 or 1
			else
				key = row.key or ""
				count = tonumber(row.count) or 0
				empty = count < 1
			end
			local atts = 0
			if type(row.attachments) == "table" then atts = #row.attachments end
			local name = row.name or key
			if kind == "gun" and empty then name = "" end
			addSlot(card, {
				side = side,
				kind = kind,
				key = key,
				class = (kind == "gun" and not empty) and key or nil,
				index = kind == "gun" and i or 0,
				count = count,
				empty = empty,
				name = name,
				clip = row.clip1 or 0,
				atts = atts,
				cap = row.cap,
			}, pad + (i - 1) * (w + gap), y, w, tall, box.x, box.y)
		end
		y = y + tall + 8
	end
	label("Guns", 16)
	local guns = view.guns or {}
	for i = 1, #guns do
		rowSlots({ guns[i] }, "gun", 58)
	end
	local hasAmmo = type(view.ammo) == "table" and #view.ammo > 0
	local stackTall = L.StackTall(box.h, y, hasAmmo)
	label("Throwables", 16)
	rowSlots(view.nades, "nade", stackTall)
	label("Meds", 16)
	rowSlots(view.meds, "med", stackTall)
	if type(view.ammo) == "table" and #view.ammo > 0 then
		label("Ammo", 16)
		rowSlots(view.ammo, "ammo", 48)
	end
end

local function layout()
	if not valid(root) or not valid(leftCard) or not valid(rightCard) then return end
	local sw, sh = screen()
	root:SetPos(0, 0)
	root:SetSize(sw, sh)
	local selfMode = state.self == true
	local box = activeBox()
	leftCard:SetPos(box.left.x, box.left.y)
	leftCard:SetSize(box.left.w, box.left.h)
	leftCard:SetVisible(true)
	if selfMode then
		rightCard:SetVisible(false)
		rightCard:SetMouseInputEnabled(false)
		rightCard:SetPos(0, 0)
		rightCard:SetSize(0, 0)
		clearKids(rightCard)
	else
		rightCard:SetVisible(true)
		rightCard:SetMouseInputEnabled(true)
		rightCard:SetPos(box.right.x, box.right.y)
		rightCard:SetSize(box.right.w, box.right.h)
	end
	hitSlots = {}
	viewYou = L.InvFromSide(state.you)
	viewThem = selfMode and L.InvFromSide(nil) or L.InvFromSide(state.them)
	fillCard(leftCard, "you", state.you, box.left)
	if not selfMode then fillCard(rightCard, "them", state.them, box.right) end
	if valid(invButton) then
		if selfMode then
			local bw, bh = 96, 22
			local header = 34
			invButton:SetSize(bw, bh)
			invButton:SetPos(box.left.x + box.left.w - bw - 8, box.left.y + math.floor((header - bh) / 2))
			invButton:SetVisible(true)
			if invButton.SetMouseInputEnabled then invButton:SetMouseInputEnabled(true) end
			if invButton.MoveToFront then invButton:MoveToFront() end
		else
			invButton:SetVisible(false)
			if invButton.SetMouseInputEnabled then invButton:SetMouseInputEnabled(false) end
		end
	end
	sizedW, sizedH = sw, sh
end

local function ensureRoot()
	if valid(root) then return root end
	if not vgui or not vgui.Create then return nil end
	root = vgui.Create("DPanel")
	root:SetVisible(false)
	root:SetMouseInputEnabled(true)
	if root.SetKeyboardInputEnabled then root:SetKeyboardInputEnabled(false) end
	root.Paint = function(_, w, h)
		surface.SetDrawColor(0, 0, 0, 150)
		surface.DrawRect(0, 0, w, h)
	end
	root.PaintOver = function(_, w, h)
		local note = state.note or ""
		if note == "" then return end
		draw.SimpleText(note, "BallisticsLoot", w / 2, h - 24, Color(230, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	function root:OnMousePressed() end
	function root:OnMouseReleased(code)
		-- Right release only adds to the stack; the left release ends the drag.
		if code == MOUSE_RIGHT_CODE then return end
		if drag then finishDrag() end
	end
	-- MakePopup keeps keyboard focus, so +use and the inventory bind never
	-- reach PlayerBindPress. These run while the panel has that focus.
	function root:OnKeyCodePressed(code)
		if onLootKeyPressed then onLootKeyPressed(code) end
	end
	function root:OnKeyCodeReleased(code)
		if onLootKeyReleased then onLootKeyReleased(code) end
	end

	local function card(title, side)
		local pnl = vgui.Create("DPanel", root)
		pnl.Paint = function(_, w, h)
			surface.SetDrawColor(18, 18, 22, 250)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(70, 78, 92, 255)
			surface.DrawOutlinedRect(0, 0, w, h)
			surface.SetDrawColor(14, 14, 18, 255)
			surface.DrawRect(0, 0, w, 34)
			draw.SimpleText(title, "BallisticsLootTitle", 12, 17, Color(240, 240, 240), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if side == "them" and state.giveOnly == true then
				draw.SimpleText("Give only", "BallisticsLootSmall", w - 12, 17, Color(160, 160, 168), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
			end
		end
		function pnl:OnMouseReleased(code)
			-- Right release only adds to the stack; the left release ends the drag.
			if code == MOUSE_RIGHT_CODE then return end
			if drag then finishDrag() end
		end
		return pnl
	end
	leftCard = card("Your inventory", "you")
	rightCard = card("Their inventory", "them")
	invButton = vgui.Create("DButton", root)
	invButton:SetText("")
	invButton:SetVisible(false)
	if invButton.SetKeyboardInputEnabled then invButton:SetKeyboardInputEnabled(false) end
	invButton.Paint = function(_, w, h)
		surface.SetDrawColor(32, 34, 40, 255)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(80, 88, 102, 255)
		surface.DrawOutlinedRect(0, 0, w, h)
		draw.SimpleText("Inventory", "BallisticsLootSmall", w / 2, h / 2, Color(230, 230, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	invButton.DoClick = function()
		closeWindow()
	end
	mark()
	return root
end

local function showWindow()
	local pnl = ensureRoot()
	if not valid(pnl) then return end
	if state.self == true and BALLISTICS.BuyWheel and type(BALLISTICS.BuyWheel.IsOpen) == "function" and BALLISTICS.BuyWheel.IsOpen() then
		buyRestore = true
		if type(BALLISTICS.BuyWheel.Hide) == "function" then BALLISTICS.BuyWheel.Hide() end
	end
	pnl:SetVisible(true)
	pnl:SetMouseInputEnabled(true)
	if pnl.MakePopup then pnl:MakePopup() end
	if pnl.SetKeyboardInputEnabled then pnl:SetKeyboardInputEnabled(true) end
	if pnl.RequestFocus then pnl:RequestFocus() end
	sizedW, sizedH = 0, 0
	layout()
	mark()
end

local function inventoryKey()
	if BALLISTICS.Keys and type(BALLISTICS.Keys.InventoryKey) == "function" then
		return BALLISTICS.Keys.InventoryKey()
	end
	return (BALLISTICS.Keys and BALLISTICS.Keys.KEY_4) or 5
end

local function keyDownCode(code)
	local Keys = BALLISTICS.Keys
	if Keys and Keys.IsBindDown then return Keys.IsBindDown(code) end
	if not input or type(input.IsKeyDown) ~= "function" then return false end
	local ok, down = pcall(input.IsKeyDown, code)
	return ok and down == true
end

-- Same skip as the F2/F3 poll: chat, console, the game menu, a text entry.
local function typingBlocked()
	if chatOpen then return true end
	local ply = localPly()
	if ply and type(ply.IsTyping) == "function" then
		local ok, on = pcall(ply.IsTyping, ply)
		if ok and on == true then return true end
	end
	if gui and gui.IsConsoleVisible and gui.IsConsoleVisible() then return true end
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return true end
	local f = vgui and vgui.GetKeyboardFocus and vgui.GetKeyboardFocus()
	if valid(f) and f.GetClassName and f:GetClassName() == "TextEntry" then return true end
	return false
end

local function selfAllowed(ply)
	local teamId = nil
	if type(ply.Team) == "function" then
		local ok, id = pcall(ply.Team, ply)
		if ok then teamId = id end
	end
	local slotted = BALLISTICS.IsPlayingTeam and BALLISTICS.IsPlayingTeam(teamId) == true
	local spectating = false
	if type(ply.Alive) == "function" and ply:Alive() == true and type(ply.GetObserverMode) == "function" then
		local ok, mode = pcall(ply.GetObserverMode, ply)
		if ok and type(mode) == "number" and mode ~= (OBS_MODE_NONE or 0) then spectating = true end
	end
	local conscious = true
	if BALLISTICS.IsConscious then
		conscious = BALLISTICS.IsConscious(ply) == true
	elseif ply.pbDown == true then
		conscious = false
	end
	return L.CanOpenSelf({
		phase = phaseOf(ply),
		alive = type(ply.Alive) == "function" and ply:Alive() == true,
		spectating = spectating,
		slotted = slotted,
		conscious = conscious,
	})
end

local function sendSelf()
	if not (net and net.Start and net.SendToServer) then return end
	net.Start("bal_loot_self")
	net.SendToServer()
end

function L.ToggleSelf()
	if state.open == true and state.self == true then
		closeWindow()
		return
	end
	local ply = localPly()
	if ply and selfAllowed(ply) then sendSelf() end
end

local function thinkInventoryKey()
	local F = BALLISTICS.FKeys
	if not F or type(F.Step) ~= "function" then return end
	local key = inventoryKey()
	local down = key > 0 and keyDownCode(key)
	local t = (RealTime and RealTime()) or 0
	if not F.Step(invEdge, down == true, t, typingBlocked()) then return end
	L.ToggleSelf()
end

local function applyState(nextState)
	if type(nextState) ~= "table" then return end
	local wasOpen = state.open == true
	state = nextState
	if state.open ~= true then
		state.open = false
		clearHold()
		useSeen = false
		hideWindow()
		return
	end
	if not wasOpen then useSeen = false end
	clearHold()
	showWindow()
end

function L.ApplyClientState(nextState)
	applyState(nextState)
end

-- The popup eats +use and, while keyboard focus is held, input.IsKeyDown.
-- Read the bound use key directly, and fall back to KEY_E (engine code 15).
local function useCode()
	local binding, code
	if input and type(input.LookupBinding) == "function" then
		local ok, name = pcall(input.LookupBinding, "+use", true)
		if ok and type(name) == "string" then binding = name end
	end
	if input and type(input.GetKeyCode) == "function" and type(binding) == "string" and binding ~= "" then
		local ok, got = pcall(input.GetKeyCode, binding)
		if ok then code = got end
	end
	local fallback = KEY_E
	if type(fallback) ~= "number" or fallback <= 0 then fallback = 15 end
	return L.UseKeyCode(binding, code, fallback)
end

local function popupUseDown()
	local code = useCode()
	if code <= 0 or not input then return false end
	if code >= (MOUSE_FIRST or 107) and code <= (MOUSE_LAST or 113) then
		if type(input.IsMouseDown) ~= "function" then return false end
		local ok, down = pcall(input.IsMouseDown, code)
		return ok and down == true
	end
	if type(input.IsKeyDown) ~= "function" then return false end
	local ok, down = pcall(input.IsKeyDown, code)
	return ok and down == true
end

local function customizeCode()
	local client = BALLISTICS.CKeyClient
	if client and type(client.KeyCode) == "function" then
		local code = client.KeyCode()
		if type(code) == "number" and code > 0 then return code end
	end
	return KEY_C or 13
end

onLootKeyPressed = function(code)
	if not windowOpen() then return end
	-- Focus eats +menu_context and can eat IsKeyDown. Match the customize bind
	-- here, close own inventory, then the same request the C key module sends.
	if BALLISTICS.CKey and BALLISTICS.CKey.InventoryHandoff(state.self == true, code, customizeCode()) then
		closeWindow()
		local client = BALLISTICS.CKeyClient
		if client and type(client.Press) == "function" then
			client.Press((CurTime and CurTime()) or 0)
		end
		return
	end
	local which = L.FocusClose(state.self == true, code, useCode(), inventoryKey())
	if which == "use" then
		if useLatch then return end
		useLatch = true
		useWas = true
		useSeen = true
		closeWindow()
		return
	end
	if which == "inventory" then
		if invEdge then invEdge.down = true end
		closeWindow()
	end
end

onLootKeyReleased = function(code)
	if not windowOpen() then return end
	if code == useCode() then
		useLatch = false
		useWas = false
	end
	local inv = inventoryKey()
	if invEdge and code == inv then invEdge.down = false end
end

local function thinkHold(ply)
	if windowOpen() and type(L.WindowUse) == "function" then
		local held = popupUseDown()
		if held then useSeen = true end
		local close, latch, was = L.WindowUse(true, held, useWas, useLatch, useSeen)
		useLatch = latch
		useWas = was
		if close then
			closeWindow()
			useLatch = true
			useWas = true
		end
		clearHold()
		return
	end
	local useNow = useDown(ply)
	useWas = useNow
	if useNow then
		local tr0 = aimTrace(ply, L.Range(BALLISTICS.Config) + 16)
		local e0 = tr0 and tr0.Entity
		local i0 = describe(ply, e0)
		gate(string.format("E held | phase=%s buy=%s window=%s latch=%s | aim=%s player=%s rag=%s self=%s aimOk=%s dist=%.0f range=%s",
			tostring(phaseOf(ply)), tostring(buyOpen()), tostring(windowOpen()), tostring(useLatch),
			valid(e0) and tostring(e0) or "none", tostring(i0.isPlayer), tostring(i0.isRagdoll), tostring(i0.isSelf), tostring(L.AimOk(i0)),
			valid(e0) and distTo(ply, e0) or -1, tostring(L.Range(BALLISTICS.Config))))
	else
		lastGate = nil
	end
	if useLatch then
		if useNow then clearHold() return end
		useLatch = false
	end
	if buyOpen() or not L.PhaseOk(phaseOf(ply)) then
		clearHold()
		return
	end
	noteHurt(ply)
	local down = useDown(ply)
	local range = L.Range(BALLISTICS.Config)
	local tr = aimTrace(ply, range + 16)
	local ent = tr and tr.Entity or nil
	local info = describe(ply, ent)
	local aimed = L.AimOk(info) and valid(ent)
	local dist = aimed and distTo(ply, ent) or math.huge
	local inRange = aimed and L.InRange(dist, range)
	local los = aimed and tr ~= nil and (tr.Entity == ent or tr.Fraction == 1 or tr.Hit == false)
	if hold == nil then
		if down and aimed and inRange and los then
			gate("ring start")
			hold = L.BeginHold(now(), copyPos(posOf(ent)))
			hold.ent = ent
			hold.sent = false
			hurtLatch = false
			if type(ply.Health) == "function" then
				local ok, hp = pcall(ply.Health, ply)
				if ok then lastHp = tonumber(hp) end
			end
		end
		ring = 0
		return
	end
	local same = aimed and ent == hold.ent
	local moved = false
	if same then moved = L.Moved(hold.origin, posOf(ent), L.MOVE) end
	local tick = L.HoldTick(hold, now(), {
		down = down,
		valid = same,
		inRange = inRange,
		los = los,
		hurt = hurtLatch,
		moved = moved,
	})
	if tick.cancel then
		if debugCv and debugCv:GetBool() and tick.reason ~= lastWhy then print("[Ballistics loot] hold cancel: " .. tostring(tick.reason)) end
		lastWhy = tick.reason
		clearHold()
		return
	end
	ring = tick.progress or 0
	if tick.done and hold.sent ~= true then
		hold.sent = true
		useLatch = true
		gate("hold done, asking server to open")
		sendOpen(hold.ent)
	end
end

local function thinkDrag()
	if type(drag) ~= "table" then
		rightWas = false
		return
	end
	local right = mouseDown(MOUSE_RIGHT_CODE)
	if right == true and not rightWas then
		drag.clicks = (drag.clicks or 0) + 1
		drag.amount = L.StackAmount(drag.have, 1, drag.clicks)
	end
	if right ~= nil then rightWas = right == true end
	local left = mouseDown(MOUSE_LEFT_CODE)
	-- The press frame can report the button up. Wait until it has been seen down.
	if left == true then drag.seenDown = true end
	if left == false and drag.seenDown == true then finishDrag() end
	placeGhost()
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_loot_state", function(payload)
		applyState(payload)
	end, {
		read = function()
			return L.ReadState({
				bool = function() return net.ReadBool() end,
				string = function() return net.ReadString() end,
				uint8 = function() return net.ReadUInt(8) end,
				uint16 = function() return net.ReadUInt(16) end,
			})
		end,
	})
end

if hook and hook.Add then
	hook.Add("StartChat", "Ballistics_Loot", function() chatOpen = true end)
	hook.Add("FinishChat", "Ballistics_Loot", function() chatOpen = false end)
	hook.Add("Think", "Ballistics_Loot", function()
		local ply = localPly()
		if ply then thinkHold(ply) end
		thinkInventoryKey()
		if windowOpen() then
			local sw, sh = screen()
			if sw ~= sizedW or sh ~= sizedH then
				sizedW, sizedH = sw, sh
				layout()
			end
			if valid(root) then
				if root.SetKeyboardInputEnabled then root:SetKeyboardInputEnabled(true) end
				root:SetMouseInputEnabled(true)
			end
			thinkDrag()
		end
	end)

	hook.Add("HUDPaint", "Ballistics_LootRing", function()
		if hold == nil or ring <= 0 or windowOpen() then return end
		local sw, sh = screen()
		paintRing(sw / 2, sh / 2, 28, 5, ring)
	end)

	-- HUDPaint draws under the loot popup. The ghost is the whole slot, painted
	-- after VGUI so it stays on top of the window while the button is held.
	hook.Add("PostRenderVGUI", "Ballistics_LootDrag", function()
		if type(drag) ~= "table" or not valid(ghost) then return end
		placeGhost()
		if ghost.PaintManual then ghost:PaintManual() end
		if type(ghost.GetChildren) ~= "function" then return end
		local kids = ghost:GetChildren()
		if type(kids) ~= "table" then return end
		for i = 1, #kids do
			local kid = kids[i]
			if valid(kid) and kid.PaintManual and (not kid.IsVisible or kid:IsVisible() ~= false) then
				kid:PaintManual()
			end
		end
	end)

	-- Escape closes the window and does not open the pause menu.
	-- Dragging uses the mouse buttons. Block fire while the window is up so a
	-- click moves an item. The use button is left alone.
	hook.Add("PlayerBindPress", "Ballistics_Loot", function(_, bind, pressed)
		if not pressed or not windowOpen() then return end
		local name = string.lower(bind or "")
		if name == "+attack" or name == "+attack2" then return true end
	end)

	hook.Add("OnPauseMenuShow", "Ballistics_Loot", function()
		if not windowOpen() then return end
		if gui and gui.HideGameUI then gui.HideGameUI() end
		closeWindow()
		return false
	end)

	hook.Add("OnScreenSizeChanged", "Ballistics_Loot", function()
		sizedW, sizedH = 0, 0
		if windowOpen() then layout() end
	end)

	if gameevent and gameevent.Listen then
		gameevent.Listen("player_hurt")
	end
	hook.Add("player_hurt", "Ballistics_LootHurt", function(data)
		local ply = localPly()
		if not ply or type(data) ~= "table" or type(ply.UserID) ~= "function" then return end
		local ok, uid = pcall(ply.UserID, ply)
		if ok and tonumber(data.userid) == tonumber(uid) then
			hurtLatch = true
		end
	end)
end
