-- C key: edge, debounce, zone permission, buy-wheel swap, server toggle.
-- Run: luajit tests/test_ckey.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/modules/customize/sh_ckey.lua")

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

local pure = readAll("gamemodes/ballistics/gamemode/modules/customize/sh_ckey.lua")
check("ckey logic does not touch the game", not pure:find("hook.Add", 1, true)
	and not pure:find("net.Start", 1, true)
	and not pure:find("ents.Create", 1, true)
	and not pure:find("LocalPlayer", 1, true))

local C = BALLISTICS.CKey
local state
local fire
fire, state = C.Press(nil, 0, false)
check("a release is not an edge", fire == false and state.last == nil)
fire, state = C.Press(state, 0, true)
check("a press is an edge", fire == true and state.last == 0)
fire, state = C.Press(state, 0.24, true)
check("a second press inside 0.25s is dropped", fire == false and state.last == 0)
fire, state = C.Press(state, 0.25, true)
check("a press at 0.25s is accepted", fire == true and state.last == 0.25)
fire, state = C.Press(state, "nope", true)
check("a bad clock is not an edge", fire == false and state.last == 0.25)
check("closed wants open", C.NextOpen(false) == true and C.NextOpen(nil) == true)
check("open wants closed", C.NextOpen(true) == false)
check("own inventory hands the customize key off", C.InventoryHandoff(true, 13, 13) == true)
check("someone else's loot does not hand off", C.InventoryHandoff(false, 13, 13) == false and C.InventoryHandoff(nil, 13, 13) == false)
check("a different key does not hand off", C.InventoryHandoff(true, 5, 13) == false)
check("a missing customize code does not hand off", C.InventoryHandoff(true, 13, 0) == false and C.InventoryHandoff(true, 13, nil) == false)

local wheel, att = C.BuySwap(false)
check("C during buy hides the wheel and opens attachments", wheel == false and att == true)
wheel, att = C.BuySwap(true)
check("C again reopens the wheel and closes attachments", wheel == true and att == false)

local function allow(over)
	local ctx = {
		want = true,
		phase = "live",
		alive = true,
		hasWeapon = true,
		inZone = true,
	}
	for k, v in pairs(over or {}) do ctx[k] = v end
	return C.Allow(ctx)
end

local ok, err = allow(nil)
check("live inside the zone may open", ok == true and err == nil)
ok, err = allow({ inZone = false })
check("live outside the zone opens view-only", ok == true and C.CanEdit({ phase = "live", inZone = false }) == false and C.CanEdit({ phase = "buy" }) == true)
check("zone text is the objective line", C.ReasonText("zone") == "Only at your objective")
ok, err = allow({ phase = "buy", inZone = false })
check("buy may open away from the flag", ok == true)
ok, err = allow({ phase = "buy", inZone = true, inventory = true })
check("buy in the zone may open while inventory is open", ok == true and err == nil)
ok, err = allow({ phase = "lobby" })
check("lobby opens view-only", ok == true and C.CanEdit({ phase = "lobby" }) == false)
ok, err = allow({ phase = "post" })
check("post opens view-only", ok == true and C.CanEdit({ phase = "post" }) == false)
ok, err = allow({ alive = false })
check("a dead player cannot open", ok == false and err == "dead")
ok, err = allow({ hasWeapon = false })
check("no TacRP weapon cannot open", ok == false and err == "weapon")
ok, err = C.Allow({ want = false, phase = "lobby", alive = false, hasWeapon = false, inZone = false })
check("closing is always allowed", ok == true)
check("a missing context cannot open", C.Allow(nil) == false)

local function must(over)
	local ctx = {
		open = true,
		alive = true,
		hasWeapon = true,
		inZone = true,
		phase = "live",
		weaponChanged = false,
	}
	for k, v in pairs(over or {}) do ctx[k] = v end
	return C.MustClose(ctx)
end

ok, err = must(nil)
check("an open menu in the live zone stays", ok == false)
ok, err = must({ inZone = false })
check("leaving the zone keeps the menu open (view-only)", ok == false and C.CanEdit({ phase = "live", inZone = false }) == false)
ok, err = must({ phase = "buy", inZone = false })
check("buy ignores the zone", ok == false)
ok, err = must({ phase = "post" })
check("post keeps the menu open (view-only)", ok == false)
ok, err = must({ alive = false })
check("death must close", ok == true and err == "dead")
ok, err = must({ weaponChanged = true })
check("a weapon switch must close", ok == true and err == "switch")
ok, err = must({ hasWeapon = false })
check("losing the weapon must close", ok == true and err == "weapon")
check("a closed menu is left alone", must({ open = false }) == false)
check("any phase change closes an open menu", C.PhaseCloses("buy", "live", true) == true)
check("the same phase does not close", C.PhaseCloses("live", "live", true) == false)
check("a closed menu ignores the phase change", C.PhaseCloses("buy", "live", false) == false)

