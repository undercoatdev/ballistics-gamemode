-- Weapon pick during buy. Run: luajit tests/test_weaponpick.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end
dofile("tests/support/gmod_stub.lua")
BALLISTICS = BALLISTICS or {}
dofile("gamemodes/ballistics/gamemode/modules/buy/sh_weaponpick.lua")
local W = BALLISTICS.WeaponPick
local list = {
	{ class = "tacrp_ak47", slot = 2, pos = 0 },
	{ class = "knife", slot = 0, pos = 0 },
	{ class = "tacrp_m1911", slot = 1, pos = 0 },
}
check("next from knife is pistol", W.Cycle(list, "knife", 1) == "tacrp_m1911")
check("next wraps to knife", W.Cycle(list, "tacrp_ak47", 1) == "knife")
check("prev from knife wraps to rifle", W.Cycle(list, "knife", -1) == "tacrp_ak47")
check("unknown current picks first", W.Cycle(list, nil, 1) == "knife")
check("slot3 picks rifle", W.Slot(list, "knife", 3) == "tacrp_ak47")
check("empty slot picks nothing", W.Slot(list, "knife", 5) == nil)
check("no weapons, nothing", W.Cycle({}, nil, 1) == nil)
check("binds map", W.BindAction("invnext") == "next" and W.BindAction("INVPREV") == "prev" and W.BindAction("slot2") == 2 and W.BindAction("+jump") == nil)

-- Server: only owned weapons can be selected.
local cmds = {}
concommand = { Add = function(n, f) cmds[n] = f end }
BALLISTICS.IsPlayer = function() return true end
local ply = { picked = nil }
function ply:HasWeapon(c) return c == "tacrp_m1911" end
function ply:SelectWeapon(c) self.picked = c end
local okLoad = pcall(dofile, "gamemodes/ballistics/gamemode/modules/buy/sv_buy.lua")
if okLoad and cmds.bal_select then
	cmds.bal_select(ply, "bal_select", { "tacrp_spr" })
	check("unowned weapon refused", ply.picked == nil)
	cmds.bal_select(ply, "bal_select", { "tacrp_m1911" })
	check("owned weapon selected", ply.picked == "tacrp_m1911")
else
	check("sv_buy loads with bal_select", false)
end
if failed then os.exit(1) end
