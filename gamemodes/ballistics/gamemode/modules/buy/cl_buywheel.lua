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
	if pnl == nil or pnl == false then return false end
	if IsValid then return IsValid(pnl) == true end
	if type(pnl) == "table" and type(pnl.IsValid) == "function" then return pnl:IsValid() == true end
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

local function configuredCap(name, fallback)
	local n = BALLISTICS.Config and BALLISTICS.Config[name]
	n = tonumber(n)
	if n == nil or n ~= n then return fallback end
	n = math.floor(n)
	if n < 0 then n = 0 end
	return n
end

local function ammoCount(ammoType)
	local ply = localPly()
	if not ply or type(ply.GetAmmoCount) ~= "function" then return 0 end
	local ok, n = pcall(ply.GetAmmoCount, ply, ammoType)
	n = ok and tonumber(n) or 0
	if not n or n ~= n or n < 0 then return 0 end
	return math.floor(n)
end

local function clientCtx(item)
	local ply = localPly()
	local alive = ply and type(ply.Alive) == "function" and ply:Alive() == true or false
	local medMax, medCount = 0, 0
	local grenadeMax, grenadeCount = nil, 0
	if item.kind == "med" then
		medMax = configuredCap("MedsMax", 3)
		if BALLISTICS.MedMax then
			local pbMax = tonumber(BALLISTICS.MedMax()) or 0
			if pbMax < medMax then medMax = pbMax end
		end
		local pb = PLAYER_BALLISTICS
		if pb and type(pb.MedAvailable) == "function" and ply then
			medCount = tonumber(pb.MedAvailable(ply, item.id)) or 0
		end
	elseif item.kind == "nade" then
		grenadeMax = configuredCap("GrenadesMax", 3)
		grenadeCount = ammoCount(item.ammo)
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
		grenadeCount = grenadeCount,
		grenadeMax = grenadeMax,
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

-- A miss is { ok = false, at = CurTime }. It is tried again every few seconds.
-- `false` is never stored: Material() before the addon mounts caches the
-- engine error material for that name, and a permanent false hid every icon.
local iconCache = {}
local iconSaid = {}

local function iconNow()
	if CurTime then return tonumber(CurTime()) or 0 end
	return 0
end

local function iconClass(item)
	if type(item) ~= "table" then return nil end
	local class = item.class or item.entity
	if type(class) ~= "string" or class == "" then return nil end
	return class
end

local function sayIcon(class, source, extra)
	local id = tostring(class) .. " " .. tostring(source)
	if iconSaid[id] then return end
	iconSaid[id] = true
	local line = "[Ballistics icon] " .. tostring(class) .. " via " .. tostring(source)
	if type(extra) == "string" and extra ~= "" then line = line .. " " .. extra end
	print(line)
end

local function rowTable(row)
	if type(row) ~= "table" then return nil end
	return row
end

local function listRow(kind, class)
	if not list or type(list.Get) ~= "function" then return nil end
	local ok, rows = pcall(list.Get, kind)
	if not ok or type(rows) ~= "table" then return nil end
	return rowTable(rows[class])
end

local function storedEnt(class)
	if not scripted_ents or type(scripted_ents.GetStored) ~= "function" then return nil end
	local ok, stored = pcall(scripted_ents.GetStored, class)
	if not ok or stored == nil then return nil end
	local kind = type(stored)
	if kind == "number" or kind == "string" or kind == "boolean" or kind == "function" then return nil end
	if type(stored.t) == "table" then return stored.t end
	return stored
end

local function storedWep(class)
	if not weapons or type(weapons.GetStored) ~= "function" then return nil end
	local ok, stored = pcall(weapons.GetStored, class)
	if not ok or stored == nil then return nil end
	local kind = type(stored)
	if kind == "number" or kind == "string" or kind == "boolean" or kind == "function" then return nil end
	return stored
end

local function pathOf(row, key)
	if type(row) ~= "table" then return nil end
	local path = row[key]
	if type(path) ~= "string" or path == "" then return nil end
	return path
end

