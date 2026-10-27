-- Run: luajit tests/test_inithooks.lua
-- A value returned from an Initialize/InitPostEntity hook stops every later
-- hook for that event (GMod hook.Call). TacRP builds TacRP.QuickNades_Index in
-- InitPostEntity; when our TeamModel.Wrap returned false it never ran, and
-- every TacRP Give crashed in SetBaseSettings (GetGrenade() was nil).
local failed = false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
local p = io.popen("find gamemodes/ballistics/gamemode -name '*.lua'")
local bad = {}
for path in p:lines() do
	local src = io.open(path):read("*a")
	for ev, ref in src:gmatch('hook%.Add%("(Init%a*)",%s*[^,]+,%s*([%w_%.]+)%s*%)') do
		bad[#bad + 1] = path .. " " .. ev .. " " .. ref
	end
end
p:close()
check("no Init hook passes a bare function that may return a value: " .. table.concat(bad, ", "), #bad == 0)

SERVER = true
BALLISTICS = { Player = { ModelFor = function() return nil end } }
PLAYER_BALLISTICS = { ApplyModel = function() end }
local added = {}
hook = { Add = function(ev, name, fn) added[ev .. "/" .. name] = fn end }
timer = nil
dofile("gamemodes/ballistics/gamemode/modules/teammodel/sv_teammodel.lua")
local fn = added["InitPostEntity/Ballistics_TeamModel"]
check("team model InitPostEntity hook returns nothing", fn ~= nil and select("#", fn()) == 0)
if failed then os.exit(1) end
