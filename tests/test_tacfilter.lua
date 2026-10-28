-- Run: luajit tests/test_tacfilter.lua
BALLISTICS = {}
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
TacRP = { Attachments = { ammo_buckshotroulette = { Category = "ammo_shotgun" }, ammo_shotgun_dragon = { Category = "ammo_shotgun" }, ammo_roulette = { Category = "ammo_roulette" }, ammo_shotgun_slugs = {} } }
hook = nil
dofile("gamemodes/ballistics/gamemode/modules/tacrpfilter/sh_tacrpfilter.lua")
local F, failed = BALLISTICS.TacFilter, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
F.HideAtts()
check("roulette hidden", TacRP.Attachments.ammo_buckshotroulette.Compatibility() == false)
check("dragon's breath hidden", TacRP.Attachments.ammo_shotgun_dragon.Compatibility() == false)
check("other rounds untouched", TacRP.Attachments.ammo_shotgun_slugs.Compatibility == nil)
check("blocked ids", F.AttBlocked("ammo_shotgun_dragon") and F.AttBlocked("ammo_buckshotroulette") and F.AttBlocked("ammo_roulette") and not F.AttBlocked("ammo_shotgun_slugs"))
check("revolver roulette hidden", TacRP.Attachments.ammo_roulette.Compatibility() == false)
check("frag allowed", F.NadeAllowed({ Ammo = "grenade" }))
check("thermite allowed", F.NadeAllowed({ Ammo = "ti_thermite" }))
check("gas not allowed", not F.NadeAllowed({ Ammo = "ti_gas" }))
check("no-ammo nade not allowed", not F.NadeAllowed({}))
if failed then os.exit(1) end
