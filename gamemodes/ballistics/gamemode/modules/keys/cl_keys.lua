-- Throwables key and the keybind panel. TacRP and Player Ballistics are not
-- edited. TacRP's G fallback is pointed at a dead key and its CreateMove is
-- wrapped, because that hook hardcodes KEY_G. tacrp_hints is forced off and
-- put back on ShutDown.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Keys = BALLISTICS.Keys or {}

local K = BALLISTICS.Keys
local HINTS = "tacrp_hints"
local THROW = "bal_throw_key"
local INV = "bal_inventory_key"

local throwState = (K.Fresh and K.Fresh()) or { down = false, ticks = 0, menu = false }
local wrapped = setmetatable({}, { __mode = "k" })
-- F1 toggle state, remembered across maps/sessions (cookie).
local pinned = (cookie and cookie.GetNumber and cookie.GetNumber("bal_keys_pinned", 0) == 1) or false
local revealUntil = 0
local f1Latch = false
local aliveSeen = false
local lastClass = nil
local hintsRemembered = nil
local hintsRunning = false

if CreateClientConVar then
	CreateClientConVar(THROW, tostring(K.KEY_3 or 4), true, false, "Throwables key (KEY_ enum). Tap quick throw, hold the menu. Default is 3.")
	CreateClientConVar(INV, tostring(K.KEY_4 or 5), true, false, "Inventory key (KEY_ enum). Toggles your inventory. Default is 4.")
end

local function convar(name)
	if type(GetConVar) ~= "function" then return nil end
	local ok, cv = pcall(GetConVar, name)
	if not ok then return nil end
	return cv
end

local function convarInt(name, fallback)
	local cv = convar(name)
	if cv == nil or type(cv.GetInt) ~= "function" then return fallback end
	local ok, n = pcall(cv.GetInt, cv)
	n = ok and tonumber(n) or nil
	if n == nil then return fallback end
	return math.floor(n)
end

function BALLISTICS.Keys.ThrowKey()
	local n = convarInt(THROW, K.KEY_3 or 4)
	if n < 0 then n = 0 end
	return n
end

function BALLISTICS.Keys.InventoryKey()
	local n = convarInt(INV, K.KEY_4 or 5)
	if n < 0 then n = 0 end
	return n
end

local function keyDown(code)
	if not input or type(input.IsKeyDown) ~= "function" then return false end
	local ok, down = pcall(input.IsKeyDown, code)
	return ok and down == true
end

local function localPly()
	if type(LocalPlayer) ~= "function" then return nil end
	local ok, ply = pcall(LocalPlayer)
	if not ok or ply == nil then return nil end
	return ply
end

local function typing()
	local ply = localPly()
	if ply and type(ply.IsTyping) == "function" then
		local ok, on = pcall(ply.IsTyping, ply)
		return ok and on == true
	end
	return false
end

local function lookup(bind)
	if not input or type(input.LookupBinding) ~= "function" then return nil end
	local ok, name = pcall(input.LookupBinding, bind)
	if ok then return name end
	return nil
end

local function codeOf(name)
	if not input or type(input.GetKeyCode) ~= "function" then return nil end
	local ok, code = pcall(input.GetKeyCode, name)
	if ok then return code end
	return nil
end

local function keyLabel(code, fallback)
	if input and type(input.GetKeyName) == "function" and tonumber(code) and code > 0 then
		local ok, name = pcall(input.GetKeyName, code)
		if ok and type(name) == "string" and name ~= "" then return string.upper(name) end
	end
	if type(K.KeyName) == "function" then
		local name = K.KeyName(code)
		if type(name) == "string" and name ~= "" and name ~= "NONE" then return name end
	end
	return fallback
end

local function bindLabel(command, fallback)
	local name = lookup(command)
	if type(name) == "string" and name ~= "" then return string.upper(name) end
	return fallback
end

local function pointBackup()
	if type(TacRP) ~= "table" or type(K.DeadBackup) ~= "function" then return end
	TacRP.GRENADE1_Backup = K.DeadBackup(keyDown)
end

local function armHints()
	hintsRunning = true
	local cv = convar(HINTS)
	if hintsRemembered == nil and cv and type(cv.GetInt) == "function" then
		local ok, n = pcall(cv.GetInt, cv)
		if ok and n ~= nil then hintsRemembered = tonumber(n) or 0 end
	end
	if cv and type(cv.SetInt) == "function" then pcall(cv.SetInt, cv, 0) end
end

local function restoreHints()
	hintsRunning = false
	local value = hintsRemembered
	hintsRemembered = nil
	if value == nil then return end
	local cv = convar(HINTS)
	if cv and type(cv.SetInt) == "function" then pcall(cv.SetInt, cv, value) end
