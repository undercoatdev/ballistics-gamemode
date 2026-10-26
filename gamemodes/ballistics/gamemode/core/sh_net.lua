-- One net registry. Server handlers get (ply, payload) with admin + rate checks.
-- WriteTable is for admin config only; game messages pass a custom write/read.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Net = BALLISTICS.Net or {}

local registry = {}
local added = {}
local buckets = {}

local MESSAGES = {
	"bal_slot_take",
	"bal_slots_sync",
	"bal_admin_assign",
	"bal_buy",
	"bal_buy_open",
	"bal_spawn_place",
	"bal_spawns_sync",
	"bal_config_set",
	"bal_config_sync",
	"bal_round_sync",
	"bal_capture_sync",
}

local function addString(name)
	if added[name] then return end
	added[name] = true
	if SERVER and util and util.AddNetworkString then
		util.AddNetworkString(name)
	end
end

local function playerId(ply)
	if not ply then return "nil" end
	if ply.SteamID64 then
		local id = ply:SteamID64()
		if id and id ~= "" then return id end
	end
	if ply.EntIndex then return "e" .. tostring(ply:EntIndex()) end
	return tostring(ply)
end

local function allowRate(ply, name, rate)
	rate = rate or 10
	if rate <= 0 then return true end
	local now = (CurTime and CurTime()) or 0
	local id = playerId(ply)
	buckets[id] = buckets[id] or {}
	local b = buckets[id][name]
	if not b or (now - b.t) >= 1 then
		buckets[id][name] = { t = now, n = 1 }
		return true
	end
	b.n = b.n + 1
	return b.n <= rate
end

local function readPayload(spec)
	if not spec or spec.read == nil then return {} end
	local r = spec.read
	if r == "table" then
		if net and net.ReadTable then return net.ReadTable() or {} end
		return {}
	elseif r == "string" then
		if net and net.ReadString then return net.ReadString() end
		return ""
	elseif type(r) == "function" then
		return r()
	end
	return {}
end

function BALLISTICS.Net.Register(name, handler, opts)
	opts = opts or {}
	addString(name)
	registry[name] = {
		handler = handler,
		admin = opts.admin and true or false,
		rate = opts.rate or 10,
		read = opts.read,
		write = opts.write,
	}
	if not handler or not net or not net.Receive then return end
	if SERVER then
		net.Receive(name, function(_, ply)
			local spec = registry[name]
			if not spec or not spec.handler or not ply then return end
			-- Fail closed: an admin-only message is refused if the admin check is missing.
			if spec.admin and not (BALLISTICS.IsAdmin and BALLISTICS.IsAdmin(ply)) then return end
			if not allowRate(ply, name, spec.rate) then return end
			spec.handler(ply, readPayload(spec))
		end)
	else
		net.Receive(name, function()
			local spec = registry[name]
			if not spec or not spec.handler then return end
			spec.handler(readPayload(spec))
		end)
	end
end

function BALLISTICS.Net.Send(name, ply, payload)
	if not SERVER or not net or not net.Start then return end
	local spec = registry[name]
	net.Start(name)
	if spec and spec.write then
		spec.write(payload)
	elseif type(payload) == "table" and net.WriteTable then
		net.WriteTable(payload)
	end
	if ply then
		net.Send(ply)
	elseif net.Broadcast then
		net.Broadcast()
	end
end

function BALLISTICS.Net.Broadcast(name, payload)
	BALLISTICS.Net.Send(name, nil, payload)
end

for i = 1, #MESSAGES do
	addString(MESSAGES[i])
end

if CLIENT then
	BALLISTICS.Net.Register("bal_config_sync", function(payload)
		if type(payload) == "table" and BALLISTICS.Config and BALLISTICS.Config.Apply then
			BALLISTICS.Config.Apply(payload)
		end
	end, { read = "table" })
end

if hook and hook.Add then
	hook.Add("PlayerDisconnected", "Ballistics_NetRate", function(ply)
		buckets[playerId(ply)] = nil
	end)
end
