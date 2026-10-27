-- Run: luajit tests/test_etap.lua
BALLISTICS = {}
dofile("gamemodes/ballistics/gamemode/modules/etap/sh_etap.lua")
local E, failed = BALLISTICS.ETap, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
check("quick tap grabs", E.OnRelease({ at = 1 }, 1.1, false) == "grab")
check("quick tap while dragging drops", E.OnRelease({ at = 1 }, 1.1, true) == "drop")
check("hold past buffer never drags", E.OnRelease({ at = 1 }, 1.3, false) == nil)
check("press that closed the loot window never drags", E.OnRelease({ at = 1, consumed = true }, 1.05, false) == nil)
check("no press, nothing", E.OnRelease(nil, 1, false) == nil)
if failed then os.exit(1) end
