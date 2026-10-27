-- Load, save, and replicate map flags. Clients only request; this file decides.
-- data/ballistics/spawns/<map>.json, else modules/spawns/defaults.lua, else none.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spawns = BALLISTICS.Spawns or {}

local D = BALLISTICS.SpawnData
local WARN = "Ballistics: this map has no Good and Bad flags. Open Admin → Spawns, place both, and save."
local BOX_WARN = "Ballistics: Place the firing squad box in Admin > Spawns."

local state = { good = nil, bad = nil, box = nil, source = "none", map = "", dirty = false }
local props = {}

local function mapName()
	if game and game.GetMap then
		local name = game.GetMap()
		if type(name) == "string" then return name end
	end
	return ""
end

local function tell(ply, text)
	print("[Ballistics] " .. text)
	if not ply or not ply.ChatPrint then return end
	if not (BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply)) then return end
	ply:ChatPrint(text)
end

local function snap(x, y, z)
	if not util or not util.TraceLine then return x, y, z end
	local tr = util.TraceLine({
		start = Vector(x, y, z + 64),
		endpos = Vector(x, y, z - 4096),
		mask = MASK_SOLID_BRUSHONLY or 16395,
	})
	if not tr or not tr.Hit or tr.HitSky or not tr.HitPos then return x, y, z end
	local p = tr.HitPos
	if p.x == nil or p.z == nil then return x, y, z end
	if math.abs(p.x - x) < 8 and math.abs(p.y - y) < 8 then
		return p.x, p.y, p.z
	end
	return x, y, p.z
end

local function snapFlag(flag)
	if not flag or not flag.pos then return nil end
	local x, y, z = snap(flag.pos.x, flag.pos.y, flag.pos.z)
	return {
		pos = { x = x, y = y, z = z },
		ang = { p = 0, y = flag.ang and flag.ang.y or 0, r = 0 },
	}
end

-- Centre z becomes ground + half height. A miss keeps the centre that was sent.
local function snapBox(box)
	if not box or not box.pos then return nil end
	local out = {
		pos = { x = box.pos.x, y = box.pos.y, z = box.pos.z },
		yaw = box.yaw or 0,
		sx = box.sx,
		sy = box.sy,
	}
	if not util or not util.TraceLine then return out end
	local x, y, z = out.pos.x, out.pos.y, out.pos.z
	local tr = util.TraceLine({
		start = Vector(x, y, z + 64),
		endpos = Vector(x, y, z - 4096),
		mask = MASK_SOLID_BRUSHONLY or 16395,
	})
	if not tr or not tr.Hit or tr.HitSky or not tr.HitPos or tr.HitPos.z == nil then
		return out
	end
	out.pos.z = tr.HitPos.z + (D.BOX_HEIGHT * 0.5)
	return out
end

local function hullBlocked(x, y, z)
	if not util or not util.TraceHull then return false end
	local feet = Vector(x, y, z + 1)
	local tr = util.TraceHull({
		start = feet,
		endpos = feet,
		mins = Vector(-16, -16, 0),
		maxs = Vector(16, 16, 72),
		mask = MASK_PLAYERSOLID or 33636363,
	})
	if not tr then return false end
	return tr.StartSolid == true or tr.AllSolid == true
end

local function clearProps()
	for i = 1, #props do
		local ent = props[i]
		if ent and ent.Remove and (not ent.IsValid or ent:IsValid()) then
			ent:Remove()
		end
	end
	props = {}
end

local function sealFlag(ent)
	if not ent then return end
	if ent.SetKeyValue then ent:SetKeyValue("solid", "0") end
	if ent.SetSolid then ent:SetSolid(SOLID_NONE or 0) end
	if ent.SetNotSolid then ent:SetNotSolid(true) end
	if ent.SetMoveType then ent:SetMoveType(MOVETYPE_NONE or 0) end
	if ent.SetCollisionGroup then
		ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE or 10)
	end
	if ent.DrawShadow then ent:DrawShadow(false) end
	local phys = ent.GetPhysicsObject and ent:GetPhysicsObject()
	if phys and (not phys.IsValid or phys:IsValid()) then
		if phys.EnableMotion then phys:EnableMotion(false) end
		if phys.EnableCollisions then phys:EnableCollisions(false) end
	end
	ent.PhysgunPickup = function() return false end
	ent.GravGunPickupAllowed = function() return false end
	ent.GravGunPunt = function() return false end
