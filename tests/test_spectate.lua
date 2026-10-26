-- Death spectate. Run: luajit tests/test_spectate.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end
dofile("tests/support/gmod_stub.lua")
BALLISTICS = BALLISTICS or {}
dofile("gamemodes/ballistics/gamemode/modules/spectate/sh_spectate.lua")
local S = BALLISTICS.Spectate
local a, b, c = {}, {}, {}
check("first pick is first mate", S.Pick({ a, b, c }, nil, nil) == a)
check("keep current", S.Pick({ a, b, c }, b, 0) == b)
check("left click next", S.Pick({ a, b, c }, b, 1) == c)
check("next wraps", S.Pick({ a, b, c }, c, 1) == a)
check("right click previous wraps", S.Pick({ a, b, c }, a, -1) == c)
check("dead current moves on", S.Pick({ a, c }, b, nil) == a)
check("nobody left", S.Pick({}, a, 1) == nil)
check("lobby keeps free cam", not S.PhaseFollows("lobby") and S.PhaseFollows("live") and S.PhaseFollows("squad"))
check("label", S.Label("Bot01") == "Spectating: Bot01" and S.Label("") == nil)
check("smoothing in range", S.Blend(0) == 0 and S.Blend(1 / 60) > 0 and S.Blend(1 / 60) < 1)

-- Server: bots are followed like players; knocked out counts as alive.
local function mk(id, alive)
	local p = { id = id, alive = alive, nw = {} }
	function p:Alive() return self.alive end
	function p:IsValid() return true end
	function p:Spectate(m) self.mode = m end
	function p:SpectateEntity(e) self.watch = e end
	function p:SetNW2Entity(k, v) self.nw[k] = v end
	return p
end
local me, bot1, bot2 = mk("me", false), mk("bot:3", true), mk("bot:4", true)
BALLISTICS.IsPlayer = function(p) return type(p) == "table" end
BALLISTICS.PlayerId = function(p) return p.id end
BALLISTICS.Slots = {
	TeamOf = function() return 1, 1 end,
	Members = function() return { "me", "bot:3", "bot:4" } end,
	Player = function(id) return ({ me = me, ["bot:3"] = bot1, ["bot:4"] = bot2 })[id] end,
}
dofile("gamemodes/ballistics/gamemode/core/sv_player.lua")
BALLISTICS.Player.Track(me)
BALLISTICS.Player.SpectateTeammates(me)
check("dead player follows a bot teammate in eye", me.watch == bot1 and me.mode == (OBS_MODE_IN_EYE or 4) and me.nw.bal_spec == bot1)
BALLISTICS.Player.SpectateTeammates(me, 1)
check("next teammate", me.watch == bot2)
bot2.alive = false
BALLISTICS.Player.RetargetSpectators(bot2)
check("watched mate died, switch", me.watch == bot1)
bot1.alive = false
BALLISTICS.Player.SpectateTeammates(me)
check("no mates: no free roam", me.mode == (OBS_MODE_FIXED or 2))
if failed then os.exit(1) end
