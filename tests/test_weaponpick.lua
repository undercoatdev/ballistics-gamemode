-- Slot select from the buy wheel and from keys 1, 2, 3. Scroll does not pick.
-- Run: luajit tests/test_weaponpick.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/modules/loadout/sh_loadout.lua")
local L = BALLISTICS.Loadout
check("scroll is not a weapon pick", L.BindSlot("invnext") == nil and L.BindSlot("INVPREV") == nil and L.BlockScroll("invnext") == true and L.BlockScroll("invprev") == true)
check("slot keys pick a loadout slot", L.BindSlot("slot2") == 2 and L.BindSlot("slot4") == nil and L.BindSlot("+jump") == nil)

local cmds = {}
concommand = { Add = function(name, fn) cmds[name] = fn end }
BALLISTICS.IsPlayer = function() return true end
BALLISTICS.PlayerId = function(ply) return ply.sid end
local ply = { sid = "p", picked = nil, held = { tacrp_m1911 = true } }
function ply:HasWeapon(class) return self.held[class] == true end
function ply:SelectWeapon(class) self.picked = class end
function ply:IsValid() return true end

local okLoad = pcall(dofile, "gamemodes/ballistics/gamemode/modules/buy/sv_buy.lua")
pcall(dofile, "gamemodes/ballistics/gamemode/modules/loadout/sv_loadout.lua")
if okLoad and cmds.bal_select and cmds.bal_slot then
	cmds.bal_select(ply, "bal_select", { "tacrp_spr" })
	check("unowned weapon refused", ply.picked == nil)
	cmds.bal_select(ply, "bal_select", { "tacrp_m1911" })
	check("owned weapon selected", ply.picked == "tacrp_m1911")

	ply.picked = nil
	BALLISTICS.Loadout.Reset(ply, "tacrp_knife")
	cmds.bal_slot(ply, "bal_slot", { "1" })
	check("an empty knife slot does nothing", ply.picked == nil)
	ply.held.tacrp_knife = true
	cmds.bal_slot(ply, "bal_slot", { "1" })
	check("slot 1 selects the knife", ply.picked == "tacrp_knife")
	BALLISTICS.Loadout.NoteGun(ply, "tacrp_m1911")
	ply.picked = nil
	cmds.bal_slot(ply, "bal_slot", { "2" })
	check("slot 2 selects the first gun", ply.picked == "tacrp_m1911")
	ply.picked = nil
	cmds.bal_slot(ply, "bal_slot", { "3" })
	check("an empty gun slot does nothing", ply.picked == nil)
	cmds.bal_slot(ply, "bal_slot", { "4" })
	check("slot 4 does not select a weapon", ply.picked == nil)
else
	check("sv_buy loads with bal_select and bal_slot", false)
end

if failed then os.exit(1) end
