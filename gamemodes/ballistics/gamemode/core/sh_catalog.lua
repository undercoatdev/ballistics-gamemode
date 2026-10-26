-- Buy catalog: 8 TacRP guns, 4 throwables, 4 Player Ballistics meds.
-- Prices live in BALLISTICS.Config.Costs under each item's key. No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Catalog = BALLISTICS.Catalog or {}

local weapons = {
	{ key = "tacrp_ex_m1911", kind = "weapon", class = "tacrp_ex_m1911", name = "Colt M1911" },
	{ key = "tacrp_mr96", kind = "weapon", class = "tacrp_mr96", name = "Manurhin MR96" },
	{ key = "tacrp_skorpion", kind = "weapon", class = "tacrp_skorpion", name = "Skorpion vz. 61" },
	{ key = "tacrp_mp5", kind = "weapon", class = "tacrp_mp5", name = "HK MP5A3" },
	{ key = "tacrp_ex_ak47", kind = "weapon", class = "tacrp_ex_ak47", name = "AK-47" },
	{ key = "tacrp_hk417", kind = "weapon", class = "tacrp_hk417", name = "HK 417" },
	{ key = "tacrp_tgs12", kind = "weapon", class = "tacrp_tgs12", name = "Tomahawk Matador" },
	{ key = "tacrp_spr", kind = "weapon", class = "tacrp_spr", name = "Remington M700 SPS" },
}

local throwables = {
	{ key = "nade_frag", kind = "nade", entity = "tacrp_ammo_frag", ammo = "grenade", name = "Frag grenade" },
	{ key = "nade_flashbang", kind = "nade", entity = "tacrp_ammo_flashbang", ammo = "ti_flashbang", name = "Flashbang" },
	{ key = "nade_smoke", kind = "nade", entity = "tacrp_ammo_smoke", ammo = "ti_smoke", name = "Smoke grenade" },
	{ key = "nade_thermite", kind = "nade", entity = "tacrp_ammo_fire", ammo = "ti_thermite", name = "Thermite grenade" },
}

local meds = {
	{ key = "med_pills", kind = "med", entity = "pb_med_extrasmall", id = 1, name = "Pills" },
	{ key = "med_small", kind = "med", entity = "pb_med_small", id = 2, name = "Small medkit" },
	{ key = "med_trauma", kind = "med", entity = "pb_med_large", id = 3, name = "Trauma bag" },
	{ key = "med_resus", kind = "med", entity = "pb_med_extralarge", id = 4, name = "Resuscitation kit" },
}

local byKey = {}
local function index(list)
	for i = 1, #list do
		byKey[list[i].key] = list[i]
	end
end
index(weapons)
index(throwables)
index(meds)

function BALLISTICS.Catalog.Weapons()
	return weapons
end

function BALLISTICS.Catalog.Throwables()
	return throwables
end

function BALLISTICS.Catalog.Meds()
	return meds
end

function BALLISTICS.Catalog.All()
	local all = {}
	for i = 1, #weapons do all[#all + 1] = weapons[i] end
	for i = 1, #throwables do all[#all + 1] = throwables[i] end
	for i = 1, #meds do all[#all + 1] = meds[i] end
	return all
end

function BALLISTICS.Catalog.Get(key)
	return byKey[key]
end

function BALLISTICS.Catalog.Price(key)
	local cfg = BALLISTICS.Config
	if not cfg then return nil end
	local costs = cfg.Costs
	if type(cfg.Get) == "function" then
		costs = cfg.Get("Costs") or costs
	end
	if type(costs) ~= "table" then return nil end
	return costs[key]
end
