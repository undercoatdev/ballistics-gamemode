-- Organ heal between rounds. Destroyed organs come back working.
-- Run: luajit tests/test_organs.lua
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
dofile("gamemodes/ballistics/gamemode/modules/organs/sh_organs.lua")

local H = BALLISTICS.Organs.Heal
check("destroyed plus 10 is 10", H(0, 100, 10) == 10)
check("heal caps at max", H(95, 100, 10) == 100)
check("a zero heal revives a destroyed organ to 1", H(0, 100, 0) == 1)
check("a healthy organ stays put when the setting is 0", H(40, 100, 0) == 40)
check("negative hp is destroyed", H(-3, 50, 10) == 7)
check("unknown max still revives", H(0, 0, 0) == 1)
check("full organ stays full", H(100, 100, 10) == 100)
check("negative amount does not damage", H(20, 100, -5) == 20)

local function maxOf(entry, side)
	if entry and entry.uid == "heart" and side == "main" then return 80 end
	if entry and entry.uid == "lung" then return 50 end
	return nil
end

local old = {
	organs = {
		layout = {
			{ uid = "heart" },
			{ uid = "lung" },
		},
		copies = {
			heart = { parts = { main = 0 } },
			lung = { parts = { l = 45, r = 10 } },
		},
	},
}
local snap = BALLISTICS.Organs.SnapshotRecord(old, maxOf)
check("snapshot keeps each side", snap and snap.parts.heart.main.hp == 0 and snap.parts.heart.main.max == 80)
check("snapshot reads both lungs", snap.parts.lung.l.hp == 45 and snap.parts.lung.r.hp == 10)
check("empty record snapshots nothing", BALLISTICS.Organs.SnapshotRecord({ organs = { copies = {} } }) == nil)

local fresh = {
	organs = {
		layout = {
			{ uid = "heart" },
			{ uid = "lung" },
		},
		copies = {
			heart = { parts = { main = 80 }, deadFired = { main = true } },
			lung = { parts = { l = 50, r = 50 }, deadFired = {} },
		},
	},
}
check("apply writes the heal", BALLISTICS.Organs.ApplyRecord(fresh, snap, 10, maxOf) == true)
check("destroyed heart heals to 10", fresh.organs.copies.heart.parts.main == 10)
check("revived heart can be destroyed again", fresh.organs.copies.heart.deadFired.main == nil)
check("lung caps at its max", fresh.organs.copies.lung.parts.l == 50)
check("damaged lung heals by the setting", fresh.organs.copies.lung.parts.r == 20)

local zero = {
	organs = {
		layout = { { uid = "heart" } },
		copies = { heart = { parts = { main = 100 }, deadFired = { main = true } } },
	},
}
BALLISTICS.Organs.ApplyRecord(zero, { parts = { heart = { main = { hp = 0, max = 100 } } } }, 0, maxOf)
check("zero setting still leaves 1", zero.organs.copies.heart.parts.main == 1)

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end
local src = readAll("gamemodes/ballistics/gamemode/modules/organs/sv_organs.lua")
check("sync uses Body Damage's own path", src:find("WriteOrganCopies", 1, true) and src:find("OrganNetPush", 1, true))
check("write is deferred past GiveOrgans", src:find("timer.Simple", 1, true) ~= nil)

if failed then os.exit(1) end
