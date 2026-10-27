-- Throwables key and the keybind list. Run: luajit tests/test_keys.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/modules/keys/sh_keys.lua")

local pure = readAll("gamemodes/ballistics/gamemode/modules/keys/sh_keys.lua")
check("key logic does not touch the game", not pure:find("hook.Add", 1, true)
	and not pure:find("LocalPlayer", 1, true)
	and not pure:find("CreateClientConVar", 1, true))

local K = BALLISTICS.Keys
check("the throw key names", K.KeyName(K.KEY_4) == "4" and K.KeyName(K.KEY_G) == "G" and K.KeyName(K.KEY_F1) == "F1" and K.KeyName(12) == "B")
check("a dead backup is key none when nothing is down", K.DeadBackup(function() return false end) == 0)
check("a dead backup skips a key that reports down", K.DeadBackup(function(code) return code == 0 end) == 101)

local state = K.Step(nil, true, 0, false)
check("a press does not throw yet", state.down == true and state.ticks == 0 and state.menu == false)
state = K.Step(state, true, 0.2, false)
check("a short hold is not the menu", state.menu == false and state.ticks == 0)
state = K.Step(state, false, 0.24, false)
check("a tap arms three throw ticks", state.down == false and state.ticks == 3 and state.menu == false)
check("three ticks pulse and then stop", K.TakeTick(state) == true and K.TakeTick(state) == true and K.TakeTick(state) == true and K.TakeTick(state) == false)

state = K.Step(nil, true, 1, false)
state = K.Step(state, true, 1.25, false)
check("a hold opens the menu and clears a throw", state.menu == true and state.ticks == 0)
state = K.Step(state, false, 1.4, false)
check("releasing a hold does not throw", state.menu == false and state.ticks == 0)

state = K.Step(K.Step(nil, true, 2, false), false, 2.1, true)
check("typing cancels a release", state.ticks == 0 and state.down == false and state.menu == false)

local pulse = K.Intent({ pulsing = true, gDown = true, grenade1Bound = false })
check("a pulse is not stripped", pulse.add1 == true and pulse.strip == false)
local stripped = K.Intent({ gDown = true, grenade1Bound = false })
check("G is stripped when it is only the fallback", stripped.strip == true and stripped.add1 == false)
local owned = K.Intent({ gDown = true, grenade1Bound = true, pulsing = true })
check("a real grenade bind is not stripped", owned.strip == false and owned.add1 == true)
local doubled = K.Intent({ pulsing = true, menu = true, boundToThrow1 = true, boundToThrow2 = true })
check("the player's own binds are not fired twice", doubled.add1 == false and doubled.add2 == false)
local menu = K.Intent({ menu = true })
check("a hold adds the menu button", menu.add2 == true and menu.add1 == false)

local g1 = K.IN_GRENADE1
local g2 = K.IN_GRENADE2
local mixed = K.ApplyButtons(1 + g1 + g2, { strip = true, add2 = true })
check("strip removes only the quick throw", mixed == 1 + g2)
check("a pulse sets the quick throw", K.ApplyButtons(0, { add1 = true }) == g1)
check("a menu sets the grenade menu", K.ApplyButtons(4, { add2 = true }) == 4 + g2)

local function lookup(bind)
	if bind == "+grenade1" then return "4" end
	if bind == "+grenade2" then return "H" end
	return nil
end
local function codeOf(name)
	if name == "4" then return K.KEY_4 end
	if name == "h" or name == "H" then return K.KEY_H end
	return nil
end
check("the same bind is the throw key", K.SameBind("+grenade1", K.KEY_4, lookup, codeOf) == true)
check("a different bind is not the throw key", K.SameBind("+grenade2", K.KEY_4, lookup, codeOf) == false)
check("an unbound command is not the throw key", K.SameBind("+attack", K.KEY_4, lookup, codeOf) == false)

check("F1 is swallowed", K.BlockBind("gm_showhelp", K.KEY_4) == true)
check("slot4 is swallowed while the throw key is 4", K.BlockBind("slot4", K.KEY_4) == true)
check("slot4 is left alone for another throw key", K.BlockBind("slot4", K.KEY_G) == false)
check("attack is not swallowed", K.BlockBind("+attack", K.KEY_4) == false)

