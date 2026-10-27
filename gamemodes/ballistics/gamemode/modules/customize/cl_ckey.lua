-- Client C key. +menu_context is an edge here, then a request to the server.
-- Hook order against TacRP's PlayerBindPress is not reliable, so Think also
-- watches the key and TacRP.KeyPressed_Customize. StartCommand on this realm
-- strips TacRP.IN_CUSTOMIZE before predicted weapon Think.
-- BUY: the ack swaps the buy wheel and the attachment menu.

BALLISTICS = BALLISTICS or {}
BALLISTICS.CKeyClient = BALLISTICS.CKeyClient or {}

local pressState
local wasDown = false
local bindHeld = false
local attOpen = false
local closeSent = false
local seenPhase
local lastWep

local function valid(ent)
	if ent == nil or ent == false then return false end
	local kind = type(ent)
	if kind == "table" and type(ent.IsValid) == "function" then
		return ent:IsValid() == true
	end
	if kind ~= "table" and IsValid then return IsValid(ent) == true end
	return kind == "table" or kind == "Panel"
end

local function localPly()
	if not LocalPlayer then return nil end
	local ply = LocalPlayer()
	if ply == nil then return nil end
	if type(ply.IsValid) == "function" and ply:IsValid() == false then return nil end
	return ply
end

local function clientPhase()
	local ply = localPly()
	if ply and type(ply.GetNW2String) == "function" then
		local p = ply:GetNW2String("bal_phase", "")
		if type(p) == "string" and p ~= "" then return p end
	end
	return "lobby"
end

local function isAlive(ply)
	if ply == nil or type(ply.Alive) ~= "function" then return false end
	return ply:Alive() == true
end

local function activeTac()
	local ply = localPly()
	if ply == nil or type(ply.GetActiveWeapon) ~= "function" then return nil end
	local wep = ply:GetActiveWeapon()
	if not valid(wep) or wep.ArcticTacRP ~= true then return nil end
	return wep
end

local function inZone(ply)
	if ply == nil or not (BALLISTICS.CKey and BALLISTICS.CKey.InRadius) then return false end
	local teamId
	if type(ply.Team) == "function" then teamId = ply:Team() end
	local snap
	if BALLISTICS.Spawns and type(BALLISTICS.Spawns.Snapshot) == "function" then
		snap = BALLISTICS.Spawns.Snapshot()
	end
	local flag = BALLISTICS.CKey.FlagPos(snap, teamId)
	local pos
	if type(ply.GetPos) == "function" then pos = ply:GetPos() end
	local radius = BALLISTICS.Config and BALLISTICS.Config.CustomizeRadius
	return BALLISTICS.CKey.InRadius(pos, flag, radius)
end

local function menuOpen(wep)
	if attOpen then return true end
	if wep and type(wep.GetCustomize) == "function" and wep:GetCustomize() == true then
		return true
	end
	return false
end

local function send(want)
	if not net or not net.Start or not net.SendToServer then return end
	net.Start("bal_customize")
	net.WriteBool(want == true)
	net.SendToServer()
end

local function hideWheel()
	local wheel = BALLISTICS.BuyWheel
	if wheel and type(wheel.Hide) == "function" then wheel.Hide() end
end

local function showWheel()
	local wheel = BALLISTICS.BuyWheel
	if not wheel or type(wheel.Open) ~= "function" then return end
	if type(wheel.IsOpen) ~= "function" or wheel.IsOpen() ~= true then
		wheel.Open()
	end
	-- TacRP's RemoveCustomizeHUD turns the clicker off. The wheel needs it back.
	if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(true) end
end

local function ensureHud(wep)
	if not wep or type(wep.CreateCustomizeHUD) ~= "function" then return end
	if valid(wep.CustomizeHUD) then return end
	wep:CreateCustomizeHUD()
end

local function removeHud(wep)
	if not wep or type(wep.RemoveCustomizeHUD) ~= "function" then return end
	if not valid(wep.CustomizeHUD) then return end
	wep:RemoveCustomizeHUD()
end

-- Hide the wheel before creating the TacRP panel: Hide clears the clicker,
-- and CreateCustomizeHUD turns it on again for the attachment screen.
local function syncVisual(open)
	local phase = clientPhase()
	local wep = activeTac()
	if open then
		if phase == "buy" then hideWheel() end
		ensureHud(wep)
	else
		removeHud(wep)
		if lastWep and lastWep ~= wep then removeHud(lastWep) end
		if phase == "buy" then showWheel() end
	end
	attOpen = open == true
end

-- Code of +menu_context. Fallback is KEY_C when the bind lookup is empty.
function BALLISTICS.CKeyClient.KeyCode()
	local fallback = KEY_C
	if type(fallback) ~= "number" or fallback <= 0 then fallback = 13 end
	if input and type(input.LookupBinding) == "function" and type(input.GetKeyCode) == "function" then
		local name = input.LookupBinding("+menu_context")
		if type(name) == "string" and name ~= "" then
			local code = input.GetKeyCode(name)
			if type(code) == "number" and code > 0 then return code end
		end
	end
	return fallback
