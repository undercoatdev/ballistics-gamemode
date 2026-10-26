-- Load, save, and replicate map flags. Clients only request; this file decides.
-- data/ballistics/spawns/<map>.json, else modules/spawns/defaults.lua, else none.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spawns = BALLISTICS.Spawns or {}

local D = BALLISTICS.SpawnData
local MODEL = "models/props_c17/signpole001.mdl"
local WARN = "Ballistics: this map has no Good and Bad flags. Open Admin → Spawns, place both, and save."

local state = { good = nil, bad = nil, source = "none", map = "", dirty = false }
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

local function teamColor(teamId)
	local col = BALLISTICS.TeamColor and BALLISTICS.TeamColor[teamId]
	if col then return col end
	if teamId == (TEAM_BAD or 2) then return Color(220, 50, 50) end
	return Color(70, 140, 255)
end

local function makeProp(flag, teamId)
	if not flag or not ents or not ents.Create then return end
	local ent = ents.Create("prop_dynamic")
	if not ent then return end
	if ent.IsValid and not ent:IsValid() then return end
	local x, y, z = snap(flag.pos.x, flag.pos.y, flag.pos.z)
	ent:SetModel(MODEL)
	ent:SetPos(Vector(x, y, z))
	ent:SetAngles(Angle(0, flag.ang and flag.ang.y or 0, 0))
	if ent.SetKeyValue then ent:SetKeyValue("solid", "0") end
	ent:SetSolid(SOLID_NONE or 0)
	ent:SetMoveType(MOVETYPE_NONE or 0)
	ent:Spawn()
	if ent.Activate then ent:Activate() end
	if ent.SetModelScale then ent:SetModelScale(0.35, 0) end
	if ent.SetRenderMode then ent:SetRenderMode(RENDERMODE_TRANSCOLOR or 1) end
	if ent.SetColor then ent:SetColor(teamColor(teamId)) end
	if ent.DrawShadow then ent:DrawShadow(false) end
	if ent.SetNW2Int then ent:SetNW2Int("bal_flag_team", teamId) end
	local phys = ent.GetPhysicsObject and ent:GetPhysicsObject()
	if phys and (not phys.IsValid or phys:IsValid()) and phys.EnableMotion then
		phys:EnableMotion(false)
	end
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
	rebuild()
	sync()
	if not D.hasBoth(state) then warnAdmins() end
	return state.source
end

local function save()
	if not state.good and not state.bad then return false, "empty" end
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
	rebuild()
	sync()
	if state.source == "defaults" then
		return true, "Ballistics: flags reset to the built-in defaults for this map."
	end
	warnAdmins()
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

if util and util.PrecacheModel then util.PrecacheModel(MODEL) end

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
	return { op = op, team = team, pos = pos, ang = ang }
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
	hook.Add("CanTool", "Ballistics_Flags", function(_, tr)
		if tr and isFlagEnt(tr.Entity) then return false end
	end)
end

-- First load happens before the map's entities exist, so InitPostEntity does
-- the first Reload. GAMEMODE is only set on a Lua refresh, when it's safe now.
if GAMEMODE then BALLISTICS.Spawns.Reload() end