end

local function forceHints()
	if not hintsRunning then return end
	local cv = convar(HINTS)
	if cv and type(cv.GetInt) == "function" and type(cv.SetInt) == "function" then
		local ok, n = pcall(cv.GetInt, cv)
		if ok and tonumber(n) ~= 0 then pcall(cv.SetInt, cv, 0) end
	end
end

local function applyCmd(cmd)
	if cmd == nil or type(cmd.GetButtons) ~= "function" or type(cmd.SetButtons) ~= "function" then return end
	if type(K.Step) ~= "function" or type(K.Intent) ~= "function" or type(K.ApplyButtons) ~= "function" then return end
	local key = BALLISTICS.Keys.ThrowKey()
	local down = key > 0 and keyDown(key)
	local now = (CurTime and CurTime()) or 0
	throwState = K.Step(throwState, down, now, typing())
	local pulsing = false
	if type(K.TakeTick) == "function" then pulsing = K.TakeTick(throwState) == true end
	local g1 = lookup("+grenade1")
	local grenade1Bound = type(g1) == "string" and g1 ~= ""
	local intent = K.Intent({
		pulsing = pulsing,
		menu = throwState.menu == true,
		grenade1Bound = grenade1Bound,
		boundToThrow1 = type(K.SameBind) == "function" and K.SameBind("+grenade1", key, lookup, codeOf) or false,
		boundToThrow2 = type(K.SameBind) == "function" and K.SameBind("+grenade2", key, lookup, codeOf) or false,
		gDown = keyDown(K.KEY_G or 17),
	})
	local ok, buttons = pcall(cmd.GetButtons, cmd)
	if not ok then return end
	cmd:SetButtons(K.ApplyButtons(buttons, intent))
end

local function tacWrapped()
	if not (hook and type(hook.GetTable) == "function") then return false end
	local ok, all = pcall(hook.GetTable)
	if not ok or type(all) ~= "table" or type(all.CreateMove) ~= "table" then return false end
	return wrapped[all.CreateMove.TacRP_CreateMove] == true
end

local function tryWrap()
	if not (hook and type(hook.GetTable) == "function" and type(hook.Add) == "function") then return end
	local ok, all = pcall(hook.GetTable)
	if not ok or type(all) ~= "table" or type(all.CreateMove) ~= "table" then return end
	local fn = all.CreateMove.TacRP_CreateMove
	if type(fn) ~= "function" or wrapped[fn] then return end
	local orig = fn
	local guard = function(cmd)
		orig(cmd)
		applyCmd(cmd)
	end
	wrapped[guard] = true
	hook.Add("CreateMove", "TacRP_CreateMove", guard)
end

local function listOpen()
	if type(K.ShowList) ~= "function" then return false end
	return K.ShowList(pinned, (CurTime and CurTime()) or 0, revealUntil) == true
end

local function toggleList()
	if type(K.ToggleList) ~= "function" then return end
	local now = (CurTime and CurTime()) or 0
	local pin, untilAt = K.ToggleList(pinned, now, revealUntil)
	pinned = pin == true
	revealUntil = 0
	if cookie and cookie.Set then cookie.Set("bal_keys_pinned", pinned and "1" or "0") end
end

-- Spawns, deploys and weapon switches never open the list: only F1 does.
local function reveal() end

local function weaponClass(ply)
	if ply == nil or type(ply.GetActiveWeapon) ~= "function" then return "" end
	local ok, wep = pcall(ply.GetActiveWeapon, ply)
	if not ok or wep == nil or type(wep.GetClass) ~= "function" then return "" end
	local classOk, class = pcall(wep.GetClass, wep)
	if classOk and type(class) == "string" then return class end
	return ""
end

local function watchLife()
	local ply = localPly()
	local alive = ply and type(ply.Alive) == "function" and ply:Alive() == true
	if not alive then
		aliveSeen = false
		return
	end
	local class = weaponClass(ply)
	if not aliveSeen then
		aliveSeen = true
		lastClass = class
		reveal()
		return
	end
	if class ~= lastClass then
		lastClass = class
		reveal()
	end
end

local function watchF1()
	local down = keyDown(K.KEY_F1 or 92)
	if down and not f1Latch then
		f1Latch = true
		toggleList()
	elseif not down then
		f1Latch = false
	end
end

function BALLISTICS.Keys.ListOpen()
	return listOpen()
end