local rows = K.Rows({
	customize = "C",
	throw = "4",
	inspect = "G",
	blindfire = "MOUSE3",
	safety = "E",
	teams = "F2",
	med = "B",
})
check("the list has the real binds", #rows == 10 and rows[1].action == "Customize / buy wheel" and rows[2].key == "4" and rows[2].action == "Tap quick throw / hold menu" and rows[3].action == "Medical / self-inspect" and rows[4].key == "MOUSE3" and rows[4].action == "Blindfire menu" and rows[6].key == "F2" and rows[7].key == "1" and rows[7].action == "Knife" and rows[8].key == "2" and rows[8].action == "Gun" and rows[9].key == "3" and rows[9].action == "Gun" and rows[10].key == "B" and rows[10].action == "Medical wheel")
local noMed = K.Rows({ med = "" })
check("a missing medical wheel is left off the list", #noMed == 9)
check("slot keys are their own lines", noMed[7].key == "1" and noMed[7].action == "Knife" and noMed[8].action == "Gun" and noMed[9].action == "Gun")

local box = K.PanelBox(8, 640, 480, true)
check("the open list sits on the DrawHints anchor", box.x == 4 and box.y == math.floor(240 - box.h / 2) and box.h == 8 * 12 and box.w == 140)
local tag = K.PanelBox(8, 640, 480, false)
check("the collapsed tag is one row", tag.x == 4 and tag.h == 12 and tag.w == 70 and tag.y == math.floor(240 - 6))
check("spawn reveals the list and F1 closes it", K.ShowList(false, 1, K.NoteSpawn(0)) == true and K.ShowList(false, 4, K.NoteSpawn(0)) == false)
local pin, untilAt = K.ToggleList(false, 10, 0)
check("F1 pins a closed list", pin == true and K.ShowList(pin, 10, untilAt) == true)
pin, untilAt = K.ToggleList(true, 12, 99)
check("F1 closes the list and cancels the timer", pin == false and untilAt == 12 and K.ShowList(pin, 12, untilAt) == false)

local compiled = loadfile("gamemodes/ballistics/gamemode/modules/keys/cl_keys.lua")
check("the keys client compiles", compiled ~= nil)

local keys = {}
local binds = { ["+menu_context"] = "c", ["+use"] = "e", invnext = "mwheelup", slot1 = "slot1" }
local names = { [5] = "4", [17] = "g", [12] = "b", [92] = "f1" }
local codes = { ["4"] = 5, ["g"] = 17, ["h"] = 18 }
local convars = {}
local created = {}
local buttons = 0
local clock = 0
local typingNow = false
local alive = true
local className = "tacrp_ex_ak47"

function CurTime() return clock end
function CreateClientConVar(name, default, save, _, help)
	created[name] = { default = default, save = save == true, help = help or "" }
	convars[name] = tonumber(default) or default
end
function GetConVar(name)
	if convars[name] == nil then return nil end
	return {
		GetInt = function() return tonumber(convars[name]) or 0 end,
		SetInt = function(_, v) convars[name] = tonumber(v) or 0 end,
		GetString = function() return tostring(convars[name]) end,
	}
end
input = {
	IsKeyDown = function(code) return keys[code] == true end,
	LookupBinding = function(cmd) return binds[cmd] end,
	GetKeyCode = function(name) return codes[string.lower(tostring(name))] end,
	GetKeyName = function(code) return names[code] end,
}
function LocalPlayer()
	return {
		Alive = function() return alive end,
		IsTyping = function() return typingNow end,
		GetActiveWeapon = function()
			return { GetClass = function() return className end }
		end,
	}
end
local cmd = {
	GetButtons = function() return buttons end,
	SetButtons = function(_, value) buttons = value end,
}
TacRP = { GRENADE1_Backup = K.KEY_G }
convars.tacrp_hints = 1
convars.playerballistics_key_inspect = 17
convars.playerballistics_med_key = 12
hook.Add("CreateMove", "TacRP_CreateMove", function(c)
	if input.IsKeyDown(K.KEY_G) and not binds["+grenade1"] then
		c:SetButtons(c:GetButtons() + K.IN_GRENADE1)
	end
end)

CLIENT = true
dofile("gamemodes/ballistics/gamemode/modules/keys/cl_keys.lua")
check("the throw convar is archived on 4", created.bal_throw_key and created.bal_throw_key.default == "5" and created.bal_throw_key.save == true)
check("hints are forced off and the old value is kept for later", convars.tacrp_hints == 0)

local function move(at)
	clock = at
	buttons = 0
	hook.Run("CreateMove", cmd)
	return buttons
end

hook.Run("Think")
check("G is no longer the grenade backup", TacRP.GRENADE1_Backup == 0)
keys[K.KEY_G] = true
local gButtons = move(0)
check("holding G does not quick throw", gButtons == 0)
keys[K.KEY_G] = false

keys[K.KEY_4] = true
move(1)
keys[K.KEY_4] = false
check("a tap pulses the quick throw", move(1.1) == K.IN_GRENADE1)
check("the pulse lasts two more ticks", move(1.11) == K.IN_GRENADE1 and move(1.12) == K.IN_GRENADE1)
check("the pulse then stops", move(1.13) == 0)

keys[K.KEY_4] = true
move(2)
check("a hold opens the throwable menu", move(2.3) == K.IN_GRENADE2)
keys[K.KEY_4] = false
check("releasing the menu does not also throw", move(2.5) == 0)

binds["+grenade1"] = "4"
keys[K.KEY_4] = true
move(3)
keys[K.KEY_4] = false
check("a bound grenade key is not pulsed again", move(3.1) == 0)
binds["+grenade1"] = nil

hook.Run("Think")
check("the list is open just after spawn", BALLISTICS.Keys.ListOpen() == true)
local hinted = BALLISTICS.Keys.HintRows()
local medRow = hinted[#hinted]
check("hints read the live binds", hinted[1].key == "C" and hinted[2].key == "4" and hinted[3].key == "G" and hinted[4].key == "H" and hinted[5].key == "E" and hinted[6].key == "F2" and hinted[7].key == "1" and hinted[7].action == "Knife" and hinted[8].key == "2" and hinted[8].action == "Gun" and hinted[9].key == "3" and hinted[9].action == "Gun" and medRow.action == "Medical wheel" and medRow.key == "B")
clock = 10
hook.Run("Think")
check("the list collapses when the reveal ends", BALLISTICS.Keys.ListOpen() == false)
check("F1 is swallowed and opens the list", hook.Run("PlayerBindPress", nil, "gm_showhelp", true) == true and BALLISTICS.Keys.ListOpen() == true)
keys[K.KEY_F1] = false
hook.Run("Think")
check("F1 closes the list", hook.Run("PlayerBindPress", nil, "gm_showhelp", true) == true and BALLISTICS.Keys.ListOpen() == false)
check("slot4 is swallowed", hook.Run("PlayerBindPress", nil, "slot4", true) == true)
check("attack is not swallowed by the keys hook", hook.Run("PlayerBindPress", nil, "+attack", true) == nil)
convars.bal_throw_key = K.KEY_G
check("slot4 works again when the throw key is not 4", hook.Run("PlayerBindPress", nil, "slot4", true) == nil)
convars.bal_throw_key = K.KEY_4

className = "tacrp_mp5"
clock = 20
hook.Run("Think")
check("switching weapons reveals the list", BALLISTICS.Keys.ListOpen() == true)

convars.playerballistics_med_key = 0
local without = BALLISTICS.Keys.HintRows()
check("a med key of none drops the wheel line", #without == #hinted - 1)

local drawn = false
local texts = 0
surface = {
	SetDrawColor = function() end,
	DrawRect = function() drawn = true end,
	CreateFont = function() end,
}
draw = { SimpleText = function() texts = texts + 1 end }
function ScrW() return 640 end
function ScrH() return 480 end
TEXT_ALIGN_LEFT = 0
TEXT_ALIGN_CENTER = 1
hook.Run("HUDPaint")
check("the panel draws", drawn == true and texts > 0)

convars.tacrp_hints = 1
hook.Run("Think")
check("hints stay off while the gamemode runs", convars.tacrp_hints == 0)
hook.Run("ShutDown")
check("shutdown restores the hint convar", convars.tacrp_hints == 1)

do
	local fit = K.PanelBox(8, 1920, 1080, true, 200)
	check("panel hugs the widest line plus padding", fit.w == 200 + 2 * K.PAD)
	local tag = K.PanelBox(1, 1920, 1080, false, 60)
	check("tag hugs its text", tag.w == 60 + 2 * K.PAD)
	check("panel stays narrow on a wide screen", K.PanelBox(8, 3840, 2160, true, 300).w < 3840 * 0.2)
end

do
	local function has(rows, key, action)
		for _, r in ipairs(rows) do if r.key == key and r.action == action then return true end end
		return false
	end
	check("F2 teams listed", has(K.Rows({}), "F2", "Teams (lobby)"))
	check("F3 admin listed for admins", has(K.Rows({ isAdmin = true }), "F3", "Admin"))
	check("F3 hidden for players", not has(K.Rows({}), "F3", "Admin"))
end

if failed then os.exit(1) end