-- file.Exists false: do not call Material. An early miss stores ___error for
-- that name for the rest of the session. nil means file.Exists is missing.
local function fileMounted(path)
	if not file or type(file.Exists) ~= "function" then return nil end
	local function has(p)
		local ok, yes = pcall(file.Exists, p, "GAME")
		if not ok then return nil end
		return yes == true
	end
	local bases = {}
	if string.sub(path, 1, 10) == "materials/" then
		bases[1] = path
	else
		bases[1] = "materials/" .. path
		bases[2] = path
	end
	local saw = false
	for i = 1, #bases do
		local base = bases[i]
		local opts = { base }
		if not string.find(base, "%.png$", 1) and not string.find(base, "%.vmt$", 1) then
			opts[#opts + 1] = base .. ".png"
			opts[#opts + 1] = base .. ".vmt"
		end
		for j = 1, #opts do
			local yes = has(opts[j])
			if yes == nil then return nil end
			saw = true
			if yes then return true end
		end
	end
	if saw then return false end
	return nil
end

local function badTexName(name)
	return name == "" or name == "error" or name == "___error"
end

-- Flag words are not a VMT. Material() turns them into bits and builds a
-- different material than the unflagged png the spawn menu draws.
-- IsError on that result used to be cached forever. A png can also report
-- IsError while $basetexture is a real texture; that one still draws.
local function matUsable(mat)
	local kind = type(mat)
	if mat == nil or kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" or kind == "function" then
		return false
	end
	local name = ""
	if mat.GetName then
		local ok, n = pcall(mat.GetName, mat)
		if ok and type(n) == "string" then name = n end
	end
	local base = ""
	if mat.GetTexture then
		local ok, tex = pcall(mat.GetTexture, mat, "$basetexture")
		if ok and tex ~= nil then
			local tk = type(tex)
			if tk ~= "number" and tk ~= "string" and tk ~= "boolean" and tk ~= "function" and tex.GetName then
				local okN, n = pcall(tex.GetName, tex)
				if okN and type(n) == "string" then base = n end
			end
		end
	end
	if not badTexName(base) then return true end
	if badTexName(name) then return false end
	if mat.IsError then
		local ok, err = pcall(mat.IsError, mat)
		if ok and err == true then return false end
	end
	return true
end

local function tryMaterial(path)
	if type(path) ~= "string" or path == "" or not Material then return nil end
	local mounted = fileMounted(path)
	if mounted == false then return nil end
	local function load(flags)
		local ok, mat
		if flags then
			ok, mat = pcall(Material, path, flags)
		else
			ok, mat = pcall(Material, path)
		end
		if ok and matUsable(mat) then return mat end
		return nil
	end
	local mat = load(nil)
	if mat then return mat end
	if mounted == true then
		mat = load("smooth")
		if mat then return mat end
	end
	return nil
end

local function modelOf(row)
	return pathOf(row, "WorldModel") or pathOf(row, "Model")
end

local function fromSelect(icon)
	if type(icon) == "string" and icon ~= "" then
		local mat = tryMaterial(icon)
		if mat then return { ok = true, mat = mat, source = "wepselect", path = icon } end
	elseif type(icon) == "number" and icon > 0 then
		return { ok = true, tex = icon, source = "wepselect" }
	end
	return nil
end

local function resolveIcon(class)
	local spawnRow = listRow("SpawnableEntities", class)
	local sent = storedEnt(class)
	local wepRow = listRow("Weapon", class)
	local wep = storedWep(class)
	local sources = {
		spawnable = pathOf(spawnRow, "IconOverride"),
		sent = pathOf(sent, "IconOverride"),
		weapon = pathOf(wepRow, "IconOverride"),
		weaponStored = pathOf(wep, "IconOverride"),
	}
	local candidates = {}
	if BALLISTICS.Catalog and type(BALLISTICS.Catalog.IconCandidates) == "function" then
		candidates = BALLISTICS.Catalog.IconCandidates(class, sources) or {}
	end
	for i = 1, #candidates do
		local row = candidates[i]
		local mat = tryMaterial(row.path)
		if mat then
			sayIcon(class, row.source, row.path)
			return { ok = true, mat = mat, source = row.source, path = row.path }
		end
	end
	local hit = fromSelect(wep and wep.WepSelectIcon) or fromSelect(wepRow and wepRow.WepSelectIcon)
	if hit then
		sayIcon(class, "wepselect", hit.path)
		return hit
	end
	return nil, modelOf(wep) or modelOf(wepRow) or modelOf(sent) or modelOf(spawnRow)
end

local function iconFor(item)
	local class = iconClass(item)
	if not class then return nil end
	local cached = iconCache[class]
	local due = true
	if BALLISTICS.Catalog and type(BALLISTICS.Catalog.IconRetry) == "function" then
		due = BALLISTICS.Catalog.IconRetry(cached, iconNow(), 3) == true
	elseif type(cached) == "table" and cached.ok == true then
		due = false
	end
	if not due then return cached end
	local hit, model = resolveIcon(class)
	if hit then
		iconCache[class] = hit
		return hit
	end
	local miss = { ok = false, at = iconNow(), model = model }
	iconCache[class] = miss
	if type(model) == "string" and model ~= "" then sayIcon(class, "model", model) end
	return miss
end

local function hideModel(panel)
	local child = panel and panel.balModel
	if not valid(child) then return end
	if child.SetVisible then child:SetVisible(false) end
end

local function showModel(panel, model, w, h)
	if not valid(panel) or type(model) ~= "string" or model == "" then return false end
	if not vgui or type(vgui.Create) ~= "function" then return false end
	local x, y, size = w, h, h
	do
		local sizeN = (tonumber(h) or 0) - 8
		if sizeN < 8 then sizeN = 8 end
		local wide = tonumber(w) or 0
		if wide > 16 and sizeN > wide - 8 then sizeN = wide - 8 end
		local left = wide - sizeN - 4
		if left < 0 then left = 0 end
		x, y, size = left, 4, sizeN
	end
	local child = panel.balModel
	if not valid(child) then
		child = vgui.Create("SpawnIcon", panel)
		if not valid(child) then child = vgui.Create("ModelImage", panel) end
		if not valid(child) then return false end
		panel.balModel = child
		child:SetMouseInputEnabled(false)
		if child.SetKeyboardInputEnabled then child:SetKeyboardInputEnabled(false) end
		child.DoClick = function() end
		child.DoRightClick = function() end
		child.OpenMenu = function() end
	end
	if panel.balGhost and child.SetPaintedManually then child:SetPaintedManually(true) end
	if child.SetAlpha then child:SetAlpha(panel.balGhost and 190 or 255) end
	if child.SetVisible then child:SetVisible(true) end
	child:SetPos(x, y)
	child:SetSize(size, size)
	if child.SetModel and child.balModelPath ~= model then
		-- SpawnIcon takes model, skin, bodygroups. ModelImage ignores the extra args.
		pcall(child.SetModel, child, model, 0, 0)
		child.balModelPath = model
	end
	return true
end

local function iconRect(w, h)
	local size = (tonumber(h) or 0) - 8
	if size < 8 then size = 8 end
	local wide = tonumber(w) or 0
	if wide > 16 and size > wide - 8 then size = wide - 8 end
	local x = wide - size - 4
	if x < 0 then x = 0 end
	return x, 4, size
end

local function drawIcon(item, w, h, panel)
	local icon = iconFor(item)
	if type(icon) ~= "table" then
		hideModel(panel)
		return
	end
	local alpha = (panel and panel.balGhost) and 190 or 255
	if icon.ok == true and icon.mat and surface and surface.SetMaterial and surface.DrawTexturedRect then
		hideModel(panel)
		local x, y, size = iconRect(w, h)
		surface.SetDrawColor(255, 255, 255, alpha)
		surface.SetMaterial(icon.mat)
		surface.DrawTexturedRect(x, y, size, size)
		return
	end
	if icon.ok == true and icon.tex and surface and surface.SetTexture and surface.DrawTexturedRect then
		hideModel(panel)
		local x, y, size = iconRect(w, h)
		surface.SetDrawColor(255, 255, 255, alpha)
		surface.SetTexture(icon.tex)
		-- Weapon-select textures are authored at about 2:1.
		surface.DrawTexturedRect(x - size, y, size * 2, size)
		return
	end
	if type(icon.model) == "string" and showModel(panel, icon.model, w, h) then return end
	hideModel(panel)
end

-- Shared with the loot window: same spawn-menu icon and fallback.
BALLISTICS.BuyWheel = BALLISTICS.BuyWheel or {}
BALLISTICS.BuyWheel.DrawIcon = drawIcon

local function freshCount(item)
	if type(item) ~= "table" or type(item.key) ~= "string" or item.key == "" then return 0 end
	local ply = localPly()
	if not ply or type(ply.GetNW2String) ~= "function" then return 0 end
	if not (BALLISTICS.Sell and type(BALLISTICS.Sell.Decode) == "function") then return 0 end
	local raw = ply:GetNW2String("bal_fresh", "")
	if type(raw) ~= "string" then raw = "" end
	local map = BALLISTICS.Sell.Decode(raw)
	if type(map) ~= "table" then return 0 end
	local n = tonumber(map[item.key]) or 0
	if n ~= n or n < 0 then return 0 end
	return math.floor(n)
end

-- Bought this phase, still in hand, and not the knife.
local function sellable(item)
	if type(item) ~= "table" then return false end
	local knife = (BALLISTICS.Sell and BALLISTICS.Sell.KNIFE) or "tacrp_knife"
	if item.class == knife or item.key == knife then return false end
	if freshCount(item) < 1 then return false end
	local ply = localPly()
	if item.kind == "weapon" then return owns(item.class) == true end
	if item.kind == "nade" then return ammoCount(item.ammo) > 0 end
	if item.kind == "med" then
		local pb = PLAYER_BALLISTICS
		if pb and type(pb.MedAvailable) == "function" and ply then
			return (tonumber(pb.MedAvailable(ply, item.id)) or 0) > 0
		end
	end
	return false
end

local function paintItem(self, w, h)
	local item = self.balItem or {}
	local price = BALLISTICS.Catalog and BALLISTICS.Catalog.Price and BALLISTICS.Catalog.Price(item.key) or nil
	local owned = item.kind == "weapon" and owns(item.class)
	local full = item.kind == "weapon" and not owned and slotsFull(item)
	local afford = type(price) == "number" and moneyOf() >= price and not owned and not full
	local hover = self.Hovered == true
	if hover then
		surface.SetDrawColor(52, 64, 82, 255)
	elseif owned or not afford then
		surface.SetDrawColor(28, 28, 32, 255)
	else
		surface.SetDrawColor(36, 38, 46, 255)
	end
	surface.DrawRect(0, 0, w, h)
	if hover then
		surface.SetDrawColor(156, 198, 236, 255)
	elseif afford then
		surface.SetDrawColor(90, 140, 190, 255)
	else
		surface.SetDrawColor(70, 70, 78, 255)
	end
	surface.DrawOutlinedRect(0, 0, w, h)
	local name = item.name or item.key or ""
	draw.SimpleText(name, "BallisticsBuy", 12, 18, Color(235, 235, 235), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local priceText = "—"
	local priceCol = Color(190, 80, 80)
	if sellable(item) then
		local n = math.floor(tonumber(price) or 0)
		if n < 0 then n = 0 end
		priceText = "Sell  +$" .. tostring(n)
		priceCol = Color(120, 210, 140)
	elseif owned then
		priceText = "Owned"
	elseif full then
		priceText = "Full"
	elseif type(price) == "number" then
		priceText = "$" .. tostring(price)
		if afford then priceCol = Color(230, 210, 140) end
	end
	draw.SimpleText(priceText, "BallisticsBuySmall", 12, 42, priceCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	drawIcon(item, w, h, self)
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
			if sellable(item) then
				if BALLISTICS.Sell and type(BALLISTICS.Sell.Send) == "function" then
					BALLISTICS.Sell.Send(item)
				end
				return
			end
			tryBuy(item)
		end
		-- Right-click sells an owned item back (buy phase, server checks).
		btn.DoRightClick = function()
			if BALLISTICS.Sell and BALLISTICS.Sell.Send then BALLISTICS.Sell.Send(item) end
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
	if tab == "weapon" and BALLISTICS.Catalog and type(BALLISTICS.Catalog.WeaponColumns) == "function" then
		-- Two columns, light left and heavy right, one entry per row each.
		local colsT = BALLISTICS.Catalog.WeaponColumns(items) or {}
		local colW = math.floor((wide - gap) / 2)
		local hh = 22
		local tallest = 0
		local function column(groups, x, heading)
			local y = 0
			local top = vgui.Create("DPanel", canvas)
			top:SetPos(x, y)
			top:SetSize(colW, hh)
			top.Paint = function(_, w, h)
				draw.SimpleText(heading, "BallisticsBuy", 4, h / 2, Color(230, 210, 140), TEXT_ALIGN_LEFT or 0, TEXT_ALIGN_CENTER or 1)
			end
			y = y + hh + 4
			for g = 1, #(groups or {}) do
				local group = groups[g]
				local head = vgui.Create("DPanel", canvas)
				head:SetPos(x, y)
				head:SetSize(colW, hh)
				local title = group.category or ""
				head.Paint = function(_, w, h)
					draw.SimpleText(title, "BallisticsBuySmall", 4, h / 2, Color(170, 186, 204), TEXT_ALIGN_LEFT or 0, TEXT_ALIGN_CENTER or 1)
				end
				y = y + hh + 2
				for i = 1, #(group.items or {}) do
					local saved = bw
					bw = colW
					addButton(group.items[i], x, y)
					bw = saved
					y = y + bh + gap
				end
			end
			if y > tallest then tallest = y end
		end
		column(colsT.light, 0, "Light weapons")
		column(colsT.heavy, colW + gap, "Heavy weapons")
		canvas:SetTall(math.max(tallest, bh))
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
	local cw = math.min(860, sw - 40)
	-- Tall enough for the taller gun column with no scrolling, no more.
	-- Chrome: header 64 + tabs 44 + status 32 + list margins 16, plus padding.
	local need = 560
	if BALLISTICS.Catalog and BALLISTICS.Catalog.WeaponColumns and BALLISTICS.Catalog.ColumnHeight then
		local list = BALLISTICS.Buy and BALLISTICS.Buy.List and BALLISTICS.Buy.List("weapon") or nil
		local cols = BALLISTICS.Catalog.WeaponColumns(list)
		local tall = math.max(BALLISTICS.Catalog.ColumnHeight(cols.light, 26, 24, 72), BALLISTICS.Catalog.ColumnHeight(cols.heavy, 26, 24, 72))
		need = 156 + tall + 12
	end
	local ch = math.min(need, sh - 40)
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
		-- Inventory button is 110 wide with a 12px right margin.
		draw.SimpleText(tostring(secs) .. "s", "BallisticsBuyTitle", w - 134, h / 2, Color(230, 220, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	local headerInv = vgui.Create("DButton", header)
	headerInv:SetText("")
	headerInv:Dock(RIGHT)
	headerInv:SetWide(110)
	headerInv:DockMargin(8, 16, 12, 16)
	if headerInv.SetKeyboardInputEnabled then headerInv:SetKeyboardInputEnabled(false) end
	headerInv.Paint = function(self, w, h)
		if self.Hovered then
			surface.SetDrawColor(46, 54, 68, 255)
		else
			surface.SetDrawColor(32, 34, 40, 255)
		end
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(90, 110, 132, 255)
		surface.DrawOutlinedRect(0, 0, w, h)
		draw.SimpleText("Inventory", "BallisticsBuySmall", w / 2, h / 2, Color(235, 235, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	headerInv.DoClick = function()
		if BALLISTICS.Loot and type(BALLISTICS.Loot.ToggleSelf) == "function" then
			BALLISTICS.Loot.ToggleSelf()
		end
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
