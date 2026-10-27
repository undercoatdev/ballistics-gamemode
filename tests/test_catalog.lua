-- Catalog lists the 8 guns, 4 throwables, and 4 meds with the confirmed classes.
-- (CS gas and medi-smoke are never offered.) Run: luajit tests/test_catalog.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")

local weapons = BALLISTICS.Catalog.Weapons()
local nades = BALLISTICS.Catalog.Throwables()
local meds = BALLISTICS.Catalog.Meds()
local all = BALLISTICS.Catalog.All()

check("8 weapons", #weapons == 8)
check("4 throwables", #nades == 4)
check("4 meds", #meds == 4)
check("16 catalog items", #all == 16)

local function byClass(class)
	for i = 1, #weapons do
		if weapons[i].class == class then return weapons[i] end
	end
end

check("AK-47 is tacrp_ex_ak47", byClass("tacrp_ex_ak47") and byClass("tacrp_ex_ak47").name == "AK-47")
check("MP5 is tacrp_mp5", byClass("tacrp_mp5") and byClass("tacrp_mp5").name == "HK MP5A3")
check("HK417 is tacrp_hk417", byClass("tacrp_hk417") and byClass("tacrp_hk417").name == "HK 417")
check("Matador is tacrp_tgs12", byClass("tacrp_tgs12") and byClass("tacrp_tgs12").name == "Tomahawk Matador")
check("M700 is tacrp_spr", byClass("tacrp_spr") and byClass("tacrp_spr").name == "Remington M700 SPS")
check("M1911 is tacrp_ex_m1911", byClass("tacrp_ex_m1911") and byClass("tacrp_ex_m1911").name == "Colt M1911")
check("MR96 is tacrp_mr96", byClass("tacrp_mr96") and byClass("tacrp_mr96").name == "Manurhin MR96")
check("Skorpion is tacrp_skorpion", byClass("tacrp_skorpion") and byClass("tacrp_skorpion").name == "Skorpion vz. 61")
check("FB Beryl is not in the catalog", byClass("tacrp_ak47") == nil)
check("knife is not in the catalog", byClass("tacrp_knife") == nil)

local function nade(key)
	return BALLISTICS.Catalog.Get(key)
end

check("frag ammo", nade("nade_frag") and nade("nade_frag").ammo == "grenade" and nade("nade_frag").entity == "tacrp_ammo_frag")
check("flashbang ammo", nade("nade_flashbang") and nade("nade_flashbang").ammo == "ti_flashbang" and nade("nade_flashbang").entity == "tacrp_ammo_flashbang")
check("smoke ammo", nade("nade_smoke") and nade("nade_smoke").ammo == "ti_smoke" and nade("nade_smoke").entity == "tacrp_ammo_smoke")
check("thermite ammo", nade("nade_thermite") and nade("nade_thermite").ammo == "ti_thermite" and nade("nade_thermite").entity == "tacrp_ammo_fire")
check("CS gas is not offered", BALLISTICS.Catalog.Get("nade_gas") == nil and BALLISTICS.Catalog.Get("ti_gas") == nil)
check("medi-smoke is not offered", BALLISTICS.Catalog.Get("nade_heal") == nil)

local function med(key)
	return BALLISTICS.Catalog.Get(key)
end

check("pills id 1", med("med_pills") and med("med_pills").id == 1 and med("med_pills").entity == "pb_med_extrasmall")
check("small medkit id 2", med("med_small") and med("med_small").id == 2 and med("med_small").entity == "pb_med_small")
check("trauma bag id 3", med("med_trauma") and med("med_trauma").id == 3 and med("med_trauma").entity == "pb_med_large")
check("resus kit id 4", med("med_resus") and med("med_resus").id == 4 and med("med_resus").entity == "pb_med_extralarge")

local missingPrice = {}
for i = 1, #all do
	local item = all[i]
	local price = BALLISTICS.Catalog.Price(item.key)
	if type(price) ~= "number" then missingPrice[#missingPrice + 1] = item.key end
end
check("every catalog key has a Config.Costs price", #missingPrice == 0)

local costKeys, catalogKeys = 0, 0
for _ in pairs(BALLISTICS.Config.Costs) do costKeys = costKeys + 1 end
for i = 1, #all do catalogKeys = catalogKeys + 1 end
check("Costs and catalog have the same size", costKeys == catalogKeys and costKeys == 16)

local orphan = false
for key in pairs(BALLISTICS.Config.Costs) do
	if not BALLISTICS.Catalog.Get(key) then orphan = true end
end
check("every Costs key is a catalog item", orphan == false)

check("AK-47 costs 900", BALLISTICS.Catalog.Price("tacrp_ex_ak47") == 900)
check("pills cost 50", BALLISTICS.Catalog.Price("med_pills") == 50)

local expectCat = {
	tacrp_ex_m1911 = "Pistol",
	tacrp_mr96 = "Magnum",
	tacrp_skorpion = "Machine Pistol",
	tacrp_mp5 = "SMG",
	tacrp_ex_ak47 = "Assault Rifle",
	tacrp_hk417 = "Battle Rifle",
	tacrp_tgs12 = "Shotgun",
	tacrp_spr = "Sniper",
}
local catOk = true
for class, category in pairs(expectCat) do
	local item = byClass(class)
	if not item or item.category ~= category then catOk = false end
end
check("each gun has its category", catOk)

local groups = BALLISTICS.Catalog.WeaponGroups()
local order = {}
for i = 1, #groups do order[i] = groups[i].category end
check("groups follow the buy order", table.concat(order, ",") == "Pistol,Magnum,Machine Pistol,SMG,Assault Rifle,Battle Rifle,Shotgun,Sniper")
check("pistol group is the m1911", #groups[1].items == 1 and groups[1].items[1].class == "tacrp_ex_m1911")
check("sniper group is the m700", groups[8].items[1].class == "tacrp_spr")

local custom = BALLISTICS.Catalog.WeaponGroups({
	{ key = "a", category = "Sniper" },
	{ key = "b", category = "Pistol" },
	{ key = "c", category = "Pistol" },
	{ key = "d", category = "Launcher" },
	{ key = "e" },
})
check("empty categories are skipped", #custom == 3 and custom[1].category == "Pistol" and #custom[1].items == 2)
check("sniper stays ahead of other", custom[2].category == "Sniper" and custom[2].items[1].key == "a")
check("unknown categories land in Other", custom[3].category == "Other" and custom[3].items[1].key == "d" and custom[3].items[2].key == "e")

local cols = BALLISTICS.Catalog.WeaponColumns()
local function keys(groups) local out = {} for _, g in ipairs(groups) do for _, it in ipairs(g.items) do out[#out + 1] = it.key end end return table.concat(out, ",") end
check("light column", keys(cols.light) == "tacrp_ex_m1911,tacrp_mr96,tacrp_skorpion,tacrp_mp5")
check("heavy column", keys(cols.heavy) == "tacrp_ex_ak47,tacrp_hk417,tacrp_tgs12,tacrp_spr")
check("gun icon path", BALLISTICS.Catalog.IconPath(BALLISTICS.Catalog.Get("tacrp_mp5")) == "entities/tacrp_mp5.png")
check("grenade icon path", BALLISTICS.Catalog.IconPath(BALLISTICS.Catalog.Get("nade_frag")) == "entities/tacrp_ammo_frag.png")
check("med icon path", BALLISTICS.Catalog.IconPath(BALLISTICS.Catalog.Get("med_pills")) == "entities/pb_med_extrasmall.png")

if failed then os.exit(1) end
