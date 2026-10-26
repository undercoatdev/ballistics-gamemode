-- Lobby slot view model and layout. No GMod calls: luajit builds the same
-- model the panels paint. Players stay out of here; callers pass string ids.

BALLISTICS = BALLISTICS or {}
BALLISTICS.LobbyView = BALLISTICS.LobbyView or {}

local GOOD = (BALLISTICS.TEAM_GOOD) or 1
local BAD = (BALLISTICS.TEAM_BAD) or 2
local SPEC = (BALLISTICS.TEAM_SPEC) or 1002

local PHASE_LOBBY = "lobby"
local PHASE_LIVE = "live"
local PHASE_POST = "post"

-- Wire names. bal_match_start is the admin Start button. Kick sends slot 0
-- because TEAM_SPEC (1002) does not fit in bal_admin_assign's uint8 team.
function BALLISTICS.LobbyView.Messages()
	return {
		take = "bal_slot_take",
		assign = "bal_admin_assign",
		start = "bal_match_start",
		ready = "bal_lobby_ready",
		slots = "bal_slots_sync",
		round = "bal_round_sync",
		config = "bal_config_set",
	}
end

local function clampPer(n)
	n = math.floor(tonumber(n) or 5)
	if n < 1 then n = 1 end
	if n > 16 then n = 16 end
	return n
end

local function teamTitle(teamId)
	local names = BALLISTICS.TeamName
	if names and names[teamId] then return names[teamId] end
	if teamId == GOOD then return "Good" end
	if teamId == BAD then return "Bad" end
	return "Spectator"
end

local function entryOf(column, slot)
	if type(column) ~= "table" then return nil end
	local entry = column[slot]
	if type(entry) == "string" then
		if entry == "" then return nil end
		return { id = entry, name = entry }
	end
	if type(entry) == "table" and type(entry.id) == "string" and entry.id ~= "" then
		return entry
	end
	return nil
end

function BALLISTICS.LobbyView.ReasonText(reason, minPer)
	if reason == nil or reason == "" or reason == "mine" then return "" end
	if reason == "taken" then return "That slot is taken." end
	if reason == "alive" then return "You cannot switch while you are alive." end
	if reason == "min players" then
		local n = math.floor(tonumber(minPer) or 1)
		if n < 0 then n = 0 end
		if n == 1 then return "Need at least 1 player on each team." end
		return "Need at least " .. tostring(n) .. " players on each team."
	end
	if reason == "not lobby" then return "The match is already running." end
	if reason == "flags" then return "Both flags must be placed before the match can start." end
	if reason == "box" then return "Place the firing squad box in Admin > Spawns" end
	if reason == "admin" then return "Only an admin can start the match." end
	if reason == "queue" or reason == "queued" then return "You will move next round." end
	if reason == "player" then return "Pick a player first." end
	if reason == "team" then return "That team is not available." end
	if reason == "slot" then return "That slot is not available." end
	return ""
end

function BALLISTICS.LobbyView.PlaceText(entry)
	if type(entry) ~= "table" then return "Spectator" end
	if entry.assigned and entry.team and entry.slot then
		return teamTitle(entry.team) .. " " .. tostring(entry.slot)
	end
	if entry.queueTeam and entry.queueSlot then
		return "Spectator, next " .. teamTitle(entry.queueTeam) .. " " .. tostring(entry.queueSlot)
	end
	return "Spectator"
end

local function findColumn(view, teamId)
	local columns = view and view.columns or {}
	for i = 1, #columns do
		if columns[i].team == teamId then return columns[i] end
	end
	return nil
end

