-- Centred TAB scoreboard. ScoreboardShow returns true so the default
-- Derma board never opens. Held closed while the spawn editor is up.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Scoreboard = BALLISTICS.Scoreboard or {}

local S = BALLISTICS.Scoreboard

local FONT_TITLE = "BallisticsScoreTitle"
local FONT_SCORE = "BallisticsScoreScore"
local FONT_COL = "BallisticsScoreCol"
local FONT_ROW = "BallisticsScoreRow"
local FONT_SPEC = "BallisticsScoreSpec"

if surface and surface.CreateFont then
	surface.CreateFont(FONT_TITLE, { font = "Roboto", size = 20, weight = 700, antialias = true })
	surface.CreateFont(FONT_SCORE, { font = "Roboto", size = 28, weight = 700, antialias = true })
	surface.CreateFont(FONT_COL, { font = "Roboto", size = 15, weight = 700, antialias = true })
	surface.CreateFont(FONT_ROW, { font = "Roboto", size = 15, weight = 500, antialias = true })
	surface.CreateFont(FONT_SPEC, { font = "Roboto", size = 13, weight = 400, antialias = true })
end

local panel

local function color(r, g, b, a)
	if Color then return Color(r, g, b, a or 255) end
	return { r = r, g = g, b = b, a = a or 255 }
end

local COL_BG = color(14, 16, 20, 225)
local COL_TEXT = color(232, 232, 232)
local COL_MUTED = color(155, 158, 166)
local COL_DEAD = color(130, 132, 138)
local COL_SPEC = color(168, 170, 176)
local COL_LINE = color(255, 255, 255, 18)

local function alivePanel(pnl)
	if pnl == nil then return false end
	if IsValid then return IsValid(pnl) == true end
	return true
end

local function validEnt(ply)
	if ply == nil or ply == false then return false end
	if IsValid then return IsValid(ply) == true end
	return true
end

local function editing()
	local sp = BALLISTICS.Spawns
	return sp ~= nil and type(sp.IsEditing) == "function" and sp.IsEditing() == true
end

local function buryDefault()
	local board = rawget(_G, "g_Scoreboard")
	if not board then return end
	if IsValid and not IsValid(board) then return end
	if type(board.SetVisible) == "function" then board:SetVisible(false) end
	if type(board.Remove) == "function" then board:Remove() end
end

local function localPlayer()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if not validEnt(ply) then return nil end
	return ply
end

local function roundsToWin()
	local cfg = BALLISTICS.Config
	if type(cfg) == "table" and cfg.RoundsToWin ~= nil then return cfg.RoundsToWin end
	return 0
end

local function headerNow()
	local snap
	local hud = BALLISTICS.RoundHud
	if hud and type(hud.Snapshot) == "function" then
		local ok, got = pcall(hud.Snapshot)
		if ok and type(got) == "table" then snap = got end
	end
	local round, good, bad = 0, 0, 0
	local ply = localPlayer()
	if ply and type(ply.GetNW2Int) == "function" then
		round = ply:GetNW2Int(S.NWRound or "bal_round", 0) or 0
		good = ply:GetNW2Int(S.NWGood or "bal_score_good", 0) or 0
		bad = ply:GetNW2Int(S.NWBad or "bal_score_bad", 0) or 0
	end
	if type(S.MatchFrom) == "function" then
		return S.MatchFrom(snap, round, good, bad, roundsToWin())
	end
	return { roundLine = "", scoreLeft = good, scoreRight = bad }
end

