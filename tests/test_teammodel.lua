-- Run: luajit tests/test_teammodel.lua
SERVER = true
BALLISTICS = { Player = { ModelFor = function(t) return t == 1 and "good.mdl" or t == 2 and "bad.mdl" or nil end } }
local pbCalls = 0
PLAYER_BALLISTICS = { ApplyModel = function(ply) pbCalls = pbCalls + 1; ply:SetModel("elite.mdl") end }
hook, timer = nil, nil
dofile("gamemodes/ballistics/gamemode/modules/teammodel/sv_teammodel.lua")
local failed = false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
local function mk(t) local p = { m = "x" }; function p:Team() return t end; function p:SetModel(m) self.m = m end; function p:GetModel() return self.m end; return p end
local g, b, s = mk(1), mk(2), mk(1002)
PLAYER_BALLISTICS.ApplyModel(g); PLAYER_BALLISTICS.ApplyModel(b); PLAYER_BALLISTICS.ApplyModel(s)
check("good gets soldier over PB", g.m == "good.mdl")
check("bad gets team model over PB", b.m == "bad.mdl")
check("spectator keeps PB choice", s.m == "elite.mdl" and pbCalls == 1)
check("wrap only once", BALLISTICS.TeamModel.Wrap() == false)
if failed then os.exit(1) end