function BALLISTICS.LobbyView.Build(input)
	input = input or {}
	local per = clampPer(input.perTeam)
	local sides = input.sides or {}
	local queue = input.queue or {}
	local names = input.names or {}
	local localId = input.localId
	local phase = input.phase or PHASE_LOBBY
	local isAdmin = input.isAdmin == true
	local minPer = math.floor(tonumber(input.minPerTeam) or 1)
	if minPer < 0 then minPer = 0 end
	local alive = input.alive == true

	local known = {}
	for id, name in pairs(names) do
		if type(id) == "string" and type(name) == "string" and name ~= "" then
			known[id] = name
		end
	end

	local queuedById = {}
	local queuedAt = {}
	for i = 1, #queue do
		local q = queue[i]
		if type(q) == "table" and type(q.id) == "string" and q.id ~= "" then
			local teamId = tonumber(q.team)
			local slot = tonumber(q.slot)
			if teamId and slot then
				queuedById[q.id] = { team = teamId, slot = slot }
				local key = tostring(teamId) .. ":" .. tostring(slot)
				local bucket = queuedAt[key]
				if not bucket then
					bucket = {}
					queuedAt[key] = bucket
				end
				bucket[#bucket + 1] = known[q.id] or q.id
			end
		end
	end

	local counts = {}
	counts[GOOD] = 0
	counts[BAD] = 0
	local columns = {}
	local mine = nil
	local seen = {}
	local roster = {}

	for _, teamId in ipairs({ GOOD, BAD }) do
		local slots = {}
		local column = sides[teamId]
		for slot = 1, per do
			local entry = entryOf(column, slot)
			local empty = entry == nil
			-- `cond and nil or x` is not a ternary: nil is false, so it would read x.
			local id = nil
			if entry then id = entry.id end
			local name = ""
			if id then
				name = known[id] or entry.name or id
				if type(name) ~= "string" or name == "" then name = id end
				counts[teamId] = counts[teamId] + 1
				if id == localId then mine = { team = teamId, slot = slot } end
				if not seen[id] then
					seen[id] = true
					local q = queuedById[id]
					roster[#roster + 1] = {
						id = id,
						name = name,
						team = teamId,
						slot = slot,
						assigned = true,
						queueTeam = q and q.team or nil,
						queueSlot = q and q.slot or nil,
					}
				end
			end
			local qnames = queuedAt[tostring(teamId) .. ":" .. tostring(slot)]
			local label
			if empty then
				if qnames and qnames[1] then
					if #qnames == 1 then
						label = "Next: " .. qnames[1]
					else
						label = "Next: " .. qnames[1] .. " +" .. tostring(#qnames - 1)
					end
				else
					label = "Empty"
				end
			else
				label = name
				if id == localId then label = name .. " (you)" end
				if qnames and qnames[1] then label = label .. " · next" end
			end
			slots[slot] = {
				team = teamId,
				slot = slot,
				empty = empty,
				id = id,
				name = name,
				mine = id ~= nil and id == localId,
				label = label,
				queued = qnames ~= nil,
				queueNames = qnames or {},
			}
		end
		columns[#columns + 1] = {
			team = teamId,
			title = teamTitle(teamId),
			count = counts[teamId],
			slots = slots,
		}
	end

	local players = input.players or {}
	for i = 1, #players do
		local p = players[i]
		if type(p) == "table" and type(p.id) == "string" and p.id ~= "" and not seen[p.id] then
			seen[p.id] = true
			local name = known[p.id] or p.name or p.id
			if type(name) ~= "string" or name == "" then name = p.id end
			local q = queuedById[p.id]
			roster[#roster + 1] = {
				id = p.id,
				name = name,
				team = nil,
				slot = nil,
				assigned = false,
				queueTeam = q and q.team or nil,
				queueSlot = q and q.slot or nil,
			}
		end
	end

	table.sort(roster, function(a, b)
		if a.name == b.name then return tostring(a.id) < tostring(b.id) end
		return tostring(a.name) < tostring(b.name)
	end)

	local unassigned = {}
	for i = 1, #roster do
		if not roster[i].assigned then unassigned[#unassigned + 1] = roster[i] end
	end

	local localQueue = nil
	if type(localId) == "string" then localQueue = queuedById[localId] end

	local start = {
		visible = false,
		enabled = false,
		waiting = false,
		label = "Start",
		reason = nil,
	}
	if phase ~= PHASE_LOBBY then
		if isAdmin then
			start.visible = true
			start.enabled = false
			start.reason = "not lobby"
		end
	elseif not isAdmin then
		start.waiting = true
		start.label = "Waiting for admin"
	else
		start.visible = true
		start.label = "Start"
		if counts[GOOD] < minPer or counts[BAD] < minPer then
			start.enabled = false
			start.reason = "min players"
		elseif input.flags == false then
			start.enabled = false
			start.reason = "flags"
		elseif input.box == false then
			start.enabled = false
			start.reason = "box"
		else
			start.enabled = true
		end
	end

	local moveNotice = nil
	if localQueue then
		moveNotice = "Moving to " .. teamTitle(localQueue.team) .. " slot " .. tostring(localQueue.slot) .. " next round."
	end

	return {
		perTeam = per,
		phase = phase,
		showCountdown = false,
		columns = columns,
		mine = mine,
		localQueue = localQueue,
		moveNotice = moveNotice,
		start = start,
		roster = roster,
		unassigned = unassigned,
		counts = { good = counts[GOOD], bad = counts[BAD] },
		minPerTeam = minPer,
		alive = alive,
	}
end

function BALLISTICS.LobbyView.Click(view, teamId, slot, input)
	input = input or {}
	view = view or {}
	teamId = tonumber(teamId)
	slot = tonumber(slot)
	local column = findColumn(view, teamId)
	local found = column and slot and column.slots[slot] or nil
	if not found then return { action = "refuse", reason = "slot" } end
	if found.mine then return { action = "noop", reason = "mine" } end
	if not found.empty then return { action = "refuse", reason = "taken" } end
	local queued = view.localQueue
	if queued and queued.team == teamId and queued.slot == slot then
		return { action = "noop", reason = "queued" }
	end
	local phase = input.phase or view.phase or PHASE_LOBBY
	local alive = input.alive
	if alive == nil then alive = view.alive == true end
	if (phase == PHASE_LIVE or phase == PHASE_POST or phase == "squad") and alive then
		return { action = "refuse", reason = "alive" }
	end
	if phase == PHASE_LIVE or phase == PHASE_POST or phase == "squad" then
		return { action = "queue", team = teamId, slot = slot }
	end
	return { action = "take", team = teamId, slot = slot }
end

-- Admin assign. An occupied slot is allowed: the server swaps or drops the
-- occupant. slot 0, team 0, or TEAM_SPEC kicks to spectator on the wire as 0,0.
function BALLISTICS.LobbyView.Assign(id, teamId, slot, perTeam)
	if type(id) ~= "string" or id == "" then
		return { action = "refuse", reason = "player" }
	end
	teamId = tonumber(teamId)
	slot = tonumber(slot)
	if slot == 0 or teamId == 0 or teamId == SPEC then
		return { action = "kick", id = id, team = 0, slot = 0 }
	end
	if teamId ~= GOOD and teamId ~= BAD then
		return { action = "refuse", reason = "team" }
	end
	local per = clampPer(perTeam)
	if not slot or slot ~= math.floor(slot) or slot < 1 or slot > per then
		return { action = "refuse", reason = "slot" }
	end
	return { action = "assign", id = id, team = teamId, slot = slot }
end

local function metrics(spec)
	spec = spec or {}
	local per = clampPer(spec.perTeam)
	local margin = spec.margin or 16
	local gap = spec.gap or 8
	local colGap = spec.colGap or 20
	local headerH = spec.headerH or 26
	local slotGap = spec.slotGap or 6
	local slotH = spec.slotH or 40
	local statusH = spec.statusH
	if statusH == nil then statusH = 20 end
	local showStart = spec.showStart ~= false
	local footerH = spec.footerH
	if footerH == nil then footerH = showStart and 44 or 0 end
	if not showStart then footerH = 0 end
	local width = spec.width or 680
	if width < 80 then width = 80 end
	local slotsBlock = per * slotH + math.max(per - 1, 0) * slotGap
	local height = spec.height
	if height == nil then
		height = margin + headerH + gap + slotsBlock + gap + statusH + margin
		if footerH > 0 then height = height + gap + footerH end
	end
	return {
		per = per,
		margin = margin,
		gap = gap,
		colGap = colGap,
		headerH = headerH,
		slotGap = slotGap,
		slotH = slotH,
		statusH = statusH,
		footerH = footerH,
		width = width,
		height = height,
	}
end

function BALLISTICS.LobbyView.Layout(spec)
	local m = metrics(spec)
	local width = m.width
	local height = m.height
	local slotsTop = m.margin + m.headerH + m.gap
	local footerY = nil
	local statusY
	if m.footerH > 0 then
		footerY = height - m.margin - m.footerH
		statusY = footerY - m.gap - m.statusH
	else
		statusY = height - m.margin - m.statusH
	end
	local slotsBottom = statusY - m.gap
	local avail = slotsBottom - slotsTop
	local slotH = math.floor((avail - m.slotGap * math.max(m.per - 1, 0)) / m.per)
	if slotH < 1 then slotH = 1 end

	local innerW = width - m.margin * 2 - m.colGap
	local colW = math.floor(innerW / 2)
	if colW < 1 then colW = 1 end
	local origins = { m.margin, m.margin + colW + m.colGap }
	local teamIds = { GOOD, BAD }
	local columns = {}
	for i = 1, 2 do
		local x = origins[i]
		local slots = {}
		for s = 1, m.per do
			slots[s] = {
				team = teamIds[i],
				slot = s,
				x = x,
				y = slotsTop + (s - 1) * (slotH + m.slotGap),
				w = colW,
				h = slotH,
			}
		end
		columns[i] = {
			team = teamIds[i],
			title = teamTitle(teamIds[i]),
			x = x,
			y = m.margin,
			w = colW,
			h = m.headerH,
			slots = slots,
		}
	end

	local start = nil
	if m.footerH > 0 and footerY then
		local startW = math.min(200, math.max(120, colW))
		if startW > width - m.margin * 2 then startW = width - m.margin * 2 end
		if startW < 1 then startW = 1 end
		start = {
			x = math.floor((width - startW) / 2),
			y = footerY,
			w = startW,
			h = m.footerH,
		}
	end

	return {
		width = width,
		height = height,
		perTeam = m.per,
		slotH = slotH,
		columns = columns,
		start = start,
		status = {
			x = m.margin,
			y = statusY,
			w = math.max(1, width - m.margin * 2),
			h = m.statusH,
		},
	}
end

function BALLISTICS.LobbyView.PreferredSize(perTeam, spec)
	spec = spec or {}
	local layout = BALLISTICS.LobbyView.Layout({
		perTeam = perTeam,
		width = spec.width,
		slotH = spec.slotH,
		showStart = spec.showStart,
		margin = spec.margin,
		statusH = spec.statusH,
	})
	return layout.width, layout.height
end

function BALLISTICS.LobbyView.Targets(layout)
	local list = {}
	if type(layout) ~= "table" then return list end
	local columns = layout.columns or {}
	for i = 1, #columns do
		local slots = columns[i].slots or {}
		for s = 1, #slots do
			local r = slots[s]
			list[#list + 1] = {
				kind = "slot",
				team = r.team,
				slot = r.slot,
				x = r.x,
				y = r.y,
				w = r.w,
				h = r.h,
			}
		end
	end
	if layout.start then
		local r = layout.start
		list[#list + 1] = { kind = "start", x = r.x, y = r.y, w = r.w, h = r.h }
	end
	return list
end

-- First matching rect wins, so callers list slots before larger zones.
function BALLISTICS.LobbyView.Hit(rects, x, y)
	if type(rects) ~= "table" then return nil end
	x = tonumber(x)
	y = tonumber(y)
	if not x or not y then return nil end
	for i = 1, #rects do
		local r = rects[i]
		if type(r) == "table" and r.w and r.h and r.x and r.y then
			if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h then
				return { kind = r.kind, team = r.team, slot = r.slot }
			end
		end
	end
	return nil
end

-- TEAMS toggle (top right, left of ADMIN). Every player sees it, lobby only.
BALLISTICS.LobbyView.TEAMS_W = 84
BALLISTICS.LobbyView.TEAMS_H = 26
BALLISTICS.LobbyView.TOP_GAP = 6

function BALLISTICS.LobbyView.TeamsButtonVisible(phase)
	return phase == nil or phase == "lobby"
end

-- x of the TEAMS button: left of ADMIN when ADMIN is shown, else in its place.
function BALLISTICS.LobbyView.TeamsButtonX(screenW, adminShown)
	local w = BALLISTICS.LobbyView.TEAMS_W
	local sw = tonumber(screenW) or 0
	local x = sw - w - 10
	if adminShown then x = x - w - BALLISTICS.LobbyView.TOP_GAP end
	if x < 0 then x = 0 end
	return x
end

-- Start checklist under the slots: Good flag, Bad flag, Firing squad box.
-- snap is the networked spawns snapshot; data is BALLISTICS.SpawnData.
function BALLISTICS.LobbyView.Checklist(snap, data)
	local function flagOk(flag)
		return type(flag) == "table" and type(flag.pos) == "table"
			and type(flag.pos.x) == "number" and type(flag.pos.y) == "number" and type(flag.pos.z) == "number"
	end
	snap = type(snap) == "table" and snap or {}
	local box = false
	if type(data) == "table" and type(data.hasBox) == "function" then
		box = data.hasBox(snap) == true
	end
	return {
		{ key = "good", label = "Good flag", ok = flagOk(snap.good) },
		{ key = "bad", label = "Bad flag", ok = flagOk(snap.bad) },
		{ key = "box", label = "Firing squad box", ok = box },
	}
end

function BALLISTICS.LobbyView.ChecklistReady(list)
	for i = 1, #(list or {}) do
		if not list[i].ok then return false end
	end
	return true
end