local function fromSlots(teamId)
	local slots = BALLISTICS.Slots
	if type(slots) ~= "table" or type(slots.Members) ~= "function" then return nil end
	local members = slots.Members(teamId)
	if type(members) ~= "table" then return nil end
	local out = {}
	for i = 1, #members do
		local ply = members[i]
		if type(slots.Player) == "function" then
			local ok, got = pcall(slots.Player, members[i])
			if ok and got ~= nil then ply = got end
		end
		if ply ~= nil then out[#out + 1] = ply end
	end
	return out
end

-- team.GetPlayers is the live team list. Slots are only a fallback.
local function teamList(teamId)
	if team and type(team.GetPlayers) == "function" then
		local ok, got = pcall(team.GetPlayers, teamId)
		if ok and type(got) == "table" then return got end
	end
	return fromSlots(teamId) or {}
end

local function rowsFor(teamId)
	local raw = teamList(teamId)
	local list = {}
	for i = 1, #raw do
		if validEnt(raw[i]) then list[#list + 1] = raw[i] end
	end
	if type(S.SortPlayers) == "function" then list = S.SortPlayers(list) end
	local rows = {}
	for i = 1, #list do
		rows[i] = (type(S.Row) == "function" and S.Row(list[i])) or { name = "", kills = 0, deaths = 0, ping = 0, alive = true }
	end
	return rows
end

local function columnTitle(teamId)
	local name
	if team and type(team.GetName) == "function" then
		local ok, got = pcall(team.GetName, teamId)
		if ok and type(got) == "string" then name = got end
	end
	if (type(name) ~= "string" or name == "") and BALLISTICS.TeamName then
		name = BALLISTICS.TeamName[teamId]
	end
	if type(S.ColumnName) == "function" then return S.ColumnName(teamId, name) end
	return tostring(name or teamId)
end

local function specNames()
	local ids, seenId = {}, {}
	local function addId(id)
		if type(id) ~= "number" or seenId[id] then return end
		seenId[id] = true
		ids[#ids + 1] = id
	end
	addId(TEAM_SPECTATOR)
	addId(TEAM_SPEC)
	addId(TEAM_UNASSIGNED)
	local seenPly, names = {}, {}
	for i = 1, #ids do
		if team and type(team.GetPlayers) == "function" then
			local ok, got = pcall(team.GetPlayers, ids[i])
			if ok and type(got) == "table" then
				for j = 1, #got do
					local ply = got[j]
					if validEnt(ply) and not seenPly[ply] then
						seenPly[ply] = true
						local row = type(S.Row) == "function" and S.Row(ply) or nil
						local name = row and row.name or ""
						if name ~= "" then names[#names + 1] = name end
					end
				end
			end
		end
	end
	table.sort(names)
	return names
end

local function textWidth(font, text)
	if surface and surface.SetFont and surface.GetTextSize then
		surface.SetFont(font)
		local w = surface.GetTextSize(tostring(text))
		if type(w) == "number" and w >= 0 then return w end
	end
	return #tostring(text) * 8
end

local function clip(font, text, maxW)
	text = tostring(text or "")
	if maxW <= 8 then return "" end
	if textWidth(font, text) <= maxW then return text end
	local ell = "..."
	if textWidth(font, ell) > maxW then return "" end
	local lo, hi, best = 1, #text, ell
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		local piece = text:sub(1, mid) .. ell
		if textWidth(font, piece) <= maxW then
			best = piece
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return best
end

local function fill(x, y, w, h, col, radius)
	if w <= 0 or h <= 0 then return end
	if draw and draw.RoundedBox then
		draw.RoundedBox(radius or 0, x, y, w, h, col)
		return
	end
	if surface and surface.SetDrawColor and surface.DrawRect then
		surface.SetDrawColor(col.r or 255, col.g or 255, col.b or 255, col.a or 255)
		surface.DrawRect(x, y, w, h)
	end
end

local function screen()
	local sw = (ScrW and ScrW()) or 0
	local sh = (ScrH and ScrH()) or 0
	if sw <= 0 then sw = 1280 end
	if sh <= 0 then sh = 720 end
	return sw, sh
end

local function panelSize(sw, sh)
	local w = math.min(740, math.floor(sw * 0.52))
	local h = math.min(500, math.floor(sh * 0.58))
	if sw > 40 and w > sw - 24 then w = sw - 24 end
	if sh > 40 and h > sh - 24 then h = sh - 24 end
	if w < 320 then w = math.min(320, sw) end
	if h < 240 then h = math.min(240, sh) end
	return w, h
end

local function place(pnl)
	if not alivePanel(pnl) or type(pnl.SetSize) ~= "function" then return end
	local sw, sh = screen()
	local w, h = panelSize(sw, sh)
	pnl:SetSize(w, h)
	if type(pnl.SetPos) == "function" then
		pnl:SetPos(math.floor((sw - w) / 2), math.floor((sh - h) / 2))
	end
end

local LEFT = TEXT_ALIGN_LEFT or 0
local RIGHT = TEXT_ALIGN_RIGHT or 2
local TOP = TEXT_ALIGN_TOP or 3

local function paintText(text, font, x, y, col, ax)
	if not draw or type(draw.SimpleText) ~= "function" then return end
	draw.SimpleText(tostring(text), font, x, y, col, ax or LEFT, TOP)
end

local function paintScore(w, header)
	local left = tostring(header.scoreLeft or 0)
	local mid = " / "
	local right = tostring(header.scoreRight or 0)
	local good = type(S.TeamColor) == "function" and S.TeamColor(TEAM_GOOD or 1) or color(80, 140, 220)
	local bad = type(S.TeamColor) == "function" and S.TeamColor(TEAM_BAD or 2) or color(210, 70, 70)
	local lw = textWidth(FONT_SCORE, left)
	local mw = textWidth(FONT_SCORE, mid)
	local rw = textWidth(FONT_SCORE, right)
	local x = math.floor(w / 2 - (lw + mw + rw) / 2)
	paintText(left, FONT_SCORE, x, 34, good, LEFT)
	paintText(mid, FONT_SCORE, x + lw, 34, COL_TEXT, LEFT)
	paintText(right, FONT_SCORE, x + lw + mw, 34, bad, LEFT)
end

local function paintColumn(x, y, w, h, teamId, rows)
	local tint = type(S.TeamColor) == "function" and S.TeamColor(teamId) or COL_TEXT
	local wash = color(tint.r or 255, tint.g or 255, tint.b or 255, 36)
	fill(x, y, w, h, wash, 4)
	fill(x, y, w, 3, tint, 0)
	paintText(columnTitle(teamId), FONT_COL, x + 10, y + 8, tint, LEFT)
	-- Right-aligned stats, spaced so "Kills" / "Deaths" / "Ping" do not collide.
	local pingX = x + w - 8
	local deathsX = pingX - 64
	local killsX = deathsX - 56
	paintText("Kills", FONT_SPEC, killsX, y + 10, COL_MUTED, RIGHT)
	paintText("Deaths", FONT_SPEC, deathsX, y + 10, COL_MUTED, RIGHT)
	paintText("Ping", FONT_SPEC, pingX, y + 10, COL_MUTED, RIGHT)
	local rowY = y + 32
	local rowH = 20
	local maxRows = math.floor((h - 40) / rowH)
	if maxRows < 1 then maxRows = 1 end
	local shown = #rows
	if shown > maxRows then shown = maxRows end
	local nameW = killsX - (x + 10) - 8
	for i = 1, shown do
		local row = rows[i]
		local ink = (row.alive == false) and COL_DEAD or COL_TEXT
		local name = clip(FONT_ROW, row.name, nameW)
		paintText(name, FONT_ROW, x + 10, rowY, ink, LEFT)
		paintText(row.kills, FONT_ROW, killsX, rowY, ink, RIGHT)
		paintText(row.deaths, FONT_ROW, deathsX, rowY, ink, RIGHT)
		paintText(row.ping, FONT_ROW, pingX, rowY, ink, RIGHT)
		rowY = rowY + rowH
	end
end

local function paint(_, w, h)
	if not draw or type(draw.SimpleText) ~= "function" then return end
	fill(0, 0, w, h, COL_BG, 6)
	if surface and surface.SetDrawColor and surface.DrawOutlinedRect then
		surface.SetDrawColor(255, 255, 255, 28)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
	local header = headerNow()
	local title = header.roundLine or ""
	paintText(title, FONT_TITLE, math.floor(w / 2), 10, COL_TEXT, TEXT_ALIGN_CENTER or 1)
	paintScore(w, header)
	fill(16, 70, w - 32, 1, COL_LINE, 0)

	local specH = 28
	local top = 82
	local bodyH = h - top - specH - 10
	if bodyH < 40 then bodyH = 40 end
	local gap = 10
	local colW = math.floor((w - 32 - gap) / 2)
	paintColumn(16, top, colW, bodyH, TEAM_GOOD or 1, rowsFor(TEAM_GOOD or 1))
	paintColumn(16 + colW + gap, top, colW, bodyH, TEAM_BAD or 2, rowsFor(TEAM_BAD or 2))

	local line = "Spectators: —"
	if type(S.SpectatorLine) == "function" then line = S.SpectatorLine(specNames()) end
	line = clip(FONT_SPEC, line, w - 32)
	paintText(line, FONT_SPEC, 16, h - specH + 2, COL_SPEC, LEFT)
end

local function closeBoard()
	local pnl = panel
	panel = nil
	if alivePanel(pnl) and type(pnl.Remove) == "function" then
		pnl:Remove()
	elseif alivePanel(pnl) and type(pnl.SetVisible) == "function" then
		pnl:SetVisible(false)
	end
end

-- Popup layer so the board draws above the HUD, without taking keys or the mouse.
local function quiet(pnl)
	if type(pnl.MakePopup) == "function" then pnl:MakePopup() end
	if type(pnl.SetMouseInputEnabled) == "function" then pnl:SetMouseInputEnabled(false) end
	if type(pnl.SetKeyboardInputEnabled) == "function" then pnl:SetKeyboardInputEnabled(false) end
	if type(pnl.SetDrawOnTop) == "function" then pnl:SetDrawOnTop(true) end
end

local function openBoard()
	if editing() then return false end
	if alivePanel(panel) then
		place(panel)
		quiet(panel)
		if type(panel.SetVisible) == "function" then panel:SetVisible(true) end
		if type(panel.MoveToFront) == "function" then panel:MoveToFront() end
		return true
	end
	if not vgui or type(vgui.Create) ~= "function" then return false end
	local pnl = vgui.Create("DPanel")
	if not pnl then return false end
	panel = pnl
	if type(pnl.SetPaintBackground) == "function" then pnl:SetPaintBackground(false) end
	quiet(pnl)
	place(pnl)
	pnl.Paint = paint
	function pnl:Think()
		if editing() then
			closeBoard()
			return
		end
		place(self)
	end
	function pnl:OnRemove()
		if panel == self then panel = nil end
	end
	if type(pnl.SetVisible) == "function" then pnl:SetVisible(true) end
	if type(pnl.MoveToFront) == "function" then pnl:MoveToFront() end
	return true
end

function S.Show()
	buryDefault()
	if editing() then return false end
	return openBoard()
end

function S.Hide()
	closeBoard()
end

local function showHook()
	S.Show()
	return true
end

local function hideHook()
	S.Hide()
	return true
end

local function scoreBind(bind)
	if type(bind) ~= "string" then return false end
	bind = string.lower(bind)
	return bind == "+showscores" or bind == "showscores" or bind == "-showscores"
end

if hook and hook.Add then
	hook.Add("ScoreboardShow", "Ballistics_Scoreboard", showHook)
	hook.Add("ScoreboardHide", "Ballistics_Scoreboard", hideHook)
	hook.Add("PlayerBindPress", "Ballistics_Scoreboard", function(_, bind, pressed)
		if not scoreBind(bind) then return end
		if editing() or bind == "-showscores" or pressed == false then
			S.Hide()
		else
			S.Show()
		end
		return true
	end)
end

if GM then
	GM.ScoreboardShow = showHook
	GM.ScoreboardHide = hideHook
end
if GAMEMODE and GAMEMODE ~= GM then
	GAMEMODE.ScoreboardShow = showHook
	GAMEMODE.ScoreboardHide = hideHook
end
