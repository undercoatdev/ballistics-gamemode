-- Spawns tab: which flag the overhead editor will place, and save.
-- Reset to defaults lives on the admin shell and calls Spawns.ConfirmReset.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Admin = BALLISTICS.Admin or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2

local function fmt(flag)
	if not flag or not flag.pos then return "not placed" end
	return string.format("%.0f, %.0f, %.0f", flag.pos.x, flag.pos.y, flag.pos.z)
end

local function paintSide(self, w, h)
	local on = BALLISTICS.Spawns and BALLISTICS.Spawns.Side and BALLISTICS.Spawns.Side() == self.balTeam
	local col = (BALLISTICS.TeamColor and BALLISTICS.TeamColor[self.balTeam]) or Color(180, 180, 180)
	if on then
		surface.SetDrawColor(col.r, col.g, col.b, 255)
	else
		surface.SetDrawColor(36, 36, 42, 255)
	end
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(col.r, col.g, col.b, 255)
	surface.DrawOutlinedRect(0, 0, w, h)
	local name = (BALLISTICS.TeamName and BALLISTICS.TeamName[self.balTeam]) or ""
	draw.SimpleText(name, "BallisticsSmall", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function BALLISTICS.Admin.BuildSpawns(parent)
	if not IsValid(parent) then return end
	parent:Clear()

	local mapLabel = vgui.Create("DLabel", parent)
	mapLabel:Dock(TOP)
	mapLabel:SetTall(20)
	mapLabel:SetText("Map")
	if mapLabel.SetTextColor then mapLabel:SetTextColor(Color(230, 230, 230)) end

	local status = vgui.Create("DLabel", parent)
	status:Dock(TOP)
	status:SetTall(20)
	status:SetText("")
	if status.SetTextColor then status:SetTextColor(Color(220, 210, 160)) end

	local ready = vgui.Create("DLabel", parent)
	ready:Dock(TOP)
	ready:SetTall(20)
	ready:SetText("")
	if ready.SetTextColor then ready:SetTextColor(Color(200, 200, 200)) end

	local goodLabel = vgui.Create("DLabel", parent)
	goodLabel:Dock(TOP)
	goodLabel:SetTall(20)
	goodLabel:SetText("Good")
	if goodLabel.SetTextColor then goodLabel:SetTextColor(Color(140, 180, 255)) end

	local badLabel = vgui.Create("DLabel", parent)
	badLabel:Dock(TOP)
	badLabel:SetTall(20)
	badLabel:SetText("Bad")
	if badLabel.SetTextColor then badLabel:SetTextColor(Color(255, 140, 140)) end

	local hint = vgui.Create("DLabel", parent)
	hint:Dock(TOP)
	hint:SetTall(36)
	hint:SetWrap(true)
	hint:SetText("Edit spawns opens an overhead view. Pick Good or Bad, click the ground, then Save.")
	if hint.SetTextColor then hint:SetTextColor(Color(180, 180, 180)) end

	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:SetTall(32)
	row:DockMargin(0, 8, 0, 8)
	row.Paint = function() end
	for _, teamId in ipairs({ GOOD, BAD }) do
		local btn = vgui.Create("DButton", row)
		btn:Dock(LEFT)
		btn:SetWide(140)
		btn:DockMargin(0, 0, 8, 0)
		btn:SetText("")
		btn.balTeam = teamId
		btn.Paint = paintSide
		btn.DoClick = function()
			if BALLISTICS.Spawns and BALLISTICS.Spawns.SetSide then
				BALLISTICS.Spawns.SetSide(teamId)
			end
		end
	end

	local edit = vgui.Create("DButton", parent)
	edit:Dock(TOP)
	edit:SetTall(32)
	edit:DockMargin(0, 4, 0, 4)
	edit:SetText("Edit spawns")
	edit.DoClick = function()
		if BALLISTICS.Spawns and BALLISTICS.Spawns.BeginEdit then
			BALLISTICS.Spawns.BeginEdit()
		end
	end

	local save = vgui.Create("DButton", parent)
	save:Dock(TOP)
	save:SetTall(32)
	save:SetText("Save")
	save.DoClick = function()
		if BALLISTICS.Spawns and BALLISTICS.Spawns.RequestSave then
			BALLISTICS.Spawns.RequestSave()
		end
	end

	local function refresh()
		if not IsValid(parent) then return end
		local snap = { map = "", source = "none", dirty = false }
		if BALLISTICS.Spawns and BALLISTICS.Spawns.Snapshot then
			snap = BALLISTICS.Spawns.Snapshot() or snap
		end
		mapLabel:SetText("Map: " .. ((snap.map ~= "" and snap.map) or "unknown"))
		local data = BALLISTICS.SpawnData
		if data and data.statusText then status:SetText(data.statusText(snap)) end
		if data and data.readiness then ready:SetText(data.readiness(snap)) end
		goodLabel:SetText("Good (blue): " .. fmt(snap.good))
		badLabel:SetText("Bad (red): " .. fmt(snap.bad))
	end

	refresh()
	if BALLISTICS.Spawns and BALLISTICS.Spawns.Listen then
		BALLISTICS.Spawns.Listen(refresh)
	end
end

if BALLISTICS.Admin.Register then
	BALLISTICS.Admin.Register("spawns", function(parent)
		BALLISTICS.Admin.BuildSpawns(parent)
	end)
end
