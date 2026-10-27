-- Lobby view model, slot layout, admin tab reset policy, start net gate.
-- Run: luajit tests/test_lobby.lua
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
dofile("gamemodes/ballistics/gamemode/modules/admin/sh_tabs.lua")
dofile("gamemodes/ballistics/gamemode/modules/lobby/sh_view.lua")

local V = BALLISTICS.LobbyView
local GOOD = TEAM_GOOD
local BAD = TEAM_BAD
local SPEC = TEAM_SPEC

local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(r, w, h)
	return r.x >= 0 and r.y >= 0 and r.w > 0 and r.h >= 0 and r.x + r.w <= w and r.y + r.h <= h
end

local function rectsOf(layout)
	local list = {}
	for i = 1, #layout.columns do
		local col = layout.columns[i]
		list[#list + 1] = { x = col.x, y = col.y, w = col.w, h = col.h, kind = "header" }
		for s = 1, #col.slots do
			local slot = col.slots[s]
			list[#list + 1] = { x = slot.x, y = slot.y, w = slot.w, h = slot.h, kind = "slot" }
		end
	end
	if layout.status and layout.status.h > 0 then
		local s = layout.status
		list[#list + 1] = { x = s.x, y = s.y, w = s.w, h = s.h, kind = "status" }
	end
	if layout.start then
		local s = layout.start
		list[#list + 1] = { x = s.x, y = s.y, w = s.w, h = s.h, kind = "start" }
	end
	return list
end

local function layoutOk(layout)
	local rects = rectsOf(layout)
	if #layout.columns ~= 2 then return false end
	if #layout.columns[1].slots ~= layout.perTeam then return false end
	if #layout.columns[2].slots ~= layout.perTeam then return false end
	if layout.columns[1].team ~= GOOD or layout.columns[2].team ~= BAD then return false end
	if layout.columns[2].x < layout.columns[1].x + layout.columns[1].w then return false end
	for i = 1, #rects do
		if not inside(rects[i], layout.width, layout.height) then return false end
		for j = i + 1, #rects do
			if overlaps(rects[i], rects[j]) then return false end
		end
	end
	local last = layout.columns[1].slots[layout.perTeam]
	local header = layout.columns[1]
	if layout.columns[1].slots[1].y < header.y + header.h then return false end
	if layout.start then
		if layout.start.y < last.y + last.h then return false end
	end
	return true
end

local layout = V.Layout({ perTeam = 5 })
check("five slots sit in two columns inside the lobby", layoutOk(layout) and layout.slotH >= 36)
check("default slot height stays readable", layout.slotH == 40)

local wide, tall = V.PreferredSize(5)
check("preferred size matches the layout", wide == layout.width and tall == layout.height)

local one = V.Layout({ perTeam = 1 })
local many = V.Layout({ perTeam = 16 })
local clamped = V.Layout({ perTeam = 0 })
local capped = V.Layout({ perTeam = 40 })
check("one slot and sixteen slots still fit", layoutOk(one) and layoutOk(many))
check("slot count clamps to 1..16", clamped.perTeam == 1 and capped.perTeam == 16 and layoutOk(clamped) and layoutOk(capped))

local bare = V.Layout({ perTeam = 5, showStart = false, statusH = 0 })
check("a grid without Start keeps the slots inside", bare.start == nil and layoutOk(bare))

local targets = V.Targets(layout)
local slot = layout.columns[2].slots[3]
local hit = V.Hit(targets, slot.x + 1, slot.y + 1)
check("hit test finds the slot under the cursor", hit and hit.kind == "slot" and hit.team == BAD and hit.slot == 3)
local startHit = V.Hit(targets, layout.start.x + 1, layout.start.y + 1)
check("hit test finds Start", startHit and startHit.kind == "start")
check("hit test misses outside the panel", V.Hit(targets, -5, -5) == nil)
check("hit test is half-open on the right edge", V.Hit(targets, slot.x + slot.w, slot.y + 1) == nil)
check("first rect wins when zones overlap", V.Hit({
	{ kind = "slot", team = GOOD, slot = 2, x = 0, y = 0, w = 10, h = 10 },
	{ kind = "spectator", x = 0, y = 0, w = 10, h = 10 },
}, 1, 1).kind == "slot")

local function build(extra)
	local input = {
		perTeam = 5,
		phase = "lobby",
		isAdmin = false,
		minPerTeam = 1,
		sides = { [GOOD] = {}, [BAD] = {} },
		queue = {},
		players = {},
		names = {},
	}
	for k, v in pairs(extra or {}) do input[k] = v end
	return V.Build(input)
end

local empty = build()
check("empty lobby labels every slot Empty", empty.columns[1].slots[1].label == "Empty" and empty.columns[2].slots[5].label == "Empty")
check("empty lobby has no countdown", empty.showCountdown == false and empty.endsAt == nil)
check("non-admin in lobby waits for an admin", empty.start.waiting == true and empty.start.visible == false and empty.start.label == "Waiting for admin")

local named = build({
	sides = { [GOOD] = { [1] = { id = "a", name = "Ada" } }, [BAD] = {} },
})
local renamed = build({
	sides = { [GOOD] = { [1] = { id = "a", name = "Ada Lovelace" } }, [BAD] = {} },
})
check("slot names follow the snapshot", named.columns[1].slots[1].label == "Ada" and named.columns[1].slots[1].empty == false)
check("rebuilding the snapshot updates the name", renamed.columns[1].slots[1].label == "Ada Lovelace")

local mine = build({
	localId = "a",
	sides = { [GOOD] = { [2] = { id = "a", name = "Ada" } }, [BAD] = {} },
})
check("the local player is marked on their slot", mine.columns[1].slots[2].mine == true and mine.columns[1].slots[2].label == "Ada (you)" and mine.mine.slot == 2)

local sides = { [GOOD] = {}, [BAD] = { [1] = { id = "b", name = "Bea" } } }
for i = 1, 5 do
	sides[GOOD][i] = { id = "g" .. i, name = "G" .. i }
end
local full = build({ sides = sides, localId = "b" })
local allTaken = true
for i = 1, 5 do
	local decision = V.Click(full, GOOD, i, { phase = "lobby", alive = false })
	if decision.action ~= "refuse" or decision.reason ~= "taken" then allTaken = false end
end
check("a full side refuses every click", allTaken and full.counts.good == 5 and full.counts.bad == 1)
check("the other side still accepts a click", V.Click(full, BAD, 2, { phase = "lobby" }).action == "take")
local own = V.Click(mine, GOOD, 2, { phase = "lobby" })
check("clicking your own slot unslots you", own.action == "leave" and own.team == GOOD and own.slot == 2)
check("an alive player cannot unslot during live", V.Click(mine, GOOD, 2, { phase = "live", alive = true }).reason == "alive")
check("a dead player unslots during live", V.Click(mine, GOOD, 2, { phase = "live", alive = false }).action == "leave")
check("an alive player cannot unslot during the firing squad", V.Click(mine, GOOD, 2, { phase = "squad", alive = true }).reason == "alive")
check("a dead player unslots during the firing squad", V.Click(mine, GOOD, 2, { phase = "squad", alive = false }).action == "leave")

local switch = V.Click(mine, BAD, 4, { phase = "lobby", alive = false })
check("clicking a free slot switches", switch.action == "take" and switch.team == BAD and switch.slot == 4)

local liveAlive = V.Click(mine, BAD, 4, { phase = "live", alive = true })
check("an alive player cannot hop during live", liveAlive.action == "refuse" and liveAlive.reason == "alive")
local liveDead = V.Click(mine, BAD, 4, { phase = "live", alive = false })
check("a dead player queues the next round", liveDead.action == "queue" and liveDead.team == BAD and liveDead.slot == 4)
local postDead = V.Click(mine, BAD, 1, { phase = "post", alive = false })
check("post round also queues", postDead.action == "queue")
local duringBuy = V.Click(mine, BAD, 4, { phase = "buy", alive = true })
check("buy takes the slot immediately", duringBuy.action == "take")
check("buy unslots immediately", V.Click(mine, GOOD, 2, { phase = "buy", alive = true }).action == "leave")

local queued = build({
	localId = "a",
	names = { a = "Ada" },
	queue = { { id = "a", team = BAD, slot = 4 } },
	sides = { [GOOD] = { [1] = { id = "a", name = "Ada" } }, [BAD] = {} },
})
check("a queued move is labelled on the target slot", queued.columns[2].slots[4].label == "Next: Ada" and queued.columns[2].slots[4].empty == true)
check("the local queue is remembered", queued.localQueue and queued.localQueue.team == BAD and queued.localQueue.slot == 4)
check("queue notice names the destination", queued.moveNotice == "Moving to Bad slot 4 next round.")
check("clicking the queued slot again does not resend", V.Click(queued, BAD, 4, { phase = "live", alive = false }).action == "noop")

local roster = build({
	players = { { id = "b", name = "Bea" }, { id = "a", name = "Ada" }, { id = "c", name = "Cee" } },
	sides = { [GOOD] = { [1] = { id = "a", name = "Ada" } }, [BAD] = {} },
})
check("roster lists each player once, spectators included", #roster.roster == 3 and #roster.unassigned == 2)
check("roster sorts by name", roster.roster[1].name == "Ada" and roster.roster[2].name == "Bea" and roster.unassigned[1].id == "b")
check("place text shows the slot or Spectator", V.PlaceText(roster.roster[1]) == "Good 1" and V.PlaceText(roster.unassigned[1]) == "Spectator")

local staff = build({
	isAdmin = true,
	minPerTeam = 1,
	sides = {
		[GOOD] = { [1] = { id = "a", name = "Ada" } },
		[BAD] = { [1] = { id = "b", name = "Bea" } },
	},
})
check("admin with both teams can start", staff.start.visible == true and staff.start.enabled == true and staff.start.waiting == false and staff.start.label == "Start")
check("admin start still has no countdown", staff.showCountdown == false and staff.endsAt == nil)

local short = build({
	isAdmin = true,
	sides = { [GOOD] = { [1] = { id = "a", name = "Ada" } }, [BAD] = {} },
})
check("admin without both teams cannot start", short.start.visible == true and short.start.enabled == false and short.start.reason == "min players")
check("min-player copy uses the singular", V.ReasonText("min players", 1) == "Need at least 1 player on each team.")
check("min-player copy pluralises", V.ReasonText("min players", 2) == "Need at least 2 players on each team.")

local running = build({ isAdmin = true, phase = "live" })
check("admin Start is disabled once the match leaves lobby", running.start.enabled == false and running.start.reason == "not lobby")
local watching = build({ isAdmin = false, phase = "live", endsAt = 50 })
check("non-admins are not told to wait once the match is running", watching.start.waiting == false and watching.start.visible == false and watching.showCountdown == false)

local noFlags = build({
	isAdmin = true,
	flags = false,
	sides = {
		[GOOD] = { [1] = { id = "a", name = "Ada" } },
		[BAD] = { [1] = { id = "b", name = "Bea" } },
	},
})
check("missing flags disable Start", noFlags.start.enabled == false and noFlags.start.reason == "flags")
check("unknown flags do not block Start", staff.start.enabled == true)

local noBox = build({
	isAdmin = true,
	flags = true,
	box = false,
	sides = {
		[GOOD] = { [1] = { id = "a", name = "Ada" } },
		[BAD] = { [1] = { id = "b", name = "Bea" } },
	},
})
check("a missing firing squad box disables Start", noBox.start.enabled == false and noBox.start.reason == "box")
check("the box reason tells the admin where to place it", V.ReasonText("box") == "Place the firing squad box in Admin > Spawns")
check("an alive player cannot switch during the firing squad", V.Click(staff, BAD, 2, { phase = "squad", alive = true }).reason == "alive")
check("a dead player queues a switch during the firing squad", V.Click(staff, BAD, 2, { phase = "squad", alive = false }).action == "queue")

local both = true
local phases = { "lobby", "buy", "live", "post" }
for p = 1, #phases do
	for _, admin in ipairs({ true, false }) do
		local view = build({ phase = phases[p], isAdmin = admin })
		if view.start.waiting and view.start.visible then both = false end
		if view.showCountdown then both = false end
	end
end
check("waiting and Start never show together, and never as a countdown", both)

check("a bad slot is refused", V.Click(empty, 3, 1).reason == "slot")
check("a player value is not a slot id", V.Assign({ SteamID64 = function() return "nope" end }, GOOD, 1, 5).reason == "player")

local assign = V.Assign("ada", GOOD, 2, 5)
check("admin can assign any slot, occupied or not", assign.action == "assign" and assign.team == GOOD and assign.slot == 2)
check("slot past the team size is refused", V.Assign("ada", GOOD, 6, 5).reason == "slot")
local kick = V.Assign("ada", SPEC, 3, 5)
check("kick to spectator uses slot 0 on the wire", kick.action == "kick" and kick.team == 0 and kick.slot == 0)
check("slot 0 is also a kick", V.Assign("ada", GOOD, 0, 5).action == "kick")
check("team 0 is a kick", V.Assign("ada", 0, 4, 5).slot == 0)

local nodes = 0
local enabled = 0
local implemented = 0
local everyReset = true
BALLISTICS.AdminTabs.Walk(nil, function(node)
	nodes = nodes + 1
	if type(node.reset) ~= "table" then everyReset = false end
	if node.reset and node.reset.enabled then enabled = enabled + 1 end
	if node.implemented then implemented = implemented + 1 end
end)
check("every admin tab and sub-tab has a reset spec", nodes == 11 and everyReset)
check("every admin tab and sub-tab is implemented and can reset", implemented == 11 and enabled == 11)

local settings = BALLISTICS.AdminTabs.Find("settings")
check("Admin Settings is the first tab", BALLISTICS.AdminTabs.Tree()[1].id == "settings" and settings and settings.title == "Admin Settings")
local settingsReq = BALLISTICS.AdminTabs.ResetRequest(settings)
check("Admin Settings reset sends the settings section", settingsReq and settingsReq.reset == true and settingsReq.section == "settings")

local teams = BALLISTICS.AdminTabs.Find("teams")
local spawns = BALLISTICS.AdminTabs.Find("spawns")
local rules = BALLISTICS.AdminTabs.Find("rules")
local weapons = BALLISTICS.AdminTabs.Find("weapons")
local gains = BALLISTICS.AdminTabs.Find("gains")
local general = BALLISTICS.AdminTabs.Find("general")
local req = BALLISTICS.AdminTabs.ResetRequest(teams)
check("Teams reset sends the teams section", req and req.reset == true and req.section == "teams" and teams.title == "Teams")
local spawnReq = BALLISTICS.AdminTabs.ResetRequest(spawns)
check("Spawns reset is a spawn action", spawnReq and spawnReq.kind == "spawns" and spawnReq.reset == true and spawnReq.section == nil)
local rulesReq = BALLISTICS.AdminTabs.ResetRequest(rules)
check("Rules reset sends the rules section", rulesReq and rulesReq.reset == true and rulesReq.section == "rules" and rules.implemented == true)
check("Weapons, gains, and general resets are on", weapons.reset.section == "weapons" and weapons.reset.enabled == true and weapons.implemented == true and BALLISTICS.AdminTabs.ResetRequest(gains).section == "gains" and BALLISTICS.AdminTabs.ResetRequest(general).section == "general")
check("the admin button is admins only", BALLISTICS.AdminTabs.ButtonVisible(true) == true and BALLISTICS.AdminTabs.ButtonVisible(false) == false and BALLISTICS.AdminTabs.ButtonVisible(nil) == false)

check("Start message name", V.Messages().start == "bal_match_start")

local got = {}
function net.Receive(name, fn)
	got[name] = fn
end

local calls = {}
function BALLISTICS.StartMatch(ply)
	calls[#calls + 1] = ply
	return true
end

dofile("gamemodes/ballistics/gamemode/modules/lobby/sv_lobby.lua")

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

check("start and ready are registered", got["bal_match_start"] ~= nil and got["bal_lobby_ready"] ~= nil)

got["bal_match_start"](nil, nil)
got["bal_match_start"](nil, user)
check("non-admins and nil players never start the match", #calls == 0)

for i = 1, 4 do
	got["bal_match_start"](nil, admin)
end
check("admin Start calls StartMatch", #calls == 4 and calls[1] == admin)
got["bal_match_start"](nil, admin)
check("Start is rate limited", #calls == 4)

local sent = {}
BALLISTICS.Slots = {
	Broadcast = function(ply) sent[#sent + 1] = ply end,
}
BALLISTICS.Round = {
	Broadcast = function(ply) sent[#sent + 1] = ply end,
}
local configs = 0
function BALLISTICS.BroadcastConfig(ply)
	configs = configs + 1
	sent[#sent + 1] = ply
end
got["bal_lobby_ready"](nil, user)
check("opening the lobby asks the server for a fresh snapshot", #sent == 3 and sent[1] == user and configs == 1)

-- TEAMS toggle button: every player, lobby only, left of ADMIN.
local LV = BALLISTICS.LobbyView
check("TEAMS shows in the lobby", LV.TeamsButtonVisible("lobby") == true)
check("TEAMS hides once the game starts", LV.TeamsButtonVisible("buy") == false and LV.TeamsButtonVisible("live") == false and LV.TeamsButtonVisible("post") == false)
check("TEAMS shows before the phase is known", LV.TeamsButtonVisible(nil) == true)
check("TEAMS sits left of ADMIN for admins", LV.TeamsButtonX(1920, true) == 1920 - 84 - 10 - 84 - 6)
check("TEAMS takes the corner for non-admins", LV.TeamsButtonX(1920, false) == 1920 - 84 - 10)
check("TEAMS never goes off screen", LV.TeamsButtonX(50, true) == 0)

-- Start checklist boxes.
do
	local CL = BALLISTICS.LobbyView.Checklist
	local data = { hasBox = function(st) return type(st.box) == "table" end }
	local none = CL({}, data)
	check("checklist has three boxes in order", #none == 3 and none[1].label == "Good flag" and none[2].label == "Bad flag" and none[3].label == "Firing squad box")
	check("all missing are red", not none[1].ok and not none[2].ok and not none[3].ok and not BALLISTICS.LobbyView.ChecklistReady(none))
	local part = CL({ good = { pos = { x = 1, y = 2, z = 3 } } }, data)
	check("only good placed", part[1].ok and not part[2].ok and not part[3].ok)
	local all = CL({ good = { pos = { x = 1, y = 2, z = 3 } }, bad = { pos = { x = 4, y = 5, z = 6 } }, box = {} }, data)
	check("all placed is ready", all[1].ok and all[2].ok and all[3].ok and BALLISTICS.LobbyView.ChecklistReady(all))
	check("no snapshot is all red", not BALLISTICS.LobbyView.ChecklistReady(CL(nil, nil)))
end

do
	-- The client has no BALLISTICS.PlayerId (server file), so cl_lobby must
	-- supply one with the server's id scheme or your own slot never reads "mine".
	local src = io.open("gamemodes/ballistics/gamemode/modules/lobby/cl_lobby.lua"):read("*a")
	local body = src:match("local function clientPlayerId%(ply%).-\nend\n")
	local fn = body and loadstring(body .. "\nreturn clientPlayerId")()
	local human = { SteamID64 = function() return "7656119" end, IsBot = function() return false end }
	local bot = { IsBot = function() return true end, UserID = function() return 12 end }
	check("client player id matches the server for humans and bots", fn ~= nil and fn(human) == "7656119" and fn(bot) == "bot:12")
	check("client installs the id when the server one is missing", src:find("if not BALLISTICS.PlayerId then BALLISTICS.PlayerId = clientPlayerId end", 1, true) ~= nil)
	local v = { columns = { { team = 1, slots = { { mine = true, empty = false } } } } }
	local ok, d = pcall(BALLISTICS.LobbyView.Click, v, 1, 1, { phase = "lobby" })
	check("clicking your own slot leaves it", ok and type(d) == "table" and (d.action == "leave" or d.reason ~= "taken"))
end

if failed then os.exit(1) end