local radius = 100
check("the boundary is inside", C.InRadius({ x = 100, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, radius) == true)
check("just outside is out", C.InRadius({ x = 101, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }, radius) == false)
check("height counts", C.InRadius({ x = 0, y = 0, z = 150 }, { x = 0, y = 0, z = 0 }, radius) == false)
check("a short height is inside", C.InRadius({ x = 0, y = 0, z = 50 }, { x = 0, y = 0, z = 0 }, radius) == true)
check("a missing flag is outside", C.InRadius({ x = 0, y = 0, z = 0 }, nil, radius) == false)
local ax, ay, az = C.Coords({ 3, 4, 5 })
check("slot coordinates work", ax == 3 and ay == 4 and az == 5)

local snap = {
	good = { pos = { x = 1, y = 2, z = 3 } },
	bad = { pos = { x = 9, y = 8, z = 7 } },
}
local good = C.FlagPos(snap, 1)
local bad = C.FlagPos(snap, "bad")
check("team 1 uses the good flag", good.x == 1 and good.z == 3)
check("team 2 uses the bad flag", bad.x == 9 and bad.z == 7)
check("a spectator has no flag", C.FlagPos(snap, 1002) == nil)

-- Server toggle. Players are tables here; the module only calls methods.
dofile("gamemodes/ballistics/gamemode/modules/customize/sv_customize.lua")

local phaseName = "live"
BALLISTICS.Round = { Phase = function() return phaseName end }
local flags = {
	good = { pos = { x = 0, y = 0, z = 0 } },
	bad = { pos = { x = 1000, y = 0, z = 0 } },
}
BALLISTICS.Spawns = { Snapshot = function() return flags end }
BALLISTICS.Config.CustomizeRadius = radius

local now = 0
CurTime = function() return now end

local roster = {}
player.GetAll = function() return roster end

local function makeWep()
	local wep = { ArcticTacRP = true, custom = false, scope = nil, order = {}, block = false }
	function wep:IsValid() return true end
	function wep:SetScopeLevel(n)
		self.scope = n
		self.order[#self.order + 1] = "scope"
	end
	function wep:ToggleCustomize(on)
		self.order[#self.order + 1] = "toggle"
		if on == true and self.block then return end
		if on == self.custom then return end
		self.custom = on == true
	end
	function wep:GetCustomize() return self.custom == true end
	return wep
end

local function makePly(id, teamId)
	local ply = {
		alive = true,
		teamId = teamId,
		pos = { x = 0, y = 0, z = 0 },
		chats = {},
		wep = nil,
	}
	function ply:IsValid() return true end
	function ply:SteamID64() return id end
	function ply:Alive() return self.alive == true end
	function ply:Team() return self.teamId end
	function ply:GetPos() return self.pos end
	function ply:GetActiveWeapon() return self.wep end
	function ply:ChatPrint(text) self.chats[#self.chats + 1] = text end
	return ply
end

local ply = makePly("76561198000000021", 1)
ply.wep = makeWep()
roster[1] = ply

ok, err = BALLISTICS.Customize.Request(ply, true)
check("server opens inside the radius", ok == true and err == nil and ply.wep.custom == true)
check("scope is cleared before the toggle", ply.wep.order[1] == "scope" and ply.wep.order[2] == "toggle" and ply.wep.scope == 0)

now = 0.1
ok, err = BALLISTICS.Customize.Request(ply, false)
check("server drops a tap inside the debounce", ok == false and err == "debounce" and ply.wep.custom == true and #ply.chats == 0)

now = 0.25
ok = BALLISTICS.Customize.Request(ply, false)
check("server closes on the next tap", ok == true and ply.wep.custom == false)

now = 1
ply.pos = { x = 150, y = 0, z = 0 }
ply.chats = {}
ok, err = BALLISTICS.Customize.Request(ply, true)
check("server opens live outside the radius view-only", ok == true and ply.wep.custom == true)
check("no refusal message for view-only", ply.chats[1] == nil)

now = 2
ply.pos = { x = 100, y = 0, z = 0 }
ok = BALLISTICS.Customize.Request(ply, true)
check("server treats the boundary as inside", ok == true and ply.wep.custom == true)

now = 3
BALLISTICS.Customize.Request(ply, false)
ply.pos = { x = 0, y = 0, z = 150 }
now = 4
ok, err = BALLISTICS.Customize.Request(ply, true)
check("height does not stop a view-only open", ok == true)

ply.pos = { x = 0, y = 0, z = 50 }
now = 5
ok = BALLISTICS.Customize.Request(ply, true)
check("server allows a short height", ok == true and ply.wep.custom == true)

now = 6
BALLISTICS.Customize.Request(ply, false)
ply.pos = { x = 1000, y = 0, z = 0 }
now = 7
ok, err = BALLISTICS.Customize.Request(ply, true)
check("the other team's flag opens view-only", ok == true and C.CanEdit({ phase = "live", inZone = false }) == false)

phaseName = "buy"
now = 8
ok = BALLISTICS.Customize.Request(ply, true)
check("buy opens away from the flag", ok == true and ply.wep.custom == true)

now = 8.25
BALLISTICS.Customize.Request(ply, false)
ply.pos = { x = 0, y = 0, z = 0 }
now = 8.5
ok, err = BALLISTICS.Customize.Request(ply, true)
check("buy inside the zone opens", ok == true and err == nil and ply.wep.custom == true)

hook.Run("Ballistics_PhaseChanged", "buy", "live")
check("a phase change force-closes", ply.wep.custom == false)

phaseName = "live"
ply.pos = { x = 0, y = 0, z = 0 }
now = 9
BALLISTICS.Customize.Request(ply, true)
ply.pos = { x = 400, y = 0, z = 0 }
BALLISTICS.Customize.Monitor()
check("walking out keeps it open (view-only)", ply.wep.custom == true)

ply.pos = { x = 0, y = 0, z = 0 }
now = 10
BALLISTICS.Customize.Request(ply, true)
hook.Run("PlayerDeath", ply)
check("death force-closes", ply.wep.custom == false)

now = 11
BALLISTICS.Customize.Request(ply, true)
local other = makeWep()
hook.Run("PlayerSwitchWeapon", ply, ply.wep, other)
check("switching weapons force-closes the old one", ply.wep.custom == false and other.custom == false)

now = 12
ply.alive = false
ply.chats = {}
ok, err = BALLISTICS.Customize.Request(ply, true)
check("server refuses a dead player", ok == false and err == "dead" and ply.chats[1] == "Ballistics: You are not alive.")

ply.alive = true
local saved = ply.wep
ply.wep = nil
now = 13
ok, err = BALLISTICS.Customize.Request(ply, true)
check("server refuses with no weapon", ok == false and err == "weapon")
ply.wep = { ArcticTacRP = false }
function ply.wep:IsValid() return true end
now = 14
ok, err = BALLISTICS.Customize.Request(ply, true)
check("server refuses a weapon that is not TacRP", ok == false and err == "weapon")
ply.wep = saved

phaseName = "post"
now = 15
ok, err = BALLISTICS.Customize.Request(ply, true)
check("server opens post view-only", ok == true)

phaseName = "lobby"
now = 16
ok, err = BALLISTICS.Customize.Request(ply, true)
check("server opens lobby view-only", ok == true)

local spec = makePly("76561198000000022", 1002)
spec.wep = makeWep()
phaseName = "live"
now = 17
ok, err = BALLISTICS.Customize.Request(spec, true)
check("a spectator with a weapon opens view-only", ok == true)

ply.wep.block = true
ply.wep.custom = false
ply.pos = { x = 0, y = 0, z = 0 }
now = 18
ok, err = BALLISTICS.Customize.Request(ply, true)
check("a toggle that does not open is not reported open", ok == false and err == "busy" and ply.wep.custom == false)
ply.wep.block = false

TacRP = { IN_CUSTOMIZE = 12345 }
local removed
local cmd = { RemoveKey = function(_, key) removed = key end }
hook.Run("StartCommand", ply, cmd)
check("StartCommand strips TacRP.IN_CUSTOMIZE", removed == 12345)
local ghost = { IsValid = function() return false end }
removed = nil
BALLISTICS.Customize.Strip(ghost, cmd)
check("an invalid player is not rewritten", removed == nil)
local savedTac = TacRP
TacRP = nil
removed = nil
BALLISTICS.Customize.Strip(ply, cmd)
check("without TacRP the command is untouched", removed == nil)
TacRP = savedTac

local glue = readAll("gamemodes/ballistics/gamemode/modules/customize/sv_customize.lua")
	.. readAll("gamemodes/ballistics/gamemode/modules/customize/cl_ckey.lua")
check("customize glue does not spawn entities", not glue:find("ents.Create", 1, true) and not glue:find("ents.Spawn", 1, true))
check("customize glue does not hook ShowTeam", not glue:find("ShowTeam", 1, true))
check("customize glue does not hook GUIMouseWheeled", not glue:find("GUIMouseWheeled", 1, true))
check("client wheel file compiles", loadfile("gamemodes/ballistics/gamemode/modules/customize/cl_ckey.lua") ~= nil)

-- Client edge, ack, and the buy-wheel swap.
CLIENT = true
dofile("gamemodes/ballistics/gamemode/modules/customize/cl_ckey.lua")

local clock = 100
CurTime = function() return clock end
player.GetAll = function() return {} end

local log = {}
local wheelOpen = true
BALLISTICS.BuyWheel = {
	IsOpen = function() return wheelOpen end,
	Open = function()
		log[#log + 1] = "wheel-open"
		wheelOpen = true
		return true
	end,
	Hide = function()
		log[#log + 1] = "wheel-hide"
		wheelOpen = false
		return true
	end,
}
gui = {
	EnableScreenClicker = function(on)
		log[#log + 1] = on and "click-on" or "click-off"
	end,
}

local cwep = { ArcticTacRP = true, custom = false, created = 0, removed = 0 }
function cwep:IsValid() return true end
function cwep:GetCustomize() return self.custom == true end
function cwep:CreateCustomizeHUD()
	self.created = self.created + 1
	self.CustomizeHUD = {}
	function self.CustomizeHUD:IsValid() return true end
	log[#log + 1] = "hud-create"
end
function cwep:RemoveCustomizeHUD()
	self.removed = self.removed + 1
	self.CustomizeHUD = nil
	log[#log + 1] = "hud-remove"
end

local cp = {
	phase = "buy",
	alive = true,
	teamId = 1,
	pos = { x = 0, y = 0, z = 0 },
	wep = cwep,
}
function cp:IsValid() return true end
function cp:GetNW2String(key, default)
	if key == "bal_phase" then return self.phase end
	return default or ""
end
function cp:Alive() return self.alive == true end
function cp:Team() return self.teamId end
function cp:GetPos() return self.pos end
function cp:GetActiveWeapon() return self.wep end
LocalPlayer = function() return cp end

local sent = {}
function net.Start(name)
	sent[#sent + 1] = { name = name }
end
function net.WriteBool(v)
	sent[#sent].want = v
end
function net.SendToServer()
	sent[#sent].sent = true
end

local keyDown = false
input = {
	LookupBinding = function(bind)
		if bind == "+menu_context" then return "c" end
		return nil
	end,
	GetKeyCode = function() return 11 end,
	IsKeyDown = function() return keyDown end,
}
TacRP.KeyPressed_Customize = false

local function release()
	keyDown = false
	TacRP.KeyPressed_Customize = false
	hook.Run("PlayerBindPress", cp, "+menu_context", false)
	hook.Run("Think")
end

keyDown = true
local before = #sent
local blocked = hook.Run("PlayerBindPress", cp, "+menu_context", true)
hook.Run("Think")
check("C is swallowed", blocked == true)
check("bind and think send one open request", #sent == before + 1 and sent[#sent].name == "bal_customize" and sent[#sent].want == true and sent[#sent].sent == true)
hook.Run("PlayerBindPress", cp, "+menu_context", true)
hook.Run("Think")
check("holding C does not send again", #sent == before + 1)
check("attack is not swallowed", hook.Run("PlayerBindPress", cp, "+attack", true) == nil)

release()
check("the release sends nothing", #sent == before + 1)

BALLISTICS.CKeyClient.Ack({ open = true })
check("buy ack hides the wheel and builds a missing panel", log[#log] == "hud-create" and log[#log - 1] == "wheel-hide" and cwep.created == 1 and wheelOpen == false)

clock = 100.25
keyDown = true
hook.Run("PlayerBindPress", cp, "+menu_context", true)
check("the next press asks to close attachments", sent[#sent].want == false)

local mark = #log
BALLISTICS.CKeyClient.Ack({ open = false })
check("closing attachments removes the panel", log[mark + 1] == "hud-remove" and cwep.CustomizeHUD == nil)
check("closing attachments reopens the wheel", log[mark + 2] == "wheel-open" and wheelOpen == true)
check("closing attachments re-enables the screen clicker", log[mark + 3] == "click-on")

release()
local kept = {}
function kept:IsValid() return true end
cwep.CustomizeHUD = kept
cwep.created = 0
BALLISTICS.CKeyClient.Ack({ open = true })
check("an existing panel is not rebuilt", cwep.created == 0 and cwep.CustomizeHUD == kept)

release()
BALLISTICS.CKeyClient.Ack({ open = false })
cwep.CustomizeHUD = nil

-- TacRP's bind hook can run first and swallow ours. The flag is the backup.
clock = 101
release()
TacRP.KeyPressed_Customize = true
before = #sent
hook.Run("Think")
check("the TacRP customize flag still sends one request", #sent == before + 1 and sent[#sent].want == true)
hook.Run("Think")
check("a held TacRP flag does not repeat", #sent == before + 1)
TacRP.KeyPressed_Customize = false
release()

clock = 102
keyDown = true
hook.Run("Think")
local opened = #sent
clock = 102.1
keyDown = false
hook.Run("Think")
keyDown = true
hook.Run("Think")
check("a second tap inside 0.25s does not send", #sent == opened)

release()
cp.phase = "live"
cp.pos = { x = 0, y = 0, z = 0 }
cwep.custom = false
BALLISTICS.CKeyClient.Ack({ open = false })
BALLISTICS.CKeyClient.Monitor()
cwep.custom = true
BALLISTICS.CKeyClient.Ack({ open = true })
BALLISTICS.CKeyClient.Monitor()
cp.pos = { x = 500, y = 0, z = 0 }
before = #sent
local logs = #log
BALLISTICS.CKeyClient.Monitor()
check("leaving the zone does not ask the server to close", #sent == before)
check("leaving the zone keeps the local panel", cwep.CustomizeHUD ~= nil)

release()
cp.phase = "buy"
cp.pos = { x = 0, y = 0, z = 0 }
cp.wep = cwep
cwep.custom = false
BALLISTICS.CKeyClient.Ack({ open = false })
BALLISTICS.CKeyClient.Monitor()
cwep.custom = true
BALLISTICS.CKeyClient.Ack({ open = true })
BALLISTICS.CKeyClient.Monitor()
local switched = { ArcticTacRP = true }
function switched:IsValid() return true end
function switched:GetCustomize() return false end
function switched:RemoveCustomizeHUD() end
cp.wep = switched
before = #log
BALLISTICS.CKeyClient.Monitor()
check("a weapon switch during buy reopens the wheel", wheelOpen == true)
local reopened = false
for i = before + 1, #log do
	if log[i] == "wheel-open" then reopened = true end
end
check("the switch close is what reopened the wheel", reopened == true)

cp.wep = cwep
cp.phase = "buy"
cwep.custom = false
BALLISTICS.CKeyClient.Ack({ open = false })
BALLISTICS.CKeyClient.Monitor()
wheelOpen = false
cwep.custom = true
BALLISTICS.CKeyClient.Ack({ open = true })
BALLISTICS.CKeyClient.Monitor()
cp.phase = "live"
before = #log
BALLISTICS.CKeyClient.Monitor()
local wheeled = false
for i = before + 1, #log do
	if log[i] == "wheel-open" then wheeled = true end
end
check("leaving buy closes attachments and does not force the wheel", cwep.CustomizeHUD == nil and wheeled == false)

local stripped
local ccmd = { RemoveKey = function(_, key) stripped = key end }
hook.Run("StartCommand", cp, ccmd)
check("the client command also loses the customize bit", stripped == TacRP.IN_CUSTOMIZE)

-- Own inventory is open. The poll still sends, and it closes that window first.
clock = 200
release()
cp.phase = "buy"
cp.pos = { x = 0, y = 0, z = 0 }
cwep.custom = false
BALLISTICS.CKeyClient.Ack({ open = false })
local sentAtClose
local closes = 0
BALLISTICS.Loot = BALLISTICS.Loot or {}
BALLISTICS.Loot.CloseSelf = function()
	closes = closes + 1
	sentAtClose = #sent
	return true
end
keyDown = true
before = #sent
hook.Run("Think")
check("the poll still sends while own inventory is open", #sent == before + 1 and sent[#sent].name == "bal_customize" and sent[#sent].want == true)
check("the poll closes own inventory before the request", closes == 1 and sentAtClose == before)
check("the customize key code follows the bind", BALLISTICS.CKeyClient.KeyCode() == 11)

if failed then os.exit(1) end
