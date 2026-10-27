-- Slots: take, switch, full, queue, leave on disconnect, admin assign.
-- Run: luajit tests/test_slots.lua
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
dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")

local GOOD = TEAM_GOOD
local BAD = TEAM_BAD
local SPEC = TEAM_SPEC
local T = BALLISTICS.SlotTable

local function teamSlot(slots, id)
	local teamId, slot = slots:TeamOf(id)
	return teamId, slot
end

local s = T.new(5)

local ok, err = s:Take(nil, GOOD, 1)
check("take rejects nil player", ok == false and err == "player")

ok, err = s:Take("a", 3, 1)
check("take rejects unknown team", ok == false and err == "team")

ok, err = s:Take("a", GOOD, 0)
check("take rejects slot 0", ok == false and err == "slot")

ok, err = s:Take("a", GOOD, 6)
check("take rejects slot past the limit", ok == false and err == "slot")

ok = s:Take("a", GOOD, 1)
check("take free slot", ok == true and teamSlot(s, "a") == GOOD)
local _, slot = teamSlot(s, "a")
check("take lands in that slot", slot == 1 and s:Count(GOOD) == 1 and s:Occupant(GOOD, 1) == "a")

ok = s:Take("a", GOOD, 2)
_, slot = teamSlot(s, "a")
check("switch leaves the old slot", ok == true and slot == 2 and s:Occupant(GOOD, 1) == nil and s:Occupant(GOOD, 2) == "a")

ok = s:Take("a", BAD, 3)
_, slot = teamSlot(s, "a")
check("switch teams", ok == true and teamSlot(s, "a") == BAD and slot == 3 and s:Count(GOOD) == 0 and s:Count(BAD) == 1)

s:Take("b", GOOD, 1)
ok, err = s:Take("a", GOOD, 1)
_, slot = teamSlot(s, "a")
check("occupied slot is refused and the taker stays", ok == false and err == "taken" and teamSlot(s, "a") == BAD and slot == 3)

ok = s:Take("a", BAD, 3)
check("taking your own slot is a no-op", ok == true and s:Occupant(BAD, 3) == "a")
ok, err = s:Request("a", BAD, 3, "lobby", false)
check("requesting your own slot unslots you", ok == true and err == "leave" and s:TeamOf("a") == nil and s:Occupant(BAD, 3) == nil)

s:Clear()
for i = 1, 5 do
	ok = s:Take("p" .. i, GOOD, i)
	if not ok then break end
end
check("five good slots fill", s:Count(GOOD) == 5)
ok, err = s:Take("extra", GOOD, 1)
check("full side refuses another player", ok == false and err == "taken" and s:TeamOf("extra") == nil)
ok, err = s:Take("extra", GOOD, 5)
check("every full slot is taken", ok == false and err == "taken")
ok = s:Take("extra", BAD, 1)
check("the other side still has room", ok == true and s:Count(BAD) == 1)