end

local function makeProp(flag, teamId)
	if not flag or not ents or not ents.Create then return end
	local ent = ents.Create("prop_dynamic")
	if not ent then return end
	if ent.IsValid and not ent:IsValid() then return end
	local x, y, z = snap(flag.pos.x, flag.pos.y, flag.pos.z)
	local model = D.flagModel and D.flagModel(teamId) or D.FLAG_MODEL_GOOD
	ent:SetModel(model)
	ent:SetPos(Vector(x, y, z + (D.FLAG_LIFT or 12))) -- models sink into the floor otherwise
	ent:SetAngles(Angle(0, flag.ang and flag.ang.y or 0, 0))
	sealFlag(ent)
	ent:Spawn()
	if ent.Activate then ent:Activate() end
	-- Spawn can turn solidity and motion back on.
	sealFlag(ent)
	if ent.SetNW2Int then ent:SetNW2Int("bal_flag_team", teamId) end
	props[#props + 1] = ent
end

local function isFlagEnt(ent)
	return ent and ent.GetNW2Int and ent:GetNW2Int("bal_flag_team", 0) ~= 0
end

local function rebuild()
	clearProps()
	local good = TEAM_GOOD or 1
	local bad = TEAM_BAD or 2
	makeProp(state.good, good)
	makeProp(state.bad, bad)
end

local function sync(ply)
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	BALLISTICS.Net.Send("bal_spawns_sync", ply, D.copy(state))
end

local function warnAdmins(ply)
	if D.hasBoth(state) then return end
	if ply then
		if BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply) and ply.ChatPrint then
			ply:ChatPrint(WARN)
		end
		return
	end
	print(WARN)
	if not player or not player.GetAll then return end
	local all = player.GetAll()
	if type(all) ~= "table" then return end
	for i = 1, #all do
		local p = all[i]
		if BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(p) and p.ChatPrint then
			p:ChatPrint(WARN)
		end
	end
end

local function warnBox(ply)
	if D.hasBox(state) then return end
	if ply then
		if BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply) and ply.ChatPrint then
			ply:ChatPrint(BOX_WARN)
		end
		return
	end
	print(BOX_WARN)
	if not player or not player.GetAll then return end
	local all = player.GetAll()
	if type(all) ~= "table" then return end
	for i = 1, #all do
		local p = all[i]
		if BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(p) and p.ChatPrint then
			p:ChatPrint(BOX_WARN)
		end
	end
end

local function perTeam()
	if BALLISTICS.Slots and BALLISTICS.Slots.Limit then
		return BALLISTICS.Slots.Limit()
	end
	local n = BALLISTICS.Config and BALLISTICS.Config.SlotsPerTeam
	if type(n) == "number" then return n end
	return 5
end

function BALLISTICS.Spawns.Snapshot()
	return D.copy(state)
end

function BALLISTICS.Spawns.HasBoth()
	return D.hasBoth(state) == true
end

function BALLISTICS.Spawns.HasBox()
	return D.hasBox(state) == true
end

function BALLISTICS.Spawns.SquadBox()
	if not D.hasBox(state) then return nil end
	local copy = D.copy(state)
	return copy.box
end

function BALLISTICS.Spawns.Sync(ply)
	sync(ply)
end

