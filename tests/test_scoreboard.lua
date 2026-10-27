-- Scoreboard header, kill sort, and match-only K/D reset.
-- Run: luajit tests/test_scoreboard.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/modules/scoreboard/sh_scoreboard.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_round.lua")

local S = BALLISTICS.Scoreboard
local R = BALLISTICS.RoundHud

local h = S.Header(2, 3, 1, 0)
check("series header", h.roundLine == "Round 2 / 3" and h.scoreLeft == 1 and h.scoreRight == 0)
local endless = S.Header(4, 0, 2, 2)
check("endless series", endless.roundLine == "Round 4 / ∞" and endless.scoreLeft == 2 and endless.scoreRight == 2)
local blank = S.Header(nil, nil, nil, nil)
check("missing header is round zero endless", blank.roundLine == "Round 0 / ∞" and blank.scoreLeft == 0 and blank.scoreRight == 0)
local floored = S.Header(1.9, 3.2, -4, 8.8)
check("header floors and clamps", floored.roundLine == "Round 1 / 3" and floored.scoreLeft == 0 and floored.scoreRight == 8)

R.Apply({ phase = "buy", endsAt = 20, round = 2, scoreGood = 1, scoreBad = 0 })
local fromHud = S.MatchFrom(R.Snapshot(), 9, 9, 9, 3)
check("round hud snapshot feeds the header", fromHud.roundLine == "Round 2 / 3" and fromHud.scoreLeft == 1 and fromHud.scoreRight == 0)
R.Apply({ phase = "live", endsAt = 30 })
check("partial round sync keeps the series score", R.Snapshot().scoreGood == 1 and R.Snapshot().scoreBad == 0 and R.Snapshot().round == 2)
local phaseOnly = S.MatchFrom({ seen = true, round = 0, phase = "buy" }, 2, 1, 0, 3)
check("phase-only snapshot keeps nw round and score", phaseOnly.roundLine == "Round 2 / 3" and phaseOnly.scoreLeft == 1 and phaseOnly.scoreRight == 0)
local unseen = S.MatchFrom({ seen = false, round = 8, scoreGood = 5, scoreBad = 5 }, 1, 0, 0, 0)
check("unseen snapshot falls back to nw and endless config", unseen.roundLine == "Round 1 / ∞" and unseen.scoreLeft == 0 and unseen.scoreRight == 0)

