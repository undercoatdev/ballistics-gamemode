-- Spawns tab: which flag the overhead editor will place, the firing squad box, and save.
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

local function fmtBox(box)
	if not box or not box.pos then return "not placed" end
	return string.format("%.0f, %.0f, %.0f   %.0f x %.0f   yaw %.0f", box.pos.x, box.pos.y, box.pos.z, box.sx or 0, box.sy or 0, box.yaw or 0)
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

	local boxLabel = vgui.Create("DLabel", parent)
	boxLabel:Dock(TOP)
	boxLabel:SetTall(20)
	boxLabel:SetText("Firing squad box")
	if boxLabel.SetTextColor then boxLabel:SetTextColor(Color(240, 200, 60)) end

	local hint = vgui.Create("DLabel", parent)
	hint:Dock(TOP)
	hint:SetTall(48)
	hint:SetWrap(true)
	hint:SetText("Edit spawns opens an overhead view. Pick Good, Bad, or Squad, click the ground, then Save. Arrows or shift+wheel rotate the box. Sliders resize it.")
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

	local squadBtn = vgui.Create("DButton", row)
	squadBtn:Dock(LEFT)
	squadBtn:SetWide(140)
	squadBtn:SetText("")
	squadBtn.Paint = function(self, w, h)
		local on = BALLISTICS.Spawns and BALLISTICS.Spawns.Side and BALLISTICS.Spawns.Side() == "box"
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
	squadBtn.DoClick = function()
		if BALLISTICS.Spawns and BALLISTICS.Spawns.SetSide then
			BALLISTICS.Spawns.SetSide("box")
		end
	end
	if squadBtn.SetTooltip then
		squadBtn:SetTooltip("Place the firing squad box from the overhead view.")
	end

	local mute = false
	local wangs = {}
	local function addSlider(title, key, minV, maxV, blurb)
		local line = vgui.Create("DPanel", parent)
		line:Dock(TOP)
		line:SetTall(28)
		line:DockMargin(0, 0, 0, 4)
		line.Paint = function(_, w, h)
			surface.SetDrawColor(32, 34, 40, 255)
			surface.DrawRect(0, 0, w, h)
		end
		if line.SetTooltip then line:SetTooltip(blurb) end
		local lab = vgui.Create("DLabel", line)
		lab:Dock(FILL)
		lab:DockMargin(8, 0, 8, 0)
		lab:SetText(title)
		if lab.SetTextColor then lab:SetTextColor(Color(230, 230, 230)) end
		if lab.SetTooltip then lab:SetTooltip(blurb) end
		local wang = vgui.Create("DNumberWang", line)
		wang:Dock(RIGHT)
		wang:SetWide(110)
		wang:DockMargin(0, 2, 4, 2)
		if wang.SetMin then wang:SetMin(minV) end
		if wang.SetMax then wang:SetMax(maxV) end
		if wang.SetDecimals then wang:SetDecimals(0) end
		if wang.SetTooltip then wang:SetTooltip(blurb) end
		local function push()
			if mute then return end
			if not (BALLISTICS.Spawns and BALLISTICS.Spawns.SetBoxDraft and BALLISTICS.Spawns.BoxDraft) then return end
			local draft = BALLISTICS.Spawns.BoxDraft()
			local val = wang.GetValue and wang:GetValue() or nil
			draft[key] = val
			BALLISTICS.Spawns.SetBoxDraft(draft.yaw, draft.sx, draft.sy, true)
		end
		wang.OnEnter = function() push() end
		local base = wang.OnLoseFocus
		wang.OnLoseFocus = function(self)
			if base then base(self) end
			push()
		end
		wangs[key] = wang
	end

	local data0 = BALLISTICS.SpawnData or {}
	local draft0 = { yaw = 0, sx = data0.BOX_LENGTH or 768, sy = data0.BOX_WIDTH or 384 }
	if BALLISTICS.Spawns and BALLISTICS.Spawns.BoxDraft then
		draft0 = BALLISTICS.Spawns.BoxDraft() or draft0
	end
	-- No number fields for box yaw / length / width (owner's call). The box
	-- keeps its stored size and rotation; placement stays in the editor.
	mute = true
	if wangs.yaw and wangs.yaw.SetValue then wangs.yaw:SetValue(draft0.yaw or 0) end
	if wangs.sx and wangs.sx.SetValue then wangs.sx:SetValue(draft0.sx or 768) end
	if wangs.sy and wangs.sy.SetValue then wangs.sy:SetValue(draft0.sy or 384) end
	mute = false

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
		boxLabel:SetText("Firing squad box: " .. fmtBox(snap.box))
		local draft = nil
		if snap.box then
			draft = { yaw = snap.box.yaw, sx = snap.box.sx, sy = snap.box.sy }
		elseif BALLISTICS.Spawns and BALLISTICS.Spawns.BoxDraft then
			draft = BALLISTICS.Spawns.BoxDraft()
		end
		if draft then
			mute = true
			local function applyWang(key)
				local wang = wangs[key]
				if not wang or not wang.SetValue then return end
				if wang.HasFocus and wang:HasFocus() then return end
				wang:SetValue(tonumber(draft[key]) or 0)
			end
			applyWang("yaw")
			applyWang("sx")
			applyWang("sy")
			mute = false
		end
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
