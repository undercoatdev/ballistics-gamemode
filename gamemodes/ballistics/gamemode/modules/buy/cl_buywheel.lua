-- Buy wheel. Forced open for the whole BUY phase: no close button, ESC and
-- outside clicks do nothing. It closes itself when the phase leaves BUY.
-- BALLISTICS.BuyWheel.Open / Hide / IsOpen let Phase 6 swap it with the
-- attachment menu. C is not bound here.

BALLISTICS = BALLISTICS or {}
BALLISTICS.BuyWheel = BALLISTICS.BuyWheel or {}

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsBuyTitle", { font = "Roboto", size = 26, weight = 700, antialias = true })
	surface.CreateFont("BallisticsBuy", { font = "Roboto", size = 18, weight = 600, antialias = true })
	surface.CreateFont("BallisticsBuySmall", { font = "Roboto", size = 15, weight = 500, antialias = true })
end

local root
local card
local canvas
local tabButtons
local tab = "weapon"
local held = false
local phaseBuy = false
local seenShow = nil
local seenPhase = nil
local deadline = 0
local sizedW, sizedH = 0, 0
local localNote = ""
local localUntil = 0
local nextClick = 0

local function valid(pnl)
	if pnl == nil then return false end
	if IsValid then return IsValid(pnl) == true end
	return false
end

local function localPly()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	if IsValid and not IsValid(ply) then return nil end
	return ply
end

local function now()
	return (CurTime and CurTime()) or 0
end

local function moneyOf()
	local ply = localPly()
	if not ply or type(ply.GetNW2Int) ~= "function" then return 0 end
	return ply:GetNW2Int("bal_money", 0) or 0
end

local function timeLeft()
	local ply = localPly()
	if phaseBuy and ply and type(ply.GetNW2Float) == "function" then
		local ends = ply:GetNW2Float("bal_phase_ends", 0) or 0
		if ends > 0 then
			local left = ends - now()
			if left < 0 then return 0 end
			return left
		end
	end
	local left = deadline - now()
	if left < 0 then return 0 end
	return left
end

local function noteText()
	if now() < localUntil and localNote ~= "" then return localNote end
	local ply = localPly()
	if ply and type(ply.GetNW2String) == "function" then
		return ply:GetNW2String("bal_buy_note", "") or ""
	end
	return ""
end

local function syncCursor()
	if BALLISTICS.UI and BALLISTICS.UI.SyncCursor then
		BALLISTICS.UI.SyncCursor()
		return
	end
	if gui and gui.EnableScreenClicker then
		gui.EnableScreenClicker(held and valid(root) and root:IsVisible())
	end
end

local function mark()
	if BALLISTICS.UI and BALLISTICS.UI.Mark then
		BALLISTICS.UI.Mark("buy", root)
	end
	syncCursor()
end

local function setStatus(text)
	localNote = text or ""
	localUntil = now() + 3
end

local function owns(class)
	local ply = localPly()
	if not ply or type(ply.HasWeapon) ~= "function" then return false end
	return ply:HasWeapon(class) == true
end

local function gunCount()
	local list = BALLISTICS.Catalog and BALLISTICS.Catalog.Weapons and BALLISTICS.Catalog.Weapons() or {}
	local n = 0
	for i = 1, #list do
		local class = list[i] and list[i].class
		if owns(class) then n = n + 1 end
	end
	return n
end

local function slotsFull(item)
	if type(item) ~= "table" or item.kind ~= "weapon" then return false end
	local maxGuns = 2
	if BALLISTICS.Loadout and tonumber(BALLISTICS.Loadout.MAX_GUNS) then
		maxGuns = BALLISTICS.Loadout.MAX_GUNS
	end
	return gunCount() >= maxGuns
end

local function playing()
	local ply = localPly()
	if not ply or type(ply.Team) ~= "function" or not BALLISTICS.IsPlayingTeam then return false end
	return BALLISTICS.IsPlayingTeam(ply:Team()) == true
