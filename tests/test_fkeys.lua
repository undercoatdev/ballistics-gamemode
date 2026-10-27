-- Run: luajit tests/test_fkeys.lua
BALLISTICS = {}
dofile("gamemodes/ballistics/gamemode/modules/fkeys/sh_fkeys.lua")
local F, failed = BALLISTICS.FKeys, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
local e = F.NewEdge()
check("press fires", F.Step(e, true, 1, false) == true)
check("held does not repeat", F.Step(e, true, 1.1, false) == false)
F.Step(e, false, 1.15, false)
check("bounce inside debounce ignored", F.Step(e, true, 1.2, false) == false)
F.Step(e, false, 1.3, false)
check("second press closes", F.Step(e, true, 2, false) == true)
F.Step(e, false, 2.1, false)
check("typing blocks", F.Step(e, true, 3, true) == false)
check("still held after typing does not fire", F.Step(e, true, 3.5, false) == false)
if failed then os.exit(1) end
