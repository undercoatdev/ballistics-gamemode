-- Built-in flags by map. Used when data/ballistics/spawns/<map>.json is absent.
-- Coordinates are walkable ground on the stock maps (info_node / info_player_start).

BALLISTICS = BALLISTICS or {}

local function face(ax, ay, bx, by)
	return math.deg(math.atan2(by - ay, bx - ax))
end

local function pair(ax, ay, az, bx, by, bz)
	return {
		good = { pos = { x = ax, y = ay, z = az }, ang = { p = 0, y = face(ax, ay, bx, by), r = 0 } },
		bad = { pos = { x = bx, y = by, z = bz }, ang = { p = 0, y = face(bx, by, ax, ay), r = 0 } },
	}
end

-- gm_construct: two nav nodes on the main ground band (z ≈ -134), about 4200 u apart.
-- gm_flatgrass: on the walkable pad around the player starts (feet near z -12280).
BALLISTICS.SpawnDefaults = {
	gm_construct = pair(-1867, -1875, -134, 1320, 859, -134),
	gm_flatgrass = pair(-896, 512, -12272, 896, -512, -12272),
}
