-- Run: luajit tests/test_pushforce.lua
bit = require("bit")
BALLISTICS = { Config = {} }
dofile("gamemodes/ballistics/gamemode/modules/pushforce/sh_pushforce.lua")
local P, failed = BALLISTICS.PushForce, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
check("default halves bullets", P.ScaleFor(2, false) == 0.5)
check("bullet flag counts", P.ScaleFor(0, true) == 0.5)
check("non-bullet untouched", P.ScaleFor(64, false) == nil)
BALLISTICS.Config.BulletPushForce = 1
check("1 = off", P.ScaleFor(2) == nil)
BALLISTICS.Config.BulletPushForce = -3
check("negative clamps to 0", P.ScaleFor(2) == 0)
if failed then os.exit(1) end