-- Slot N stands on the ring around this team's flag, nudged out if the hull is blocked.
-- No flag for that side means no spawn point (the round must not invent a map start).
function BALLISTICS.Spawns.PlayerSpawn(teamId, slot)
	local side = D.side(teamId)
	local flag = side and state[side]
	if not flag or not flag.pos then return nil end
	local per = perTeam()
	local function blocked(c)
		local x, y, z = snap(flag.pos.x + c.x, flag.pos.y + c.y, flag.pos.z + 16)
		return hullBlocked(x, y, z)
	end
	local stood, stoodAng = D.playerPoint(flag, slot, per, blocked)
	if not stood then return nil end
	local x, y, z = snap(stood.x, stood.y, stood.z + 16)
	local yaw = stoodAng and stoodAng.y or 0
	return Vector(x, y, z + 2), Angle(0, yaw, 0)
end

function BALLISTICS.Spawns.Reload()
	local map = mapName()
	local saved = nil
	local path = D.mapFile(map)
	if path and file and file.Exists and file.Exists(path, "DATA") and file.Read then
		saved = file.Read(path, "DATA")
	end
	state = D.resolve(saved, BALLISTICS.SpawnDefaults, map)
	state.good = snapFlag(state.good)
	state.bad = snapFlag(state.bad)
	state.box = snapBox(state.box)
	rebuild()
	sync()
	if not D.hasBoth(state) then warnAdmins() end
	if not D.hasBox(state) then warnBox() end
	return state.source
end

local function save()
	local hasBox = type(state.box) == "table" and type(state.box.pos) == "table"
	if not state.good and not state.bad and not hasBox then return false, "empty" end
	local map = mapName()
	local path = D.mapFile(map)
	if not path then return false, "map" end
	state.map = map
	local json, err = D.toJSON(state)
	if not json then return false, err end
	if file and file.CreateDir then
		file.CreateDir("ballistics")
		file.CreateDir("ballistics/spawns")
	end
	if not file or not file.Write then return false, "file" end
	file.Write(path, json)
	state.source = "file"
	state.dirty = false
	sync()
	return true
end

local function reset()
	local map = mapName()
	local path = D.mapFile(map)
	if path and file and file.Delete then file.Delete(path) end
	state = D.resolve(nil, BALLISTICS.SpawnDefaults, map)
	state.good = snapFlag(state.good)
	state.bad = snapFlag(state.bad)
	state.box = snapBox(state.box)
	rebuild()
	sync()
	if state.source == "defaults" then
		return true, "Ballistics: flags reset to the built-in defaults for this map."
	end
	warnAdmins()
	warnBox()
	return true, "Ballistics: this map has no built-in flags. Place both before the round can start."
end

function BALLISTICS.Spawns.Handle(ply, payload)
	if not (BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply)) then return false, "admin" end
	if type(payload) ~= "table" then return false, "payload" end
	local op = tonumber(payload.op) or 0
	if op == D.OP_PLACE then
		local pos = payload.pos
		if type(pos) == "table" then
			local x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z)
			if x and y and z then
				x, y, z = snap(x, y, z)
				pos = { x = x, y = y, z = z }
			end
		end
		local nextState, err = D.place(state, payload.team, pos, payload.ang)
		if not nextState then
			tell(ply, "Ballistics: " .. D.reasonText(err))
			return false, err
		end
		state = nextState
		state.map = mapName()
		rebuild()
		sync()
		local side = D.side(payload.team) or "flag"
		tell(ply, "Ballistics: placed the " .. side .. " flag. Save to keep it.")
		return true
	elseif op == D.OP_BOX then
		local pos = payload.pos
		local yaw = payload.yaw
		if yaw == nil and type(payload.ang) == "table" then yaw = payload.ang.y end
		local nextState, err = D.placeBox(state, pos, yaw, payload.sx, payload.sy)
		if not nextState then
			tell(ply, "Ballistics: " .. D.reasonText(err))
			return false, err
		end
		nextState.box = snapBox(nextState.box)
		state = nextState
		state.map = mapName()
		state.dirty = true
		sync()
		tell(ply, "Ballistics: placed the firing squad box. Save to keep it.")
		return true
	elseif op == D.OP_SAVE then
		local ok, err = save()
		if not ok then
			tell(ply, "Ballistics: " .. D.reasonText(err))
			return false, err
		end
		tell(ply, "Ballistics: flags saved for this map.")
		return true
	elseif op == D.OP_RESET then
		local ok, msg = reset()
		if msg then tell(ply, msg) end
		return ok
	end
	return false, "op"