local members = s:Members(GOOD)
check("members come back in slot order", #members == 5 and members[1] == "p1" and members[5] == "p5")

ok = s:Leave("p3")
check("leave opens the slot", ok == true and s:Occupant(GOOD, 3) == nil and s:Count(GOOD) == 4 and s:TeamOf("p3") == nil)
ok, err = s:Leave("p3")
check("leave is idempotent", ok == true and err == "none")
ok = s:Take("extra2", GOOD, 3)
check("freed slot can be taken", ok == true and s:Occupant(GOOD, 3) == "extra2")

s:Clear()
s:Take("a", GOOD, 1)
s:Take("b", BAD, 1)
ok, err = s:Assign("a", BAD, 1)
_, slot = teamSlot(s, "a")
local _, bslot = teamSlot(s, "b")
check("admin assign swaps two slotted players", ok == true and err == "swap" and teamSlot(s, "a") == BAD and slot == 1 and teamSlot(s, "b") == GOOD and bslot == 1)

s:Clear()
s:Take("b", GOOD, 1)
ok, err = s:Assign("a", GOOD, 1)
check("admin assign displaces an occupant to spectator", ok == true and s:Occupant(GOOD, 1) == "a" and s:TeamOf("b") == nil)

ok, err = s:Assign("a", SPEC, 4)
check("admin assign to spectator clears the slot", ok == true and s:TeamOf("a") == nil and s:Count(GOOD) == 0)

s:Take("a", GOOD, 2)
ok = s:Assign("a", GOOD, 0)
check("admin assign slot 0 kicks to spectator", ok == true and s:TeamOf("a") == nil)

s:Take("a", GOOD, 1)
s:Take("b", BAD, 2)
ok, err = s:Request("a", BAD, 2, "live", true)
_, slot = teamSlot(s, "a")
check("alive player cannot switch during live", ok == false and err == "alive" and teamSlot(s, "a") == GOOD and slot == 1)

ok, err = s:Request("a", BAD, 1, "live", false)
_, slot = teamSlot(s, "a")
check("dead player queues a live switch and keeps the old slot", ok == true and err == "queued" and slot == 1 and s:Occupant(GOOD, 1) == "a")
local qTeam, qSlot = s:Queued("a")
check("queue records the request", qTeam == BAD and qSlot == 1)

ok, err = s:Request("b", GOOD, 2, "post", true)
check("alive player cannot switch during post", ok == false and err == "alive" and s:Occupant(BAD, 2) == "b")

ok, err = s:Request("b", GOOD, 1, "squad", true)
check("alive player cannot switch during the firing squad", ok == false and err == "alive" and s:Occupant(BAD, 2) == "b")
ok, err = s:Request("b", GOOD, 1, "squad", false)
check("a dead player queues a switch during the firing squad", ok == true and err == "queued" and s:Occupant(BAD, 2) == "b" and s:Queued("b") == GOOD)

s:Clear()
s:Take("a", GOOD, 1)
ok, err = s:Request("a", GOOD, 1, "live", true)
check("an alive player cannot unslot during live", ok == false and err == "alive" and s:Occupant(GOOD, 1) == "a")
ok, err = s:Request("a", GOOD, 1, "live", false)
check("a dead player unslots immediately during live", ok == true and err == "leave" and s:TeamOf("a") == nil)

s:Clear()
s:Take("a", GOOD, 1)
s:Queue("a", BAD, 2)
ok, err = s:Request("a", GOOD, 1, "lobby", false)
check("unslot drops a queued move", ok == true and err == "leave" and s:TeamOf("a") == nil and s:Queued("a") == nil)

s:Clear()
s:Take("a", GOOD, 1)
s:Take("m", GOOD, 2)
s:Queue("a", BAD, 1)
s:Queue("m", BAD, 1)
local applied = s:ApplyQueued()
check("apply moves the first queued id", s:Occupant(BAD, 1) == "a" and s:Occupant(GOOD, 1) == nil)
local mStayed = false
for i = 1, #applied do
	if applied[i].id == "m" and applied[i].ok == false and applied[i].err == "taken" then mStayed = true end
end
check("second player queued onto the same slot stays put", mStayed and s:Occupant(GOOD, 2) == "m" and s:Queued("a") == nil)

s:Clear()
s:Take("z", GOOD, 1)
s:Queue("z", BAD, 2)
s:Leave("z")
check("leave drops a queued switch", s:TeamOf("z") == nil and s:Queued("z") == nil and #s:ApplyQueued() == 0)

local limit = 5
local flex = T.new(function() return limit end)
flex:Take("a", GOOD, 5)
limit = 2
check("shrinking the limit drops overflow slots", flex:TeamOf("a") == nil and flex:Count(GOOD) == 0)
ok, err = flex:Take("a", GOOD, 3)
check("shrunk limit rejects the old index", ok == false and err == "slot")
ok = flex:Take("a", GOOD, 2)
check("shrunk limit still accepts a legal slot", ok == true and flex:Occupant(GOOD, 2) == "a")

-- Singleton: disconnect hook, SetTeam, and the live-phase request gate.
local function fake(id, alive)
	local ply = { id = id, alive = alive ~= false, teamId = nil, name = id }
	function ply:SteamID64() return self.id end
	function ply:Alive() return self.alive end
	function ply:SetTeam(teamId) self.teamId = teamId end
	function ply:Team() return self.teamId end
	function ply:Nick() return self.name end
	return ply
end

BALLISTICS.Slots.ClearAll()
local alpha = fake("A")
local beta = fake("B")
ok = BALLISTICS.Slots.Take(alpha, GOOD, 1)
check("singleton take sets the gmod team", ok == true and alpha.teamId == GOOD and BALLISTICS.Slots.TeamOf(alpha) == GOOD)
check("singleton remembers the player", BALLISTICS.Slots.Player("A") == alpha)

ok, err = BALLISTICS.Slots.Take(beta, GOOD, 1)
check("singleton refuses a full slot", ok == false and err == "taken" and beta.teamId == nil)

ok = BALLISTICS.Slots.Take(beta, BAD, 1)
check("singleton other side", ok == true and beta.teamId == BAD)

local swapped = BALLISTICS.Slots.Assign(alpha, BAD, 1)
check("singleton admin swap updates both teams", swapped == true and alpha.teamId == BAD and beta.teamId == GOOD)

local gamma = fake("C", false)
local displaced = BALLISTICS.Slots.Assign(gamma, GOOD, 1)
check("singleton admin displace kicks the occupant", displaced == true and gamma.teamId == GOOD and beta.teamId == SPEC and BALLISTICS.Slots.TeamOf(beta) == nil)

BALLISTICS.Slots.ClearAll()
local delta = fake("D")
BALLISTICS.Slots.Take(delta, GOOD, 4)
local seen = 0
hook.Add("Ballistics_SlotsChanged", "slots", function() seen = seen + 1 end)
local before = seen
hook.Run("PlayerDisconnected", delta)
check("disconnect frees the slot", BALLISTICS.Slots.TeamOf("D") == nil and BALLISTICS.Slots.Count(GOOD) == 0 and BALLISTICS.Slots.Player("D") == nil)
check("disconnect notifies listeners", seen > before)
ok = BALLISTICS.Slots.Take(fake("E"), GOOD, 4)
check("disconnected slot can be taken", ok == true and BALLISTICS.Slots.Count(GOOD) == 1)

BALLISTICS.Round = {
	Phase = function() return "live" end,
}
local hopper = fake("H", true)
BALLISTICS.Slots.Take(hopper, GOOD, 2)
hopper.alive = true
ok, err = BALLISTICS.Slots.Request(hopper, BAD, 2)
check("singleton blocks a living hopper in live", ok == false and err == "alive" and hopper.teamId == GOOD)
hopper.alive = false
ok, err = BALLISTICS.Slots.Request(hopper, BAD, 2)
check("singleton queues a dead hopper in live", ok == true and err == "queued" and BALLISTICS.Slots.TeamOf(hopper) == GOOD)

BALLISTICS.Round = { Phase = function() return "lobby" end }
local specced = nil
BALLISTICS.Player = {
	MakeSpectator = function(ply) specced = ply end,
}
local seater = fake("S")
BALLISTICS.Slots.Take(seater, GOOD, 3)
ok, err = BALLISTICS.Slots.Request(seater, GOOD, 3)
check("singleton unslot frees the seat and spectates", ok == true and err == "leave" and BALLISTICS.Slots.TeamOf(seater) == nil and seater.teamId == SPEC and specced == seater)
BALLISTICS.Player = nil
local results = BALLISTICS.Slots.ApplyQueued()
local moved = false
for i = 1, #results do
	if results[i].id == "H" and results[i].ok then moved = true end
end
check("apply queued switch updates the team", moved and BALLISTICS.Slots.TeamOf(hopper) == BAD and hopper.teamId == BAD)
BALLISTICS.Round = nil

check("player id prefers steamid64", BALLISTICS.PlayerId(alpha) == "A")
check("player id keeps a plain string", BALLISTICS.PlayerId("steam") == "steam")

if failed then os.exit(1) end
