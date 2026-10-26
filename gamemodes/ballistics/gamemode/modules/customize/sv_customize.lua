-- Server customize toggle. TacRP's own C path is a level bit on the usercmd
-- (TacRP.IN_CUSTOMIZE). StartCommand strips that bit so weapon Think never
-- toggles. The client asks with bal_customize; this file is the only place
-- that calls ToggleCustomize. Scope is cleared first so C is not a peek.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Customize = BALLISTICS.Customize or {}

local presses = {}

local function finite(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function validEnt(ent)
	if ent == nil or ent == false then return false end
	local kind = type(ent)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "Player" and kind ~= "Entity" and kind ~= "Weapon" then
		return false
	end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	if kind ~= "table" and IsValid then return IsValid(ent) == true end
	return kind == "table"
end

local function playerId(ply)
	if BALLISTICS.PlayerId then return BALLISTICS.PlayerId(ply) end
	if ply == nil then return nil end
	if type(ply.SteamID64) == "function" then
		local id = ply:SteamID64()
		if type(id) == "string" and id ~= "" and id ~= "0" then return id end
	end
	return tostring(ply)
end

local function radius()
	local n = BALLISTICS.Config and tonumber(BALLISTICS.Config.CustomizeRadius)
	if not finite(n) or n <= 0 then n = 2 / 0.01905 end
	return n
end

local function phaseOf()
	if BALLISTICS.Round and type(BALLISTICS.Round.Phase) == "function" then
		local p = BALLISTICS.Round.Phase()
		if type(p) == "string" and p ~= "" then return p end
	end
	return "lobby"
end

local function teamOf(ply)
	if BALLISTICS.Slots and type(BALLISTICS.Slots.TeamOf) == "function" then
		local id = BALLISTICS.Slots.TeamOf(ply)
		if id ~= nil then return id end
	end
	if type(ply.Team) == "function" then return ply:Team() end
	return nil
end

local function inZone(ply)
	if not validEnt(ply) or type(ply.GetPos) ~= "function" then return false end
	local snap
	if BALLISTICS.Spawns and type(BALLISTICS.Spawns.Snapshot) == "function" then
		snap = BALLISTICS.Spawns.Snapshot()
	end
	local flag = BALLISTICS.CKey.FlagPos(snap, teamOf(ply))
	return BALLISTICS.CKey.InRadius(ply:GetPos(), flag, radius())
end

local function isAlive(ply)
	if not validEnt(ply) or type(ply.Alive) ~= "function" then return false end
	return ply:Alive() == true
end

local function activeTac(ply)
	if not validEnt(ply) or type(ply.GetActiveWeapon) ~= "function" then return nil end
	local wep = ply:GetActiveWeapon()
	if not validEnt(wep) or wep.ArcticTacRP ~= true then return nil end
	return wep
end

local function isOpen(wep)
	if not validEnt(wep) or type(wep.GetCustomize) ~= "function" then return false end
	return wep:GetCustomize() == true
end

-- SetScopeLevel(0) then ToggleCustomize. The order matters: a scoped weapon
-- treats C as peek, and ToggleCustomize refuses to open during a runaway burst
-- after the scope call. The returned bool is the weapon's state afterwards.
local function apply(wep, want)
	if not validEnt(wep) then return false end
	if type(wep.SetScopeLevel) == "function" then wep:SetScopeLevel(0) end
	want = want == true
	if type(wep.ToggleCustomize) == "function" then
		wep:ToggleCustomize(want)
	elseif type(wep.SetCustomize) == "function" then
		wep:SetCustomize(want)
	end
	return isOpen(wep)
end

local function ack(ply, open, reason)
	if not (BALLISTICS.Net and BALLISTICS.Net.Send) then return end
	BALLISTICS.Net.Send("bal_customize_ack", ply, {
		open = open == true,
		reason = type(reason) == "string" and reason or "",
	})
end

local function tell(ply, reason)
	local text = BALLISTICS.CKey.ReasonText(reason)
	if not text or type(ply.ChatPrint) ~= "function" then return end
	ply:ChatPrint("Ballistics: " .. text)
end

function BALLISTICS.Customize.Strip(ply, cmd)
	if TacRP == nil or TacRP.IN_CUSTOMIZE == nil then return end
	if cmd == nil or type(cmd.RemoveKey) ~= "function" then return end
	if ply ~= nil and type(ply.IsValid) == "function" and ply:IsValid() == false then return end
	cmd:RemoveKey(TacRP.IN_CUSTOMIZE)
end

function BALLISTICS.Customize.CloseWeapon(ply, wep, reason)
	if not isOpen(wep) then return false end
	apply(wep, false)
	ack(ply, false, reason or "")
	return true
end

function BALLISTICS.Customize.CloseActive(ply, reason)
	return BALLISTICS.Customize.CloseWeapon(ply, activeTac(ply), reason)
end

function BALLISTICS.Customize.Request(ply, want)
	if not validEnt(ply) then return false, "player" end
	local id = playerId(ply) or tostring(ply)
	local now = (CurTime and CurTime()) or 0
	local fire, state = BALLISTICS.CKey.Press(presses[id], now, true)
	presses[id] = state
	if not fire then return false, "debounce" end

	want = want == true
	local wep = activeTac(ply)
	local allowed, reason = BALLISTICS.CKey.Allow({
		want = want,
		phase = phaseOf(),
		alive = isAlive(ply),
		hasWeapon = wep ~= nil,
		inZone = inZone(ply),
	})
	if not allowed then
		if wep and isOpen(wep) then apply(wep, false) end
		ack(ply, false, reason)
		tell(ply, reason)
		return false, reason
	end
	if not want then
		if wep then apply(wep, false) end
		ack(ply, false, "")
		return true
	end
	if not wep then
		ack(ply, false, "weapon")
		tell(ply, "weapon")
		return false, "weapon"
	end
	local opened = apply(wep, true)
	ack(ply, opened, "")
	if not opened then return false, "busy" end
	return true
end

local function eachPly(fn)
	local seen = {}
	local function one(ply)
		if ply == nil or seen[ply] then return end
		seen[ply] = true
		if not validEnt(ply) then return end
		fn(ply)
	end
	if BALLISTICS.Player and type(BALLISTICS.Player.Each) == "function" then
		BALLISTICS.Player.Each(one)
	end
	if player and type(player.GetAll) == "function" then
		local all = player.GetAll()
		if type(all) == "table" then
			for i = 1, #all do one(all[i]) end
		end
	end
end

function BALLISTICS.Customize.Monitor()
	local phase = phaseOf()
	eachPly(function(ply)
		local wep = activeTac(ply)
		if not wep or not isOpen(wep) then return end
		local must, why = BALLISTICS.CKey.MustClose({
			open = true,
			alive = isAlive(ply),
			hasWeapon = true,
			inZone = inZone(ply),
			phase = phase,
			weaponChanged = false,
		})
		if must then BALLISTICS.Customize.CloseWeapon(ply, wep, why) end
	end)
end

if hook and hook.Add then
	hook.Add("StartCommand", "Ballistics_StripCustomize", function(ply, cmd)
		BALLISTICS.Customize.Strip(ply, cmd)
	end)

	hook.Add("PlayerDeath", "Ballistics_CustomizeDeath", function(ply)
		BALLISTICS.Customize.CloseActive(ply, "dead")
	end)

	hook.Add("PlayerSwitchWeapon", "Ballistics_CustomizeSwitch", function(ply, oldWep, newWep)
		if oldWep ~= nil and oldWep ~= newWep then
			BALLISTICS.Customize.CloseWeapon(ply, oldWep, "switch")
		end
	end)

	hook.Add("Ballistics_PhaseChanged", "Ballistics_CustomizePhase", function(oldPhase, newPhase)
		if not BALLISTICS.CKey.PhaseCloses(oldPhase, newPhase, true) then return end
		eachPly(function(ply)
			local wep = activeTac(ply)
			if wep and isOpen(wep) then
				BALLISTICS.Customize.CloseWeapon(ply, wep, "phase")
			end
		end)
	end)

	hook.Add("PlayerDisconnected", "Ballistics_CustomizeForget", function(ply)
		local id = playerId(ply)
		if id then presses[id] = nil end
	end)

	local nextAt = 0
	hook.Add("Think", "Ballistics_CustomizeZone", function()
		local now = (CurTime and CurTime()) or 0
		if now < nextAt then return end
		local rate = BALLISTICS.Config and tonumber(BALLISTICS.Config.TickRate) or 0.1
		if not finite(rate) or rate <= 0 then rate = 0.1 end
		nextAt = now + rate
		BALLISTICS.Customize.Monitor()
	end)
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_customize", function(ply, payload)
		local want = false
		if type(payload) == "table" then want = payload.want == true end
		BALLISTICS.Customize.Request(ply, want)
	end, {
		rate = 8,
		read = function()
			return { want = net.ReadBool() == true }
		end,
	})

	BALLISTICS.Net.Register("bal_customize_ack", nil, {
		write = function(payload)
			payload = payload or {}
			net.WriteBool(payload.open == true)
			local reason = payload.reason
			if type(reason) ~= "string" then reason = "" end
			net.WriteString(reason)
		end,
	})
end