end

local function clientCtx(item)
	local ply = localPly()
	local alive = ply and type(ply.Alive) == "function" and ply:Alive() == true or false
	local medMax, medCount = 0, 0
	if item.kind == "med" then
		if BALLISTICS.MedMax then medMax = BALLISTICS.MedMax() or 0 end
		local pb = PLAYER_BALLISTICS
		if pb and type(pb.MedAvailable) == "function" and ply then
			medCount = tonumber(pb.MedAvailable(ply, item.id)) or 0
		end
	end
	local menu = nil
	if BALLISTICS.BuyMenuEnabled then menu = BALLISTICS.BuyMenuEnabled() == true end
	return {
		phase = phaseBuy and "buy" or "live",
		alive = alive,
		slotted = playing(),
		menuEnabled = menu,
		item = item,
		price = BALLISTICS.Catalog and BALLISTICS.Catalog.Price and BALLISTICS.Catalog.Price(item.key) or nil,
		balance = moneyOf(),
		owned = item.kind == "weapon" and owns(item.class) or false,
		gunSlotsFull = slotsFull(item),
		limits = BALLISTICS.Config and BALLISTICS.Config.BuyLimits or {},
		weaponBuys = 0,
		nadeCount = 0,
		medCount = medCount,
		medMax = medMax,
	}
end

local function sendBuy(key)
	if not net or not net.Start then return end
	net.Start("bal_buy")
	net.WriteString(key)
	net.SendToServer()
end

local function tryBuy(item)
	if not item or not phaseBuy then return end
	local t = now()
	if t < nextClick then return end
	nextClick = t + 0.2
	if BALLISTICS.Buy and BALLISTICS.Buy.Validate then
		local ok, err = BALLISTICS.Buy.Validate(clientCtx(item))
		if not ok then
			setStatus(BALLISTICS.Buy.ReasonText and BALLISTICS.Buy.ReasonText(err) or "Could not buy that.")
			return
		end
	end
	setStatus("")
	localUntil = 0
	sendBuy(item.key)
end