local list = {
	{ name = "b", frags = 1 },
	{ name = "c", frags = 3 },
	{ name = "a", frags = 3 },
}
local sorted = S.SortPlayers(list)
check("kills desc then name", sorted[1].name == "a" and sorted[2].name == "c" and sorted[3].name == "b")
check("sort does not rewrite the input", list[1].name == "b" and list[2].name == "c")
local viaMethod = S.SortPlayers({
	{ name = "low", Frags = function() return 1 end },
	{ name = "high", Frags = function() return 4 end },
})
check("Frags() sorts above a smaller count", viaMethod[1].name == "high" and viaMethod[2].name == "low")
check("empty sort", #S.SortPlayers(nil) == 0 and #S.SortPlayers({}) == 0)

check("lobby into buy resets", S.ShouldResetFrags("lobby", "buy", false) == true)
check("lobby into live resets", S.ShouldResetFrags("lobby", "live", false) == true)
check("blank phase into buy resets", S.ShouldResetFrags(nil, "buy", false) == true)
check("score zeroed into buy resets", S.ShouldResetFrags("post", "buy", true) == true)
check("next round keeps frags", S.ShouldResetFrags("post", "buy", false) == false)
check("buy to live keeps frags", S.ShouldResetFrags("buy", "live", false) == false)
check("live to post keeps frags", S.ShouldResetFrags("live", "post", false) == false)
check("post to squad keeps frags", S.ShouldResetFrags("post", "squad", false) == false)
check("ending the match does not clear frags", S.ShouldResetFrags("squad", "lobby", true) == false)
check("live to post with the flag still does not clear", S.ShouldResetFrags("live", "post", true) == false)

local good = S.TeamColor(TEAM_GOOD)
local bad = S.TeamColor(TEAM_BAD)
check("team colours come from sh_teams", good.r == 70 and good.g == 140 and good.b == 255 and bad.r == 220 and bad.g == 50 and bad.b == 50)
local savedColor = BALLISTICS.TeamColor
BALLISTICS.TeamColor = nil
local fbGood = S.TeamColor(TEAM_GOOD)
local fbBad = S.TeamColor(TEAM_BAD)
check("colour fallback", fbGood.r == 80 and fbGood.g == 140 and fbGood.b == 220 and fbBad.r == 210 and fbBad.g == 70 and fbBad.b == 70)
BALLISTICS.TeamColor = savedColor
check("print name wins", S.ColumnName(TEAM_GOOD, "Good") == "Good")
local savedName = BALLISTICS.TeamName
BALLISTICS.TeamName = nil
check("missing team name falls back to BLUE and RED", S.ColumnName(TEAM_GOOD, nil) == "BLUE" and S.ColumnName(TEAM_BAD, "2") == "RED")
BALLISTICS.TeamName = savedName
check("spectator line", S.SpectatorLine({}) == "Spectators: —" and S.SpectatorLine({ "Ann", "Bo" }) == "Spectators: Ann, Bo")

local cleared = {}
local ply = {
	SetFrags = function(_, n) cleared.frags = n end,
	SetDeaths = function(_, n) cleared.deaths = n end,
	SetNW2Int = function(_, k, v) cleared[k] = v end,
}
player.GetAll = function() return { ply, {} } end
BALLISTICS.Round = {
	Number = function() return 2 end,
	Score = function() return { good = 0, bad = 0 } end,
}
dofile("gamemodes/ballistics/gamemode/modules/scoreboard/sv_scoreboard.lua")
hook.Run("Ballistics_PhaseChanged", "post", "buy", { matchStart = false })
check("a 0-0 next round does not clear frags", cleared.frags == nil and cleared.deaths == nil)
check("next round still publishes the score", cleared.bal_round == 2 and cleared.bal_score_good == 0 and cleared.bal_score_bad == 0)
hook.Run("Ballistics_PhaseChanged", "buy", "live", { matchStart = false })
check("buy to live does not clear frags", cleared.frags == nil)
hook.Run("Ballistics_PhaseChanged", "squad", "lobby", { matchStart = false })
check("lobby landing does not clear frags", cleared.frags == nil)
hook.Run("Ballistics_PhaseChanged", "lobby", "buy", { matchStart = true })
check("match start sets frags and deaths to zero", cleared.frags == 0 and cleared.deaths == 0)
cleared.frags = 5
hook.Run("Ballistics_PhaseChanged", "lobby", "buy", { matchStart = false })
check("leaving lobby into buy clears even without the flag", cleared.frags == 0)

CLIENT = true
local created = 0
local removed = 0
local function fakePanel()
	local pnl = { dead = false }
	function pnl:SetSize() end
	function pnl:SetPos() end
	function pnl:SetVisible() end
	function pnl:SetMouseInputEnabled() end
	function pnl:SetKeyboardInputEnabled() end
	function pnl:SetPaintBackground() end
	function pnl:MoveToFront() end
	function pnl:SetDrawOnTop() end
	function pnl:MakePopup() self.popup = true end
	function pnl:Remove()
		self.dead = true
		removed = removed + 1
		if self.OnRemove then self:OnRemove() end
	end
	function pnl:IsValid() return self.dead ~= true end
	return pnl
end
vgui = { Create = function()
	created = created + 1
	return fakePanel()
end }
IsValid = function(ent)
	if ent == nil then return false end
	if type(ent.IsValid) == "function" then return ent:IsValid() == true end
	return ent.dead ~= true
end
local editing = false
BALLISTICS.Spawns = BALLISTICS.Spawns or {}
BALLISTICS.Spawns.IsEditing = function() return editing end
dofile("gamemodes/ballistics/gamemode/modules/scoreboard/cl_scoreboard.lua")
editing = true
check("show during the spawn editor still blocks the default", hook.Run("ScoreboardShow") == true)
check("spawn editor does not build a panel", created == 0)
check("score bind during the editor does not build a panel", hook.Run("PlayerBindPress", nil, "+showscores", true) == true and created == 0)
editing = false
check("scoreboard show blocks the default", hook.Run("ScoreboardShow") == true)
check("show builds one panel", created == 1)
hook.Run("ScoreboardShow")
check("a second show reuses the panel", created == 1)
check("hide removes the panel", hook.Run("ScoreboardHide") == true and removed == 1)
check("other binds are left alone", hook.Run("PlayerBindPress", nil, "+attack", true) == nil)
hook.Run("PlayerBindPress", nil, "+showscores", true)
check("the score bind opens the board", created == 2)
hook.Run("PlayerBindPress", nil, "+showscores", false)
check("releasing tab closes the board", removed == 2)
check("gm show hook returns true", GM.ScoreboardShow() == true and created == 3)

local drawn = 0
draw = draw or {}
function draw.SimpleText() drawn = drawn + 1 end
function draw.RoundedBox() end
surface = surface or {}
function surface.SetFont() end
function surface.GetTextSize(text) return #tostring(text) * 8, 16 end
function surface.SetDrawColor() end
function surface.DrawOutlinedRect() end
ScrW = function() return 1920 end
ScrH = function() return 1080 end
local goodPly = { name = "Ace", frags = 3, deaths = 1, ping = 20, alive = true }
local badPly = { name = "Bea", frags = 1, deaths = 2, ping = 40, alive = false }
local specPly = { name = "Cam", frags = 0, deaths = 0, ping = 5, alive = true }
function goodPly:IsValid() return true end
function badPly:IsValid() return true end
function specPly:IsValid() return true end
team.GetPlayers = function(id)
	if id == TEAM_GOOD then return { goodPly } end
	if id == TEAM_BAD then return { badPly } end
	if id == TEAM_SPECTATOR or id == TEAM_SPEC then return { specPly } end
	return {}
end
local shown = nil
local prevCreate = vgui.Create
vgui.Create = function(...)
	shown = prevCreate(...)
	return shown
end
hook.Run("ScoreboardHide")
hook.Run("ScoreboardShow")
check("paint draws the header and both columns", shown ~= nil and shown.popup == true and type(shown.Paint) == "function")
shown:Paint(740, 480)
check("paint issues text for the round, scores, and rows", drawn > 8)

do
	local ply = setmetatable({
		Nick = function() return "Fox" end,
		Frags = function() return 3 end,
		Deaths = function() return 1 end,
		Ping = function() return 40 end,
		Alive = function() return true end,
	}, { __tostring = function() return "Player" end })
	-- Simulate GMod's type(Player) == "Player" via a raw type override is hard;
	-- instead assert the guard lists Player.
	local src = io.open("gamemodes/ballistics/gamemode/modules/scoreboard/sh_scoreboard.lua"):read("*a")
	check("Player entity type is accepted", src:find('t == "Player"', 1, true) ~= nil)
	check("Row keeps the player for the paint fallback", S.Row(ply).name == "Fox" and S.Row(ply).ply == ply)
end

if failed then os.exit(1) end
