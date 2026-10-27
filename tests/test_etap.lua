-- Run: luajit tests/test_etap.lua
BALLISTICS = {}
dofile("gamemodes/ballistics/gamemode/modules/etap/sh_etap.lua")
local E, failed = BALLISTICS.ETap, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
local a, t = E.OnRelease({ at = 1 }, 1.1, false, nil)
check("a single tap does nothing but is remembered", a == nil and t == 1.1)
check("double tap grabs", (E.OnRelease({ at = 1.2 }, 1.3, false, 1.1)) == "grab")
check("double tap while dragging drops", (E.OnRelease({ at = 1.2 }, 1.3, true, 1.1)) == "drop")
local a2, t2 = E.OnRelease({ at = 2 }, 2.1, false, 1.1)
check("taps too far apart do not drag", a2 == nil and t2 == 2.1)
check("hold past buffer never drags", E.OnRelease({ at = 1 }, 1.3, false, 1.0) == nil)
check("press that closed the loot window never drags", E.OnRelease({ at = 1, consumed = true }, 1.05, false, 0.9) == nil)
check("no press, nothing", E.OnRelease(nil, 1, false) == nil)
check("hint while aiming", E.HintText("E", false, true) == "Double-tap E to drag, hold E to loot")
check("hint while dragging", E.HintText("E", true, false) == "Double-tap E to drop")
check("no hint otherwise", E.HintText("E", false, false) == nil)
if failed then os.exit(1) end
