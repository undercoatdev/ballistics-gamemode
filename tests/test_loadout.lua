-- Loadout slots: knife, then guns in acquisition order. Run: luajit tests/test_loadout.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

dofile("tests/support/gmod_stub.lua")
local pure = readAll("gamemodes/ballistics/gamemode/modules/loadout/sh_loadout.lua")
check("loadout logic does not touch the game", not pure:find("hook.Add", 1, true)
	and not pure:find("LocalPlayer", 1, true)
	and not pure:find("timer.Simple", 1, true)
	and not pure:find("concommand", 1, true))
dofile("gamemodes/ballistics/gamemode/modules/loadout/sh_loadout.lua")
local L = BALLISTICS.Loadout

local knife, guns = L.Resolve({}, {
	{ class = "tacrp_knife", role = "melee" },
	{ class = "nade_frag", role = "nade" },
	{ class = "med_pills", role = "med" },
	"tacrp_ex_m1911",
}, nil)
check("the melee is slot 1", knife == "tacrp_knife" and L.At(knife, guns, 1) == "tacrp_knife")
check("a med and a throwable take no slot", #guns == 1 and guns[1] == "tacrp_ex_m1911" and L.At(knife, guns, 2) == "tacrp_ex_m1911" and L.At(knife, guns, 3) == nil)

local _, ordered = L.Resolve(nil, { "tacrp_knife", "tacrp_pistol", "tacrp_ak" }, "tacrp_knife")
check("guns follow acquisition order", ordered[1] == "tacrp_pistol" and ordered[2] == "tacrp_ak" and L.Full(ordered) == true)

local _, shifted = L.Resolve({ "tacrp_ak", "tacrp_pistol" }, { "tacrp_pistol" }, "tacrp_knife")
check("dropping the first gun shifts the other to slot 2", shifted[1] == "tacrp_pistol" and shifted[2] == nil and L.At("tacrp_knife", shifted, 2) == "tacrp_pistol" and L.At("tacrp_knife", shifted, 3) == nil and L.Full(shifted) == false)

local keepKnife, kept = L.ResolveSlots({ "tacrp_ak", "tacrp_pistol" }, { "tacrp_pistol" }, "tacrp_knife")
check("ResolveSlots keeps the remaining gun in its slot", keepKnife == "tacrp_knife" and kept[1] == false and kept[2] == "tacrp_pistol")
local _, keptBoth = L.ResolveSlots({ "tacrp_ak", "tacrp_pistol" }, { "tacrp_ak", "tacrp_pistol" }, "tacrp_knife")
check("ResolveSlots keeps both gun slots", keptBoth[1] == "tacrp_ak" and keptBoth[2] == "tacrp_pistol")
local _, filled = L.ResolveSlots({ false, "tacrp_pistol" }, { "tacrp_ak", "tacrp_pistol" }, "tacrp_knife")
check("ResolveSlots fills the first free slot", filled[1] == "tacrp_ak" and filled[2] == "tacrp_pistol")
check("FreeSlot is the first empty gun slot", L.FreeSlot(nil) == 1 and L.FreeSlot({}) == 1 and L.FreeSlot(kept) == 1 and L.FreeSlot({ "tacrp_ak", false }) == 2 and L.FreeSlot(keptBoth) == nil)

local _, stayed = L.Resolve({ "tacrp_ak", "tacrp_pistol" }, { "tacrp_ak" }, "tacrp_knife")
check("dropping the second gun leaves the first in slot 2", stayed[1] == "tacrp_ak" and stayed[2] == nil)

local _, appended = L.Resolve({ "tacrp_ak" }, { "tacrp_ak", "tacrp_pistol" }, "tacrp_knife")
check("a new gun fills slot 3", appended[1] == "tacrp_ak" and appended[2] == "tacrp_pistol")

local _, capped = L.Resolve({ "tacrp_ak", "tacrp_pistol" }, { "tacrp_ak", "tacrp_pistol", "tacrp_spr" }, "tacrp_knife")
check("a third gun does not take a slot", #capped == 2 and capped[1] == "tacrp_ak" and capped[2] == "tacrp_pistol")

local _, once = L.Resolve(nil, { "tacrp_pistol", "tacrp_pistol", "tacrp_ak" }, "tacrp_knife")
check("a repeated gun is one slot", #once == 2 and once[1] == "tacrp_pistol" and once[2] == "tacrp_ak")

check("empty hands have no slots", L.At(nil, {}, 1) == nil and L.At("tacrp_knife", {}, 2) == nil)
check("slot binds are 1, 2 and 3", L.BindSlot("slot1") == 1 and L.BindSlot("SLOT2") == 2 and L.BindSlot("slot3") == 3)
check("slot4 is not a loadout slot", L.BindSlot("slot4") == nil and L.BindSlot("slot10") == nil)
check("scroll is not a slot", L.BindSlot("invnext") == nil and L.BindSlot("invprev") == nil and L.BindSlot("+attack") == nil and L.BindSlot(nil) == nil)
check("scroll binds are blocked", L.BlockScroll("invnext") == true and L.BlockScroll("INVPREV") == true and L.BlockScroll("slot1") == false and L.BlockScroll("+attack") == false and L.BlockScroll(nil) == false)

BALLISTICS.PlayerId = function(ply) return ply.sid end
BALLISTICS.IsPlayer = function() return true end

local ply = { sid = "s", list = { "tacrp_knife" }, valid = true, selected = nil }
function ply:IsValid() return self.valid == true end
function ply:HasWeapon(class)
	for i = 1, #self.list do
		if self.list[i] == class then return true end
	end
	return false
end
function ply:GetWeapons()
	local out = {}
	for i = 1, #self.list do
		local class = self.list[i]
		out[i] = { GetClass = function() return class end, IsValid = function() return true end }
	end
	return out
end
function ply:SelectWeapon(class) self.selected = class end

dofile("gamemodes/ballistics/gamemode/modules/loadout/sv_loadout.lua")
BALLISTICS.Loadout.Reset(ply, "tacrp_knife")
check("the knife noted", BALLISTICS.Loadout.NoteGun(ply, "tacrp_knife") == false)
check("slot 1 is the knife", BALLISTICS.Loadout.ClassFor(ply, 1) == "tacrp_knife")
check("empty gun slots do nothing", BALLISTICS.Loadout.ClassFor(ply, 2) == nil and BALLISTICS.Loadout.ClassFor(ply, 3) == nil)
BALLISTICS.Loadout.NoteGun(ply, "tacrp_ak")
ply.list = { "tacrp_knife", "tacrp_ak" }
BALLISTICS.Loadout.NoteGun(ply, "tacrp_pistol")
ply.list = { "tacrp_knife", "tacrp_ak", "tacrp_pistol" }
check("server slots follow buy order", BALLISTICS.Loadout.ClassFor(ply, 2) == "tacrp_ak" and BALLISTICS.Loadout.ClassFor(ply, 3) == "tacrp_pistol" and BALLISTICS.Loadout.GunCount(ply) == 2)
check("a third noted gun is refused", BALLISTICS.Loadout.NoteGun(ply, "tacrp_spr") == false and BALLISTICS.Loadout.GunCount(ply) == 2)
ply.list = { "tacrp_knife", "tacrp_pistol" }
check("removing the first gun leaves slot 2 empty", BALLISTICS.Loadout.ClassFor(ply, 2) == nil and BALLISTICS.Loadout.ClassFor(ply, 3) == "tacrp_pistol")
ply.list = {}
check("a dropped knife is an empty slot", BALLISTICS.Loadout.ClassFor(ply, 1) == nil)

local ran = {}
timer.Simple = function(delay, fn) ran[#ran + 1] = { delay = delay, fn = fn } end
ply.list = { "tacrp_ak" }
ply.valid = true
ply.selected = nil
BALLISTICS.Loadout.Equip(ply, "tacrp_ak")
check("equip selects immediately", ply.selected == "tacrp_ak" and #ran == 1 and ran[1].delay == 0)
ply.selected = nil
ran[1].fn()
check("equip selects again on the next tick", ply.selected == "tacrp_ak")
ply.list = {}
ply.selected = nil
ran[1].fn()
check("a late select does nothing once the gun is gone", ply.selected == nil)
ply.valid = false
ply.list = { "tacrp_ak" }
ply.selected = nil
ran[1].fn()
check("a late select does nothing once the player is gone", ply.selected == nil)

local calls = {}
function RunConsoleCommand(...) calls[#calls + 1] = { ... } end
CLIENT = true
dofile("gamemodes/ballistics/gamemode/modules/loadout/cl_loadout.lua")
check("slot1 selects that slot", hook.Run("PlayerBindPress", nil, "slot1", true) == true and calls[1][1] == "bal_slot" and calls[1][2] == "1")
local n = #calls
check("a slot release is swallowed and does not select again", hook.Run("PlayerBindPress", nil, "slot2", false) == true and #calls == n)
check("slot4 is not swallowed by the loadout hook", hook.Run("PlayerBindPress", nil, "slot4", true) == nil)
check("attack is not swallowed", hook.Run("PlayerBindPress", nil, "+attack", true) == nil)
check("scroll is swallowed", hook.Run("PlayerBindPress", nil, "invnext", true) == true and hook.Run("PlayerBindPress", nil, "INVPREV", true) == true)
BALLISTICS.Spawns = { IsEditing = function() return true end }
check("the spawn editor keeps the scroll wheel", hook.Run("PlayerBindPress", nil, "invnext", true) == nil)
BALLISTICS.Spawns.IsEditing = function() return false end
check("scroll is swallowed again once the editor closes", hook.Run("PlayerBindPress", nil, "invprev", true) == true)

if failed then os.exit(1) end