function BALLISTICS.Keys.HintRows()
	local throw = BALLISTICS.Keys.ThrowKey()
	local inspect = convarInt("playerballistics_key_inspect", K.KEY_G or 17)
	local medCode = convar("playerballistics_med_key") and convarInt("playerballistics_med_key", 0) or 0
	local med = nil
	if medCode > 0 then med = keyLabel(medCode, "B") end
	if type(K.Rows) ~= "function" then return {} end
	return K.Rows({
		customize = bindLabel("+menu_context", "C"),
		throw = keyLabel(throw, "3"),
		inventory = keyLabel(BALLISTICS.Keys.InventoryKey(), "4"),
		inspect = keyLabel(inspect, "G"),
		blindfire = bindLabel("+zoom", "H"),
		safety = bindLabel("+use", "E"),
		teams = bindLabel("gm_showteam", "F2"),
		admin = bindLabel("gm_showspare1", "F3"),
		isAdmin = BALLISTICS.ClientIsAdmin and BALLISTICS.ClientIsAdmin() == true or false,
		med = med,
	})
end

local fontMade = false
local function fontName()
	if type(TacRP) == "table" then return "TacRP_HD44780A00_5x8_5" end
	if not fontMade and surface and type(surface.CreateFont) == "function" then
		surface.CreateFont("BallisticsKeys", { font = "Courier New", size = 14, weight = 500 })
		fontMade = true
	end
	return "BallisticsKeys"
end

local function paint()
	if not surface or not draw or type(ScrW) ~= "function" or type(ScrH) ~= "function" then return end
	if type(K.PanelBox) ~= "function" then return end
	local open = listOpen()
	local rows = open and BALLISTICS.Keys.HintRows() or {}
	local face = fontName()
	local widest, keyW = 0, 0
	local gap = 0
	local tag = K.TAG or "F1 Keybinds"
	if surface.SetFont and surface.GetTextSize then
		surface.SetFont(face)
		gap = surface.GetTextSize("  ") or 0
		if open then
			local actW = 0
			for i = 1, #rows do
				local kw = surface.GetTextSize(tostring(rows[i].key)) or 0
				local aw = surface.GetTextSize(tostring(rows[i].action)) or 0
				if kw > keyW then keyW = kw end
				if aw > actW then actW = aw end
			end
			widest = keyW + gap + actW
		else
			widest = surface.GetTextSize(tag) or 0
		end
	end
	local box = K.PanelBox(open and #rows or 1, ScrW(), ScrH(), open, widest)
	local white = Color and Color(255, 255, 255) or { r = 255, g = 255, b = 255, a = 255 }
	surface.SetDrawColor(0, 0, 0, 150)
	if type(TacRP) == "table" and type(TacRP.DrawCorneredBox) == "function" then
		TacRP.DrawCorneredBox(box.x, box.y, box.w, box.h, white)
	elseif type(surface.DrawRect) == "function" then
		surface.DrawRect(box.x, box.y, box.w, box.h)
	end
	local function text(str, x, y, align)
		if type(draw.SimpleText) ~= "function" then return end
		draw.SimpleText(str, face, x, y, white, align or TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	if not open then
		text(tag, box.x + K.PAD, box.y + box.h / 2)
		return
	end
	-- Key column measured with GetTextSize and right-aligned, so wide keys
	-- (F2, 1 2, MOUSE3) never start left of the panel.
	local keyRight = box.x + K.PAD + keyW
	for i = 1, #rows do
		local y = box.y + (i - 0.5) * box.row
		text(tostring(rows[i].key), keyRight, y, TEXT_ALIGN_RIGHT)
		text(tostring(rows[i].action), keyRight + gap, y)
	end
end

if hook and hook.Add then
	hook.Add("CreateMove", "Ballistics_ThrowKey", function(cmd)
		-- Think installs the TacRP wrapper, which applies the buttons after
		-- TacRP. Doing it here as well would step the tap twice.
		if tacWrapped() then return end
		applyCmd(cmd)
	end)
	hook.Add("Think", "Ballistics_Keys", function()
		pointBackup()
		tryWrap()
		forceHints()
		watchF1()
		watchLife()
	end)
	hook.Add("PlayerBindPress", "Ballistics_Keys", function(_, bind, pressed)
		local invKey = BALLISTICS.Keys.InventoryKey and BALLISTICS.Keys.InventoryKey() or nil
		if type(K.BlockBind) ~= "function" or not K.BlockBind(bind, BALLISTICS.Keys.ThrowKey(), invKey) then return end
		if pressed ~= false and type(bind) == "string" and string.lower(bind) == "gm_showhelp" then
			if not f1Latch then
				f1Latch = true
				toggleList()
			end
		end
		return true
	end)
	hook.Add("HUDPaint", "Ballistics_Keys", paint)
	hook.Add("InitPostEntity", "Ballistics_Keys", function()
		armHints()
		pointBackup()
		tryWrap()
	end)
	hook.Add("ShutDown", "Ballistics_Keys", restoreHints)
end

armHints()
