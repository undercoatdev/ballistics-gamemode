-- Spawn records: JSON round-trip, defaults fallback, ring offsets, admin save.
-- Run: luajit tests/test_spawns.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/modules/spawns/sh_spawns.lua")
dofile("gamemodes/ballistics/gamemode/modules/spawns/defaults.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_tabs.lua")

local D = BALLISTICS.SpawnData
local defs = BALLISTICS.SpawnDefaults

local function dist2(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

local function near(a, b, eps)
	return math.abs(a - b) < (eps or 1e-4)
end

local props = D.flagProps()
check("flag models are the cash register and the bomb", props.good == "models/props_c17/cashregister01a.mdl" and props.bad == "models/combine_helicopter/helicopter_bomb01.mdl" and D.flagModel("good") == props.good and D.flagModel(2) == props.bad)
check("flag props are not solid and cannot be taken", props.solid == "none" and props.pickup == false and props.damage == false)
check("the nearest flag is chosen by distance", D.nearestSide({ good = { pos = { x = 0, y = 0, z = 0 } }, bad = { pos = { x = 100, y = 0, z = 0 } } }, { x = 10, y = 0, z = 0 }, 96) == "good")
check("a far point picks no flag", D.nearestSide({ good = { pos = { x = 0, y = 0, z = 0 } } }, { x = 500, y = 0, z = 0 }) == nil)
check("map file is data/ballistics/spawns/<map>.json", D.mapFile("gm_construct") == "ballistics/spawns/gm_construct.json")
check("map file rejects traversal and spaces", D.mapFile("../x") == nil and D.mapFile("gm construct") == nil and D.mapFile("") == nil and D.mapFile("gm_flatgrass") ~= nil)

for _, map in ipairs({ "gm_construct", "gm_flatgrass" }) do
	local state = D.resolve(nil, defs, map)
	check(map .. " defaults place both flags", state.source == "defaults" and D.hasBoth(state))
	check(map .. " defaults are far enough apart", dist2(state.good.pos, state.bad.pos) > 500)
	local built = D.resolve(nil, defs, map)
	check(map .. " defaults are not the same tables as the shipped ones", built.good ~= defs[map].good and built.good.pos ~= defs[map].good.pos)
end

check("unknown map has no flags", D.resolve(nil, defs, "gm_nowhere").source == "none" and D.hasBoth(D.resolve(nil, defs, "gm_nowhere")) == false)
check("empty save falls through to defaults", D.resolve("{}", defs, "gm_construct").source == "defaults")
check("corrupt save falls through to defaults", D.resolve("{nope", defs, "gm_flatgrass").source == "defaults" and D.hasBoth(D.resolve("{nope", defs, "gm_flatgrass")))

local partial = '{"good":{"pos":{"x":1,"y":2,"z":3},"ang":{"p":0,"y":15,"r":0}},"bad":null}'
local one = D.resolve(partial, defs, "gm_construct")
check("a saved file wins over defaults", one.source == "file" and one.good.pos.x == 1 and one.good.pos.y == 2)
check("a one-sided file does not borrow the other flag", one.bad == nil and D.hasBoth(one) == false)

local messy = [[
  {
    "bad" : { "ang" : { "r" : 4, "p" : 9, "y" : 180.5 }, "pos" : { "z" : -12272, "x" : 896, "y" : -512 } },
    "good" : { "pos" : { "x" : -896.5, "y" : 512, "z" : -12272 }, "ang" : { "y" : 12.25, "p" : 1, "r" : 2 } }
  }
]]
local parsed = D.fromJSON(messy)
check("JSON objects ignore key order and whitespace", parsed and parsed.good.pos.x == -896.5 and parsed.bad.pos.z == -12272)
check("flags are stored upright", parsed.good.ang.p == 0 and parsed.good.ang.r == 0 and parsed.bad.ang.y == 180.5 and parsed.good.ang.y == 12.25)

local round = D.fromJSON(D.toJSON(parsed))
check("JSON round-trip keeps both flags", round and D.hasBoth(round))
check("JSON round-trip keeps coordinates", round and near(round.good.pos.x, parsed.good.pos.x) and near(round.bad.pos.y, parsed.bad.pos.y) and near(round.good.ang.y, 12.25) and near(round.bad.pos.z, -12272))
check("toJSON refuses an empty record", D.toJSON({ good = nil, bad = nil }) == nil)

local base = D.resolve(nil, defs, "gm_construct")
local moved, err = D.place(base, 1, { x = 10, y = 20, z = 30 }, { y = 45 })
check("place updates Good and marks the record unsaved", moved and moved.dirty and moved.good.pos.x == 10 and moved.good.ang.y == 45 and moved.bad.pos.x == base.bad.pos.x)
check("place does not mutate the previous record", base.dirty == false and base.good.pos.x ~= 10)
check("place accepts the side name", D.place(base, "bad", { x = 800, y = 0, z = 0 }).bad.pos.x == 800)
local tooClose = D.place(base, "bad", { x = base.good.pos.x + 10, y = base.good.pos.y, z = base.good.pos.z })
check("flags closer than 64 are refused", tooClose == nil)
local edge = D.place(base, 2, { x = base.good.pos.x + 64, y = base.good.pos.y, z = 0 })
check("flags 64 units apart are accepted", edge and edge.bad ~= nil)
check("a non-number position is refused", D.place(base, 1, { x = 0 / 0, y = 0, z = 0 }) == nil)
check("an infinite position is refused", D.place(base, 1, { x = 1 / 0, y = 0, z = 0 }) == nil)
check("a position past the map limit is refused", D.place(base, 1, { x = 200001, y = 0, z = 0 }) == nil)
check("an unknown team is refused", D.place(base, 3, { x = 0, y = 0, z = 0 }) == nil)
check("status names the source and unsaved edits", D.statusText(base) == "Built-in defaults" and D.statusText(moved) == "Built-in defaults (unsaved)" and D.statusText({ source = "file" }) == "Saved for this map" and D.statusText({ source = "none" }) == "No flags")
check("readiness asks for both flags until they exist", D.readiness(one) == "Both flags must be placed before the round can start." and D.readiness(base) == "Both flags are placed.")

local function outsideBox(flag, box)
	local dx = flag.pos.x - box.pos.x
	local dy = flag.pos.y - box.pos.y
	local rad = math.rad(box.yaw)
	local c, s = math.cos(rad), math.sin(rad)
	local lx = dx * c + dy * s
	local ly = -dx * s + dy * c
	return math.abs(lx) > box.sx * 0.5 + 1 or math.abs(ly) > box.sy * 0.5 + 1
end

for _, map in ipairs({ "gm_construct", "gm_flatgrass" }) do
	local state = D.resolve(nil, defs, map)
	local box = state.box
	local midX = (state.good.pos.x + state.bad.pos.x) * 0.5
	local midY = (state.good.pos.y + state.bad.pos.y) * 0.5
	check(map .. " default box sits between the flags", box and near(box.pos.x, midX, 1e-6) and near(box.pos.y, midY, 1e-6) and near(box.pos.z, state.good.pos.z + 64, 1e-6) and near(box.sx, 768, 1e-6) and near(box.sy, 384, 1e-6))
	check(map .. " flags stand outside the firing squad box", outsideBox(state.good, box) and outsideBox(state.bad, box))
end

check("an old save with no box stays without one", one.box == nil and D.hasBox(one) == false)
local legacy = D.fromJSON('{"good":{"pos":{"x":1,"y":2,"z":3},"ang":{"p":0,"y":0,"r":0}},"bad":{"pos":{"x":80,"y":0,"z":3},"ang":{"p":0,"y":180,"r":0}}}')
check("a legacy file loads both flags and no box", legacy and D.hasBoth(legacy) and legacy.box == nil)
local brokenBox = D.fromJSON('{"good":{"pos":{"x":1,"y":2,"z":3},"ang":{"p":0,"y":0,"r":0}},"bad":{"pos":{"x":80,"y":0,"z":3},"ang":{"p":0,"y":180,"r":0}},"box":{"pos":{"x":"no","y":0,"z":0},"yaw":0,"sx":10,"sy":10}}')
check("an invalid box is dropped and the flags stay", brokenBox and brokenBox.good.pos.x == 1 and brokenBox.box == nil and D.hasBoth(brokenBox))

local kept = D.place(base, 1, { x = 10, y = 20, z = 30 }, { y = 45 })
check("placing a flag keeps the firing squad box", kept and kept.box and near(kept.box.pos.x, base.box.pos.x, 1e-6) and near(kept.box.sx, base.box.sx, 1e-6))
local clamped = D.placeBox(base, { x = 1, y = 2, z = 3 }, 370, 50, 9000)
check("box size clamps and yaw wraps", clamped and clamped.box.sx == 128 and clamped.box.sy == 8192 and near(clamped.box.yaw, 10, 1e-6) and clamped.box.pos.z == 3 and clamped.dirty == true)
check("a non-finite box is refused", D.placeBox(base, { x = 0 / 0, y = 0, z = 0 }, 0, 768, 384) == nil)
check("place box does not move the flags", clamped.good.pos.x == base.good.pos.x and clamped.bad.pos.x == base.bad.pos.x)
local bare = D.copy(base)
bare.box = nil
check("missing box asks to be placed", D.readiness(bare) == "Both flags are placed. Place the firing squad box in Admin > Spawns.")

local corners = D.boxCorners({ pos = { x = 0, y = 0, z = 64 }, yaw = 0, sx = 768, sy = 384 })
check("the box has eight corners and twelve edges", corners and #corners == 8 and #D.BOX_EDGES == 12)
check("yaw 0 puts a bottom corner at the near corner", corners and near(corners[1].x, -384, 1e-6) and near(corners[1].y, -192, 1e-6) and near(corners[1].z, 0, 1e-6) and near(corners[2].x, 384, 1e-6))
local turned = D.boxCorners({ pos = { x = 0, y = 0, z = 64 }, yaw = 90, sx = 768, sy = 384 })
check("yaw 90 turns local +X onto world +Y", turned and near(turned[2].x, 192, 1e-4) and near(turned[2].y, 384, 1e-4))

local pts = {}
for slot = 1, 5 do
	pts[slot] = D.ringCandidates(slot, 5, 40)[1]
	check("slot " .. slot .. " sits on the 40 unit ring", near(dist2(pts[slot], { x = 0, y = 0 }), 40, 1e-6))
end
check("slot 1 is due east of the flag", near(pts[1].x, 40, 1e-6) and near(pts[1].y, 0, 1e-6) and pts[1].yaw == 0)
local minSep = 1e9
for i = 1, 5 do
	for j = i + 1, 5 do
		local d = dist2(pts[i], pts[j])
		if d < minSep then minSep = d end
	end
end
check("five spawn points do not stack", minSep > 32)

local pushed, index = D.chooseCandidate(1, 5, 40, function(_, i) return i == 1 end)
check("a blocked ring point uses the next candidate", index == 2 and near(dist2(pushed, { x = 0, y = 0 }), 72, 1e-6))
local last, lastIndex = D.chooseCandidate(1, 5, 40, function() return true end)
check("every blocked candidate still returns a point", last ~= nil and lastIndex == 7)

local flag = { pos = { x = 100, y = -50, z = 8 } }
local stood, stoodAng = D.playerPoint(flag, 1, 5, function(_, i) return i == 1 end)
check("player spawn is the flag plus the ring offset", stood and near(stood.x, 172) and near(stood.y, -50) and stood.z == 8 and stoodAng.p == 0)

local dx, dy = D.pan(0, { w = true }, 10)
check("W pans toward the top of a top-down view", near(dx, 10, 1e-6) and near(dy, 0, 1e-6))
dx, dy = D.pan(0, { d = true }, 10)
check("D pans toward the right of a top-down view", near(dx, 0, 1e-6) and near(dy, -10, 1e-6))
dx, dy = D.pan(0, { w = true, d = true }, 10)
check("diagonal pan keeps the same speed", near(math.sqrt(dx * dx + dy * dy), 10, 1e-6))
check("no keys do not pan", D.pan(0, {}, 10) == 0)

local eye = { x = 10, y = 20, yaw = 0, halfW = 100, halfH = 50 }
local center = D.groundPoint(80, 40, 160, 80, eye)
check("screen center is the camera", center and near(center.x, 10, 1e-6) and near(center.y, 20, 1e-6))
local top = D.groundPoint(80, 0, 160, 80, eye)
check("the top of the screen is +X when the camera looks down", top and near(top.x, 60, 1e-6) and near(top.y, 20, 1e-6))

local wide = D.overview({ x = -100, y = -5000, z = -20 }, { x = 100, y = 5000, z = 40 }, 90, 16 / 9)
check("overview frames every corner of the bounds", D.covers(wide, -100, -5000) and D.covers(wide, 100, 5000) and D.covers(wide, -100, 5000) and D.covers(wide, 100, -5000))
check("overview does not claim a point far outside", D.covers(wide, 0, 50000) == false)
check("overview sits above the top of the bounds", wide.z > 40)
local flat = D.overview({ x = -5000, y = -5000, z = -16 }, { x = 5000, y = 5000, z = 16 }, 90, 1)
check("a flat map is still framed from above", flat.z > 16 and D.covers(flat, -5000, -5000) and D.covers(flat, 5000, 5000))
local missing = D.overview(nil, nil, 90, 1)
check("missing bounds fall back to a high overview", missing.x == 0 and missing.y == 0 and missing.z == 4096 and missing.halfH == 2048)
local zoomed = D.zoom(100, 1, 2)
check("scroll in shrinks the window", near(zoomed, 85))
zoomed = D.zoom(70, 1, 1)
check("zoom does not go below 64", zoomed == 64)

local nodes = 0
local enabled = 0
BALLISTICS.AdminTabs.Walk(nil, function(node)
	nodes = nodes + 1
	if node.reset and node.reset.enabled then enabled = enabled + 1 end
end)
local spawns = BALLISTICS.AdminTabs.Find("spawns")
local req = BALLISTICS.AdminTabs.ResetRequest(spawns)
check("the Spawns tab is live and its reset is not a config section", spawns.implemented == true and req and req.kind == "spawns" and req.section == nil and enabled == 10)

-- Server: admin-only place/save/reset, file then defaults then none.
local disk = {}
function file.Exists(path) return disk[path] ~= nil end
function file.Read(path) return disk[path] end
function file.Write(path, contents) disk[path] = contents end
function file.Delete(path) disk[path] = nil end
function file.CreateDir() end

function util.TraceLine(tr)
	return {
		Hit = true,
		HitSky = false,
		HitPos = { x = tr.start.x, y = tr.start.y, z = 7 },
	}
end

local handlers = {}
function net.Receive(name, fn)
	handlers[name] = fn
end
local queue = {}
function net.ReadUInt() return table.remove(queue, 1) or 0 end
function net.ReadFloat() return table.remove(queue, 1) or 0 end

local mapNow = "gm_construct"
function game.GetMap() return mapNow end
local clock = 0
function CurTime() return clock end

dofile("gamemodes/ballistics/gamemode/modules/spawns/sv_spawns.lua")
-- The real server reloads on InitPostEntity, not at file load.
check("no flags are loaded at file load (waits for InitPostEntity)", BALLISTICS.Spawns.HasBoth() == false)
BALLISTICS.Spawns.Reload()

local function person(id, admin)
	return {
		IsAdmin = function() return admin end,
		IsSuperAdmin = function() return false end,
		SteamID64 = function() return id end,
		ChatPrint = function() end,
	}
end

local admin = person("ADMIN", true)
local user = person("USER", false)
local OP = D

local function snap()
	return BALLISTICS.Spawns.Snapshot()
end

local loaded = snap()
check("server loads construct defaults and snaps them to the ground", loaded.source == "defaults" and loaded.dirty == false and D.hasBoth(loaded) and loaded.good.pos.z == 7 and near(loaded.good.pos.x, defs.gm_construct.good.pos.x, 1e-6))
check("the default box snaps to ground plus half its height", loaded.box and BALLISTICS.Spawns.HasBox() == true and near(loaded.box.pos.z, 71, 1e-6) and near(loaded.box.sx, 768, 1e-6))

local pos, ang = BALLISTICS.Spawns.PlayerSpawn(TEAM_GOOD, 1)
check("Good slot 1 stands 40 units east of its flag", pos and near(pos.x, loaded.good.pos.x + 40, 1e-4) and near(pos.y, loaded.good.pos.y, 1e-4) and near(pos.z, 9, 1e-6) and ang and ang.p == 0)
local badPos = BALLISTICS.Spawns.PlayerSpawn(TEAM_BAD, 1)
check("Bad spawns on its own flag, not Good's", badPos and near(badPos.x, loaded.bad.pos.x + 40, 1e-4) and math.abs(badPos.x - pos.x) > 500)

util.TraceHull = function(tr)
	local flag = snap().good.pos
	local ddx = tr.start.x - flag.x
	local ddy = tr.start.y - flag.y
	if math.sqrt(ddx * ddx + ddy * ddy) < 50 then return { StartSolid = true } end
	return { StartSolid = false }
end
local nudged = BALLISTICS.Spawns.PlayerSpawn(TEAM_GOOD, 1)
check("a blocked hull steps out to the next ring", nudged and near(dist2(nudged, loaded.good.pos), 72, 1e-3))
util.TraceHull = nil

local function netPlace(ply, team, x, y, z)
	queue = { OP.OP_PLACE, team, x, y, z, 0, 90, 0 }
	handlers.bal_spawn_place(nil, ply)
end

local before = snap().good.pos.x
netPlace(user, TEAM_GOOD, 0, 0, 0)
check("a non-admin place request is ignored", snap().good.pos.x == before)
local direct = BALLISTICS.Spawns.Handle(user, { op = OP.OP_PLACE, team = 1, pos = { x = 0, y = 0, z = 0 } })
check("Handle refuses a non-admin", direct == false and snap().good.pos.x == before)

local rejected = BALLISTICS.Spawns.Handle(admin, { op = OP.OP_PLACE, team = 9, pos = { x = 0, y = 0, z = 0 } })
check("the server rejects a bad team", rejected == false)
rejected = BALLISTICS.Spawns.Handle(admin, { op = OP.OP_PLACE, team = 2, pos = { x = snap().good.pos.x + 10, y = snap().good.pos.y, z = 0 } })
check("the server rejects a flag on top of the other", rejected == false and snap().bad.pos.x == loaded.bad.pos.x)

for i = 1, 10 do
	netPlace(admin, TEAM_GOOD, 100 * i, 0, 50)
end
check("ten places update the Good flag and mark it unsaved", near(snap().good.pos.x, 1000, 1e-6) and snap().good.pos.z == 7 and snap().dirty == true)
netPlace(admin, TEAM_GOOD, 50, 0, 0)
check("places past the rate limit are dropped", near(snap().good.pos.x, 1000, 1e-6))
clock = 5

queue = { OP.OP_BOX, 0, 100, 200, 40, 0, 90, 0, 768, 384 }
handlers.bal_spawn_place(nil, admin)
check("an admin can place the firing squad box", snap().box and near(snap().box.pos.x, 100, 1e-6) and near(snap().box.pos.y, 200, 1e-6) and near(snap().box.pos.z, 71, 1e-6) and near(snap().box.yaw, 90, 1e-6) and near(snap().box.sx, 768, 1e-6) and snap().dirty == true)
queue = { OP.OP_BOX, 0, 1, 2, 3, 0, 0, 0, 768, 384 }
handlers.bal_spawn_place(nil, user)
check("a non-admin cannot place the box", near(snap().box.pos.x, 100, 1e-6))

queue = { OP.OP_SAVE, 0, 0, 0, 0, 0, 0, 0 }
handlers.bal_spawn_place(nil, admin)
local path = D.mapFile("gm_construct")
local saved = D.fromJSON(disk[path] or "")
check("save writes this map's JSON", saved and near(saved.good.pos.x, 1000) and saved.bad and saved.box and snap().source == "file" and snap().dirty == false)

mapNow = "gm_construct"
BALLISTICS.Spawns.Reload()
check("reload reads the saved file back", near(snap().good.pos.x, 1000, 1e-6) and snap().source == "file" and D.hasBoth(snap()) and snap().box and near(snap().box.pos.x, 100, 1e-6) and near(snap().box.yaw, 90, 1e-6))

disk[path] = '{"good":{"pos":{"x":12,"y":0,"z":1},"ang":{"p":0,"y":0,"r":0}},"bad":null}'
BALLISTICS.Spawns.Reload()
check("a partial file is not filled in from defaults", snap().source == "file" and snap().bad == nil and snap().box == nil and near(snap().good.pos.x, 12, 1e-6) and BALLISTICS.Spawns.HasBoth() == false and BALLISTICS.Spawns.HasBox() == false)

disk[path] = "{broken"
BALLISTICS.Spawns.Reload()
check("a broken file falls back to built-in defaults", snap().source == "defaults" and BALLISTICS.Spawns.HasBoth() == true and near(snap().good.pos.x, defs.gm_construct.good.pos.x, 1e-6))

queue = { OP.OP_RESET, 0, 0, 0, 0, 0, 0, 0 }
-- Put a saved override down, then reset must delete it.
disk[path] = D.toJSON(snap())
BALLISTICS.Spawns.Reload()
handlers.bal_spawn_place(nil, admin)
check("reset deletes the save and restores defaults", disk[path] == nil and snap().source == "defaults" and near(snap().good.pos.x, defs.gm_construct.good.pos.x, 1e-6) and snap().dirty == false)

mapNow = "gm_nowhere"
BALLISTICS.Spawns.Reload()
check("a map with no file and no defaults has no flags", snap().source == "none" and BALLISTICS.Spawns.HasBoth() == false)
local nonePos = BALLISTICS.Spawns.PlayerSpawn(TEAM_GOOD, 1)
check("players are not given a fake flag when none is placed", nonePos == nil)
queue = { OP.OP_RESET, 0, 0, 0, 0, 0, 0, 0 }
handlers.bal_spawn_place(nil, admin)
check("reset on a map with no defaults stays empty", snap().source == "none" and disk[D.mapFile("gm_nowhere")] == nil and BALLISTICS.Spawns.HasBoth() == false)

-- Place both, save, and come back after a reload.
netPlace(admin, TEAM_GOOD, -400, 0, 3)
netPlace(admin, TEAM_BAD, 400, 0, 3)
queue = { OP.OP_SAVE, 0, 0, 0, 0, 0, 0, 0 }
handlers.bal_spawn_place(nil, admin)
BALLISTICS.Spawns.Reload()
check("saved flags for a map without defaults come back", BALLISTICS.Spawns.HasBoth() == true and near(snap().good.pos.x, -400, 1e-6) and near(snap().bad.pos.x, 400, 1e-6) and snap().source == "file" and BALLISTICS.Spawns.HasBox() == false)

concommand = { Add = function() end }
dofile("gamemodes/ballistics/gamemode/core/sh_state.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_round.lua")
check("the round will not start until both flags exist", BALLISTICS.HasBothFlags() == true)
local through = BALLISTICS.Round.SpawnTransform(TEAM_GOOD, 1)
local directSpawn = BALLISTICS.Spawns.PlayerSpawn(TEAM_GOOD, 1)
check("the round uses the spawns module for the spawn transform", through and directSpawn and near(through.x, directSpawn.x, 1e-6) and near(through.y, directSpawn.y, 1e-6) and near(through.z, directSpawn.z, 1e-6))

mapNow = "gm_empty"
disk[D.mapFile("gm_empty")] = nil
BALLISTICS.Spawns.Reload()
check("with no flags the round reports them missing", BALLISTICS.HasBothFlags() == false and BALLISTICS.Round.SpawnTransform(TEAM_BAD, 2) == nil)

local oldTrace = util.TraceLine
util.TraceLine = function() return { Hit = false } end
local missed = BALLISTICS.Spawns.Handle(admin, { op = D.OP_BOX, pos = { x = 5, y = 6, z = 80 }, ang = { y = 15 }, sx = 200, sy = 300 })
check("a missed ground trace keeps the centre height", missed == true and snap().box and near(snap().box.pos.z, 80, 1e-6) and near(snap().box.yaw, 15, 1e-6))
util.TraceLine = oldTrace

mapNow = "gm_construct"
local made = {}
ents = ents or {}
function ents.Create()
	local ent = { kv = {} }
	function ent:SetModel(m) self.model = m end
	function ent:SetPos(p) self.pos = p end
	function ent:SetAngles(a) self.ang = a end
	function ent:SetKeyValue(k, v) self.kv[k] = v end
	function ent:SetSolid(s) self.solid = s end
	function ent:SetNotSolid(v) self.notSolid = v end
	function ent:SetMoveType(m) self.move = m end
	function ent:SetCollisionGroup(g) self.collision = g end
	function ent:DrawShadow() end
	function ent:GetPhysicsObject()
		return {
			IsValid = function() return true end,
			EnableMotion = function(_, on) ent.motion = on end,
			EnableCollisions = function(_, on) ent.collisions = on end,
		}
	end
	function ent:Spawn()
		self.spawned = true
		self.solid = 6
	end
	function ent:Activate() end
	function ent:SetNW2Int(_, v) self.nw = v end
	function ent:GetNW2Int() return self.nw or 0 end
	function ent:IsValid() return true end
	made[#made + 1] = ent
	return ent
end
BALLISTICS.Spawns.Reload()
check("flag props use the team models", #made == 2 and made[1].model == D.FLAG_MODEL_GOOD and made[2].model == D.FLAG_MODEL_BAD)
check("spawn cannot make a flag solid again", made[1].solid == 0 and made[1].notSolid == true and made[1].kv.solid == "0" and made[1].motion == false and made[1].collisions == false and made[1].collision == 10)
check("a flag cannot be picked up or shot", made[1].PhysgunPickup() == false and made[1].GravGunPickupAllowed() == false and made[1].GravGunPunt() == false and hook.Run("PhysgunPickup", nil, made[1]) == false and hook.Run("EntityTakeDamage", made[1]) == true and hook.Run("ShouldCollide", made[1], {}) == false)
ents.Create = nil

local editor = loadfile("gamemodes/ballistics/gamemode/modules/spawns/cl_spawns_editor.lua")
local tab = loadfile("gamemodes/ballistics/gamemode/modules/admin/cl_tab_spawns.lua")
check("spawn editor and Spawns tab compile", editor ~= nil and tab ~= nil)

if failed then os.exit(1) end
