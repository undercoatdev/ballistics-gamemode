-- Slot table: take, switch, leave, queue across LIVE, admin assign.
-- Pure rules live on BALLISTICS.SlotTable so luajit can construct a table
-- with no GMod. BALLISTICS.Slots is the server singleton.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2
local SPEC = TEAM_SPEC or 1002

local SlotTable = {}
SlotTable.__index = SlotTable

function SlotTable.new(perTeam)
	local per = 5
	local fn = nil
	if type(perTeam) == "function" then
		fn = perTeam
	elseif tonumber(perTeam) then
		per = math.floor(tonumber(perTeam))
	end
	return setmetatable({
		perTeam = per,
		perTeamFn = fn,
		grid = { [GOOD] = {}, [BAD] = {} },
		where = {},
		queued = {},
	}, SlotTable)
end

function SlotTable:Limit()
	local n = self.perTeam
	if self.perTeamFn then n = self.perTeamFn() end
	n = math.floor(tonumber(n) or 5)
	if n < 1 then n = 1 end
	if n > 16 then n = 16 end
	return n
end

function SlotTable:_trim()
	local n = self:Limit()
	for _, teamId in ipairs({ GOOD, BAD }) do
		local grid = self.grid[teamId]
		local drop = {}
		for slot in pairs(grid) do
			if type(slot) ~= "number" or slot < 1 or slot > n then
				drop[#drop + 1] = slot
			end
		end
		for i = 1, #drop do
			local slot = drop[i]
			local id = grid[slot]
			grid[slot] = nil
			local where = id and self.where[id]
			if where and where.team == teamId and where.slot == slot then
				self.where[id] = nil
			end
		end
	end
end

function SlotTable:_valid(id, teamId, slot)
	if id == nil or id == "" then return false, "player" end
	if teamId ~= GOOD and teamId ~= BAD then return false, "team" end
	slot = tonumber(slot)
	if not slot or slot ~= math.floor(slot) then return false, "slot" end
	if slot < 1 or slot > self:Limit() then return false, "slot" end
	return true, slot
end

function SlotTable:_unset(id)
	local where = self.where[id]
	if not where then return end
	local grid = self.grid[where.team]
	if grid and grid[where.slot] == id then grid[where.slot] = nil end
	self.where[id] = nil
end

function SlotTable:_set(id, teamId, slot)
	self:_unset(id)
	self.grid[teamId][slot] = id
	self.where[id] = { team = teamId, slot = slot }
	self.queued[id] = nil
end

function SlotTable:TeamOf(id)
	if id == nil then return nil end
	self:_trim()
	local where = self.where[tostring(id)]
	if not where then return nil end
	return where.team, where.slot
end

function SlotTable:Queued(id)
	if id == nil then return nil end
	local req = self.queued[tostring(id)]
	if not req then return nil end
	return req.team, req.slot
end

function SlotTable:Count(teamId)
	self:_trim()
	local grid = self.grid[teamId]
	if not grid then return 0 end
	local n = 0
	local limit = self:Limit()
	for slot = 1, limit do
		if grid[slot] ~= nil then n = n + 1 end
	end
	return n
end

function SlotTable:Members(teamId)
	self:_trim()
	local list = {}
	local grid = self.grid[teamId]
	if not grid then return list end
	local limit = self:Limit()
	for slot = 1, limit do
		if grid[slot] ~= nil then list[#list + 1] = grid[slot] end
	end
	return list
end

function SlotTable:Occupant(teamId, slot)
	self:_trim()
	local grid = self.grid[teamId]
	if not grid then return nil end
	return grid[slot]
end

function SlotTable:Take(id, teamId, slot)
	if id ~= nil then id = tostring(id) end
	local ok, err = self:_valid(id, teamId, slot)
	if not ok then return false, err end
	slot = err
	self:_trim()
	local occupant = self.grid[teamId][slot]
	if occupant == id then
		self.queued[id] = nil
		return true
	end
	if occupant ~= nil then return false, "taken" end
	self:_set(id, teamId, slot)
	return true
end

function SlotTable:Leave(id)
	if id == nil or id == "" then return false, "player" end
	id = tostring(id)
	self.queued[id] = nil
	if not self.where[id] then return true, "none" end
	self:_unset(id)
	return true
end

function SlotTable:Queue(id, teamId, slot)
	if id ~= nil then id = tostring(id) end
	local ok, err = self:_valid(id, teamId, slot)
	if not ok then return false, err end
	slot = err
	self.queued[id] = { team = teamId, slot = slot }
	return true, "queued"
end

-- LIVE/POST: a living slotted player cannot hop. A dead one is queued for the
-- next BUY. LOBBY/BUY take effect immediately (the caller respawns on BUY).
function SlotTable:Request(id, teamId, slot, phase, alive)
	if phase == "live" or phase == "post" then
		if alive then return false, "alive" end
		return self:Queue(id, teamId, slot)
	end
	return self:Take(id, teamId, slot)
end

function SlotTable:ApplyQueued()
	local list = {}
	for id, req in pairs(self.queued) do
		list[#list + 1] = { id = id, team = req.team, slot = req.slot }
	end
	table.sort(list, function(a, b) return tostring(a.id) < tostring(b.id) end)
	self.queued = {}
	local results = {}
	for i = 1, #list do
		local req = list[i]
		local ok, err = self:Take(req.id, req.team, req.slot)
		results[#results + 1] = { id = req.id, ok = ok, err = err, team = req.team, slot = req.slot }
	end
	return results
end

-- Admin. Occupied slot swaps when the assignee already has a slot, otherwise
-- the occupant is dropped to spectator. team spec or slot 0 clears the player.
function SlotTable:Assign(id, teamId, slot)
	if id == nil or id == "" then return false, "player" end
	id = tostring(id)
	if teamId == SPEC or slot == 0 then
		return self:Leave(id)
	end
	local ok, err = self:_valid(id, teamId, slot)
	if not ok then return false, err end
	slot = err
	self:_trim()
	local occupant = self.grid[teamId][slot]
	if occupant == nil or occupant == id then
		return self:Take(id, teamId, slot)
	end
	local current = self.where[id]
	if not current then
		self:_unset(occupant)
		self.queued[occupant] = nil
		return self:Take(id, teamId, slot)
	end
	local oldTeam, oldSlot = current.team, current.slot
	self.grid[oldTeam][oldSlot] = occupant
	self.where[occupant] = { team = oldTeam, slot = oldSlot }
	self.grid[teamId][slot] = id
	self.where[id] = { team = teamId, slot = slot }
	self.queued[id] = nil
	self.queued[occupant] = nil
	return true, "swap"
end

function SlotTable:Clear()
	self.grid = { [GOOD] = {}, [BAD] = {} }
	self.where = {}
	self.queued = {}
	return true
end

function SlotTable:Snapshot()
	self:_trim()
	local limit = self:Limit()
	local function side(teamId)
		local list = {}
		local grid = self.grid[teamId]
		for slot = 1, limit do
			list[slot] = grid[slot]
		end
		return list
	end
	local queued = {}
	for id, req in pairs(self.queued) do
		queued[id] = { team = req.team, slot = req.slot }
	end
	return { perTeam = limit, [GOOD] = side(GOOD), [BAD] = side(BAD), queued = queued }
end

BALLISTICS.SlotTable = SlotTable

local live = SlotTable.new(function()
	local n = BALLISTICS.Config and BALLISTICS.Config.SlotsPerTeam
	if type(n) ~= "number" then return 5 end
	return n
end)

local plyById = {}

-- GMod players are userdata (type "Player"). Luajit tests use plain tables.
function BALLISTICS.IsPlayer(ply)
	local kind = type(ply)
	return kind == "table" or kind == "Player" or kind == "Entity" or kind == "userdata"
end

function BALLISTICS.PlayerId(ply)
	if ply == nil then return nil end
	local kind = type(ply)
	if kind == "string" then
		if ply == "" then return nil end
		return ply
	end
	if kind == "number" then return tostring(ply) end
	if not BALLISTICS.IsPlayer(ply) then return nil end
	if type(ply.SteamID64) == "function" then
		local id = ply:SteamID64()
		if type(id) == "string" and id ~= "" and id ~= "0" then return id end
	end
	if type(ply.UserID) == "function" then
		local uid = ply:UserID()
		if uid and uid ~= 0 then return "uid:" .. tostring(uid) end
	end
	if type(ply.EntIndex) == "function" then
		return "ent:" .. tostring(ply:EntIndex())
	end
	return tostring(ply)
end

local function remember(ply, id)
	if id and BALLISTICS.IsPlayer(ply) then plyById[id] = ply end
end

-- GMod entities are userdata. Luajit fakes are plain tables; IsValid(table)
-- is false in GMod, so only defer to the global for non-tables.
local function isValid(ent)
	if ent == nil or ent == false then return false end
	if type(ent) == "table" and type(ent.IsValid) == "function" then
		return ent:IsValid() == true
	end
	if type(ent) ~= "table" and IsValid then return IsValid(ent) end
	return type(ent) == "table"
end

BALLISTICS.Slots = BALLISTICS.Slots or {}

function BALLISTICS.Slots.Limit()
	return live:Limit()
end

function BALLISTICS.Slots.Player(id)
	if id == nil then return nil end
	local ply = plyById[tostring(id)]
	if not ply then return nil end
	if not isValid(ply) then
		plyById[tostring(id)] = nil
		return nil
	end
	return ply
end

function BALLISTICS.Slots.EachPlayer(fn)
	for id, ply in pairs(plyById) do
		if isValid(ply) then fn(ply, id) end
	end
end

function BALLISTICS.Slots.Find(id)
	if id == nil then return nil end
	local want = tostring(id)
	local found = BALLISTICS.Slots.Player(want)
	if found then return found end
	if player and player.GetAll then
		local all = player.GetAll()
		if type(all) == "table" then
			for i = 1, #all do
				local ply = all[i]
				if BALLISTICS.PlayerId(ply) == want then
					remember(ply, want)
					return ply
				end
			end
		end
	end
	return nil
end

local function nickOf(ply, id)
	if BALLISTICS.IsPlayer(ply) then
		if type(ply.Nick) == "function" then
			local name = ply:Nick()
			if type(name) == "string" and name ~= "" then return name end
		end
		if type(ply.Name) == "function" then
			local name = ply:Name()
			if type(name) == "string" and name ~= "" then return name end
		end
	end
	return tostring(id)
end

function BALLISTICS.Slots.NetPayload()
	local snap = live:Snapshot()
	local sides = { [GOOD] = {}, [BAD] = {} }
	for _, teamId in ipairs({ GOOD, BAD }) do
		local column = snap[teamId]
		for slot = 1, snap.perTeam do
			local id = column[slot]
			if id then
				sides[teamId][slot] = { id = id, name = nickOf(plyById[id], id) }
			end
		end
	end
	local queue = {}
	for id, req in pairs(snap.queued) do
		queue[#queue + 1] = { id = id, team = req.team, slot = req.slot }
	end
	table.sort(queue, function(a, b) return tostring(a.id) < tostring(b.id) end)
	return { perTeam = snap.perTeam, sides = sides, queue = queue }
end

function BALLISTICS.Slots.Broadcast(target)
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	BALLISTICS.Net.Send("bal_slots_sync", target, BALLISTICS.Slots.NetPayload())
end

local function changed()
	BALLISTICS.Slots.Broadcast()
	if hook and hook.Run then hook.Run("Ballistics_SlotsChanged") end
end

local function setTeam(ply, teamId)
	if not BALLISTICS.IsPlayer(ply) or type(ply.SetTeam) ~= "function" then return end
	if teamId == GOOD or teamId == BAD or teamId == SPEC then ply:SetTeam(teamId) end
end

local function maybeRespawn(ply, teamId)
	if teamId ~= GOOD and teamId ~= BAD then return end
	if not BALLISTICS.IsPlayer(ply) then return end
	if not (BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() == "buy") then return end
	if BALLISTICS.Player and BALLISTICS.Player.SpawnInRound then
		BALLISTICS.Player.SpawnInRound(ply)
	end
end

function BALLISTICS.Slots.Count(teamId)
	return live:Count(teamId)
end

function BALLISTICS.Slots.Members(teamId)
	return live:Members(teamId)
end

function BALLISTICS.Slots.TeamOf(ply)
	local id = BALLISTICS.PlayerId(ply)
	if not id then return nil end
	return live:TeamOf(id)
end

function BALLISTICS.Slots.SlotOf(ply)
	local id = BALLISTICS.PlayerId(ply)
	if not id then return nil end
	local teamId, slot = live:TeamOf(id)
	return slot, teamId
end

function BALLISTICS.Slots.Take(ply, teamId, slot)
	local id = BALLISTICS.PlayerId(ply)
	if not id then return false, "player" end
	remember(ply, id)
	local ok, err = live:Take(id, teamId, slot)
	if not ok then return false, err end
	setTeam(ply, teamId)
	changed()
	maybeRespawn(ply, teamId)
	return true
end

function BALLISTICS.Slots.Leave(ply)
	local id = BALLISTICS.PlayerId(ply)
	if not id then return false, "player" end
	local had = live:TeamOf(id) ~= nil or live:Queued(id) ~= nil
	local ok, err = live:Leave(id)
	if had then
		setTeam(ply, SPEC)
		changed()
	end
	return ok, err
end

function BALLISTICS.Slots.Request(ply, teamId, slot)
	local id = BALLISTICS.PlayerId(ply)
	if not id then return false, "player" end
	remember(ply, id)
	local phase = "lobby"
	if BALLISTICS.Round and BALLISTICS.Round.Phase then
		phase = BALLISTICS.Round.Phase() or "lobby"
	end
	local alive = false
	if BALLISTICS.IsPlayer(ply) and type(ply.Alive) == "function" then
		alive = ply:Alive() == true
	end
	local ok, err = live:Request(id, teamId, slot, phase, alive)
	if not ok then return false, err end
	if err == "queued" then
		changed()
		return true, "queued"
	end
	setTeam(ply, teamId)
	changed()
	maybeRespawn(ply, teamId)
	return true
end

function BALLISTICS.Slots.Assign(ply, teamId, slot)
	local id = BALLISTICS.PlayerId(ply)
	if not id then return false, "player" end
	remember(ply, id)
	local target = BALLISTICS.IsPlayer(ply) and ply or BALLISTICS.Slots.Player(id)
	local previous = nil
	if teamId == GOOD or teamId == BAD then
		previous = live:Occupant(teamId, tonumber(slot) or -1)
	end
	local ok, err = live:Assign(id, teamId, slot)
	if not ok then return false, err end
	if teamId == SPEC or slot == 0 or not live:TeamOf(id) then
		setTeam(target, SPEC)
	else
		local nowTeam = live:TeamOf(id)
		setTeam(target, nowTeam)
		maybeRespawn(target, nowTeam)
	end
	if previous and previous ~= id then
		local other = plyById[previous]
		local otherTeam = live:TeamOf(previous)
		if otherTeam then
			setTeam(other, otherTeam)
			maybeRespawn(other, otherTeam)
		else
			setTeam(other, SPEC)
		end
	end
	changed()
	return true, err
end

function BALLISTICS.Slots.ApplyQueued()
	local results = live:ApplyQueued()
	for i = 1, #results do
		local row = results[i]
		if row.ok then
			setTeam(plyById[row.id], row.team)
		end
	end
	if #results > 0 then changed() end
	return results
end

function BALLISTICS.Slots.ClearAll()
	for _, ply in pairs(plyById) do
		setTeam(ply, SPEC)
	end
	live:Clear()
	changed()
	return true
end

function BALLISTICS.Slots.Forget(ply)
	local id = BALLISTICS.PlayerId(ply)
	if id then plyById[id] = nil end
end

if hook and hook.Add then
	hook.Add("PlayerDisconnected", "Ballistics_SlotsLeave", function(ply)
		-- Don't SetTeam on a player who is already disconnecting.
		local id = BALLISTICS.PlayerId(ply)
		if not id then return end
		local had = live:TeamOf(id) ~= nil or live:Queued(id) ~= nil
		live:Leave(id)
		plyById[id] = nil
		if had then changed() end
	end)
	hook.Add("PlayerInitialSpawn", "Ballistics_SlotsSync", function(ply)
		local id = BALLISTICS.PlayerId(ply)
		remember(ply, id)
		BALLISTICS.Slots.Broadcast(ply)
	end)
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	-- bal_slots_sync: uint8 perTeam, then Good (1) and Bad (2) columns of
	-- perTeam entries (bool occupied, string id, string name), then uint8
	-- queue count of (string id, uint8 team, uint8 slot).
	BALLISTICS.Net.Register("bal_slots_sync", nil, {
		write = function(payload)
			payload = payload or {}
			local per = payload.perTeam or 0
			net.WriteUInt(per, 8)
			local sides = payload.sides or {}
			for teamId = 1, 2 do
				local column = sides[teamId] or {}
				for slot = 1, per do
					local entry = column[slot]
					if entry and entry.id then
						net.WriteBool(true)
						net.WriteString(entry.id)
						net.WriteString(entry.name or "")
					else
						net.WriteBool(false)
					end
				end
			end
			local queue = payload.queue or {}
			net.WriteUInt(#queue, 8)
			for i = 1, #queue do
				net.WriteString(queue[i].id or "")
				net.WriteUInt(queue[i].team or 0, 8)
				net.WriteUInt(queue[i].slot or 0, 8)
			end
		end,
	})

	BALLISTICS.Net.Register("bal_slot_take", function(ply, payload)
		if type(payload) ~= "table" then return end
		BALLISTICS.Slots.Request(ply, payload.team, payload.slot)
	end, {
		rate = 5,
		read = function()
			return { team = net.ReadUInt(8), slot = net.ReadUInt(8) }
		end,
	})

	BALLISTICS.Net.Register("bal_admin_assign", function(_, payload)
		if type(payload) ~= "table" then return end
		local id = payload.id
		if type(id) ~= "string" or id == "" then return end
		local target = BALLISTICS.Slots.Find(id) or id
		BALLISTICS.Slots.Assign(target, payload.team, payload.slot)
	end, {
		admin = true,
		rate = 5,
		read = function()
			return { id = net.ReadString(), team = net.ReadUInt(8), slot = net.ReadUInt(8) }
		end,
	})
end
