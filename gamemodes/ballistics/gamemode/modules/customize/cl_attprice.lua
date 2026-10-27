-- Draw the slot price on TacRP's customize screen. TacRP_CreateCustomizeHUD
-- walks the panel for TacRPAttSlot children and wraps PaintOver. Slots created
-- later (the attachment list) are wrapped on the panel Think. Red means the
-- balance cannot cover that slot.
-- TacRP's Drop Weapon button is the bottom-centre DButton created in
-- SWEP:CreateCustomizeHUD (cl_customize.lua). The hook runs after that button
-- exists. Hide it and draw the live balance where it sat.

BALLISTICS = BALLISTICS or {}
BALLISTICS.AttPrice = BALLISTICS.AttPrice or {}

if surface and surface.CreateFont then
	surface.CreateFont("BallisticsAttPrice", { font = "Roboto", size = 14, weight = 700, antialias = true })
	surface.CreateFont("BallisticsAttBalance", { font = "Roboto", size = 22, weight = 700, antialias = true })
end

local COL_OK = Color(235, 235, 235)
local COL_NO = Color(220, 40, 40)
local COL_BAL = Color(230, 210, 140)

local function valid(ent)
	if ent == nil or ent == false then return false end
	local kind = type(ent)
	if kind == "table" and type(ent.IsValid) == "function" then
		return ent:IsValid() == true
	end
	if kind ~= "table" and IsValid then return IsValid(ent) == true end
	return kind == "table" or kind == "Panel"
end

local function localPly()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	return ply
end

local function balance()
	local ply = localPly()
	if ply == nil or type(ply.GetNW2Int) ~= "function" then return 0 end
	local n = tonumber(ply:GetNW2Int("bal_money", 0))
	if not n or n ~= n then return 0 end
	return math.floor(n)
end

local function isSlot(pnl)
	if pnl == nil then return false end
	if type(pnl.GetClassName) == "function" then
		local ok, name = pcall(pnl.GetClassName, pnl)
		if ok and name == "TacRPAttSlot" then return true end
	end
	if type(pnl.GetSlot) == "function" and type(pnl.GetShortName) == "function" and type(pnl.GetInstalled) == "function" then
		return true
	end
	return false
end