end

function BALLISTICS.CKeyClient.Press(now)
	if not (BALLISTICS.CKey and BALLISTICS.CKey.Press) then return false end
	local fire, state = BALLISTICS.CKey.Press(pressState, now, true)
	pressState = state
	if not fire then return false end
	-- The loot popup owns the keyboard. Close own inventory before the request
	-- so the server is not asked while that window is up, and the menu can show.
	local loot = BALLISTICS.Loot
	if loot and type(loot.CloseSelf) == "function" then loot.CloseSelf() end
	local wep = activeTac()
	local open = menuOpen(wep)
	local phase = clientPhase()
	local want
	if phase == "buy" then
		local _, att = BALLISTICS.CKey.BuySwap(open)
		want = att == true
	else
		want = BALLISTICS.CKey.NextOpen(open) == true
	end
	send(want)
	return true
end

function BALLISTICS.CKeyClient.ContextDown()
	if input and type(input.IsKeyDown) == "function" and type(input.LookupBinding) == "function" and type(input.GetKeyCode) == "function" then
		local name = input.LookupBinding("+menu_context")
		if type(name) == "string" and name ~= "" then
			local code = input.GetKeyCode(name)
			if code and input.IsKeyDown(code) == true then return true end
		end
	end
	if TacRP and TacRP.KeyPressed_Customize == true then return true end
	return false
end

function BALLISTICS.CKeyClient.NoteKey(down, now)
	local rising = down == true and not wasDown
	wasDown = down == true
	if not rising then return false end
	return BALLISTICS.CKeyClient.Press(now) == true
end

function BALLISTICS.CKeyClient.Ack(payload)
	if type(payload) ~= "table" then return end
	closeSent = false
	syncVisual(payload.open == true)
end

function BALLISTICS.CKeyClient.Monitor()
	local phase = clientPhase()
	local wep = activeTac()
	local open = menuOpen(wep)
	local changed = false
	if lastWep ~= nil and lastWep ~= wep then changed = true end
	local prev = seenPhase
	local edge = prev ~= nil and prev ~= phase
	seenPhase = phase

	local function shut()
		if closeSent then return end
		closeSent = true
		send(false)
		syncVisual(false)
	end

	if edge and open and BALLISTICS.CKey.PhaseCloses(prev, phase, true) then
		shut()
		if wep then lastWep = wep end
		return
	end

	if open then
		local must = BALLISTICS.CKey.MustClose({
			open = true,
			alive = isAlive(localPly()),
			hasWeapon = wep ~= nil,
			inZone = inZone(localPly()),
			phase = phase,
			weaponChanged = changed,
		})
		if must then shut() end
	else
		closeSent = false
	end
	if wep then lastWep = wep end
end

if CLIENT and BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_customize_ack", function(payload)
		BALLISTICS.CKeyClient.Ack(payload)
	end, {
		read = function()
			return { open = net.ReadBool() == true, reason = net.ReadString() }
		end,
	})
end

if CLIENT and hook and hook.Add then
	hook.Add("StartCommand", "Ballistics_StripCustomizeClient", function(ply, cmd)
		if BALLISTICS.Customize and type(BALLISTICS.Customize.Strip) == "function" then
			BALLISTICS.Customize.Strip(ply, cmd)
			return
		end
		if TacRP == nil or TacRP.IN_CUSTOMIZE == nil then return end
		if cmd ~= nil and type(cmd.RemoveKey) == "function" then
			cmd:RemoveKey(TacRP.IN_CUSTOMIZE)
		end
	end)

	hook.Add("PlayerBindPress", "Ballistics_CKey", function(ply, bind, pressed)
		if type(bind) ~= "string" or string.lower(bind) ~= "+menu_context" then return end
		local me = localPly()
		if me ~= nil and ply ~= nil and ply ~= me then return end
		if pressed == true then
			if not bindHeld then
				bindHeld = true
				local now = (CurTime and CurTime()) or 0
				BALLISTICS.CKeyClient.Press(now)
			end
		else
			bindHeld = false
		end
		return true
	end)

	hook.Add("Think", "Ballistics_CKey", function()
		local now = (CurTime and CurTime()) or 0
		-- Poll the key even while a loot window is open. MakePopup holds focus,
		-- so PlayerBindPress does not run; IsKeyDown still can, and the panel
		-- key handler is the path when focus swallows IsKeyDown.
		BALLISTICS.CKeyClient.NoteKey(BALLISTICS.CKeyClient.ContextDown(), now)
		BALLISTICS.CKeyClient.Monitor()
	end)
end
