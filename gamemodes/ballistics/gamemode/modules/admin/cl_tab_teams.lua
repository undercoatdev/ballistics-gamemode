-- Teams tab: drag a player onto a slot, or select one and click the slot.
-- Kick sends bal_admin_assign with slot 0 (spectator). The server swaps when
-- the target slot is already occupied.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Admin = BALLISTICS.Admin or {}

local GOOD = BALLISTICS.TEAM_GOOD or 1
local BAD = BALLISTICS.TEAM_BAD or 2

local function viewNow()
	if BALLISTICS.Lobby and BALLISTICS.Lobby.View then return BALLISTICS.Lobby.View() end
	return nil
end

local function rosterKey(view)
	if not view then return "" end
	local parts = {}
	local roster = view.roster or {}
	for i = 1, #roster do
		local row = roster[i]
		parts[i] = table.concat({
			tostring(row.id),
			tostring(row.name),
			tostring(row.team),
			tostring(row.slot),
			tostring(row.queueTeam),
			tostring(row.queueSlot),
		}, ":")
	end
	return table.concat(parts, "|")
end

local function paintRow(w, h, entry, selected, dragging)
	local bg = Color(32, 34, 40, 255)
	if selected then bg = Color(58, 72, 98, 255) end
	if dragging then bg = Color(80, 90, 40, 255) end
	surface.SetDrawColor(bg.r, bg.g, bg.b, bg.a)
	surface.DrawRect(0, 0, w, h)
	local name = (entry and entry.name) or ""
	draw.SimpleText(name, "BallisticsSlot", 8, h / 2, Color(240, 240, 240), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	local place = "Spectator"
	if BALLISTICS.LobbyView and BALLISTICS.LobbyView.PlaceText then
		place = BALLISTICS.LobbyView.PlaceText(entry)
	end
	draw.SimpleText(place, "BallisticsSmall", w - 8, h / 2, Color(190, 190, 190), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

function BALLISTICS.Admin.BuildTeams(parent)
	if not IsValid(parent) then return end
	parent:Clear()

	local holder = { view = viewNow(), selected = nil, key = "", drag = nil }
	local slotButtons = { [GOOD] = {}, [BAD] = {} }
	local headerLabels = {}
	local scroll
	local grid
	local specZone
	local kick
	local status
	local ghost
	local listening = false

	local function setStatus(text)
		if IsValid(status) then status:SetText(text or "") end
	end

	local function applySelection()
		if IsValid(kick) then kick:SetEnabled(holder.selected ~= nil) end
	end

	local function panelRect(pnl)
		if not IsValid(pnl) then return nil end
		local x, y = pnl:LocalToScreen(0, 0)
		local w, h = pnl:GetSize()
		return { x = x, y = y, w = w, h = h }
	end

	local function hitAt(x, y)
		local rects = {}
		for _, teamId in ipairs({ GOOD, BAD }) do
			local col = slotButtons[teamId]
			for slot = 1, #col do
				local rect = panelRect(col[slot])
				if rect then
					rect.kind = "slot"
					rect.team = teamId
					rect.slot = slot
					rects[#rects + 1] = rect
				end
			end
		end
		local zone = panelRect(specZone)
		if zone then
			zone.kind = "spectator"
			rects[#rects + 1] = zone
		end
		if not (BALLISTICS.LobbyView and BALLISTICS.LobbyView.Hit) then return nil end
		return BALLISTICS.LobbyView.Hit(rects, x, y)
	end

	local function stopGhost()
		if IsValid(ghost) then ghost:SetVisible(false) end
		holder.drag = nil
	end

	local function finishDrag(x, y)
		local drag = holder.drag
		stopGhost()
		if not drag then return end
		local moved = math.abs((x or 0) - drag.sx) > 8 or math.abs((y or 0) - drag.sy) > 8
		holder.selected = drag.id
		applySelection()
		if not moved then return end
		local hit = hitAt(x, y)
		if not hit or not (BALLISTICS.Lobby and BALLISTICS.Lobby.RequestAssign) then return end
		local decision
		if hit.kind == "slot" then
			decision = BALLISTICS.Lobby.RequestAssign(drag.id, hit.team, hit.slot)
		elseif hit.kind == "spectator" then
			decision = BALLISTICS.Lobby.RequestAssign(drag.id, 0, 0)
		end
		if not decision then return end
		if decision.action == "kick" then
			setStatus("Moved to spectator.")
		elseif decision.action == "assign" then
			setStatus("Assigned.")
		else
			local text = ""
			if BALLISTICS.LobbyView and BALLISTICS.LobbyView.ReasonText then
				text = BALLISTICS.LobbyView.ReasonText(decision.reason)
			end
			setStatus(text)
		end
	end

	local function ensureGhost()
		if IsValid(ghost) then return ghost end
		if not vgui or not vgui.Create then return nil end
		ghost = vgui.Create("DLabel")
		ghost:SetFont("BallisticsSlot")
		ghost:SetText("")
		ghost:SetSize(180, 28)
		ghost:SetVisible(false)
		ghost:SetZPos(32767)
		ghost:SetMouseInputEnabled(false)
		if ghost.SetTextColor then ghost:SetTextColor(Color(255, 255, 255)) end
		ghost.Paint = function(self, w, h)
			surface.SetDrawColor(20, 20, 24, 230)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(220, 170, 60, 255)
			surface.DrawOutlinedRect(0, 0, w, h)
			local text = ""
			if self.GetText then text = self:GetText() or "" end
			draw.SimpleText(text, "BallisticsSlot", 8, h / 2, Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		function ghost:Think()
			local drag = holder.drag
			if not drag then
				self:SetVisible(false)
				return
			end
			local x = (gui and gui.MouseX and gui.MouseX()) or 0
			local y = (gui and gui.MouseY and gui.MouseY()) or 0
			self:SetPos(x + 14, y + 10)
			if not input or not input.IsMouseDown or not MOUSE_LEFT then return end
			if input.IsMouseDown(MOUSE_LEFT) then
				drag.held = true
			elseif drag.held then
				finishDrag(x, y)
			end
		end
		return ghost
	end

	local function assignSelected(teamId, slot)
		if not holder.selected then
			setStatus("Select a player, then click a slot.")
			return
		end
		if not (BALLISTICS.Lobby and BALLISTICS.Lobby.RequestAssign) then return end
		local decision = BALLISTICS.Lobby.RequestAssign(holder.selected, teamId, slot)
		if decision.action == "kick" then
			setStatus("Moved to spectator.")
		elseif decision.action == "assign" then
			setStatus("Assigned.")
		else
			local text = ""
			if BALLISTICS.LobbyView and BALLISTICS.LobbyView.ReasonText then
				text = BALLISTICS.LobbyView.ReasonText(decision.reason)
			end
			setStatus(text)
		end
	end

	local function rebuildRows()
		if not IsValid(scroll) then return end
		scroll:Clear()
		local view = holder.view
		local roster = (view and view.roster) or {}
		local canvas = scroll
		if scroll.GetCanvas then canvas = scroll:GetCanvas() or scroll end
		for i = 1, #roster do
			local entry = roster[i]
			local row = vgui.Create("DButton", canvas)
			row:SetText("")
			row:SetTall(32)
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, 4)
			row.Paint = function(_, w, h)
				local drag = holder.drag
				paintRow(w, h, entry, holder.selected == entry.id, drag and drag.id == entry.id)
			end
			function row:OnMousePressed(code)
				if code ~= MOUSE_LEFT then return end
				self:MouseCapture(true)
				local x = (gui and gui.MouseX and gui.MouseX()) or 0
				local y = (gui and gui.MouseY and gui.MouseY()) or 0
				holder.selected = entry.id
				applySelection()
				holder.drag = { id = entry.id, name = entry.name, sx = x, sy = y }
				local label = ensureGhost()
				if IsValid(label) then
					label:SetText(entry.name or "")
					label:SetVisible(true)
					label:MoveToFront()
				end
			end
			function row:OnMouseReleased(code)
				if code ~= MOUSE_LEFT then return end
				self:MouseCapture(false)
				local x = (gui and gui.MouseX and gui.MouseX()) or 0
				local y = (gui and gui.MouseY and gui.MouseY()) or 0
				finishDrag(x, y)
			end
		end
		holder.key = rosterKey(view)
	end

	local function ensureSlotButtons(per)
		if not IsValid(grid) then return end
		for _, teamId in ipairs({ GOOD, BAD }) do
			slotButtons[teamId] = slotButtons[teamId] or {}
			local col = slotButtons[teamId]
			for slot = 1, per do
				if not IsValid(col[slot]) then
					local btn = vgui.Create("DButton", grid)
					btn:SetText("")
					btn.DoClick = function()
						assignSelected(teamId, slot)
					end
					btn.Paint = function(_, w, h)
						local info = { team = teamId, slot = slot, empty = true, label = "Empty" }
						local view = holder.view
						if view then
							local columns = view.columns or {}
							for c = 1, #columns do
								if columns[c].team == teamId and columns[c].slots[slot] then
									info = columns[c].slots[slot]
								end
							end
						end
						if BALLISTICS.Lobby and BALLISTICS.Lobby.PaintSlot then
							BALLISTICS.Lobby.PaintSlot(w, h, info)
						end
					end
					col[slot] = btn
				end
			end
			for slot = per + 1, 16 do
				if IsValid(col[slot]) then col[slot]:Remove() end
				col[slot] = nil
			end
			if not IsValid(headerLabels[teamId]) then
				local header = vgui.Create("DPanel", grid)
				header.Paint = function(self, w, h)
					local r, g, b = 180, 180, 180
					if BALLISTICS.Lobby and BALLISTICS.Lobby.TeamColor then
						r, g, b = BALLISTICS.Lobby.TeamColor(teamId)
					end
					surface.SetDrawColor(r, g, b, 255)
					surface.DrawRect(0, 0, w, h)
					draw.SimpleText(self.balText or "", "BallisticsSmall", w / 2, h / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
				headerLabels[teamId] = header
			end
		end
	end

	local function positionGrid()
		if not IsValid(grid) then return end
		local w, h = grid:GetSize()
		if w < 40 or h < 40 then return end
		local view = holder.view
		local per = (view and view.perTeam) or 5
		local layout = BALLISTICS.LobbyView.Layout({
			width = w,
			height = h,
			perTeam = per,
			showStart = false,
			margin = 8,
			statusH = 0,
		})
		for i = 1, #layout.columns do
			local col = layout.columns[i]
			local header = headerLabels[col.team]
			if IsValid(header) then
				header:SetPos(col.x, col.y)
				header:SetSize(col.w, col.h)
				local title = col.title or ""
				local count = 0
				if view then
					local columns = view.columns or {}
					for c = 1, #columns do
						if columns[c].team == col.team then
							title = columns[c].title or title
							count = columns[c].count or 0
						end
					end
				end
				header.balText = string.upper(title) .. "  " .. tostring(count) .. "/" .. tostring(per)
			end
			for s = 1, #col.slots do
				local rect = col.slots[s]
				local btn = slotButtons[col.team] and slotButtons[col.team][s]
				if IsValid(btn) then
					btn:SetPos(rect.x, rect.y)
					btn:SetSize(rect.w, rect.h)
				end
			end
		end
	end

	local function refresh()
		if not IsValid(parent) then return end
		holder.view = viewNow()
		local per = (holder.view and holder.view.perTeam) or 5
		ensureSlotButtons(per)
		local key = rosterKey(holder.view)
		if key ~= holder.key then rebuildRows() end
		applySelection()
		positionGrid()
	end

	local hint = vgui.Create("DLabel", parent)
	hint:Dock(TOP)
	hint:SetTall(22)
	hint:SetText("Drag a player onto a slot, or select one and click a slot.")
	if hint.SetTextColor then hint:SetTextColor(Color(200, 200, 200)) end

	status = vgui.Create("DLabel", parent)
	status:Dock(BOTTOM)
	status:SetTall(22)
	status:SetText("")
	if status.SetTextColor then status:SetTextColor(Color(230, 220, 170)) end

	local left = vgui.Create("DPanel", parent)
	left:Dock(LEFT)
	left:SetWide(250)
	left:DockMargin(0, 6, 8, 0)
	left.Paint = function() end

	specZone = vgui.Create("DPanel", left)
	specZone:Dock(BOTTOM)
	specZone:SetTall(64)
	specZone:DockPadding(6, 6, 6, 6)
	specZone.Paint = function(_, w, h)
		local hot = holder.drag ~= nil
		if hot then
			surface.SetDrawColor(90, 90, 96, 255)
		else
			surface.SetDrawColor(40, 40, 46, 255)
		end
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(160, 160, 160, 255)
		surface.DrawOutlinedRect(0, 0, w, h)
	end

	kick = vgui.Create("DButton", specZone)
	kick:Dock(FILL)
	kick:SetText("Kick to spectator")
	kick:SetEnabled(false)
	kick.DoClick = function()
		assignSelected(0, 0)
	end

	scroll = vgui.Create("DScrollPanel", left)
	scroll:Dock(FILL)

	grid = vgui.Create("DPanel", parent)
	grid:Dock(FILL)
	grid.Paint = function() end
	function grid:PerformLayout()
		positionGrid()
	end

	function parent:OnRemove()
		stopGhost()
		if IsValid(ghost) then ghost:Remove() end
	end

	refresh()
	local tries = 0
	local function later()
		if not IsValid(grid) then return end
		positionGrid()
		tries = tries + 1
		if grid:GetWide() < 40 and tries < 8 then
			timer.Simple(0.1, later)
		end
	end
	timer.Simple(0, later)

	if not listening and BALLISTICS.Lobby and BALLISTICS.Lobby.Listen then
		listening = true
		BALLISTICS.Lobby.Listen(function()
			if IsValid(parent) then refresh() end
		end)
	end
end

if BALLISTICS.Admin.Register then
	BALLISTICS.Admin.Register("teams", function(parent)
		BALLISTICS.Admin.BuildTeams(parent)
	end)
end
