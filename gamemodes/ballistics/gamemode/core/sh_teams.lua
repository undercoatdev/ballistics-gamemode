-- Team ids and names. 5 slots per side live in Config.SlotsPerTeam / sv_slots.

BALLISTICS = BALLISTICS or {}

TEAM_GOOD = 1
TEAM_BAD = 2
TEAM_SPEC = TEAM_SPECTATOR or 1002

BALLISTICS.TEAM_GOOD = TEAM_GOOD
BALLISTICS.TEAM_BAD = TEAM_BAD
BALLISTICS.TEAM_SPEC = TEAM_SPEC

local function col(r, g, b)
	if Color then return Color(r, g, b) end
	return { r = r, g = g, b = b, a = 255 }
end

BALLISTICS.TeamColor = {
	[TEAM_GOOD] = col(70, 140, 255),
	[TEAM_BAD] = col(220, 50, 50),
	[TEAM_SPEC] = col(180, 180, 180),
}

BALLISTICS.TeamName = {
	[TEAM_GOOD] = "Good",
	[TEAM_BAD] = "Bad",
	[TEAM_SPEC] = "Spectator",
}

function BALLISTICS.IsPlayingTeam(id)
	return id == TEAM_GOOD or id == TEAM_BAD
end

if team and team.SetUp then
	team.SetUp(TEAM_GOOD, "Good", BALLISTICS.TeamColor[TEAM_GOOD])
	team.SetUp(TEAM_BAD, "Bad", BALLISTICS.TeamColor[TEAM_BAD])
	team.SetUp(TEAM_SPEC, "Spectator", BALLISTICS.TeamColor[TEAM_SPEC])
end