end

if util and util.PrecacheModel then
	if D.FLAG_MODEL_GOOD then util.PrecacheModel(D.FLAG_MODEL_GOOD) end
	if D.FLAG_MODEL_BAD then util.PrecacheModel(D.FLAG_MODEL_BAD) end
end

local function readPlace()
	local pos = {}
	local ang = {}
	local op = net.ReadUInt(8)
	local team = net.ReadUInt(8)
	pos.x = net.ReadFloat()
	pos.y = net.ReadFloat()
	pos.z = net.ReadFloat()
	ang.p = net.ReadFloat()
	ang.y = net.ReadFloat()
	ang.r = net.ReadFloat()
	local sx = net.ReadFloat()
	local sy = net.ReadFloat()
	return { op = op, team = team, pos = pos, ang = ang, sx = sx, sy = sy }
end

local function writeFlag(flag)
	local on = type(flag) == "table" and type(flag.pos) == "table"
	net.WriteBool(on)
	if not on then return end
	net.WriteFloat(flag.pos.x or 0)
	net.WriteFloat(flag.pos.y or 0)
	net.WriteFloat(flag.pos.z or 0)
	local ang = flag.ang or {}
	net.WriteFloat(ang.p or 0)
	net.WriteFloat(ang.y or 0)
	net.WriteFloat(ang.r or 0)
end

local function writeBox(box)
	local on = type(box) == "table" and type(box.pos) == "table"
	net.WriteBool(on)
	if not on then return end
	net.WriteFloat(box.pos.x or 0)
	net.WriteFloat(box.pos.y or 0)
	net.WriteFloat(box.pos.z or 0)
	net.WriteFloat(box.yaw or 0)
	net.WriteFloat(box.sx or 0)
	net.WriteFloat(box.sy or 0)
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_spawn_place", function(ply, payload)
		BALLISTICS.Spawns.Handle(ply, payload)
	end, { admin = true, rate = 10, read = readPlace })

	BALLISTICS.Net.Register("bal_spawns_sync", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteString(payload.map or "")
			net.WriteString(payload.source or "none")
			net.WriteBool(payload.dirty == true)
			writeFlag(payload.good)
			writeFlag(payload.bad)
			writeBox(payload.box)
		end,
	})
end

if hook and hook.Add then
	hook.Add("InitPostEntity", "Ballistics_Spawns", function()
		BALLISTICS.Spawns.Reload()
	end)
	hook.Add("PlayerInitialSpawn", "Ballistics_SpawnsSync", function(ply)
		sync(ply)
		warnAdmins(ply)
		warnBox(ply)
		if timer and timer.Simple then
			timer.Simple(1, function()
				if ply and type(ply.IsValid) == "function" and ply:IsValid() ~= true then return end
				sync(ply)
			end)
		end
	end)
	hook.Add("PhysgunPickup", "Ballistics_Flags", function(_, ent)
		if isFlagEnt(ent) then return false end
	end)
	hook.Add("GravGunPickupAllowed", "Ballistics_Flags", function(_, ent)
		if isFlagEnt(ent) then return false end
	end)
	hook.Add("GravGunPunt", "Ballistics_Flags", function(_, ent)
		if isFlagEnt(ent) then return false end
	end)
	hook.Add("CanTool", "Ballistics_Flags", function(_, tr)
		if tr and isFlagEnt(tr.Entity) then return false end
	end)
	hook.Add("EntityTakeDamage", "Ballistics_Flags", function(ent)
		if isFlagEnt(ent) then return true end
	end)
	hook.Add("ShouldCollide", "Ballistics_Flags", function(a, b)
		if isFlagEnt(a) or isFlagEnt(b) then return false end
	end)
end

-- First load happens before the map's entities exist, so InitPostEntity does
-- the first Reload. GAMEMODE is only set on a Lua refresh, when it's safe now.
if GAMEMODE then BALLISTICS.Spawns.Reload() end
