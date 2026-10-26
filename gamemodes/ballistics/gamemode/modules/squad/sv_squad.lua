-- Lines both teams up when the squad phase starts, then freezes the losers.
-- Does not call SpawnInRound, so gear keep and organ carry-over stay off.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Squad = BALLISTICS.Squad or {}

local GOOD = TEAM_GOOD or 1
local BAD = TEAM_BAD or 2
local KNIFE = "tacrp_knife"

local active = false
local lined = {}

local function now()
	return (CurTime and CurTime()) or 0
end

local function winnerOf()
	if not (BALLISTICS.Round and type(BALLISTICS.Round.Snapshot) == "function") then return nil end
	local snap = BALLISTICS.Round.Snapshot()
	if type(snap) ~= "table" then return nil end
	if snap.matchWinner == "good" or snap.matchWinner == "bad" then return snap.matchWinner end
	return nil
end

local function sendState(ply, on, winner, freezeEnd, frozen)
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	BALLISTICS.Net.Send("bal_squad", ply, {
		active = on == true,
		winner = winner or "",
		freezeEnd = freezeEnd or 0,
		frozen = frozen == true,
	})
end

local function vecAt(pos)
	if not pos then return nil end
	local z = (pos.z or 0) + 2
	if Vector then return Vector(pos.x, pos.y, z) end
	return { x = pos.x, y = pos.y, z = z }
end

local function angAt(yaw)
	if Angle then return Angle(0, yaw or 0, 0) end
	return { p = 0, y = yaw or 0, r = 0 }
end

local function giveKit(ply, kit)
	if not kit then return end
	if kit.weapon and ply.Give then
		local wep = ply:Give(kit.weapon, true)
		if (wep == nil or wep == false) and ply.GetWeapon then
			wep = ply:GetWeapon(kit.weapon)
		end
		local ammo, clip, rounds = nil, nil, 0
		if BALLISTICS.Squad.Reserve then
			ammo, clip, rounds = BALLISTICS.Squad.Reserve(wep, kit.mags)
		end
		if type(ammo) == "string" and ammo ~= "" and ammo ~= "none" and ply.SetAmmo then
			ply:SetAmmo(rounds or 0, ammo)
		end
		if wep and type(wep.SetClip1) == "function" and clip and clip > 0 then
			wep:SetClip1(clip)
		end
		if ply.SelectWeapon then ply:SelectWeapon(kit.weapon) end
	end
	if kit.knife and ply.Give then
		ply:Give(KNIFE)
		if not kit.weapon and ply.SelectWeapon then ply:SelectWeapon(KNIFE) end
	end
end

local function standFor(list, slot)
	if not list then return nil end
	for i = 1, #list do
		if list[i].slot == slot then return list[i] end
	end
	return nil
end