local function childList(pnl)
	local list = {}
	if pnl == nil then return list end
	if type(pnl.GetChildren) == "function" then
		local ok, kids = pcall(pnl.GetChildren, pnl)
		if ok and type(kids) == "table" then
			for i = 1, #kids do
				list[#list + 1] = kids[i]
			end
		end
	end
	if type(pnl.GetCanvas) == "function" then
		local ok, canvas = pcall(pnl.GetCanvas, pnl)
		if ok and canvas ~= nil and canvas ~= pnl then
			list[#list + 1] = canvas
		end
	end
	return list
end

local function walk(pnl, fn, seen)
	if pnl == nil or seen[pnl] then return end
	seen[pnl] = true
	fn(pnl)
	local kids = childList(pnl)
	for i = 1, #kids do
		walk(kids[i], fn, seen)
	end
end

local function slotTableOf(pnl)
	local slotId
	local wep
	if type(pnl.GetSlot) == "function" then slotId = pnl:GetSlot() end
	if type(pnl.GetWeapon) == "function" then wep = pnl:GetWeapon() end
	if type(slotId) == "table" then return slotId end
	if wep == nil or type(wep.Attachments) ~= "table" then return nil end
	local slottbl = wep.Attachments[slotId]
	if type(slottbl) ~= "table" then return nil end
	return slottbl
end

local function wrapSlot(pnl)
	if pnl.BallisticsPriceWrapped == true then return end
	if not (BALLISTICS.AttPrice and BALLISTICS.AttPrice.Cost) then return end
	pnl.BallisticsPriceWrapped = true
	local prev = pnl.PaintOver
	pnl.PaintOver = function(self, w, h)
		if type(prev) == "function" then prev(self, w, h) end
		if not draw or type(draw.SimpleText) ~= "function" then return end
		local slottbl = slotTableOf(self)
		if not slottbl then return end
		local price = BALLISTICS.AttPrice.Cost(slottbl)
		if type(price) ~= "number" then return end
		local afford = BALLISTICS.AttPrice.Afford(price, balance())
		local col = COL_OK
		if not afford then col = COL_NO end
		local alignR = TEXT_ALIGN_RIGHT or 2
		local alignT = TEXT_ALIGN_TOP or 3
		draw.SimpleText("$" .. tostring(price), "BallisticsAttPrice", (tonumber(w) or 0) - 2, 1, col, alignR, alignT)
	end
end

local function moneyText()
	return "$" .. tostring(balance())
end

local LABEL_W = 160
local LABEL_H = 24

local function placeMoney(lab)
	if lab == nil or type(BALLISTICS.AttPrice.MoneyPlace) ~= "function" then return end
	local sw = (ScrW and ScrW()) or 0
	local sh = (ScrH and ScrH()) or 0
	local x, y = BALLISTICS.AttPrice.MoneyPlace(sw, sh, LABEL_W, LABEL_H)
	if type(lab.SetPos) == "function" then lab:SetPos(x, y) end
	if type(lab.SetSize) == "function" then lab:SetSize(LABEL_W, LABEL_H) end
end

local function ensureLabel(root)
	if not vgui or type(vgui.Create) ~= "function" then return end
	if valid(root.BallisticsBalance) then
		local lab = root.BallisticsBalance
		if type(lab.SetText) == "function" then lab:SetText(moneyText()) end
		placeMoney(lab)
		return
	end
	local lab = vgui.Create("DLabel", root)
	if lab == nil then return end
	root.BallisticsBalance = lab
	if type(lab.SetFont) == "function" then lab:SetFont("BallisticsAttBalance") end
	if type(lab.SetTextColor) == "function" then lab:SetTextColor(COL_BAL) end
	if type(lab.SetText) == "function" then lab:SetText(moneyText()) end
	if type(lab.SetContentAlignment) == "function" then lab:SetContentAlignment(5) end
	if type(lab.SetMouseInputEnabled) == "function" then lab:SetMouseInputEnabled(false) end
	if type(lab.SetZPos) == "function" then lab:SetZPos(100) end
	placeMoney(lab)
end

-- TacRP parents the Drop Weapon button on the customize panel. Hide it and
-- drop its click so the weapon cannot be dropped from this screen.
local function hideDrop(pnl)
	if pnl == nil or pnl.BallisticsDropHidden == true then return end
	if type(BALLISTICS.AttPrice.IsDropButton) ~= "function" then return end
	local className
	if type(pnl.GetClassName) == "function" then
		local ok, name = pcall(pnl.GetClassName, pnl)
		if ok then className = name end
	end
	local x, y, w, h = 0, 0, 0, 0
	if type(pnl.GetPos) == "function" then
		local ok, a, b = pcall(pnl.GetPos, pnl)
		if ok then
			x = tonumber(a) or 0
			y = tonumber(b) or 0
		end
	end
	if type(pnl.GetSize) == "function" then
		local ok, a, b = pcall(pnl.GetSize, pnl)
		if ok then
			w = tonumber(a) or 0
			h = tonumber(b) or 0
		end
	end
	local sw = (ScrW and ScrW()) or 0
	local sh = (ScrH and ScrH()) or 0
	if not BALLISTICS.AttPrice.IsDropButton(className, x, y, w, h, sw, sh) then return end
	pnl.BallisticsDropHidden = true
	pnl.DoClick = function() end
	pnl.DoRightClick = function() end
	if type(pnl.SetVisible) == "function" then pcall(pnl.SetVisible, pnl, false) end
	if type(pnl.SetMouseInputEnabled) == "function" then pcall(pnl.SetMouseInputEnabled, pnl, false) end
	if type(pnl.SetKeyboardInputEnabled) == "function" then pcall(pnl.SetKeyboardInputEnabled, pnl, false) end
end

local function decorate(root)
	walk(root, function(pnl)
		if isSlot(pnl) then wrapSlot(pnl) end
		hideDrop(pnl)
	end, {})
	ensureLabel(root)
end

function BALLISTICS.AttPrice.ApplyHUD(panel)
	if panel == nil then return end
	decorate(panel)
	if panel.BallisticsPriceThink == true then return end
	panel.BallisticsPriceThink = true
	local prev = panel.Think
	panel.Think = function(self)
		if type(prev) == "function" then prev(self) end
		decorate(self)
	end
end

if CLIENT and hook and hook.Add then
	hook.Add("TacRP_CreateCustomizeHUD", "Ballistics_AttPrice", function(_, panel)
		BALLISTICS.AttPrice.ApplyHUD(panel)
	end)
end
