-- Run: luajit tests/test_tacfilter.lua
BALLISTICS = {}
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
TacRP = { Attachments = {
	ammo_buckshotroulette = { Category = "ammo_shotgun" },
	ammo_shotgun_dragon = { Category = "ammo_shotgun" },
	ammo_roulette = { Category = "ammo_roulette" },
	ammo_surplus = { Category = "ammo_pistol", PrintName = "att.ammo_surplus.name" },
	ammo_surplus2 = { Category = "ammo_shotgun" },
	bolt_surplus = { Category = "bolt", PrintName = "att.bolt_surplus.name" },
	foo_surplus_bar = { Category = "ammo_pistol" },
	acc_oldmag = { PrintName = "Surplus Magazine" },
	acc_worn = { FullName = "Factory Surplus Bolt" },
	acc_shout = { PrintName = "SURPLUS PACK" },
	acc_duffelbag = { Category = "acc_duffle" },
	ammo_shotgun_slugs = {},
	acc_extmag_pistol = { PrintName = "Extended Mag" },
	ammo_ebullet = { PrintName = "Extra Bullet" },
} }
hook = nil
dofile("gamemodes/ballistics/gamemode/modules/tacrpfilter/sh_tacrpfilter.lua")
local F, failed = BALLISTICS.TacFilter, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
F.HideAtts()
check("roulette hidden", TacRP.Attachments.ammo_buckshotroulette.Compatibility() == false)
check("dragon's breath hidden", TacRP.Attachments.ammo_shotgun_dragon.Compatibility() == false)
check("other rounds untouched", TacRP.Attachments.ammo_shotgun_slugs.Compatibility == nil)
check("blocked ids", F.AttBlocked("ammo_shotgun_dragon") and F.AttBlocked("ammo_buckshotroulette") and F.AttBlocked("ammo_roulette") and F.AttBlocked("ammo_surplus") and F.AttBlocked("ammo_surplus2") and F.AttBlocked("bolt_surplus") and F.AttBlocked("acc_duffelbag") and not F.AttBlocked("ammo_shotgun_slugs") and not F.AttBlocked("acc_extmag_pistol") and not F.AttBlocked("ammo_ebullet"))
check("surplus in the id or the display name is blocked", F.AttBlocked("foo_surplus_bar") and F.AttBlocked("acc_oldmag") and F.AttBlocked("acc_worn") and F.AttBlocked("acc_shout") and F.AttBlocked("Bolt_Surplus"))
check("revolver roulette hidden", TacRP.Attachments.ammo_roulette.Compatibility() == false)
check("surplus and gun bag hidden", TacRP.Attachments.ammo_surplus.Compatibility() == false and TacRP.Attachments.ammo_surplus2.Compatibility() == false and TacRP.Attachments.bolt_surplus.Compatibility() == false and TacRP.Attachments.foo_surplus_bar.Compatibility() == false and TacRP.Attachments.acc_oldmag.Compatibility() == false and TacRP.Attachments.acc_worn.Compatibility() == false and TacRP.Attachments.acc_duffelbag.Compatibility() == false)
check("extended mag and extra bullet stay available", TacRP.Attachments.acc_extmag_pistol.Compatibility == nil and TacRP.Attachments.ammo_ebullet.Compatibility == nil)
check("frag allowed", F.NadeAllowed({ Ammo = "grenade" }))
check("thermite allowed", F.NadeAllowed({ Ammo = "ti_thermite" }))
check("gas not allowed", not F.NadeAllowed({ Ammo = "ti_gas" }))
check("no-ammo nade not allowed", not F.NadeAllowed({}))
if failed then os.exit(1) end