local function paintItem(self, w, h)
	local item = self.balItem or {}
	local price = BALLISTICS.Catalog and BALLISTICS.Catalog.Price and BALLISTICS.Catalog.Price(item.key) or nil
	local owned = item.kind == "weapon" and owns(item.class)
	local full = item.kind == "weapon" and not owned and slotsFull(item)
	local afford = type(price) == "number" and moneyOf() >= price and not owned and not full
	if owned or not afford then
		surface.SetDrawColor(28, 28, 32, 255)
	elseif self.Hovered then
		surface.SetDrawColor(46, 54, 68, 255)
	else
		surface.SetDrawColor(36, 38, 46, 255)
	end
	surface.DrawRect(0, 0, w, h)
	if afford then
		surface.SetDrawColor(90, 140, 190, 255)
	else
		surface.SetDrawColor(70, 70, 78, 255)
	end
	surface.DrawOutlinedRect(0, 0, w, h)
	local name = item.name or item.key or ""
	draw.SimpleText(name, "BallisticsBuy", 12, 18, Color(235, 235, 235), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local priceText = "—"
	local priceCol = Color(190, 80, 80)
	if owned then
		priceText = "Owned"
	elseif full then
		priceText = "Full"
	elseif type(price) == "number" then
		priceText = "$" .. tostring(price)
		if afford then priceCol = Color(230, 210, 140) end
	end
	draw.SimpleText(priceText, "BallisticsBuySmall", 12, 42, priceCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function refill()
	if not valid(canvas) or not vgui or not vgui.Create then return end
	canvas:Clear()
	local items = {}
	if BALLISTICS.Buy and BALLISTICS.Buy.List then items = BALLISTICS.Buy.List(tab) or {} end
	local wide = canvas:GetWide()
	if wide < 200 and valid(card) then wide = card:GetWide() - 16 end
	if wide < 200 then wide = 720 end
	local gap = 8
	local cols = 2
	local bw = math.floor((wide - gap) / cols)
	local bh = 64
	local function addButton(item, x, y)
		local btn = vgui.Create("DButton", canvas)
		btn:SetText("")
		btn:SetPos(x, y)
		btn:SetSize(bw, bh)
		btn.balItem = item
		btn.Paint = paintItem
		if btn.SetKeyboardInputEnabled then btn:SetKeyboardInputEnabled(false) end
		btn.DoClick = function()
			tryBuy(item)
		end
	end
	local function place(list, y)
		for i = 1, #list do
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			addButton(list[i], col * (bw + gap), y + row * (bh + gap))
		end
		local rows = math.ceil(#list / cols)
		if rows < 1 then return y end
		return y + rows * (bh + gap)
	end
	if tab == "weapon" and BALLISTICS.Catalog and type(BALLISTICS.Catalog.WeaponGroups) == "function" then
		local groups = BALLISTICS.Catalog.WeaponGroups(items) or {}
		local y = 0
		local hh = 22
		for g = 1, #groups do
			local group = groups[g]
			local head = vgui.Create("DPanel", canvas)
			head:SetPos(0, y)
			head:SetSize(wide, hh)
			local title = group.category or ""
			head.Paint = function(_, w, h)
				if not draw or not draw.SimpleText then return end
				draw.SimpleText(title, "BallisticsBuy", 4, h / 2, Color(170, 186, 204), TEXT_ALIGN_LEFT or 0, TEXT_ALIGN_CENTER or 1)
			end
			y = y + hh + 4
			y = place(group.items or {}, y)
		end
		if y < 1 then y = bh end
		canvas:SetTall(y)
		return
	end
	for i = 1, #items do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		addButton(items[i], col * (bw + gap), row * (bh + gap))
	end
	local rows = math.ceil(#items / cols)
	if rows < 1 then rows = 1 end
	canvas:SetTall(rows * (bh + gap))
end

local function paintTab(self, w, h)
	if self.balTab == tab then
		surface.SetDrawColor(48, 86, 128, 255)
	elseif self.Hovered then
		surface.SetDrawColor(48, 48, 56, 255)
	else
		surface.SetDrawColor(32, 32, 38, 255)
	end
	surface.DrawRect(0, 0, w, h)
	local title = "Tab"
	if BALLISTICS.Buy and BALLISTICS.Buy.TabTitle then
		title = BALLISTICS.Buy.TabTitle[self.balTab] or title
	end
	draw.SimpleText(title, "BallisticsBuy", w / 2, h / 2, Color(240, 240, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function layout()
	if not valid(root) or not valid(card) then return end
	local sw = (ScrW and ScrW()) or 1280
	local sh = (ScrH and ScrH()) or 720
	root:SetPos(0, 0)
	root:SetSize(sw, sh)
	local cw = math.min(780, sw - 40)
	local ch = math.min(560, sh - 40)
	if cw < 280 then cw = sw end
	if ch < 220 then ch = sh end
	card:SetSize(cw, ch)
	card:SetPos(math.floor((sw - cw) / 2), math.floor((sh - ch) / 2))
	if valid(canvas) then
		canvas:SetWide(cw - 24)
		refill()
	end
end

local function layoutIfNeeded()
	local sw = (ScrW and ScrW()) or 0
	local sh = (ScrH and ScrH()) or 0
	if sw == sizedW and sh == sizedH then return end
	sizedW, sizedH = sw, sh
	layout()
end

local function ensureRoot()
	if valid(root) then return root end
	if not vgui or not vgui.Create then return nil end
	root = vgui.Create("DPanel")
	root:SetVisible(false)
	root:SetMouseInputEnabled(true)
	root.Paint = function(_, w, h)
		surface.SetDrawColor(0, 0, 0, 170)
		surface.DrawRect(0, 0, w, h)
	end
	-- Outside clicks land here and do nothing. There is no close control.
	function root:OnMousePressed() end

	card = vgui.Create("DPanel", root)
	card.Paint = function(_, w, h)
		surface.SetDrawColor(18, 18, 22, 250)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(70, 78, 92, 255)
		surface.DrawOutlinedRect(0, 0, w, h)
	end

	local header = vgui.Create("DPanel", card)
	header:Dock(TOP)
	header:SetTall(64)
	header.Paint = function(_, w, h)
		surface.SetDrawColor(14, 14, 18, 255)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText("BUY", "BallisticsBuyTitle", 16, h / 2, Color(240, 240, 240), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("$" .. tostring(moneyOf()), "BallisticsBuyTitle", w / 2, h / 2, Color(120, 200, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		local secs = math.ceil(timeLeft() - 1e-4)
		if secs < 0 then secs = 0 end
		draw.SimpleText(tostring(secs) .. "s", "BallisticsBuyTitle", w - 16, h / 2, Color(230, 220, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	local tabs = vgui.Create("DPanel", card)
	tabs:Dock(TOP)
	tabs:SetTall(44)
	tabs:DockPadding(8, 6, 8, 6)
	tabs.Paint = function() end
	tabButtons = {}
	local order = (BALLISTICS.Buy and BALLISTICS.Buy.TabOrder) or { "weapon", "nade", "med" }
	for i = 1, #order do
		local id = order[i]
		local btn = vgui.Create("DButton", tabs)
		btn:Dock(LEFT)
		btn:SetWide(160)
		btn:DockMargin(0, 0, 8, 0)
		btn:SetText("")
		btn.balTab = id
		btn.Paint = paintTab
		if btn.SetKeyboardInputEnabled then btn:SetKeyboardInputEnabled(false) end
		btn.DoClick = function()
			tab = id
			refill()
		end
		tabButtons[id] = btn
	end

	local status = vgui.Create("DPanel", card)
	status:Dock(BOTTOM)
	status:SetTall(32)
	status.Paint = function(_, w, h)
		surface.SetDrawColor(14, 14, 18, 255)
		surface.DrawRect(0, 0, w, h)
		local text = noteText()
		if text ~= "" then
			draw.SimpleText(text, "BallisticsBuySmall", w / 2, h / 2, Color(230, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end

	local scroll = vgui.Create("DScrollPanel", card)
	scroll:Dock(FILL)
	scroll:DockMargin(12, 8, 12, 8)
	if scroll.GetCanvas then
		canvas = scroll:GetCanvas()
	end
	if not valid(canvas) then
		canvas = vgui.Create("DPanel", scroll)
		canvas:Dock(TOP)
	end
	canvas.Paint = function() end

	sizedW, sizedH = 0, 0
	layout()
	mark()
	return root
end

function BALLISTICS.BuyWheel.IsOpen()
	return held == true and valid(root) and root:IsVisible()
end

-- The popup eats slot keys, so select loadout slots here. The scroll wheel is
-- left to the list. invnext/invprev are blocked in PlayerBindPress, and slot4
-- is left for the throwables key.
function BALLISTICS.BuyWheel.HookWeaponPick(pnl)
	if not valid(pnl) or pnl.balWeaponPick then return end
	pnl.balWeaponPick = true
	local oldKey = pnl.OnKeyCodePressed
	pnl.OnKeyCodePressed = function(self, code)
		local bind = input and input.LookupKeyBinding and input.LookupKeyBinding(code)
		local slot = BALLISTICS.Loadout and BALLISTICS.Loadout.BindSlot and BALLISTICS.Loadout.BindSlot(bind)
		if slot ~= nil then
			if RunConsoleCommand then RunConsoleCommand("bal_slot", tostring(slot)) end
			return true
		end
		if oldKey then return oldKey(self, code) end
	end
end

function BALLISTICS.BuyWheel.Open()
	if not phaseBuy then return false end
	local pnl = ensureRoot()
	if not valid(pnl) then
		held = false
		return false
	end
	held = true
	BALLISTICS.BuyWheel.HookWeaponPick(pnl)
	pnl:SetVisible(true)
	pnl:SetMouseInputEnabled(true)
	if pnl.MakePopup then pnl:MakePopup() end
	sizedW, sizedH = 0, 0
	layoutIfNeeded()
	refill()
	mark()
	return true
end

function BALLISTICS.BuyWheel.Hide()
	held = false
	if valid(root) then
		root:SetVisible(false)
		root:SetMouseInputEnabled(false)
		if root.SetKeyboardInputEnabled then root:SetKeyboardInputEnabled(false) end
	end
	mark()
	return true
end

local function applyShow(show)
	show = show and true or false
	if seenShow == show then return end
	seenShow = show
	phaseBuy = show
	if show then
		BALLISTICS.BuyWheel.Open()
	else
		BALLISTICS.BuyWheel.Hide()
	end
end

-- nil until the server has published a phase. The bool is only meaningful then.
local function readPhase()
	local ply = localPly()
	if not ply or type(ply.GetNW2String) ~= "function" then return nil end
	local phase = ply:GetNW2String("bal_phase", "")
	if type(phase) ~= "string" or phase == "" then return nil end
	local show = false
	if type(ply.GetNW2Bool) == "function" then
		show = ply:GetNW2Bool("bal_buy_show", false) == true
	end
	return phase, show
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	-- Stock HL2 coin-slot sound as the purchase cha-ching.
	BALLISTICS.BuyWheel.BUY_SOUND = "ambient/levels/labs/coinslot1.wav"
	BALLISTICS.Net.Register("bal_buy_ok", function()
		if surface and surface.PlaySound then surface.PlaySound(BALLISTICS.BuyWheel.BUY_SOUND) end
	end, { read = function() return true end })

	BALLISTICS.Net.Register("bal_buy_open", function(payload)
		if type(payload) ~= "table" then return end
		local left = tonumber(payload.timeLeft) or 0
		if left < 0 then left = 0 end
		deadline = now() + left
		applyShow(payload.open == true)
	end, {
		read = function()
			return { open = net.ReadBool(), timeLeft = net.ReadFloat() }
		end,
	})
end

local function swallowEscape()
	if not held then return end
	if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() and gui.HideGameUI then
		gui.HideGameUI()
	end
	if not valid(root) then
		root = nil
		card = nil
		canvas = nil
		if phaseBuy then BALLISTICS.BuyWheel.Open() end
		return
	end
	if not root:IsVisible() then
		root:SetVisible(true)
		root:SetMouseInputEnabled(true)
		if root.MakePopup then root:MakePopup() end
		mark()
	end
end

if hook and hook.Add then
	-- Open and close on the phase edge only. A later poll of the same phase
	-- must not reopen the wheel after BuyWheel.Hide (Phase 6's C toggle).
	-- A stale "lobby" value must not shut a wheel the buy net message just opened.
	hook.Add("Think", "Ballistics_BuyWheel", function()
		local phase, show = readPhase()
		if phase ~= nil and phase ~= seenPhase then
			local prev = seenPhase
			seenPhase = phase
			if phase == "buy" then
				applyShow(show)
			elseif prev == "buy" then
				applyShow(false)
			end
		end
		if not held then return end
		swallowEscape()
		layoutIfNeeded()
	end)

	hook.Add("OnPauseMenuShow", "Ballistics_BuyWheel", function()
		if BALLISTICS.BuyWheel.IsOpen() then return false end
	end)

	hook.Add("PlayerBindPress", "Ballistics_BuyWheel", function(_, bind, pressed)
		if not pressed or not BALLISTICS.BuyWheel.IsOpen() then return end
		if string.lower(bind or "") == "cancelselect" then return true end
	end)

	hook.Add("OnScreenSizeChanged", "Ballistics_BuyWheel", function()
		sizedW, sizedH = 0, 0
		if held then layoutIfNeeded() end
	end)
end
