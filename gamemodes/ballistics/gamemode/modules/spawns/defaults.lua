-- Built-in flags by map. Used when data/ballistics/spawns/<map>.json is absent.
-- Coordinates are walkable ground on the stock maps (info_node / info_player_start).
-- gm_construct / gm_frame: fox playtest placements (Oct 2026).

BALLISTICS = BALLISTICS or {}

local function face(ax, ay, bx, by)
	return math.deg(math.atan2(by - ay, bx - ax))
end

local function pair(ax, ay, az, bx, by, bz)
	local data = BALLISTICS.SpawnData or {}
	local length = data.BOX_LENGTH or 768
	local width = data.BOX_WIDTH or 384
	local lift = ((data.BOX_HEIGHT or 128) * 0.5)
	return {
		good = { pos = { x = ax, y = ay, z = az }, ang = { p = 0, y = face(ax, ay, bx, by), r = 0 } },
		bad = { pos = { x = bx, y = by, z = bz }, ang = { p = 0, y = face(bx, by, ax, ay), r = 0 } },
		-- Between the flags, on the ground, long axis along the flag line.
		box = {
			pos = { x = (ax + bx) * 0.5, y = (ay + by) * 0.5, z = az + lift },
			yaw = face(ax, ay, bx, by),
			sx = length,
			sy = width,
		},
	}
end

-- gm_flatgrass: on the walkable pad around the player starts (feet near z -12280).
BALLISTICS.SpawnDefaults = {
	gm_construct = {
		good = { pos = { x = -5499.148438, y = -3300.04126, z = 256.03125 }, ang = { p = 0.0, y = 31.379276, r = 0.0 } },
		bad = { pos = { x = -4203.476563, y = -3397.376221, z = 250.0 }, ang = { p = 0.0, y = 175.703827, r = 0.0 } },
		box = { pos = { x = -4144.935547, y = -2247.141113, z = 314.0 }, yaw = 162.304977, sx = 768.0, sy = 384.0 },
	},
	gm_frame = {
		good = { pos = { x = -2158.354004, y = -9.64475, z = -191.96875 }, ang = { p = 0.0, y = 118.373383, r = 0.0 } },
		bad = { pos = { x = 879.92981, y = -876.944763, z = -191.96875 }, ang = { p = 0.0, y = 164.068222, r = 0.0 } },
		box = { pos = { x = -226.962387, y = 2261.038086, z = 64.03125 }, yaw = 0.0, sx = 768.0, sy = 384.0 },
	},
	gm_flatgrass = pair(-896, 512, -12272, 896, -512, -12272),
}