local function membersOf(teamId)
	local out = {}
	if not (BALLISTICS.Slots and BALLISTICS.Slots.Members and BALLISTICS.Slots.Player) then
		return out
	end
	local ids = BALLISTICS.Slots.Members(teamId) or {}
	for i = 1, #ids do
		local ply = BALLISTICS.Slots.Player(ids[i])
		if ply then
			local slot = i
			if BALLISTICS.Slots.TeamOf then
				local _, got = BALLISTICS.Slots.TeamOf(ply)
				if type(got) == "number" then slot = got end
			end
			out[#out + 1] = { ply = ply, slot = slot }
		end
	end
	return out
end

local function spawnOne(ply, stand, role, kit, teamId, winner, freezeEnd)
	if ply == nil or not kit then return end
	local pos = stand and vecAt(stand.pos) or nil
	local eye = stand and angAt(stand.yaw) or nil
	ply.balNextSpawn = true
	ply.balSpawnPos = pos
	ply.balSpawnAng = eye
	if ply.SetTeam then ply:SetTeam(teamId) end
	if ply.UnSpectate then ply:UnSpectate() end
	if ply.SetNoTarget then ply:SetNoTarget(false) end
	if ply.Spawn then ply:Spawn() end
	if BALLISTICS.Player and BALLISTICS.Player.Wipe then
		BALLISTICS.Player.Wipe(ply)
	end
	giveKit(ply, kit)
	if pos and ply.SetPos then ply:SetPos(pos) end
	if eye and ply.SetEyeAngles then ply:SetEyeAngles(eye) end
	local frozen = role == "loser" and kit.freeze > 0
	if frozen then
		ply.balSquadUntil = freezeEnd
	else
		ply.balSquadUntil = nil
	end
	if BALLISTICS.Player and BALLISTICS.Player.SetFrozen then
		BALLISTICS.Player.SetFrozen(ply, frozen == true)
	end
	ply.balSquadRole = role
	lined[#lined + 1] = ply
	sendState(ply, true, winner, frozen and freezeEnd or 0, frozen)
end

function BALLISTICS.Squad.Begin()
	local winner = winnerOf()
	if winner ~= "good" and winner ~= "bad" then return end
	lined = {}
	active = true
	local box = nil
	if BALLISTICS.Spawns and type(BALLISTICS.Spawns.SquadBox) == "function" then
		box = BALLISTICS.Spawns.SquadBox()
	end
	local settings = BALLISTICS.Squad.Settings(BALLISTICS.Config or {})
	local freezeEnd = now() + settings.freeze
	local good = membersOf(GOOD)
	local bad = membersOf(BAD)
	local goodSlots, badSlots = {}, {}
	for i = 1, #good do goodSlots[i] = good[i].slot end
	for i = 1, #bad do badSlots[i] = bad[i].slot end
	local layout = nil
	if box and BALLISTICS.Squad.Line then
		layout = BALLISTICS.Squad.Line(box, goodSlots, badSlots)
	end
	local cfg = BALLISTICS.Config or {}
	for i = 1, #good do
		local role = BALLISTICS.Squad.Role(GOOD, winner)
		local stand = layout and standFor(layout.good, good[i].slot) or nil
		spawnOne(good[i].ply, stand, role, BALLISTICS.Squad.Kit(role, cfg), GOOD, winner, freezeEnd)
	end
	for i = 1, #bad do
		local role = BALLISTICS.Squad.Role(BAD, winner)
		local stand = layout and standFor(layout.bad, bad[i].slot) or nil
		spawnOne(bad[i].ply, stand, role, BALLISTICS.Squad.Kit(role, cfg), BAD, winner, freezeEnd)
	end
end

function BALLISTICS.Squad.End()
	if not active and #lined == 0 then return end
	active = false
	for i = 1, #lined do
		local ply = lined[i]
		if ply then
			ply.balSquadUntil = nil
			ply.balSquadRole = nil
			if BALLISTICS.Player and BALLISTICS.Player.SetFrozen then
				BALLISTICS.Player.SetFrozen(ply, false)
			end
			sendState(ply, false, "", 0, false)
		end
	end
	lined = {}
end

function BALLISTICS.Squad.Active()
	return active == true
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_squad", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteBool(payload.active == true)
			net.WriteString(payload.winner or "")
			net.WriteFloat(payload.freezeEnd or 0)
			net.WriteBool(payload.frozen == true)
		end,
	})
end

if hook and hook.Add then
	hook.Add("Ballistics_PhaseChanged", "Ballistics_Squad", function(old, new)
		if new == "squad" then
			BALLISTICS.Squad.Begin()
		elseif old == "squad" then
			BALLISTICS.Squad.End()
		end
	end)

	hook.Add("Think", "Ballistics_SquadFreeze", function()
		if not active then return end
		if BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase() ~= "squad" then return end
		local t = now()
		for i = 1, #lined do
			local ply = lined[i]
			if ply and ply.balSquadUntil and t >= ply.balSquadUntil then
				local alive = true
				if type(ply.Alive) == "function" then alive = ply:Alive() ~= false end
				if alive and BALLISTICS.Player and BALLISTICS.Player.SetFrozen then
					BALLISTICS.Player.SetFrozen(ply, false)
				end
				ply.balSquadUntil = nil
				sendState(ply, true, winnerOf() or "", 0, false)
			end
		end
	end)
end
