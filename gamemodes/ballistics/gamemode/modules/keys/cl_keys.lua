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
	CreateClientConVar("bal_keys_version", "0", true, false, "Internal: keybind layout version, used to migrate old saved keys.")
end

-- Saved (FCVAR_ARCHIVE) values from the old layout (throw 4, inventory 5)
-- beat the new defaults. Reset both once per layout version.
do
	local cv = type(GetConVar) == "function" and GetConVar("bal_keys_version") or nil
	local want = K.KEYS_VERSION or 2
	local saved = cv and type(cv.GetInt) == "function" and cv:GetInt() or nil
	if saved ~= nil and RunConsoleCommand and K.NeedsMigration and K.NeedsMigration(saved, want) then
		RunConsoleCommand(THROW, tostring(K.KEY_3 or 4))
		RunConsoleCommand(INV, tostring(K.KEY_4 or 5))
		RunConsoleCommand("bal_keys_version", tostring(want))
	end
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

local function backupCode()
	local code = type(K.DeadBackup) == "function" and K.DeadBackup(keyDown) or 101
	code = tonumber(code)
	if not code or code ~= code or code <= 0 then code = 101 end
	return math.floor(code)
end

local function grenadeFallback()
	if BALLISTICS.Keys.ThrowKey then
		return keyLabel(BALLISTICS.Keys.ThrowKey(), "!")
	end
	return "!"
end

-- TacRP.GetBind uppercases GetKeyName(GRENADE*_Backup) when the command is
-- unbound. A nameless backup (KEY_NONE) throws inside the weapon HUD.
local function guardBind(orig)
	return function(binding)
		if binding == "+grenade1" or binding == "+grenade2" then
			local bound = lookup(binding)
			if type(bound) ~= "string" or bound == "" then
				local code = binding == "+grenade1" and TacRP.GRENADE1_Backup or TacRP.GRENADE2_Backup
				local namer = input and input.GetKeyName
				if type(K.BackupLabel) == "function" then
					return K.BackupLabel(code, namer, grenadeFallback())
				end
				return grenadeFallback()
			end
		end
		if type(orig) ~= "function" then return "!" end
		local ok, result = pcall(orig, binding)
		if ok and type(result) == "string" and result ~= "" then return result end
		return "!"
	end
end

local function tryWrapBind()
	if type(TacRP) ~= "table" then return end
	local function wrap(field)
		local fn = TacRP[field]
		if type(fn) ~= "function" or wrapped[fn] then return end
		local guard = guardBind(fn)
		wrapped[guard] = true
		TacRP[field] = guard
	end
	wrap("GetBind")
	wrap("GetBindKey")
end

local function pointBackup()
	if type(TacRP) ~= "table" or type(K.DeadBackup) ~= "function" then return end
	local code = backupCode()
	TacRP.GRENADE1_Backup = code
	-- TacRP reads the wheel key from GRENADE2_Backup when +grenade2 is unbound
	-- (fresh clients). That was H; point it at our throwables key so the
	-- wheel follows bal_throw_key and H does nothing for it.
	TacRP.GRENADE2_Backup = BALLISTICS.Keys.ThrowKey()
	tryWrapBind()
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

-- Player Ballistics' med wheel: hold Z to open, release to close. PB reads the
-- key through PLAYER_BALLISTICS.MedKeyCode, so that is wrapped (PB untouched).
local function wrapMed()
	local PB = PLAYER_BALLISTICS
	if type(PB) ~= "table" or PB.BallisticsMedZ then return end
	if type(PB.MedKeyCode) ~= "function" or type(PB.MedKeyRelease) ~= "function" then return end
	PB.BallisticsMedZ = true
	local release = PB.MedKeyRelease
	PB.MedKeyCode = function() return KEY_Z or K.KEY_Z or 36 end
	PB.MedHold = function() return 0.05 end
	PB.MedKeyRelease = function(...) return K.MedRelease(release, ...) end
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
	buttons = K.ApplyButtons(buttons, intent)
	if type(K.BashButtons) == "function" then
		buttons = K.BashButtons(buttons, keyDown(K.KEY_V or 32))
	end
	cmd:SetButtons(buttons)
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
	local med = "Z"
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

local smallMade = false
local function smallFont()
	if not smallMade and surface and type(surface.CreateFont) == "function" then
		surface.CreateFont("BallisticsKeysSmall", { font = "Roboto", size = 13, weight = 500 })
		surface.CreateFont("BallisticsKeysMain", { font = "Roboto", size = 15, weight = 600 })
		smallMade = true
	end
	return "BallisticsKeysMain", "BallisticsKeysSmall"
end

-- Compact list: fixed narrow keycap column, action left-aligned beside it,
-- sub-actions indented and smaller, a small gap between number and letter keys.
local function paint()
	if not surface or not draw or type(ScrW) ~= "function" or type(ScrH) ~= "function" then return end
	if type(surface.SetFont) ~= "function" or type(surface.GetTextSize) ~= "function" or type(surface.DrawRect) ~= "function" or type(draw.SimpleText) ~= "function" then return end
	local open = listOpen()
	local tag = K.TAG or "F1 Keybinds"
	local main, small = smallFont()
	local white = Color(235, 235, 235)
	local dim = Color(180, 186, 196)
	local PAD, CAP, MAINH, SUBH, GAP = 6, 34, 20, 15, 6
	if not open then
		surface.SetFont(main)
		local tw = surface.GetTextSize(tag) or 60
		local h = MAINH + 4
		local y = math.floor(ScrH() / 2 - h / 2)
		surface.SetDrawColor(0, 0, 0, 150)
		surface.DrawRect(8, y, tw + PAD * 2, h)
		draw.SimpleText(tag, main, 8 + PAD, y + h / 2, white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		return
	end
	local rows = BALLISTICS.Keys.HintRows()
	local h, w = PAD * 2, 0
	for i = 1, #rows do
		local r = rows[i]
		surface.SetFont(r.sub and small or main)
		local aw = surface.GetTextSize(tostring(r.action)) or 0
		local lw = CAP + 8 + (r.sub and 8 or 0) + aw
		if lw > w then w = lw end
		h = h + (r.sub and SUBH or MAINH) + (r.gap and GAP or 0)
	end
	w = w + PAD * 2
	local x = 8
	local y = math.floor(ScrH() / 2 - h / 2)
	surface.SetDrawColor(0, 0, 0, 160)
	surface.DrawRect(x, y, w, h)
	local cy = y + PAD
	for i = 1, #rows do
		local r = rows[i]
		if r.gap then
			cy = cy + GAP
			surface.SetDrawColor(255, 255, 255, 30)
			surface.DrawRect(x + PAD, cy - GAP / 2 - 1, w - PAD * 2, 1)
		end
		if r.sub then
			draw.SimpleText(tostring(r.action), small, x + PAD + CAP + 16, cy + SUBH / 2, dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cy = cy + SUBH
		else
			local capH = MAINH - 4
			surface.SetDrawColor(255, 255, 255, 40)
			surface.DrawRect(x + PAD, cy + 2, CAP, capH)
			surface.SetDrawColor(255, 255, 255, 90)
			surface.DrawOutlinedRect(x + PAD, cy + 2, CAP, capH)
			draw.SimpleText(tostring(r.key), small, x + PAD + CAP / 2, cy + MAINH / 2, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(tostring(r.action), main, x + PAD + CAP + 8, cy + MAINH / 2, white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			cy = cy + MAINH
		end
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
		wrapMed()
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
pointBackup()
